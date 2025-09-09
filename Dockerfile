FROM oven/bun:latest

# Base packages
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    unzip \
    bzip2 \
    procps \
    && rm -rf /var/lib/apt/lists/*
   # qwen-code use procps(pgrep), bzip2 is necessary for goose installation

# Install Node.js 20.x (for global File and modern web APIs used by qwen-code)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node -v && npm -v

# Install Agent CLIs
RUN curl -LsSf https://aider.chat/install.sh | sh
RUN CONFIGURE=false curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash
ARG NPM_REGISTRY=https://registry.npmjs.org
RUN npm config set fund false \
    && npm config set audit false \
    && npm config set progress false \
    && npm config set fetch-retries 5 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set registry "$NPM_REGISTRY"

# Install CLIs with simple retry loops for resilience
RUN set -e; \
    pkgs="@anthropic-ai/claude-code @openai/codex @google/gemini-cli @qwen-code/qwen-code opencode-ai"; \
    for pkg in $pkgs; do \
      echo "Installing $pkg"; \
      for i in 1 2 3 4 5; do \
        if npm install -g "$pkg"; then break; fi; \
        echo "Retry $i for $pkg"; \
        sleep 4; \
      done; \
    done
RUN curl -fsS https://cursor.com/install | bash

ENV PATH="/root/.local/bin:/root/.cursor/bin:${PATH}"

WORKDIR /app

COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

COPY . .

RUN npm i -g corepack@0.29.4 && corepack enable

CMD ["bash"]
