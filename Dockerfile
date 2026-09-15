# syntax=docker/dockerfile:1

# botmux 基础镜像：安装 GitHub Release 的自包含二进制。
FROM node:22-bookworm-slim

# Runtime system dependencies:
# - tmux: default session backend (required)
# - git: project work, repo cloning, worktree
# - ca-certificates: HTTPS for API calls, Lark SDK, font downloads
# - canvas runtime libs: for @napi-rs/canvas terminal screenshot rendering
# - fonts-noto-cjk: CJK character coverage in terminal screenshots
# - fonts-noto-color-emoji: emoji rendering in screenshots
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux git curl ca-certificates \
    libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libgif7 libjpeg62-turbo librsvg2-2 \
    fonts-noto-cjk fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

ARG BOTMUX_VERSION=latest
RUN set -eux; \
    version="${BOTMUX_VERSION}"; \
    case "$version" in latest) ;; v*) ;; *) version="v${version}" ;; esac; \
    BOTMUX_VERSION="$version" BOTMUX_INSTALL_DIR=/usr/local/bin \
      sh -c 'curl -fsSL https://raw.githubusercontent.com/deepcoldy/botmux/master/install.sh | sh'; \
    botmux --version; \
    if [ "$version" != latest ]; then test "$(botmux --version)" = "${version#v}"; fi

# ── AI CLI tools ──────────────────────────────────────────────────────────────
# botmux 是桥接层，本身不包含 AI 能力。至少需要安装一个 CLI 才能工作。
# 默认安装 Codex（npm 全局包，预编译二进制，无需工具链），替换/追加见下方注释。
RUN npm install -g @openai/codex
# 其他常见 CLI 安装方式（按需取消注释）：
# RUN npm install -g @anthropic-ai/claude-code  # Claude Code
# RUN npm install -g @google/gemini-cli          # Gemini CLI
# RUN npm install -g @anthropic-ai/aiden         # Aiden
# RUN npm install -g opencode-ai/opencode        # OpenCode
# RUN npm install -g cursor-talk                 # Cursor CLI
# RUN npm install -g @antigravity/cli            # Antigravity
# RUN pip install kiro-cli                       # Kiro CLI (需先重新装 python3 + python3-pip)

# Run as the non-root `node` user that already ships with the base image
# (uid/gid 1000). No dedicated account needed — reusing `node` avoids a
# redundant user and the uid drift a fresh `useradd` would introduce.
WORKDIR /app

# Setup data directory (logs, session state). SESSION_DATA_DIR 指向这里（绝对路径）。
RUN mkdir -p /app/data/logs && chown -R node:node /app/data

# App home: config dir (bots.json, config.json, .env, fonts) + default CLI
# working dir. /home/botmux isn't the `node` user's passwd home (/home/node),
# so chown the whole tree to make $HOME (set below) fully writable by `node`
# — git config, tool caches and session state all land here at runtime.
RUN mkdir -p /home/botmux/.botmux /home/botmux/projects \
    && chown -R node:node /home/botmux

USER node

ENV NODE_ENV=production
ENV SESSION_DATA_DIR=/app/data
ENV HOME=/home/botmux
ENV WORKING_DIR=/home/botmux/projects

# 用最终的非 root 身份校验二进制。
RUN command -v botmux && botmux --version

# Dashboard & web terminal proxy ports
EXPOSE 7891 8800

# botmux 二进制位于 /usr/local/bin。
CMD ["botmux", "start"]
