# syntax=docker/dockerfile:1

# botmux 基础镜像：直接从 npm 全局安装已发布的 botmux（不再从源码编译）。
# 版本由 BOTMUX_VERSION 控制（默认 latest）；CI 可 --build-arg 固定到某次发版的
# 版本号，让 :master / :sha-xxx 这些镜像 tag 的内容可复现。
#
# ⚠️ 语义变化：镜像内是「npm 上发布的 botmux」，与当前构建的源码 commit 解耦——
#    发版只在打 v* tag 时发生，故 :master 镜像可能滞后于 master 上尚未发版的改动。
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

# 从 npm 全局安装 botmux（bin: botmux → dist/cli.js，落到 /usr/local/bin）。
# node-pty 是原生模块、无预编译产物（见 package.json 的 onlyBuiltDependencies），
# npm 安装时需 C/C++ 工具链现场编译；故临时装 python3/make/gcc/g++，装完在同一层
# purge——编译出的 .node 留在全局 node_modules 里，工具链不进最终 layer，镜像保持精简。
ARG BOTMUX_VERSION=latest
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 make gcc g++; \
    npm install -g "botmux@${BOTMUX_VERSION}"; \
    npm cache clean --force; \
    apt-get purge -y python3 make gcc g++; \
    apt-get autoremove -y --purge; \
    rm -rf /var/lib/apt/lists/* /root/.npm

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

# Dashboard & web terminal proxy ports
EXPOSE 7891 8800

# botmux 已全局安装，bin 在 PATH（/usr/local/bin/botmux）——用绝对命令启动，
# 不再依赖 WORKDIR 下的相对入口（旧版是 `node dist/cli.js`，依赖 WORKDIR=/app）。
CMD ["botmux", "start"]
