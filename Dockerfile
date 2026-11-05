# Multi-stage / Production image for Jarvis (AI Pipeline) v1.9.0
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    gawk \
    sed \
    grep \
    coreutils \
    curl \
    ca-certificates \
    gnupg \
    jq \
    tor \
    git \
    figlet \
    openssl \
    ncurses-bin \
    socat \
    ffmpeg \
    libimage-exiftool-perl \
    file \
    procps \
    php-cli \
    && rm -rf /var/lib/apt/lists/*

# 2. Install glow (terminal Markdown renderer via official Charm repo)
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y --no-install-recommends glow \
    && rm -rf /var/lib/apt/lists/* || echo "Glow not available, falling back to cat"

# 3. Install official static prebuilt binaries (htmlq, websocat, curl-impersonate)
RUN curl -sfL https://github.com/mgdm/htmlq/releases/latest/download/htmlq-x86_64-linux.tar.gz | tar -xz -C /usr/local/bin htmlq \
    && chmod +x /usr/local/bin/htmlq \
    && curl -sfL https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-unknown-linux-musl -o /usr/local/bin/websocat \
    && chmod +x /usr/local/bin/websocat \
    && curl -sfL https://github.com/lexiforest/curl-impersonate/releases/download/v2.3.2/curl-impersonate-v2.3.2.x86_64-linux-gnu.tar.gz | tar -xz -C /usr/local/bin curl-impersonate \
    && chmod +x /usr/local/bin/curl-impersonate

# 4. Set up application work directory
WORKDIR /app

# Copy project files
COPY . .

# Ensure all scripts and tools are executable
RUN chmod +x *.sh engines/*.sh plugins/*.sh tools/*.sh 2>/dev/null || true

# 5. Configure Tor with ControlPort for JarNet and SOCKS proxy
RUN echo "Log notice stdout" >> /etc/tor/torrc && \
    echo "SocksPort 0.0.0.0:9050" >> /etc/tor/torrc && \
    echo "ControlPort 9051" >> /etc/tor/torrc && \
    echo "CookieAuthentication 1" >> /etc/tor/torrc && \
    echo "HTTPTunnelPort 9080" >> /etc/tor/torrc

# Expose Tor SOCKS, HTTP Tunnel, ControlPort and optional local web server
EXPOSE 8080 9050 9051 9080

# Default entrypoint starts Tor in background and forwards all arguments to cli.sh
ENTRYPOINT ["/bin/bash", "-c", "tor & sleep 2 && ./cli.sh \"$@\"", "--"]
