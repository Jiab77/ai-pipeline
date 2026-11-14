# Multi-stage / Production image for Jarvis (AI Pipeline) v1.9.4
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
    chafa \
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

# Tor is fully configured by the embedded config/torrc (single source of truth):
# cli.sh detects Tor at boot and starts it itself with `tor -f config/torrc`.
# SOCKS/ControlPort bind to loopback only — nothing Tor-related is exposed.

# Expose the local web server port
EXPOSE 8080

# Forward all arguments to cli.sh (it self-manages Tor)
ENTRYPOINT ["/bin/bash", "-c", "exec ./cli.sh \"$@\"", "--"]
