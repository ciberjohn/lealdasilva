#!/bin/bash

# --- 1. Permission Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./fix_docker_universal.sh)"
  exit 1
fi

# --- 2. Dynamic OS Detection ---
echo "--- Detecting System Information ---"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    CURRENT_CODENAME=$VERSION_CODENAME
else
    CURRENT_CODENAME=$(lsb_release -cs)
fi

echo "Detected OS Codename: $CURRENT_CODENAME"

# --- 3. Repository Repair ---
# We check if the docker list file exists and if it points to the WRONG codename
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
# Sometimes it's named differently, check common default
if [ ! -f "$DOCKER_LIST" ]; then
    DOCKER_LIST=$(grep -l "download.docker.com" /etc/apt/sources.list.d/* | head -n 1)
fi

if [ -f "$DOCKER_LIST" ]; then
    echo "Checking Docker repository file: $DOCKER_LIST"
    
    # If the file DOES NOT contain the current codename, but contains 'jammy' or 'focal' etc
    if ! grep -q "$CURRENT_CODENAME" "$DOCKER_LIST"; then
        echo "MISMATCH DETECTED: Repo file does not match OS ($CURRENT_CODENAME)."
        echo "Backing up and patching repository file..."
        cp "$DOCKER_LIST" "${DOCKER_LIST}.bak"
        
        # Regex to replace whatever old codename (word between stable and arch, or just the codename) 
        # This sed command blindly swaps any distribution codename for the current one in that file
        # It looks for the standard docker.list format
        sed -i "s/ubuntu \([a-z]*\) stable/ubuntu $CURRENT_CODENAME stable/g" "$DOCKER_LIST"
        
        echo "Repository patched to point to $CURRENT_CODENAME."
    else
        echo "Repository looks correct (matches $CURRENT_CODENAME)."
    fi
else
    echo "WARNING: Could not find a dedicated docker.list file. Skipping repo repair step."
fi

# --- 4. Update Lists ---
echo "--- Updating Apt Catalog ---"
apt-get update -qq

# --- 5. Find Safe Version (1.7.x) ---
echo "--- Searching for Safe containerd.io (1.7.x) ---"

# We query the policy, filter for 1.7., and grab the first one (highest 1.7 available)
# This works regardless of whether it's Debian, Ubuntu, Noble, or Jammy.
TARGET_VERSION=$(apt-cache madison containerd.io | awk '{print $3}' | grep '1.7.' | head -n 1)

if [ -z "$TARGET_VERSION" ]; then
    echo "ERROR: Could not find any 1.7.x version of containerd.io."
    echo "If you are using the default Ubuntu packages (docker.io), uninstall them and install official docker-ce."
    exit 1
fi

echo "Target Safe Version Identified: $TARGET_VERSION"

# --- 6. Execute Downgrade ---
echo "--- Installing & Holding Version ---"
apt-get install -y --allow-downgrades containerd.io="$TARGET_VERSION"

if [ $? -eq 0 ]; then
    apt-mark hold containerd.io
    echo "SUCCESS: containerd.io downgraded and held at $TARGET_VERSION"
    
    echo "--- Restarting Docker ---"
    systemctl restart docker
    
    echo "--- Verification ---"
    docker version | grep "Version"
    echo "You can now start your containers."
else
    echo "FAILED: Apt install failed."
    exit 1
fi