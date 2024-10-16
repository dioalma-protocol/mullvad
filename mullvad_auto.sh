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

# Initialize available relays
available_relays=()
fetch_available_relays() {
    log_message "Fetching available relays..."
    available_relays=($(curl --silent https://api.mullvad.net/app/v1/relays | jq -r .wireguard.relays[].hostname))
    log_message "Available relays fetched: ${available_relays[@]}"
}

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
        AVAILABLE_COUNTRIES=("${available_relays[@]}")
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
    for relay in "${AVAILABLE_COUNTRIES[@]}"; do
        echo "$relay"
    done > "$COUNTRY_CONFIG_FILE"
}

# Function to change to a random relay from the selected list
change_country_once() {
    log_message "Attempting to change country..."
    current_action="Selecting a new random relay..."
    
    if [[ ${#AVAILABLE_COUNTRIES[@]} -eq 0 ]]; then
        log_message "No countries selected. Please select countries in the menu."
        current_action="No countries selected!"
        sleep 2
        return
    fi

    # Pick a random relay from the list
    RANDOM_COUNTRY=${AVAILABLE_COUNTRIES[$RANDOM % ${#AVAILABLE_COUNTRIES[@]}]}
    RANDOM_COUNTRY_NAME="$RANDOM_COUNTRY"

    log_message "Selected random relay: $RANDOM_COUNTRY_NAME"
    current_action="Changing to $RANDOM_COUNTRY_NAME..."

    mullvad relay set location "$RANDOM_COUNTRY_NAME" > /dev/null 2>&1
    mullvad reconnect > /dev/null 2>&1
    sleep 10  # Allow time for the change to take effect

    # Update our tracked current country directly
    current_country="$RANDOM_COUNTRY_NAME"
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

# Display the relay selection menu
set_available_relays() {
    COUNTRY_ITEMS=()
    for relay in "${available_relays[@]}"; do
        COUNTRY_ITEMS+=("$relay" "$relay Enabled" "on")
    done

    exec 3>&1
    SELECTED_RELAYS=$(dialog --checklist "Select Available Relays" 20 60 15 "${COUNTRY_ITEMS[@]}" 2>&1 1>&3)
    exec 3>&-

    if [[ -n "$SELECTED_RELAYS" ]]; then
        AVAILABLE_COUNTRIES=()
        for relay in $SELECTED_RELAYS; do
            AVAILABLE_COUNTRIES+=("${relay//\"}")
        done
        save_country_config
        log_message "Relay selection updated"
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
            1 "Change to a random relay now" \
            2 "Set the automatic shuffle interval" \
            3 "Select available relays" \
            4 Exit \
            2>&1 1>&3)
        exit_code=$?
        exec 3>&-

        case $selection in
            1) change_country_once ;;  # Change relay once, then return to the menu
            2) set_shuffle_interval ;; # Set shuffle interval
            3) set_available_relays ;;  # Select available relays
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
fetch_available_relays  # Fetch available relays
load_config     # Load configurations
change_country_once  # Initial shuffle
countdown_timer & # Start the countdown in the background
show_menu  # Display the main menu

