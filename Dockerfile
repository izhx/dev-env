ARG PYTHON_VERSION=3.12-bookworm
ARG NODE_VERSION=24-bookworm-slim
ARG UV_VERSION=0.12.5
ARG DOCKER_CLI_VERSION=28.2.2-cli

FROM node:${NODE_VERSION} AS node
FROM astral/uv:${UV_VERSION} AS uv

FROM python:${PYTHON_VERSION} AS runtime

ARG USER_NAME=root
ARG USER_UID=0
ARG USER_GID=0
ARG USER_HOME=/root
ARG INSTALL_CLAUDE_CODE=false
ARG INSTALL_CODEX=false
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        psmisc \
        ripgrep \
        sudo \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Reuse Node.js and npm from the official Node image.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Reuse uv and uvx from Astral's official distroless image.
COPY --from=uv /uv /uvx /usr/local/bin/

# Keep the base image's root user when the defaults are unchanged. A custom
# user gets a matching group, home directory, and passwordless sudo.
RUN if [ "${USER_NAME}" = "root" ]; then \
        if [ "${USER_UID}" != "0" ] \
            || [ "${USER_GID}" != "0" ] \
            || [ "${USER_HOME}" != "/root" ]; then \
            echo "root requires USER_UID=0 USER_GID=0 USER_HOME=/root" >&2; \
            exit 1; \
        fi; \
    else \
        if [ "${USER_UID}" = "0" ] \
            || [ "${USER_GID}" = "0" ] \
            || [ "${USER_HOME}" = "/root" ]; then \
            echo "a custom user requires non-root UID/GID and home" >&2; \
            exit 1; \
        fi; \
        groupadd --gid "${USER_GID}" "${USER_NAME}"; \
        useradd \
            --uid "${USER_UID}" \
            --gid "${USER_GID}" \
            --home-dir "${USER_HOME}" \
            --create-home \
            --no-log-init \
            --shell /bin/bash \
            "${USER_NAME}"; \
        printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USER_NAME}" \
            > "/etc/sudoers.d/${USER_NAME}"; \
        chmod 0440 "/etc/sudoers.d/${USER_NAME}"; \
    fi

ENV HOME=${USER_HOME} \
    USER=${USER_NAME} \
    LOGNAME=${USER_NAME} \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai \
    DISABLE_AUTOUPDATER=1 \
    NPM_CONFIG_PREFIX=${USER_HOME}/.local \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    UV_LINK_MODE=copy \
    CLAUDE_CONFIG_DIR=${USER_HOME}/.claude \
    CODEX_HOME=${USER_HOME}/.codex \
    PATH=${USER_HOME}/.local/bin:${PATH}

USER ${USER_NAME}
WORKDIR ${USER_HOME}

# Install optional npm CLIs into the selected user's home. Both are disabled by
# default; user-local ownership also permits temporary upgrades without sudo.
RUN if [ "${INSTALL_CLAUDE_CODE}" = "true" ]; then \
        npm install --global "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"; \
    fi \
    && if [ "${INSTALL_CODEX}" = "true" ]; then \
        npm install --global "@openai/codex@${CODEX_VERSION}"; \
    fi \
    && if [ "${INSTALL_CLAUDE_CODE}" = "true" ] \
        || [ "${INSTALL_CODEX}" = "true" ]; then \
        npm cache clean --force; \
    fi \
    && if [ "${INSTALL_CLAUDE_CODE}" = "true" ]; then claude --version; fi \
    && if [ "${INSTALL_CODEX}" = "true" ]; then codex --version; fi

CMD ["bash"]

# Compose selects docker-false by default, so the Docker donor image is outside
# the build graph and is not pulled. docker-true adds only client-side tools.
FROM runtime AS docker-false

FROM docker:${DOCKER_CLI_VERSION} AS docker-cli

FROM runtime AS docker-true
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ \
    /usr/local/libexec/docker/cli-plugins/

# Plain `docker build .` is also Docker-CLI-free unless a target is selected.
FROM docker-false AS final
