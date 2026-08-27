ARG PYTHON_VERSION=3.12-bookworm
ARG NODE_VERSION=24-bookworm-slim
ARG UV_VERSION=0.12.5
ARG DOCKER_CLI_VERSION=28.5.1-cli

FROM node:${NODE_VERSION} AS node
FROM astral/uv:${UV_VERSION} AS uv

FROM python:${PYTHON_VERSION} AS runtime-common

ARG IN_MAINLAND=false
ARG INSTALL_CLAUDE=false
ARG INSTALL_CODEX=false
ARG CLAUDE_VERSION=latest
ARG CODEX_VERSION=latest

RUN if [ "${IN_MAINLAND}" = "true" ]; then \
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
            debian_sources=/etc/apt/sources.list.d/debian.sources; \
        elif [ -f /etc/apt/sources.list ]; then \
            debian_sources=/etc/apt/sources.list; \
        else \
            echo "Debian apt sources file not found" >&2; \
            exit 1; \
        fi; \
        sed -i \
            -e 's|http://deb.debian.org/debian-security|https://mirrors.cernet.edu.cn/debian-security|g' \
            -e 's|https://deb.debian.org/debian-security|https://mirrors.cernet.edu.cn/debian-security|g' \
            -e 's|http://security.debian.org/debian-security|https://mirrors.cernet.edu.cn/debian-security|g' \
            -e 's|https://security.debian.org/debian-security|https://mirrors.cernet.edu.cn/debian-security|g' \
            -e 's|http://deb.debian.org/debian|https://mirrors.cernet.edu.cn/debian|g' \
            -e 's|https://deb.debian.org/debian|https://mirrors.cernet.edu.cn/debian|g' \
            "${debian_sources}"; \
    fi \
    && apt-get update -o APT::Update::Error-Mode=any \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server \
        psmisc \
        ripgrep \
        sudo \
        tmux \
        unzip \
        vim \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Keep the key-only SSH policy and generated host keys entirely in the image.
RUN install -d -m 0755 /run/sshd /etc/ssh/sshd_config.d \
    && printf '%s\n' \
        'PubkeyAuthentication yes' \
        'AuthenticationMethods publickey' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'ChallengeResponseAuthentication no' \
        'PermitEmptyPasswords no' \
        'PermitRootLogin prohibit-password' \
        > /etc/ssh/sshd_config.d/10-key-only.conf \
    && ssh-keygen -A \
    && /usr/sbin/sshd -t

# Generate the runtime entrypoint in the image; keep it out of the build
# context while retaining a readable, normal shell script.
RUN printf '%s\n' \
        '#!/bin/sh' \
        'set -eu' \
        '' \
        'install -d -m 0700 "${HOME}/.ssh"' \
        ': > "${HOME}/.ssh/authorized_keys"' \
        'if [ -n "${SSH_PUBLIC_KEY:-}" ]; then' \
        '    printf "%s\n" "${SSH_PUBLIC_KEY}" > "${HOME}/.ssh/authorized_keys"' \
        'fi' \
        'chmod 0600 "${HOME}/.ssh/authorized_keys"' \
        'sudo install -d -m 0755 /run/sshd' \
        'sudo /usr/sbin/sshd -t' \
        'sudo /usr/sbin/sshd' \
        '' \
        'exec "$@"' \
        > /usr/local/bin/dev-env-entrypoint \
    && chmod 0755 /usr/local/bin/dev-env-entrypoint

# Reuse Node.js and npm from the official Node image.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Reuse uv and uvx from Astral's official distroless image.
COPY --from=uv /uv /uvx /usr/local/bin/

# Apply package mirrors system-wide so both dev and root inherit them. User and
# project configuration can still override these defaults.
RUN if [ "${IN_MAINLAND}" = "true" ]; then \
        printf '%s\n' \
            '[global]' \
            'index-url = https://mirrors.cernet.edu.cn/pypi/web/simple' \
            > /etc/pip.conf; \
        install -d -m 0755 /etc/uv; \
        printf '%s\n' \
            '[[index]]' \
            'url = "https://mirrors.cernet.edu.cn/pypi/web/simple"' \
            'default = true' \
            > /etc/uv/uv.toml; \
        printf '%s\n' \
            'registry=https://registry.npmmirror.com' \
            > /etc/npmrc; \
        chmod 0644 /etc/pip.conf /etc/uv/uv.toml /etc/npmrc; \
    fi

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai \
    DISABLE_AUTOUPDATER=1 \
    NPM_CONFIG_GLOBALCONFIG=/etc/npmrc \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    UV_LINK_MODE=copy \
    CLAUDE_CONFIG_DIR=/agent-data/claude \
    CODEX_HOME=/agent-data/codex

# Install optional agent CLIs once into the system npm prefix. Runtime users
# keep writable state under /agent-data and may temporarily override these
# versions by installing newer packages into their own npm prefix.
RUN install -d -m 0755 /agent-data \
    && install -d -m 0700 \
        "${CLAUDE_CONFIG_DIR}" \
        "${CODEX_HOME}" \
    && if [ "${INSTALL_CLAUDE}" = "true" ]; then \
        npm install --global \
            --allow-scripts="@anthropic-ai/claude-code" \
            "@anthropic-ai/claude-code@${CLAUDE_VERSION}"; \
    fi \
    && if [ "${INSTALL_CODEX}" = "true" ]; then \
        npm install --global "@openai/codex@${CODEX_VERSION}"; \
    fi \
    && if [ "${INSTALL_CLAUDE}" = "true" ] \
        || [ "${INSTALL_CODEX}" = "true" ]; then \
        npm cache clean --force; \
    fi \
    && if [ "${INSTALL_CLAUDE}" = "true" ]; then claude --version; fi \
    && if [ "${INSTALL_CODEX}" = "true" ]; then codex --version; fi

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/dev-env-entrypoint"]
CMD ["bash"]

# The default branch always creates the fixed non-root account dev. Only its
# numeric UID/GID are configurable so bind-mount ownership can match the host.
FROM runtime-common AS dev-runtime

ARG USER_UID=1000
ARG USER_GID=1000

RUN if [ "${USER_UID}" = "0" ] || [ "${USER_GID}" = "0" ]; then \
        echo "dev mode requires non-zero USER_UID and USER_GID" >&2; \
        exit 1; \
    fi \
    && groupadd --gid "${USER_GID}" dev \
    && useradd \
        --uid "${USER_UID}" \
        --gid "${USER_GID}" \
        --home-dir /workspace \
        --create-home \
        --no-log-init \
        --shell /bin/bash \
        dev \
    && printf '%s\n' 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev

# /agent-data comes from the common root-owned stage. Give dev ownership of its
# writable agent state before switching users.
RUN chown -R dev:dev /agent-data

ENV HOME=/workspace \
    USER=dev \
    LOGNAME=dev \
    NPM_CONFIG_PREFIX=/workspace/.local \
    PATH=/workspace/.local/bin:${PATH}

USER dev
WORKDIR /workspace

RUN install -d -m 0700 "${HOME}/.ssh"

# The root branch leaves /root intact and has no /workspace compatibility link.
FROM runtime-common AS root-runtime

ENV HOME=/root \
    USER=root \
    LOGNAME=root \
    NPM_CONFIG_PREFIX=/root/.local \
    PATH=/root/.local/bin:${PATH}

USER root
WORKDIR /root

RUN install -d -m 0700 "${HOME}/.ssh"

# Docker CLI is a separate donor so the default targets do not pull it.
FROM docker:${DOCKER_CLI_VERSION} AS docker-cli

FROM dev-runtime AS dev-docker-false

FROM dev-runtime AS dev-docker-true
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ \
    /usr/local/libexec/docker/cli-plugins/

FROM root-runtime AS root-docker-false

FROM root-runtime AS root-docker-true
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ \
    /usr/local/libexec/docker/cli-plugins/

# Plain `docker build .` produces the dev, Docker-CLI-free image.
FROM dev-docker-false AS final
