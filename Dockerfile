FROM vaultwarden/server:alpine

# Install dependencies
RUN apk add --no-cache bash curl tzdata sqlite rclone

# Install Litestream based on architecture
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        curl -L https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-arm64.tar.gz | tar -xz -C /usr/local/bin; \
    else \
        curl -L https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.tar.gz | tar -xz -C /usr/local/bin; \
    fi

# Copy our custom entrypoint script and litestream config
COPY entrypoint.sh /entrypoint.sh
COPY litestream.yml /etc/litestream.yml
RUN chmod +x /entrypoint.sh

# Environment settings
ENV ROCKET_PORT=8080
ENV PORT=8080

# Expose the Cloudflare HTTP supported port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
