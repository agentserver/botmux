# syntax=docker/dockerfile:1

# Build the agentserver fork from source so the image contains the reviewed
# all-interface Web binding and authentication integration, rather than the
# upstream npm artifact with the same version number.
FROM node:trixie-slim AS dsh-fork-builder
ARG DSH_REPOSITORY=https://github.com/agentserver/deepseek-harness.git
ARG DSH_REF=7a7650576061b7ffd73bb95a313abddfe7a50c40
ARG PNPM_VERSION=11.7.0
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates python3 make g++ \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g "pnpm@${PNPM_VERSION}"
WORKDIR /src/deepseek-harness
RUN git init \
    && git remote add origin "${DSH_REPOSITORY}" \
    && git fetch --depth 1 origin "${DSH_REF}" \
    && git checkout --detach FETCH_HEAD
RUN pnpm install --frozen-lockfile
RUN pnpm build
RUN pnpm --filter @deepseek-ai/dsh deploy --prod --legacy /opt/dsh-runtime

# botmux 基础镜像：安装 GitHub Release 的自包含二进制。
FROM node:trixie-slim

# Runtime system dependencies:
# - tmux: default session backend (required)
# - git/curl/ca-certificates: project work and HTTPS
# - canvas libraries/fonts: terminal screenshots
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux git curl ca-certificates sudo vim zsh python3 iproute2 iputils-ping \
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

ARG DSH_VERSION=0.2.1-alpha.1
ARG PNPM_VERSION=11.7.0
RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
    && mkdir -p /home/node/.dsh \
    && chown -R node:node /home/node/.dsh \
    && DSH_HOME=/home/node/.dsh dsh --version \
    && pnpm --version \
    && npm cache clean --force

COPY --from=dsh-fork-builder /opt/dsh-runtime /opt/dsh-runtime
RUN ln -sf /opt/dsh-runtime/node_modules/.bin/dsh /usr/local/bin/dsh \
    && DSH_HOME=/home/node/.dsh dsh --version

# Preinstall the two managed dsh profiles. The Kubernetes init container only
# copies these files into the persistent home; it never resolves packages from
# the network during Pod startup.
COPY deploy/dsh-profiles /opt/dsh-profiles
RUN set -eux; \
    for profile in web botmux; do \
      cd "/opt/dsh-profiles/${profile}"; \
      pnpm install --config.strict-peer-dependencies=false --ignore-scripts --reporter=append-only; \
    done; \
    chown -R node:node /opt/dsh-profiles

WORKDIR /home/node

# App home and default CLI working directory.
RUN mkdir -p /home/node/.botmux \
    && chown -R node:node /home/node

USER node

ENV NODE_ENV=production
ENV SESSION_DATA_DIR=/home/node/.botmux/data
ENV HOME=/home/node
ENV WORKING_DIR=/home/node
ENV DSH_HOME=/home/node/.dsh

# 用最终的非 root 身份校验二进制。
RUN command -v botmux && botmux --version \
    && command -v codex && codex --version \
    && command -v dsh && dsh --version \
    && command -v pnpm && pnpm --version

# Dashboard & web terminal proxy ports
EXPOSE 7891 8800

# botmux 二进制位于 /usr/local/bin。
CMD ["botmux", "start"]
