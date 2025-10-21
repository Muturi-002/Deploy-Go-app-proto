#!/bin/bash

# Deployment logging and error handling
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="deploy_${TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Trap function for unexpected errors
trap 'echo "ERROR: Script failed at line $LINENO. Exit code: $?" | tee -a "$LOG_FILE"; exit 99' ERR

# Set script options
set -euo pipefail

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "$LOG_FILE"
}

log_info "Starting deployment script. Log file: $LOG_FILE"

# Cleanup function for removing all deployed resources
cleanup_deployment() {
    log_info "=========> Starting cleanup process..."
    
    if [ -z "${SERVER_USER:-}" ] || [ -z "${SERVER_ADDRESS:-}" ]; then
        log_error "Server details not available for cleanup. Please provide SERVER_USER and SERVER_ADDRESS."
        exit 1
    fi
    
    log_info "Stopping and removing Docker containers..."
    ssh "$SERVER_USER@$SERVER_ADDRESS" "
        docker stop hng13-devops-go-app 2>/dev/null || true
        docker rm hng13-devops-go-app 2>/dev/null || true
        docker rmi hng13-devops-go-app 2>/dev/null || true
    " || log_error "Failed to cleanup Docker containers"
    
    log_info "Removing Nginx configuration..."
    ssh "$SERVER_USER@$SERVER_ADDRESS" "
        sudo rm -f /etc/nginx/sites-available/go-app
        sudo rm -f /etc/nginx/sites-enabled/go-app
        sudo systemctl reload nginx 2>/dev/null || true
    " || log_error "Failed to cleanup Nginx configuration"
    
    log_info "Removing deployment directory..."
    ssh "$SERVER_USER@$SERVER_ADDRESS" "rm -rf ~/Go-Docker" || log_error "Failed to remove deployment directory"
    
    log_success "Cleanup completed successfully!"
    echo "All deployed resources have been removed from the remote server."
    exit 0
}

# Check for cleanup flag
if [ "${1:-}" = "--cleanup" ]; then
    echo "========> Cleanup Mode Activated"
    echo "This will remove all deployed resources from the remote server."
    echo ""
    read -p "Enter your Remote Server Address (IP/Hostname): " SERVER_ADDRESS
    read -p "Enter your Remote Server Username: " SERVER_USER
    read -p "Enter the path to your SSH key: " SSH_KEY_PATH
    
    # Validate SSH connection for cleanup
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_error "SSH key not found at: $SSH_KEY_PATH"
        exit 2
    fi
    
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SERVER_USER@$SERVER_ADDRESS" "echo SSH_OK" 2>&1 >/dev/null
    if [ "$?" -ne 0 ]; then
        log_error "SSH connection failed. Cannot perform cleanup."
        exit 3
    fi
    
    cleanup_deployment
fi

echo "========> Let's get started with deployment!!!"
echo "----------------"
echo ""
echo "These are the details needed to proceed with your deployment:"
echo "1. GitHub Repository URL- this is the URL of the repository with source code for your dockerized application. Give the full URL!!"
echo "2. Personal Access Token (PAT)- a token that allows access to your GitHub repository for a limited period of time."
echo "3. Remote Server Address details- the IP address, the username and ssh key path (within local machine) of the remote server where the application will be deployed."
echo "4. Application Port- the internal port of your dockerized application."
echo "5. Private Key Path- the path to your SSH private key for authentication to the remote server. MUST BE ABSOLUTE!!"

echo ""
read -p "Enter your GitHub Repo URL: " REPO_URL
read -p "Enter your Personal Access Token (PAT): " PAT
read -p "Enter your Remote Server Address (IP/Hostname): " SERVER_ADDRESS
read -p "Enter your Remote Server Username: " SERVER_USER
read -p "Enter the path to your SSH key: " SSH_KEY_PATH
read -p "Enter your Application Port: " APP_PORT

echo ""
echo "GitHub Repo URL: $REPO_URL"
echo "Personal Access Token (PAT): $PAT"
echo "Remote Server IP Address: $SERVER_ADDRESS"
echo "Remote Server Username: $SERVER_USER"
echo "SSH Key Path: $SSH_KEY_PATH"
echo "Application Port: $APP_PORT" 

PARENT_DIR=$(pwd)

### SSH connectivity dry-run
ssh_dry_run() {
    log_info "Performing SSH dry-run to $SERVER_USER@$SERVER_ADDRESS using key $SSH_KEY_PATH"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_error "SSH key not found at: $SSH_KEY_PATH"
        exit 2
    fi

    # Attempt Dry run SSH connection
    ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$SERVER_USER@$SERVER_ADDRESS" "echo SSH_OK" 2>&1 >/dev/null
    if [ "$?" -ne 0 ]; then
        log_error "SSH dry-run failed. Please check server address, username, and key permissions."
        exit 3
    fi

    log_success "SSH dry-run succeeded. Remote host reachable and authenticated."
}

echo ""
echo "----------------"
echo ""

echo "=========> Cloning Repo provided using PAT...."

# Extract repository name from URL for proper cloning
REPO_NAME=$(basename "$REPO_URL" .git)
log_info "Repository name: $REPO_NAME"

if [ -d "$REPO_NAME" ]; then
    log_info "Directory $REPO_NAME already exists. Updating repository..."
    cd "$REPO_NAME"
    git pull origin main
    log_success "Repository updated successfully"
else
    log_info "Cloning repository from $REPO_URL"
    
    # Construct authenticated GitHub URL with PAT (expects full GitHub URL)
    if [[ "$REPO_URL" == https://github.com/* ]]; then
        # Remove https://github.com/ prefix and reconstruct with PAT
        REPO_PATH="${REPO_URL#https://github.com/}"
        NEW_REPO_URL="https://$PAT@github.com/$REPO_PATH.git"
    else
        log_error "Invalid repository URL format. Please provide a full GitHub URL!"
        exit 1
    fi
    
    git clone "$NEW_REPO_URL"

    if [ -d "$REPO_NAME" ] && [ -d "$REPO_NAME/.git" ]; then
        log_success "Repository cloned successfully!"
        cd "$REPO_NAME"
        git pull origin main
    else
        log_error "Failed to clone repo. Please check the URL and PAT provided"
        exit 1
    fi
fi
echo ""
echo "----------------"
echo ""

log_info "Checking for Docker-related files in repository..."
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
    log_success "Docker-related files found in the repository."
else
    log_error "No Docker-related files found in the repository. Ensure you have a Docker-related file."
    exit 1
fi

echo ""
echo "----------------"
echo ""

echo "=========> Test SSH Connection to Remote server with dry-run..."

ssh_dry_run

echo "------> Add private key to ssh-agent..."
echo "SSH-Agent running : $(eval "$(ssh-agent -s)")"
ssh-add "$SSH_KEY_PATH"
echo Confirm key is added: $(ssh-add -l)

echo ""
echo "----------------"
echo ""

log_info "Preparing environment on remote server..."
log_info "Cleaning up any corrupted repository configurations..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "
    # Remove any corrupted Docker repository files
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker.list.save
"

log_info "Updating system packages..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo apt-get update"
log_success "System packages updated"

log_info "Installing Docker and Docker Compose if not present..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "
    if command -v docker >/dev/null 2>&1 && command -v docker compose >/dev/null 2>&1; then
        echo 'Docker and Docker-Compose already installed'
        echo 'Docker Version:' \$(docker --version)
        echo 'Docker-Compose Version:' \$(docker compose version)
    else 
        echo 'Installing latest versions of Docker and Docker-Compose...'
        sudo apt install curl ca-certificates -y 
        sudo mkdir -p /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc 
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        echo Docker and Docker-Compose installed successfully
        echo Docker Version: $(docker --version)
        echo Docker-Compose Version: $(docker compose version)

        sudo systemctl enable docker
        sudo systemctl start docker
    fi"

log_info "Adding $SERVER_USER to docker group..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo usermod -aG docker \$USER"

log_info "Installing NGINX if not present..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "
    if command -v nginx >/dev/null 2>&1; then 
        echo 'NGINX is already installed'
        nginx -v 2>&1
    else 
        sudo apt-get install nginx -y
        sudo systemctl enable nginx
        sudo systemctl start nginx
        echo 'NGINX installed successfully'
        nginx -v 2>&1
    fi"

log_success "Remote environment preparation completed"

echo ""
echo "----------------"
echo ""
log_info "=========> Deploying Dockerized Application on remote server..."
log_info "Creating deployment directory..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "rm -rf Go-Docker && mkdir -p Go-Docker"

log_info "Transferring project files..."
scp -r "$PARENT_DIR/$REPO_NAME"/* "$SERVER_USER@$SERVER_ADDRESS:~/Go-Docker/" || { 
    log_error "File transfer failed"; 
    exit 4; 
}
log_success "Project files transferred successfully"

log_info "Building and deploying Docker container..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "
    cd Go-Docker
    
    if docker ps -q --filter name=hng13-devops-go-app | grep -q .; then
        log_info 'Stopping existing container...'
        docker stop hng13-devops-go-app
    fi
    
    if docker ps -aq --filter name=hng13-devops-go-app | grep -q .; then
        log_info 'Removing existing container...'
        docker rm hng13-devops-go-app
    fi
    
    if docker images -q hng13-devops-go-app | grep -q .; then
        log_info 'Removing existing image for clean build...'
        docker rmi hng13-devops-go-app 2>/dev/null || true
    fi

    echo 'Building new Docker image...'
    docker build -t hng13-devops-go-app .
    
    echo 'Starting new container...'
    docker run -d -p $APP_PORT:$APP_PORT --name hng13-devops-go-app --restart unless-stopped hng13-devops-go-app
" || { 
    log_error "Docker deployment failed"; 
    exit 5; 
}
log_success "Docker container deployed successfully"

log_info "Validating Container Health..."
log_info "Checking container status..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "echo \"\$(docker ps -a --filter name=hng13-devops-go-app --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}')\""

log_info "Checking container logs..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "echo \"\$(docker logs hng13-devops-go-app)\""

log_info "Testing application accessibility on port $APP_PORT..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sleep 5 && curl -f -s http://localhost:$APP_PORT > /dev/null" || { 
    log_error "App not accessible on port $APP_PORT"; 
    exit 6; 
}
log_success "Application is accessible on port $APP_PORT"

echo ""
echo "----------------"
echo ""
log_info "=========> Configuring Nginx Reverse Proxy..."
log_info "Creating Nginx configuration for reverse proxy..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo tee /etc/nginx/sites-available/go-app > /dev/null <<EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF"

log_info "Enabling the site and removing default..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo ln -sf /etc/nginx/sites-available/go-app /etc/nginx/sites-enabled/"
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo rm -f /etc/nginx/sites-enabled/default"

log_info "Testing Nginx configuration..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo nginx -t" || { 
    log_error "Nginx config test failed"; 
    exit 7; 
}

log_info "Reloading Nginx..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo systemctl restart nginx" || { 
    log_error "Nginx reload failed"; 
    exit 8; 
}
log_success "Nginx reverse proxy configured successfully"

echo ""
echo "----------------"
echo ""
log_info "=========> Validating Complete Deployment..."
log_info "Checking Docker service status..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sudo systemctl is-active docker" || { 
    log_error "Docker service not running"; 
    exit 9; 
}

log_info "Verifying container health..."
CONTAINER_STATUS=$(ssh "$SERVER_USER@$SERVER_ADDRESS" "docker inspect hng13-devops-go-app --format '{{.State.Status}}'")
if [ "$CONTAINER_STATUS" != "running" ]; then
    log_error "Container not running. Status: $CONTAINER_STATUS"
    exit 10
fi

log_info "Testing Nginx proxy..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "curl -f -s http://localhost/ > /dev/null" || { 
    log_error "Nginx proxy test failed"; 
    exit 11; 
}

log_info "Testing external accessibility..."
curl -f -s "http://$SERVER_ADDRESS/" > /dev/null || { 
    log_error "External access test failed"; 
    exit 12; 
}

echo ""
echo "----------------"
echo ""

log_info "=========> Cleanup and Finalization..."
echo "Sleeping for 1 minute to ensure all services stabilize..."
ssh "$SERVER_USER@$SERVER_ADDRESS" "sleep 60"

echo ""
echo "----------------"
echo ""

log_success "=========> Deployment Complete! ========="
log_success "Application deployed successfully"
log_success "Container running on port $APP_PORT"  
log_success "Nginx proxy configured on port 80"
log_success "External access verified"

echo ""
echo "View the application at: http://$SERVER_ADDRESS/"
echo "Container status: $(ssh "$SERVER_USER@$SERVER_ADDRESS" "docker ps --filter name=hng13-app --format '{{.Status}}'")"
echo ""
log_info "Deployment completed at: $(date)"
log_info "Log file saved as: $LOG_FILE"
