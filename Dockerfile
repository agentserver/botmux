# syntax=docker/dockerfile:1

# ── Build stage ──────────────────────────────────────────────────────────────
FROM node:22-bookworm-slim AS build

# Native build dependencies (node-pty C++ compilation)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make gcc g++ \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@9.5.0 --activate

WORKDIR /app

# Install dependencies (layer cached unless lockfile / package.json changes)
COPY pnpm-lock.yaml package.json ./
RUN pnpm install --frozen-lockfile

# Copy source and build
COPY . .
RUN pnpm build

# Remove devDependencies from node_modules
RUN pnpm prune --prod

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM node:22-bookworm-slim

# Runtime system dependencies:
# - tmux: default session backend (required)
# - git: project work, repo cloning, worktree
# - ca-certificates: HTTPS for API calls, Lark SDK, font downloads
# - canvas runtime libs: for @napi-rs/canvas terminal screenshot rendering
# - fonts-noto-cjk: CJK character coverage in terminal screenshots
# - fonts-noto-color-emoji: emoji rendering in screenshots
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux git ca-certificates \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libgif7 libjpeg62-turbo librsvg2-2 \
    fonts-noto-cjk fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# ── AI CLI tools ──────────────────────────────────────────────────────────────
# botmux 是桥接层，本身不包含 AI 能力。至少需要安装一个 CLI 才能工作。
# 默认安装 Codex（npm 全局包），替换/追加见下方注释。
RUN npm install -g @openai/codex
# 其他常见 CLI 安装方式（按需取消注释）：
# RUN npm install -g @anthropic-ai/claude-code  # Claude Code
# RUN npm install -g @google/gemini-cli          # Gemini CLI
# RUN npm install -g @anthropic-ai/aiden         # Aiden
# RUN npm install -g opencode-ai/opencode        # OpenCode
# RUN npm install -g cursor-talk                 # Cursor CLI
# RUN npm install -g @antigravity/cli            # Antigravity
# RUN pip install kiro-cli                       # Kiro CLI (需要 python3-pip)

# Create non-root user for daemon and CLI child processes
RUN useradd --create-home --shell /bin/bash botmux

WORKDIR /app

# Copy built artifacts from build stage
COPY --from=build --chown=botmux:botmux /app/dist ./dist
COPY --from=build --chown=botmux:botmux /app/node_modules ./node_modules
COPY --from=build --chown=botmux:botmux /app/package.json ./
COPY --from=build --chown=botmux:botmux /app/ecosystem.config.cjs ./

# Setup data directory (logs, session state)
RUN mkdir -p /app/data/logs && chown -R botmux:botmux /app/data

# Setup config directory (bots.json, config.json, .env, fonts)
RUN mkdir -p /home/botmux/.botmux && chown -R botmux:botmux /home/botmux/.botmux

# Default working directory for CLI sessions
RUN mkdir -p /home/botmux/projects && chown -R botmux:botmux /home/botmux/projects

USER botmux

ENV NODE_ENV=production
ENV SESSION_DATA_DIR=/app/data
ENV HOME=/home/botmux
ENV WORKING_DIR=/home/botmux/projects

# Dashboard & web terminal proxy ports
EXPOSE 7891 8800

CMD ["node", "dist/cli.js", "start"]