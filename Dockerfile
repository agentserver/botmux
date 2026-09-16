# syntax=docker/dockerfile:1

# botmux 基础镜像：安装 GitHub Release 的自包含二进制。
FROM node:trixie-slim

# Runtime system dependencies:
# - tmux: default session backend (required)
# - git/curl/ca-certificates: project work and HTTPS
# - canvas libraries/fonts: terminal screenshots
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux git curl ca-certificates sudo vim zsh \
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

RUN CODEX_INSTALL_DIR=/usr/local/bin CODEX_HOME=/usr/local/share/codex CODEX_NON_INTERACTIVE=1 \
    sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | sh'; \
    chown -R node:node /usr/local/share/codex /usr/local/bin/codex /usr/local/bin/codex-code-mode-host; \
    codex --version

WORKDIR /home/node

# App home and default CLI working directory.
RUN mkdir -p /home/node/.botmux \
    && chown -R node:node /home/node

USER node

ENV NODE_ENV=production
ENV SESSION_DATA_DIR=/home/node/.botmux/data
ENV HOME=/home/node
ENV WORKING_DIR=/home/node

# 用最终的非 root 身份校验二进制。
RUN command -v botmux && botmux --version && command -v codex && codex --version

# Dashboard & web terminal proxy ports
EXPOSE 7891 8800

# botmux 二进制位于 /usr/local/bin。
CMD ["botmux", "start"]
