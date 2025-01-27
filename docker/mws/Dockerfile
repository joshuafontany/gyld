# Updated to Node 23 base
FROM node:23
# Accept build arguments for private keys
ARG DOTENV_PRIVATE_KEY
ARG DOTENV_PRIVATE_KEY_PRODUCTION

# Set environment variables from build arguments
ENV DOTENV_PRIVATE_KEY=$DOTENV_PRIVATE_KEY
ENV DOTENV_PRIVATE_KEY_PRODUCTION=$DOTENV_PRIVATE_KEY_PRODUCTION

# Install system dependencies
RUN apt-get update && apt-get install -y \
  git \
  sqlite3 \
  && rm -rf /var/lib/apt/lists/*

# Install dotenvx globally
RUN npm install -g @dotenvx/dotenvx

# Create the app directory
WORKDIR /app

# Clone your *fork* of TiddlyWiki multi-wiki-support branch
RUN git clone -b multi-wiki-support --single-branch \
    https://github.com/joshuafontany/TiddlyWiki5 /app/TiddlyWiki5

# Install TiddlyWiki MWS dependencies
WORKDIR /app/TiddlyWiki5
RUN npm install

# Expose default MWS port inside the container
EXPOSE 8080

# Output encrypted value and plain text SUBDOMAINS during build
RUN dotenvx run --quiet -- sh -c 'echo "Encrypted SUBDOMAINS: $SUBDOMAINS"'

# Default command placeholder to be overridden in docker-compose
CMD dotenvx run -f .env -- node ./tiddlywiki.js ./editions/${WIKI_FOLDER} --mws-listen $HOST $PORT
