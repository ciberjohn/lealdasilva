#!/usr/bin/env bash
set -e

# Define constants
readonly PROJECT_DIR="$HOME/OllamaAndOI"
readonly OLLAMA_INSTALL_URL="https://ollama.com/install.sh"

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Install Ollama
if ! command_exists ollama; then
  echo "Installing Ollama..."
  curl -fsSL "$OLLAMA_INSTALL_URL" | sh
  if ! command_exists ollama; then
    echo "Ollama installation failed. Exiting."
    exit 1
  fi
  echo "Ollama installed successfully."
else
  echo "Ollama is already installed."
fi

# Install Docker
if ! command_exists docker; then
  echo "Docker is not installed. Installing Docker..."
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  echo "Docker installed successfully."
else
  echo "Docker is already installed."
fi

# Install Docker Compose plugin
if ! docker compose version &> /dev/null; then
  echo "Docker Compose plugin not found. Installing it..."
  sudo apt update
  sudo apt install -y docker-compose-plugin
  if ! docker compose version &> /dev/null; then
    echo "Docker Compose plugin installation failed. Exiting."
    exit 1
  fi
  echo "Docker Compose plugin installed successfully."
else
  echo "Docker Compose plugin is already installed."
fi

# Create project directory
echo "Creating project directory: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || exit 1

# Define volume paths
readonly OLLAMA_VOLUME_PATH="$PROJECT_DIR/volumes/ollama"
readonly OPEN_WEBUI_VOLUME_PATH="$PROJECT_DIR/volumes/open-webui"

# Create docker-compose.yml file
echo "Creating docker-compose.yml file..."
cat <<EOF > docker-compose.yml
version: "3.8"
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:ollama
    container_name: open-webui
    ports:
      - "3000:8080"
    volumes:
      - $OLLAMA_VOLUME_PATH:/root/.ollama
      - $OPEN_WEBUI_VOLUME_PATH:/app/backend/data
    restart: always
volumes:
  ollama:
  open-webui:
EOF

# Create necessary directories for volumes
echo "Creating volume directories..."
mkdir -p "$OLLAMA_VOLUME_PATH"
mkdir -p "$OPEN_WEBUI_VOLUME_PATH"

# Start the Docker Compose project
echo "Starting the Docker Compose project..."
docker compose up -d --pull always
if [ $? -ne 0 ]; then
  echo "Failed to start Docker Compose project. Check the logs for errors."
  exit 1
fi

echo "Ollama is running locally on the host. Open-WebUI is now running in Docker."
echo "Access Open-WebUI at http://localhost:3000"