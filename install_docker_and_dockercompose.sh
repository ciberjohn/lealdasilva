#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
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

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    show_progress "Requesting sudo privileges"
    SUDO="sudo"
else
    SUDO=""
fi

# Install prerequisites
show_progress "Installing prerequisites..."
$SUDO apt-get update
$SUDO apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Add Docker's official GPG key using more secure method
show_progress "Adding Docker's GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
show_progress "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
show_progress "Installing Docker Engine..."
$SUDO apt-get update
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Configure Docker to use systemd as cgroup driver
show_progress "Configuring Docker daemon..."
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

# Create systemd directory for Docker
$SUDO mkdir -p /etc/systemd/system/docker.service.d

# Restart Docker
show_progress "Restarting Docker daemon..."
$SUDO systemctl daemon-reload
$SUDO systemctl restart docker
$SUDO systemctl enable docker

# Add user to Docker group
show_progress "Adding current user to Docker group..."
$SUDO usermod -aG docker "$USER"
newgrp docker

# Verify installations
show_progress "Verifying installations..."
docker --version
docker compose version

# Test Docker installation
show_progress "Testing Docker installation..."
docker run --rm hello-world

# Cleanup
show_progress "Cleaning up..."
$SUDO apt-get clean
$SUDO apt-get autoremove -y

echo "
===========================================
   Docker Installation Complete!
   - Docker Engine is installed
   - Docker Compose plugin is installed
   - Docker service is enabled
   - Current user added to docker group
   
   Please log out and back in for 
   group changes to take effect.
==========================================="