#!/bin/bash

# Auto-reboot script - reboots server if uptime exceeds 30 days (720 hours)
# Add to crontab to run automatically: 0 */6 * * * /path/to/auto-reboot.sh

LOG_FILE="/var/log/auto-reboot.log"
MAX_UPTIME_HOURS=720  # 30 days * 24 hours

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Get uptime in hours
get_uptime_hours() {
    # Get uptime in seconds and convert to hours
    uptime_seconds=$(cat /proc/uptime | awk '{print $1}')
    uptime_hours=$(echo "$uptime_seconds / 3600" | bc)
    echo "$uptime_hours"
}

# Main execution
log_message "Starting uptime check"

current_uptime=$(get_uptime_hours)
log_message "Current uptime: $current_uptime hours"

if (( $(echo "$current_uptime > $MAX_UPTIME_HOURS" | bc -l) )); then
    log_message "Uptime exceeds $MAX_UPTIME_HOURS hours. Initiating reboot..."
    
    # Send notification before reboot (optional)
    # echo "Server rebooting due to uptime limit exceeded" | mail -s "Server Auto-Reboot" admin@example.com
    
    # Reboot the server
    /sbin/reboot
else
    log_message "Uptime is within acceptable limits. No action needed."
fi

exit 0