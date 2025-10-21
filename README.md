# Automated Docker Deployment Script

**Stage 1 of the HNG13 Devops track**

The task given was to create a bash script file, `deploy.sh`, that will automate the setup, configuration and deployment of a Dockerized application of choice. These are the prerequisites required for this task.

### 1. Collect Parameters from User Input

Prompt for and validate:
- Git Repository URL
- Personal Access Token (PAT)
- Remote server SSH details:
  - Username
  - Server IP address
  - SSH key path
- Application port (internal container port)

### 2. Clone the Repository

- Authenticate and clone the repo using the PAT
- If it already exists, pull the latest changes instead
- Switch to the specified branch

### 3. Navigate into the Cloned Directory

- Automatically `cd` into the cloned project folder
- Verify that a `Dockerfile` or `docker-compose.yml` exists
- Log success or failure

### 4. SSH into the Remote Server

- Establish SSH connection with provided credentials
- Perform connectivity checks (ping or SSH dry-run)
- Execute remaining commands remotely (`ssh user@ip "commands..."`)

### 5. Prepare the Remote Environment

On the remote host:
- Update system packages
- Install Docker, Docker Compose, and Nginx (if missing)
- Add user to Docker group (if needed)
- Enable and start services
- Confirm installation versions

### 6. Deploy the Dockerized Application

- Transfer project files (via `scp` or `rsync`)
- Navigate to project directory
- Build and run containers (`docker build` + `docker run` or `docker-compose up -d`)
- Validate container health and logs
- Confirm app accessibility on the specified port

### 7. Configure Nginx as a Reverse Proxy

- Dynamically create or overwrite Nginx config
- Forward HTTP (port 80) traffic to container's internal port
- Ensure SSL readiness (optional self-signed cert or Certbot placeholder)
- Test config and reload Nginx

### 8. Validate Deployment

Confirm that:
- Docker service is running
- The target container is active and healthy
- Nginx is proxying correctly
- Test endpoint using `curl` or `wget` locally and remotely

### 9. Implement Logging and Error Handling

- Log all actions (success/failure) to a timestamped log file (e.g., `deploy_YYYYMMDD.log`)
- Include trap functions for unexpected errors
- Use meaningful exit codes per stage

### 10. Ensure Idempotency and Cleanup

- Script should safely re-run without breaking existing setups
- Gracefully stop/remove old containers before redeployment
- Prevent duplicate Docker networks or Nginx configs
- (Optional) Include a `--cleanup` flag to remove all deployed resources

  **NOTE** Cleanup is important if you are executing the script again.

## Lessons learnt
1. Remote connection to a Linux server. Check out this [article](https://medium.com/@martinmnjoroge03/ssh-remote-connection-potential-issue-47187a2a19a8) to see what I learnt when starting this task.
2. Creating logs and updating them through a bash script.
3. Docker:
  - Reminded myself on how to build and run a containerized application. [Repo](https://github.com/Muturi-002/Go-docker-proto)
  - Checking container logs for container health
4. Error handling
  - Handling multiple errors through multiple exit codes.
5. NGINX
  - Learnt how to configure a proxy to a container's port.
6. GitHub
  - Generating a Personal Access Token
7. Debugging script using log files