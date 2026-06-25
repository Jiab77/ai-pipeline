# Multi-stage build / Production image for Minimalist Experimental AI Pipeline
FROM debian:stable-slim

# Install system dependencies
RUN apt update && apt install -y --no-install-recommends \
    bash \
    curl \
    jq \
    tor \
    php-cli \
    git \
    figlet \
    ca-certificates \
    sed \
    openssl \
    ncurses-bin \
    && rm -rf /var/lib/apt/lists/*

# Install glow (Markdown renderer in terminal)
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y glow \
    && rm -rf /var/lib/apt/lists/* || echo "Glow not available, falling back to cat"

# Install htmlq (download precompiled binary to keep image slim)
RUN curl -L -s https://github.com/mgdm/htmlq/releases/download/v0.4.0/htmlq-x86_64-linux.tar.gz | tar -xzf - -C /usr/local/bin \
    && chmod +x /usr/local/bin/htmlq

# Set up work directory
WORKDIR /app

# Copy all project files
COPY . .

# Ensure production scripts are executable
RUN chmod +x core.sh cli.sh tools.sh tools/web-fetch.sh tools/web-browse/web-browse.js 2>/dev/null || true

# Configure Tor to run in the background
RUN echo "Log notice stdout" >> /etc/tor/torrc && \
    echo "SocksPort 0.0.0.0:9050" >> /etc/tor/torrc && \
    echo "HTTPTunnelPort 9080" >> /etc/tor/torrc

# Expose PHP server port and Tor ports
EXPOSE 8080 9050 9080

# Default entrypoint starts Tor in the background and launches interactive or pipeline mode
ENTRYPOINT ["/bin/bash", "-c", "tor & sleep 2 && ./cli.sh \"$@\""]