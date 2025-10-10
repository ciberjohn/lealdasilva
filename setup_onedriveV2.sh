#!/usr/bin/env bash

# IMPROVEMENTS:
# 1. Better shebang for improved portability across systems
# 2. Added error handling and strict mode
# 3. Added color coding for better readability
# 4. Replaced crontab with systemd user service
# 5. Added command existence checking
# 6. Added directory checks
# 7. Improved mount options for better performance
# 8. Added service management
# 9. Added user feedback and status messages
# 10. Added proper cleanup and error handling

# Exit on error, undefined variables, and pipe failures
set -euo pipefail
IFS=$'\n\t'

# Define colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Function to display formatted messages
show_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check if directory is empty
is_dir_empty() {
    [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

show_message "$BLUE" "#### Please read this article first: https://medium.com/@joaolealdasilva/mounting-onedrive-on-linux-with-rclone-958cc2e12efc ####"

# Check if rclone is already installed
if ! command_exists rclone; then
    show_message "$YELLOW" "Installing rclone..."
    $SUDO apt update
    $SUDO apt install -y rclone
else
    show_message "$GREEN" "rclone is already installed"
fi

# Setup OneDrive directory with safety checks
ONEDRIVE_DIR="$HOME/onedrive"
if [ ! -d "$ONEDRIVE_DIR" ]; then
    show_message "$YELLOW" "Creating OneDrive directory at $ONEDRIVE_DIR"
    mkdir -p "$ONEDRIVE_DIR"
else
    if ! is_dir_empty "$ONEDRIVE_DIR"; then
        show_message "$RED" "Warning: $ONEDRIVE_DIR exists and is not empty"
        read -p "Do you want to continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            show_message "$RED" "Setup aborted"
            exit 1
        fi
    fi
fi

# Create systemd user service for persistent mount
# Improvement: Using systemd instead of crontab for better service management
show_message "$YELLOW" "Creating systemd user service for OneDrive mount..."
mkdir -p ~/.config/systemd/user/
cat << EOF > ~/.config/systemd/user/rclone-onedrive.service
[Unit]
Description=OneDrive (rclone)
AssertPathIsDirectory=${ONEDRIVE_DIR}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount \
    --vfs-cache-mode writes \
    --vfs-cache-max-age 24h \
    --vfs-read-chunk-size 10M \
    --vfs-read-chunk-size-limit 512M \
    --buffer-size 512M \
    --dir-cache-time 24h \
    --timeout 1h \
    onedrive: ${ONEDRIVE_DIR}
ExecStop=/bin/fusermount -u ${ONEDRIVE_DIR}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

# Enable and start the service with proper error handling
show_message "$YELLOW" "Enabling and starting OneDrive service..."
systemctl --user daemon-reload || {
    show_message "$RED" "Failed to reload systemd daemon"
    exit 1
}
systemctl --user enable rclone-onedrive.service || {
    show_message "$RED" "Failed to enable OneDrive service"
    exit 1
}
systemctl --user start rclone-onedrive.service || {
    show_message "$RED" "Failed to start OneDrive service"
    exit 1
}

# Improved user feedback with clear next steps
show_message "$GREEN" "Setup complete!"
show_message "$YELLOW" "Next steps:"
echo -e "${BLUE}1. Run 'rclone config' to link your OneDrive account"
echo -e "2. Run 'rclone ls onedrive:' to verify the connection"
echo -e "3. Check mount status: 'systemctl --user status rclone-onedrive'"
echo -e "4. View logs: 'journalctl --user -u rclone-onedrive'${NC}"