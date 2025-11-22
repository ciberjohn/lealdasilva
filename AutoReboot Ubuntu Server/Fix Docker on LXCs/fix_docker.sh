#!/bin/bash

# 1. Fix the Repository Mismatch
echo "--- Fixing Docker Repository (Jammy -> Noble) ---"

# Find the file defining the docker repo. Usually /etc/apt/sources.list.d/docker.list
# We use sed to replace 'jammy' with 'noble' inside that file.
if grep -q "jammy" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
    sed -i 's/jammy/noble/g' /etc/apt/sources.list.d/docker.list
    echo "Updated docker.list to use Noble."
elif grep -q "jammy" /etc/apt/sources.list 2>/dev/null; then
    sed -i 's/jammy/noble/g' /etc/apt/sources.list
    echo "Updated sources.list to use Noble."
else
    echo "Could not automatically find the file with 'jammy' inside. Continuing anyway to see if apt-get update fixes it..."
fi

# 2. Update the catalog
echo "--- Updating Apt Catalog ---"
apt-get update

# 3. Perform the Downgrade
echo "--- Installing containerd.io 1.7.28 for Noble ---"

# Note: The version string for Noble is usually slightly different. 
# We force this specific version which is known to work with LXC.
apt-get install -y --allow-downgrades containerd.io=1.7.28-1~ubuntu.24.04~noble

if [ $? -eq 0 ]; then
    echo "--- Success! ---"
    apt-mark hold containerd.io
    echo "containerd.io held at 1.7.28."
    
    systemctl restart docker
    echo "Docker restarted. Try running your containers now."
else
    echo "--- Failed ---"
    echo "Could not find the specific package version. Run 'apt-cache policy containerd.io' to see what is available now that the repo is fixed."
fi