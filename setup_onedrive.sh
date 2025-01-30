#!/bin/bash

#### PLEASE read this blog article first: https://blog.lealdasilva.com/mounting-onedrive-on-linux-with-rclone/ ###

echo "Updating package list and installing rclone..."
sudo apt update && sudo apt install -y rclone

echo "Ensuring the onedrive directory exists..."
mkdir -p "$HOME/onedrive"

echo "Adding mount command to crontab..."
(crontab -l 2>/dev/null; echo "@reboot sleep 20 && rclone mount onedrive: $HOME/onedrive --vfs-cache-mode writes") | crontab -

echo "\n\033[1;32mSetup complete!\033[0m"
echo "\033[1;33mNext step:\033[0m Run \033[1;34mrclone config\033[0m to link your OneDrive account."
echo "After setup, use \033[1;34mrclone ls onedrive:\033[0m to verify the connection."
