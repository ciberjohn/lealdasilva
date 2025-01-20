# Instructions to Install Ollama and Open-WebUI with GPU (NVIDIA) support

This guide provides step-by-step instructions to install **Ollama** directly on the host using its official installation script and set up **Open-WebUI** in Docker Compose. All configurations and data for Open-WebUI and Ollama will be hosted under `$HOME/OllamaAndOI`.

---

## **1. Overview**

We will:

1. Install Ollama directly on the host using its official script.
2. Set up Open-WebUI using Docker Compose, based on the `docker run` command.
3. Store all configuration and data under `$HOME/OllamaAndOI`.
4. Provide a single script to automate the setup.

---

## **2. Single Installation Script**

Save the following script as `setup_ollama_and_openwebui.sh`:

```bash
#!/bin/bash
set -e

# Define project directory
PROJECT_DIR="$HOME/OllamaAndOI"

# Install Ollama on the host
if ! command -v ollama &> /dev/null; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "Ollama is already installed."
fi

# Verify Ollama installation
if ! command -v ollama &> /dev/null; then
  echo "Ollama installation failed. Exiting."
  exit 1
fi

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Installing Docker..."
  sudo apt update && sudo apt install -y ca-certificates curl gnupg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io
fi

# Ensure Docker Compose is available
if ! docker compose version &> /dev/null; then
  echo "Docker Compose plugin not found. Installing it..."
  sudo apt update && sudo apt install -y docker-compose-plugin
fi

# Create project directory
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create docker-compose.yml file
cat <<EOF > docker-compose.yml
version: "3.8"
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:ollama
    container_name: open-webui
    ports:
      - "3000:8080"
    volumes:
      - ollama:/root/.ollama
      - open-webui:/app/backend/data
    deploy:
      resources:
        reservations:
          devices:
          - driver: "nvidia"
            count: all
            capabilities: ["gpu"]
    restart: always
volumes:
  ollama:
  open-webui:
EOF

# Create necessary directories for volumes
mkdir -p "$PROJECT_DIR/volumes/open-webui"
mkdir -p "$PROJECT_DIR/volumes/ollama"

# Start the Docker Compose project
docker compose up -d

echo "Ollama is running locally on the host. Open-WebUI is now running in Docker. Access Open-WebUI at http://localhost:3000"
```

---

## **3. How to Use the Script**

1. Save the script to a file named `setup_ollama_and_openwebui.sh`.
2. Make it executable:
   ```bash
   chmod +x setup_ollama_and_openwebui.sh
   ```
3. Run the script:
   ```bash
   ./setup_ollama_and_openwebui.sh
   ```

---

## **4. Access Open-WebUI**

Once the script completes, you can access Open-WebUI in your browser at:

```
http://localhost:3000
```


All data for **Open-WebUI** will be stored under `$HOME/OllamaAndOI/volumes/open-webui`, and data for **Ollama** will be stored under `$HOME/OllamaAndOI/volumes/ollama`. Ollama runs locally on the host, and Open-WebUI is set up in Docker Compose with GPU support enabled.

---

# Instructions to Install Ollama and Open-WebUI with CPU-Only Support

This guide provides step-by-step instructions to install **Ollama** directly on the host using its official installation script and set up **Open-WebUI** in Docker Compose. This installation method uses a single container image that bundles **Open-WebUI** with **Ollama**. All configurations and data for Open-WebUI and Ollama will be hosted under `$HOME/OllamaAndOI`.

---

## **1. Overview**

We will:

1. Install Ollama directly on the host using its official script.
2. Set up Open-WebUI using Docker Compose, based on the `docker run` command.
3. Store all configuration and data under `$HOME/OllamaAndOI`.
4. Provide a single script to automate the setup.

---

## **2. Single Installation Script**

Save the following script as `setup_ollama_and_openwebui.sh`:

```bash
#!/bin/bash
set -e

# Define project directory
PROJECT_DIR="$HOME/OllamaAndOI"

# Install Ollama on the host
if ! command -v ollama &> /dev/null; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "Ollama is already installed."
fi

# Verify Ollama installation
if ! command -v ollama &> /dev/null; then
  echo "Ollama installation failed. Exiting."
  exit 1
fi

# Ensure Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Installing Docker..."
  sudo apt update && sudo apt install -y ca-certificates curl gnupg
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io
fi

# Ensure Docker Compose is available
if ! docker compose version &> /dev/null; then
  echo "Docker Compose plugin not found. Installing it..."
  sudo apt update && sudo apt install -y docker-compose-plugin
fi

# Create project directory
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create docker-compose.yml file
cat <<EOF > docker-compose.yml
version: "3.8"
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:ollama
    container_name: open-webui
    ports:
      - "3000:8080"
    volumes:
      - ollama:/root/.ollama
      - open-webui:/app/backend/data
    restart: always
volumes:
  ollama:
  open-webui:
EOF

# Create necessary directories for volumes
mkdir -p "$PROJECT_DIR/volumes/open-webui"
mkdir -p "$PROJECT_DIR/volumes/ollama"

# Start the Docker Compose project
docker compose up -d

echo "Ollama is running locally on the host. Open-WebUI is now running in Docker. Access Open-WebUI at http://localhost:3000"
```

---

## **3. How to Use the Script**

1. Save the script to a file named `setup_ollama_and_openwebui.sh`.
2. Make it executable:
   ```bash
   chmod +x setup_ollama_and_openwebui.sh
   ```
3. Run the script:
   ```bash
   ./setup_ollama_and_openwebui.sh
   ```

---

## **4. Access Open-WebUI**

Once the script completes, you can access Open-WebUI in your browser at:

```
http://localhost:3000
```

All data for **Open-WebUI** will be stored under `$HOME/OllamaAndOI/volumes/open-webui`, and data for **Ollama** will be stored under `$HOME/OllamaAndOI/volumes/ollama`. Ollama runs locally on the host, and Open-WebUI is set up in Docker Compose for CPU-only support.



