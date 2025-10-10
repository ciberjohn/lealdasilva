#!/bin/bash

# Function to display progress
show_progress() {
    echo "===> $1"
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    show_progress "Requesting sudo privileges"
    SUDO="sudo"
else
    SUDO=""
fi

# Check if Docker is installed
if command -v docker &> /dev/null; then
    show_progress "Docker found on system. Proceeding with removal..."
    
    # Stop Docker service
    show_progress "Stopping Docker service..."
    $SUDO systemctl stop docker docker.socket containerd
    
    # Disable Docker service
    show_progress "Disabling Docker service..."
    $SUDO systemctl disable docker docker.socket containerd
    
    # Remove Docker packages
    show_progress "Removing Docker packages..."
    if command -v apt &> /dev/null; then
        $SUDO apt remove -y docker-ce docker-ce-cli containerd.io docker docker.io
        $SUDO apt autoremove -y
    elif command -v dnf &> /dev/null; then
        $SUDO dnf remove -y docker-ce docker-ce-cli containerd.io docker docker.io
        $SUDO dnf autoremove -y
    elif command -v yum &> /dev/null; then
        $SUDO yum remove -y docker-ce docker-ce-cli containerd.io docker docker.io
        $SUDO yum autoremove -y
    fi
else
    show_progress "Docker not found on system. Proceeding with Podman check..."
fi

# Install required dependencies based on the package manager
show_progress "Installing required dependencies..."
if command -v apt &> /dev/null; then
    $SUDO apt update
    $SUDO apt install -y \
        runc \
        conmon \
        crun \
        slirp4netns \
        fuse-overlayfs \
        containernetworking-plugins
elif command -v dnf &> /dev/null; then
    $SUDO dnf install -y \
        runc \
        conmon \
        crun \
        slirp4netns \
        fuse-overlayfs \
        containernetworking-plugins
elif command -v yum &> /dev/null; then
    $SUDO yum install -y \
        runc \
        conmon \
        crun \
        slirp4netns \
        fuse-overlayfs \
        containernetworking-plugins
fi

# Check if Podman is already installed
if command -v podman &> /dev/null; then
    show_progress "Podman is already installed!"
else
    # Install Podman
    show_progress "Installing Podman..."
    if command -v apt &> /dev/null; then
        $SUDO apt install -y podman podman-docker
    elif command -v dnf &> /dev/null; then
        $SUDO dnf install -y podman podman-docker
    elif command -v yum &> /dev/null; then
        $SUDO yum install -y podman podman-docker
    else
        show_progress "Error: Unable to determine package manager. Please install Podman manually."
        exit 1
    fi
fi

# Check if Podman Compose is already installed
if command -v podman-compose &> /dev/null; then
    show_progress "Podman Compose is already installed!"
else
    # Install Podman Compose
    show_progress "Installing Podman Compose..."
    if command -v pip3 &> /dev/null; then
        $SUDO pip3 install podman-compose
    else
        show_progress "Installing Python pip first..."
        if command -v apt &> /dev/null; then
            $SUDO apt install -y python3-pip
        elif command -v dnf &> /dev/null; then
            $SUDO dnf install -y python3-pip
        elif command -v yum &> /dev/null; then
            $SUDO yum install -y python3-pip
        fi
        $SUDO pip3 install podman-compose
    fi
fi

# Configure Podman to use runc as the default runtime
show_progress "Configuring Podman runtime..."
mkdir -p ~/.config/containers/
cat <<EOF > ~/.config/containers/containers.conf
[engine]
runtime = "runc"
EOF

# Restart Podman system service if it exists
if systemctl is-active --quiet podman.socket; then
    show_progress "Restarting Podman service..."
    $SUDO systemctl restart podman.socket
fi

echo "
===========================================
   Thank you for choosing Podman! 
   Your system is now ready to use 
   Podman and Podman Compose.
   The following components have been installed:
   - runc (OCI runtime)
   - conmon (container monitor)
   - crun (alternative OCI runtime)
   - slirp4netns (rootless networking)
   - fuse-overlayfs (rootless storage)
   - containernetworking-plugins
   Happy containerization!
==========================================="