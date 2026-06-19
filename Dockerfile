# Multi-stage build / Production image for Minimalist Experimental AI Pipeline
FROM debian:stable-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    jq \
    tor \
    php-cli \
    git \
    figlet \
    ca-certificates \
    iconv \
    sed \
    ncurses-bin \
    &> /dev/null || apt-get install -y \
    bash curl jq tor php-cli git figlet ca-certificates sed ncurses-bin

# Install glow (Markdown renderer in terminal) if possible, or fallback
RUN curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y glow || echo "Glow not available, falling back to cat"

# Set up work directory
WORKDIR /app

# Copy all project files
COPY . .

# Ensure production scripts are executable
RUN chmod +x pipeline.sh run-tools.sh web_fetch.sh 2>/dev/null || true

# Configure Tor to run in the background
RUN echo "Log notice stdout" >> /etc/tor/torrc && \
    echo "SocksPort 0.0.0.0:9050" >> /etc/tor/torrc && \
    echo "HTTPTunnelPort 9080" >> /etc/tor/torrc

# Expose PHP server port and Tor ports
EXPOSE 8080 9050 9080

# Default entrypoint starts Tor in the background and launches interactive or pipeline mode
ENTRYPOINT ["/bin/bash", "-c", "tor & sleep 2 && ./pipeline.sh \"$@\""]
CMD ["--chat"]
