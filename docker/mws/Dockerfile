# Example: Node 18 base
FROM node:18-bullseye

# Install system dependencies
RUN apt-get update && apt-get install -y \
  git \
  sqlite3 \
  && rm -rf /var/lib/apt/lists/*

# Create the app directory
WORKDIR /app

# Clone your *fork* of TiddlyWiki multi-wiki-support branch
# You can adjust the URL/branch as needed
RUN git clone -b multi-wiki-support --single-branch \
    https://github.com/joshuafontany/TiddlyWiki5 /app/TiddlyWiki5

# Install TiddlyWiki MWS dependencies
WORKDIR /app/TiddlyWiki5
RUN npm install

# Expose default MWS port inside the container
EXPOSE 8080

# By default, just show help
CMD ["npm", "start"]
