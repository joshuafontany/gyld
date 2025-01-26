#!/bin/bash

# Project root directory
PROJECT_ROOT=$(pwd)

echo "Setting up Gyld project structure at $PROJECT_ROOT"

# Create necessary directories
mkdir -p \
    docker \
    src/auth \
    src/wiki

# Create necessary files
touch \
    docker/docker-compose.yml \
    src/server.js \
    .env \
    .gitignore \
    README.md

# Populate .gitignore
cat <<EOL > .gitignore
node_modules/
.env
*.log
.DS_Store
EOL

# Populate README.md
cat <<EOL > README.md
# Gyld Project

## Project Overview
Gyld is a Node.js application that integrates TiddlyWiki5, using BlueSky ATProtocol for authentication and authorization.

## Setup
\`\`\`bash
npm install
bash setup_project.sh
docker-compose up -d
\`\`\`

## Structure
- **docker/** - Configuration files for Docker containers
- **src/** - Application source code
  - **auth/** - Authentication logic
  - **wiki/** - TiddlyWiki integrations
- **.env** - Environment variables configuration

EOL

# Populate docker-compose.yml
cat <<EOL > docker/docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: gyld_db
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  pds:
    image: atproto/pds:latest
    environment:
      - DATABASE_URL=postgres://admin:secret@postgres:5432/gyld_db
    depends_on:
      - postgres
    ports:
      - "2583:2583"

  tiddlywiki:
    image: node:latest
    working_dir: /app
    volumes:
      - .:/app
    command: ["npx", "tiddlywiki", "wiki", "--listen", "host=0.0.0.0"]
    ports:
      - "8080:8080"

volumes:
  pgdata:
EOL

# Populate src/server.js
cat <<EOL > src/server.js
const express = require('express');
const app = express();
require('dotenvx').load();

app.get('/', (req, res) => {
  res.send('Welcome to Gyld!');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(\`Gyld server running on port \${PORT}\`);
});
EOL

echo "Project structure setup complete."

# Instructions for next steps
echo "Next steps:"
echo "1. Review the created files."
echo "2. Run 'docker-compose up -d' to start services."
echo "3. Access the app via http://localhost."

exit 0
