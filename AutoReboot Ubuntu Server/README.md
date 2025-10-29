# Auto-Reboot Script

This script automatically reboots a server if its uptime exceeds a specified threshold (default: 30 days or 720 hours). It is designed to be run periodically via a cron job.

## Features

- Checks server uptime in hours.
- Logs all actions to `/var/log/auto-reboot.log`.
- Reboots the server if uptime exceeds the defined limit.
- Optional notification before reboot (commented out in the script).

## Usage

1. **Set Up the Script**  
   Save the script as `auto-reboot.sh` and ensure it is executable:
   ```bash
   chmod +x auto-reboot.sh