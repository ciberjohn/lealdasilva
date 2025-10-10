#!/usr/bin/env bash

# This script handles migration to Docker:
#
# 1. If Podman exists:
#    - Removes Podman and all its components
#    - Installs Docker and Docker Compose plugin
#
# 2. If Docker exists with legacy compose:
#    - Offers to migrate to compose plugin
#    - Optional: Creates compatibility alias
#
# 3. If Docker exists with plugin:
#    - Verifies installation and exits
#
# 4. If no container runtime:
#    - Installs Docker and Docker Compose plugin

set -euo pipefail
IFS=$'\n\t'

# Function to display progress
show_progress() {
    echo "===> $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to get Ubuntu codename
get_ubuntu_codename() {
    # Check if this is Linux Mint
    if [ -f "/etc/linuxmint/info" ]; then
        # Extract Ubuntu base from Linux Mint
        UBUNTU_BASE=$(grep "UBUNTU_CODENAME" /etc/os-release | cut -d= -f2 | tr -d '"')
        echo "$UBUNTU_BASE"
    else
        # For Ubuntu and others, use lsb_release directly
        lsb_release -cs
    fi
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    show_progress "Requesting sudo privileges"
    SUDO="sudo"
else
    SUDO=""
fi

# Function to remove Podman
remove_podman() {
    show_progress "Removing Podman and related components..."
    
    # Stop Podman services if running
    if systemctl is-active --quiet podman.socket; then
        $SUDO systemctl stop podman.socket
        $SUDO systemctl disable podman.socket
    fi

    # Remove Podman packages based on distribution
    if command_exists apt; then
        # For Ubuntu/Debian/Mint
        PODMAN_PACKAGES=(
            "podman"
            "podman-docker"
            "containernetworking-plugins"
        )
        
        for package in "${PODMAN_PACKAGES[@]}"; do
            if $SUDO apt-cache show "$package" > /dev/null 2>&1; then
                $SUDO apt remove -y "$package"
            fi
        done
        $SUDO apt autoremove -y
        
    elif command_exists dnf; then
        $SUDO dnf remove -y podman podman-docker containers-common containernetworking-plugins
        $SUDO dnf autoremove -y
    elif command_exists yum; then
        $SUDO yum remove -y podman podman-docker containers-common containernetworking-plugins
        $SUDO yum autoremove -y
    fi

    # Remove Podman configuration and data
    rm -rf ~/.config/containers ~/.local/share/containers
    $SUDO rm -rf /var/lib/containers

    # Remove Podman Compose if installed
    if command_exists podman-compose; then
        $SUDO pip3 uninstall -y podman-compose || true
    fi

    show_progress "Podman removal completed"
}

# Function to install Docker
install_docker() {
    show_progress "Installing Docker prerequisites..."
    $SUDO apt-get update
    $SUDO apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    show_progress "Adding Docker's GPG key..."
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    # Get the correct Ubuntu codename
    UBUNTU_CODENAME=$(get_ubuntu_codename)
    show_progress "Using Ubuntu codename: $UBUNTU_CODENAME"

    show_progress "Adding Docker repository..."
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $UBUNTU_CODENAME stable" | \
    $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    show_progress "Installing Docker Engine..."
    $SUDO apt-get update
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Configure Docker
    show_progress "Configuring Docker..."
    $SUDO mkdir -p /etc/docker
    cat <<EOF | $SUDO tee /etc/docker/daemon.json
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

    $SUDO mkdir -p /etc/systemd/system/docker.service.d
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable docker
    $SUDO systemctl start docker
    $SUDO usermod -aG docker "$USER"
}

# Main logic
if command_exists podman; then
    show_progress "Podman found on system. Removing it..."
    remove_podman
    show_progress "Installing Docker..."
    install_docker
elif command_exists docker; then
    if command_exists docker-compose; then
        show_progress "Legacy Docker Compose found. Would you like to:"
        echo "1. Remove it and install the plugin version"
        echo "2. Keep both and create an alias for compatibility"
        read -p "Enter your choice (1 or 2): " choice

        case $choice in
            1)
                show_progress "Removing legacy Docker Compose..."
                $SUDO apt remove -y docker-compose
                $SUDO apt install -y docker-compose-plugin
                ;;
            2)
                show_progress "Creating alias for docker compose..."
                echo 'alias docker-compose="docker compose"' >> ~/.bashrc
                source ~/.bashrc
                ;;
            *)
                show_progress "Invalid choice. Keeping current setup."
                ;;
        esac
    else
        show_progress "Docker is already installed with compose plugin. No action needed."
    fi
else
    show_progress "No container runtime found. Installing Docker..."
    install_docker
fi

# Verify installation
if docker --version && docker compose version; then
    echo "
===========================================
   Docker Installation Status
   - Docker Engine: $(docker --version)
   - Docker Compose: $(docker compose version)
   
   Installation completed successfully!
   
   If you just installed Docker, please 
   log out and back in for group changes 
   to take effect.
==========================================="
fi