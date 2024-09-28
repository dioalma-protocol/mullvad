#!/bin/bash

# Name of the configuration data file
CONFIG_FILE="${HOME}/mullvad_auto_data"
COUNTRY_CONFIG_FILE="${HOME}/mullvad_auto_countries"
LOG_FILE="${HOME}/mullvad_auto_log.txt"

# Correcting paths if running as sudo
if [[ $EUID -eq 0 ]]; then
  USER_HOME=$(eval echo ~$(logname))
  CONFIG_FILE="${USER_HOME}/mullvad_auto_data"
  COUNTRY_CONFIG_FILE="${USER_HOME}/mullvad_auto_countries"
  LOG_FILE="${USER_HOME}/mullvad_auto_log.txt"
else
  USER_HOME="$HOME"
fi

# Telegram link and website
TELEGRAM_LINK="t.me/dioalmaprotocol"
WEBSITE="dioalmaprotocol.pt"

# List of all possible countries with full names and single abbreviations based on Mullvad VPN
ALL_COUNTRIES=( "Albania al" "Argentina ar" "Austria at" "Australia au" "Belgium be" "Bulgaria bg" "Brazil br" 
                "Canada ca" "Switzerland ch" "Czech Republic cz" "Germany de" "Denmark dk" "Estonia ee" 
                "Spain es" "Finland fi" "France fr" "Greece gr" "Hong Kong hk" "Hungary hu" "Ireland ie" 
                "Israel il" "India in" "Iceland is" "Italy it" "Japan jp" "South Korea kr" "Luxembourg lu" 
                "Latvia lv" "Moldova md" "North Macedonia mk" "Mexico mx" "Malaysia my" "Netherlands nl" 
                "Norway no" "New Zealand nz" "Philippines ph" "Poland pl" "Portugal pt" "Romania ro" 
                "Serbia rs" "Sweden se" "Singapore sg" "Slovenia si" "Slovakia sk" "Turkey tr" "Taiwan tw" 
                "Ukraine ua" "United Kingdom uk" "United States us" )

# Initialize the current country
current_country="Unknown"
current_action="Starting up..."  # Used to display current status actions in the menu

# Clear the log at the start of the script
initialize_log() {
    echo "-----------------------------------------" > "$LOG_FILE"
    echo "Mullvad Auto VPN Script Started - $(date)" >> "$LOG_FILE"
    echo "Telegram Support: $TELEGRAM_LINK" >> "$LOG_FILE"
    echo "Website: $WEBSITE" >> "$LOG_FILE"
    echo "-----------------------------------------" >> "$LOG_FILE"
}

# Log function to ensure all messages are written to the log file
log_message() {
    echo "$(date) - $1" | tee -a "$LOG_FILE"
}

# Load the configuration from file or set default values
load_config() {
    log_message "Loading configuration..."
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_message "Config file loaded"
    else
        SHUFFLE_HOURS=1
        SHUFFLE_MINUTES=0
        save_config  # Save the default configuration
        log_message "Default configuration set"
    fi
    
    # Load the available countries configuration
    if [[ -f "$COUNTRY_CONFIG_FILE" ]]; then
        AVAILABLE_COUNTRIES=()
        while IFS= read -r line; do
            AVAILABLE_COUNTRIES+=("$line")
        done < "$COUNTRY_CONFIG_FILE"
        log_message "Country config loaded with the following countries:"
        for country in "${AVAILABLE_COUNTRIES[@]}"; do
            log_message " - $country"
        done
    else
        AVAILABLE_COUNTRIES=("${ALL_COUNTRIES[@]}")
        save_country_config  # Save the default country selection
        log_message "Default country configuration set"
    fi
}

# Save the current configuration to the file
save_config() {
    echo "SHUFFLE_HOURS=$SHUFFLE_HOURS" > "$CONFIG_FILE"
    echo "SHUFFLE_MINUTES=$SHUFFLE_MINUTES" >> "$CONFIG_FILE"
}

# Save the current country selection to the file in the correct format
save_country_config() {
    for ((i=0; i<${#AVAILABLE_COUNTRIES[@]}; i+=2)); do
        echo "${AVAILABLE_COUNTRIES[i]} ${AVAILABLE_COUNTRIES[i+1]}"
    done > "$COUNTRY_CONFIG_FILE"
}

# Function to change to a random country from the selected list
change_country_once() {
    log_message "Attempting to change country..."
    current_action="Selecting a new random country..."
    
    if [[ ${#AVAILABLE_COUNTRIES[@]} -eq 0 ]]; then
        log_message "No countries selected. Please select countries in the menu."
        current_action="No countries selected!"
        sleep 2
        return
    fi

    # Ensure pairs are reconstructed correctly
    selected_countries=()
    for ((i=0; i<${#AVAILABLE_COUNTRIES[@]}; i+=2)); do
        selected_countries+=("${AVAILABLE_COUNTRIES[i]} ${AVAILABLE_COUNTRIES[i+1]}")
    done

    # Pick a random country from the list
    RANDOM_COUNTRY=${selected_countries[$RANDOM % ${#selected_countries[@]}]}
    RANDOM_COUNTRY_NAME=$(echo $RANDOM_COUNTRY | awk '{print $1}')
    RANDOM_COUNTRY_CODE=$(echo $RANDOM_COUNTRY | awk '{print $2}')

    log_message "Selected random country: $RANDOM_COUNTRY_NAME ($RANDOM_COUNTRY_CODE)"
    current_action="Changing to $RANDOM_COUNTRY_NAME ($RANDOM_COUNTRY_CODE)..."

    mullvad relay set location $RANDOM_COUNTRY_CODE > /dev/null 2>&1
    mullvad reconnect > /dev/null 2>&1
    sleep 10  # Allow time for the change to take effect

    # Update our tracked current country directly
    current_country="$RANDOM_COUNTRY_NAME (${RANDOM_COUNTRY_CODE^^})"
    log_message "Successfully connected to $current_country"
    current_action="Connected to $current_country"
}

# Display the dialog for changing the interval
set_shuffle_interval() {
    exec 3>&1
    VALUES=$(dialog --ok-label "Save" --form "Set Shuffle Interval" 15 50 0 \
        "Hours:" 1 1 "$SHUFFLE_HOURS" 1 15 5 0 \
        "Minutes:" 2 1 "$SHUFFLE_MINUTES" 2 15 5 0 \
        2>&1 1>&3)
    exit_code=$?
    exec 3>&-

    if [ $exit_code -eq 0 ]; then
        SHUFFLE_HOURS=$(echo "$VALUES" | sed -n 1p)
        SHUFFLE_MINUTES=$(echo "$VALUES" | sed -n 2p)
        save_config
        log_message "Shuffle interval updated: $SHUFFLE_HOURS hours, $SHUFFLE_MINUTES minutes"
        countdown_timer &  # Restart the countdown timer with the new interval
    fi
}

# Display the country selection menu
set_available_countries() {
    COUNTRY_ITEMS=()
    for entry in "${ALL_COUNTRIES[@]}"; do
        country_name=$(echo $entry | awk '{print $1}')
        country_code=$(echo $entry | awk '{print $2}')
        
        if [[ " ${AVAILABLE_COUNTRIES[@]} " =~ " ${country_name} ${country_code} " ]]; then
            COUNTRY_ITEMS+=("$country_name $country_code" "${country_name} Enabled" "on")
        else
            COUNTRY_ITEMS+=("$country_name $country_code" "${country_name} Disabled" "off")
        fi
    done

    exec 3>&1
    SELECTED_COUNTRIES=$(dialog --checklist "Select Available Countries" 20 60 15 "${COUNTRY_ITEMS[@]}" 2>&1 1>&3)
    exec 3>&-

    if [[ -n "$SELECTED_COUNTRIES" ]]; then
        AVAILABLE_COUNTRIES=()
        for country in $SELECTED_COUNTRIES; do
            AVAILABLE_COUNTRIES+=("${country//\"}")
        done
        save_country_config
        log_message "Country selection updated"
    fi
}

# Function to start the countdown
countdown_timer() {
    sleep_time=$(calculate_sleep_time)
    while [ $sleep_time -gt 0 ]; do
        hours=$((sleep_time / 3600))
        minutes=$(((sleep_time % 3600) / 60))
        seconds=$((sleep_time % 60))
        current_action="Waiting $hours hour(s), $minutes minute(s), and $seconds second(s) before the next automatic shuffle..."
        sleep 1
        sleep_time=$((sleep_time - 1))
    done
    current_action="Automatic shuffle initiated..."
    change_country_once
    countdown_timer & # Restart countdown
}

# Display the main menu and refresh the current country frequently
show_menu() {
    while true; do
        dynamic_title="Mullvad VPN Manager - $current_action"
        
        exec 3>&1
        selection=$(dialog --clear \
            --backtitle "$dynamic_title" \
            --title "Current Status: $current_country" \
            --menu "Telegram: $TELEGRAM_LINK | Website: $WEBSITE\nShuffle interval: Every $SHUFFLE_HOURS hour(s) and $SHUFFLE_MINUTES minute(s)" 20 60 6 \
            1 "Change to a random country now" \
            2 "Set the automatic shuffle interval" \
            3 "Select available countries" \
            4 Exit \
            2>&1 1>&3)
        exit_code=$?
        exec 3>&-

        case $selection in
            1) change_country_once ;;  # Change country once, then return to the menu
            2) set_shuffle_interval ;; # Set shuffle interval
            3) set_available_countries ;;  # Select available countries
            4) clear; pkill -P $$; exit 0 ;;  # Exit the program and stop background tasks
        esac
    done
}

# Calculate total sleep time in seconds based on hours and minutes
calculate_sleep_time() {
    echo "$((SHUFFLE_HOURS * 3600 + SHUFFLE_MINUTES * 60))"
}

# Start the script
initialize_log  # Initialize the log at the start
load_config     # Load configurations
change_country_once  # Initial shuffle
countdown_timer & # Start the countdown in the background
show_menu  # Display the main menu

