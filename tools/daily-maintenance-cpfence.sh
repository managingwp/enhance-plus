#!/bin/bash
# Script by cPFence Team, https://cpfence.app
#
# Description:
# This script performs routine server maintenance tasks:
# - Truncates user error logs larger than 5MB and server logs larger than 100MB, keeping only the last entries using `sponge` (ensure `sponge` is installed on the server).
# - Retains only the last 10 days of system journal logs.
# - Updates and upgrades packages non-interactively and checks if a reboot is required.
# - Clears APT cache to save space.

# Truncate error logs > 5MB for users on server
/usr/bin/find /var/www \( -name "*.log" -o -name "*_log" \) -size +5M -exec sh -c '
  for file; do
    tail -c 5M "$file" | /usr/bin/sponge "$file"
  done
' sh {} +

# Truncate server logs > 100MB
/usr/bin/find /var/log \( -name "*.log" -o -name "*_log" \) -size +100M -exec sudo sh -c '
  for file; do
    tail -c 100M "$file" | /usr/bin/sponge "$file"
  done
' sh {} +

# Keep only the last 10 days of logs in the journal
sudo journalctl --vacuum-time=10d > /dev/null 2>&1

# Set non-interactive environment for package installations
export DEBIAN_FRONTEND=noninteractive

# Define your command
CMD="apt-get"

# Run the update, upgrade, and autoremove in a non-interactive manner and check if a reboot is required
update_output=$(${CMD} update -y > /dev/null 2>&1 && \
               ${CMD} full-upgrade -y > /dev/null 2>&1 && \
               ${CMD} autoremove -y > /dev/null 2>&1 && \
               [ -f /var/run/reboot-required ] && echo "Reboot required" || echo "No reboot required")

# Output the result
echo "$update_output"

# If a reboot is required, display more info about the reason
if [ -f /var/run/reboot-required ]; then
    echo "The following packages require a reboot:"
    cat /var/run/reboot-required.pkgs
fi

# Check for errors
if [ $? -eq 0 ]; then
    echo "Script executed successfully."
else
    echo "Error occurred during script execution."
fi

# Clear APT cache
apt-get clean