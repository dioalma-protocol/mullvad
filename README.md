Mullvad Auto VPN Script
Description
This script automates the process of connecting to random VPN locations using the Mullvad service. It allows you to set a timer for how often the connection should change and manage available countries.

Prerequisites
Before running the script, ensure that you have the following installed:

Mullvad VPN Client: Make sure the Mullvad VPN client is installed and configured on your system.
Dialog: This script uses the dialog package to create user interfaces in the terminal. You can install it using:
bash
Copy code
sudo apt install dialog  # For Debian/Ubuntu-based systems
sudo dnf install dialog  # For Fedora/RHEL-based systems
sudo yum install dialog   # For CentOS/RHEL-based systems
Setup Instructions
Download the Script: Save the script from the following GitHub repository:

Mullvad Auto VPN Script: https://github.com/dioalma-protocol/mullvad/blob/main/mullvad_auto.sh
Make the Script Executable:

bash
Copy code
chmod +x mullvad_auto.sh
Run the Script: Start the script using the command:

bash
Copy code
./mullvad_auto.sh
Initial Configuration: Upon first run, the script will create configuration files in your home directory:

mullvad_auto_data
mullvad_auto_countries
You can edit mullvad_auto_countries to select specific countries.

Changing Timer Configuration
To change the shuffle interval:
Select the option to set the automatic shuffle interval in the menu.
Enter the desired hours and minutes.
Note: The program must be restarted for changes to the timer configuration to take effect.
Troubleshooting
Killing the Script Process
Occasionally, the program may not close properly. In such cases, you can kill the process manually:

Find the Process ID:

bash
Copy code
ps aux | grep mullvad_auto
Kill the Process: Use the following command with the Process ID you found:

bash
Copy code
sudo kill <Process_ID>
Support
For any questions or issues, feel free to reach out through our Telegram support channel:

Telegram Support: https://t.me/dioalmaprotocol
