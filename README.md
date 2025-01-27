# Gyld Project

## Project Overview
Gyld is a Node.js application that integrates TiddlyWiki5's new `multi-wiki-support` branch, using BlueSky ATProtocol for authentication and authorization.

## Setup

### Prerequisites
Ensure the following dependencies are installed on your WSL system:

- **NVM, Node.js & npm** (for backend)
- **Docker & Docker Compose** (for containerized services)
- **NGINX** (as a reverse proxy)
- **Python** (required for Certbot SSL management and other scripts)
- **yq (YAML CLI)** (safely edit `docker-compose.yml` when adding or removing subdomains)

### Install Project Dependencies
```bash
npm install
```

### Install and Configure NGINX

#### Install NGINX on Ubuntu (WSL)
```bash
sudo apt update
sudo apt install nginx -y
```

#### Verify NGINX Installation
```bash
nginx -v
```

#### Deploy the Correct Configuration and Start NGINX
```bash
bash deploy_nginx_config.sh dev        # For local HTTP development
bash deploy_nginx_config.sh production # For production/HTTPS deployment
```

### Running the Project
After installing dependencies and setting up NGINX, run the following to start all services:

```bash
docker-compose up -d
```

You can access the project via:

- **Local Development:** `http://gyld.local` (after adding to `/etc/hosts`)
- **Production:** `https://gyld.app` (with valid SSL certificates)

### Adding Hosts Entry (for Local Development)
Add the following entry to your `/etc/hosts` file to simulate the domain locally:

```plaintext
127.0.0.1 gyld.local
```

### Production SSL Setup with Certbot
For production deployment, Certbot is used to obtain and renew SSL certificates for the domain `gyld.app`.

#### Install Certbot and NGINX Plugin
```bash
sudo apt install certbot python3-certbot-nginx -y
```

#### Obtain SSL Certificates
```bash
sudo certbot --nginx -d gyld.app -d www.gyld.app
```

#### Renew Certificates Automatically
Certbot will automatically schedule renewal. You can manually test renewal with:
```bash
sudo certbot renew --dry-run
```

#### Update NGINX Configuration for SSL
Modify the NGINX configuration to include the SSL certificate paths provided by Certbot.

---

**Project Structure Highlights**  
- **docker/** - Configuration files for Docker containers  
- **nginx-configs/** - Contains separate NGINX configurations for local and production  
- **src/** - Application source code  
  - **auth/** - Authentication logic  
- **.env** - Environment variables configuration  

---

## Managing Subdomains with `yq`

When adding or removing MWS subdomains, we want to cleanly manipulate the `docker-compose.yml` file—especially for removing service blocks—without breaking YAML indentation. We use [`yq`](https://github.com/mikefarah/yq) to reliably parse and edit YAML.

### Installing `yq` on Linux
```bash
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
chmod +x /usr/bin/yq
```

This installs `yq` to `/usr/bin` and makes it executable. You can verify by running:
```bash
yq --version
```

After installing `yq`, you can use the provided `add_subdomain.sh` and `remove_subdomain.sh` scripts to manage subdomains without YAML formatting issues.
