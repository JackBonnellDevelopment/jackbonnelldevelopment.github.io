# Use Node.js LTS as base image (supports ARM64)
FROM node:20-bookworm

# Set platform to ensure ARM64 support
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Install Hugo Extended
# Hugo Extended requires additional dependencies for SCSS/SASS support
RUN apt-get update && apt-get install -y \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Hugo Extended (latest version that supports ARM64)
# Using the official Hugo binary release
ARG HUGO_VERSION=0.128.0
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then \
        wget -O /tmp/hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-arm64.tar.gz \
        && tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin/ \
        && rm /tmp/hugo.tar.gz \
        && chmod +x /usr/local/bin/hugo; \
    else \
        wget -O /tmp/hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz \
        && tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin/ \
        && rm /tmp/hugo.tar.gz \
        && chmod +x /usr/local/bin/hugo; \
    fi

# Verify Hugo installation
RUN hugo version

# Create a non-root user
RUN useradd -m -s /bin/bash vscode \
    && mkdir -p /home/vscode/.npm \
    && chown -R vscode:vscode /home/vscode

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER vscode

# Set environment variables
ENV NODE_ENV=development
ENV PATH="/home/vscode/.local/bin:${PATH}"

