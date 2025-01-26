# Gyld Project

## Project Overview
Gyld is a Node.js application that integrates TiddlyWiki5, using BlueSky ATProtocol for authentication and authorization.

## Setup

### Prerequisites
Ensure the following dependencies are installed on your system:

- **Node.js & npm** (for backend)
- **Docker & Docker Compose** (for containerized services)
- **NGINX** (as a reverse proxy)
- **Python** (required for Certbot SSL management)

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

#### Deploy the Correct Configuration
```bash
bash deploy_nginx_config.sh dev        # For local development
bash deploy_nginx_config.sh production # For production deployment
```

#### Start NGINX Service
```bash
sudo service nginx start
```

### Running the Project
After installing dependencies and setting up NGINX, run the following to start all services:

```bash
docker-compose up -d
```

You can access the project via:

- **Local Development:** `http://gyld.local` (after adding to `/etc/hosts`)
- **Production:** `https://gyld.app` (with valid SSL certificates)

### Adding Hosts Entry (for local development)
Add the following entry to your `/etc/hosts` file to simulate the domain locally:

```plaintext
127.0.0.1 gyld.local
```

### Production SSL Setup with Certbot
For production deployment, Certbot is used to obtain and renew SSL certificates for the domains `gyld.app` and `gyld.social`.

#### Install Certbot and NGINX Plugin
```bash
sudo apt install certbot python3-certbot-nginx -y
```

#### Obtain SSL Certificates
```bash
sudo certbot --nginx -d gyld.app -d www.gyld.app -d gyld.social -d www.gyld.social
```

#### Renew Certificates Automatically
Certbot will automatically schedule renewal. You can manually test renewal with:
```bash
sudo certbot renew --dry-run
```

#### Update NGINX Configuration for SSL
Modify the NGINX configuration to include the SSL certificate paths provided by Certbot.

## Structure

```
gyld/
├── docker/
│   ├── docker-compose.yml
├── nginx-configs/
│   ├── nginx.dev.conf
│   ├── nginx.prod.conf
├── src/
│   ├── server.js
│   ├── auth/
│   ├── wiki/
├── .env
├── .gitignore
├── README.md
└── package.json
```

- **docker/** - Configuration files for Docker containers
- **nginx-configs/** - Contains separate NGINX configurations for local and production
- **src/** - Application source code
  - **auth/** - Authentication logic
  - **wiki/** - TiddlyWiki integrations
- **.env** - Environment variables configuration

