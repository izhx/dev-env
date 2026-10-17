ARG CUDA_IMAGE=nvidia/cuda:13.0.2-devel-ubuntu24.04
ARG NODE_VERSION=24-bookworm-slim
ARG UV_VERSION=0.12.5
ARG DOCKER_CLI_VERSION=28.5.1-cli

FROM node:${NODE_VERSION} AS node
FROM astral/uv:${UV_VERSION} AS uv

FROM ${CUDA_IMAGE} AS runtime-common

ARG IN_MAINLAND=false

# The CUDA base already supplies build-essential, ca-certificates, libatomic1,
# libstdc++6, procps and xz-utils. Only add the missing development tools below.
# Only replace Ubuntu repositories; leave NVIDIA's CUDA repository intact.
RUN if [ "${IN_MAINLAND}" = "true" ]; then \
        if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
            ubuntu_sources=/etc/apt/sources.list.d/ubuntu.sources; \
        elif [ -f /etc/apt/sources.list ]; then \
            ubuntu_sources=/etc/apt/sources.list; \
        else \
            echo "Ubuntu apt sources file not found" >&2; \
            exit 1; \
        fi; \
        sed -i -E \
            -e 's|https?://([a-z]{2}\.)?archive.ubuntu.com/ubuntu/?|https://mirrors.cernet.edu.cn/ubuntu/|g' \
            -e 's|https?://security.ubuntu.com/ubuntu/?|https://mirrors.cernet.edu.cn/ubuntu/|g' \
            -e 's|https?://ports.ubuntu.com/ubuntu-ports/?|https://mirrors.cernet.edu.cn/ubuntu-ports/|g' \
            "${ubuntu_sources}"; \
    fi \
    && apt-get update -o APT::Update::Error-Mode=any \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        cmake \
        curl \
        file \
        git \
        jq \
        less \
        libffi-dev \
        libssl-dev \
        ninja-build \
        openssh-client \
        openssh-server \
        pkg-config \
        psmisc \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python-is-python3 \
        ripgrep \
        sudo \
        tmux \
        tzdata \
        unzip \
        vim \
        wget \
        zip \
        zlib1g-dev \
    && ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && printf '%s\n' Asia/Shanghai > /etc/timezone \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Preserve dev-env's policy: host keys are generated at build time and reused.
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

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

COPY --from=uv /uv /uvx /usr/local/bin/

# These defaults apply to both ubuntu and root, including SSH sessions.
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
    CODEX_HOME=/agent-data/codex \
    CUDA_HOME=/usr/local/cuda \
    CUDA_PATH=/usr/local/cuda

RUN install -d -m 0755 /agent-data /opt/agent-bin-src \
    && install -d -m 0700 "${CLAUDE_CONFIG_DIR}" "${CODEX_HOME}"

EXPOSE 22

COPY --chmod=0755 assets/dev-env-entrypoint /usr/local/bin/dev-env-entrypoint
RUN /bin/sh -n /usr/local/bin/dev-env-entrypoint \
    && python3 --version && node --version && npm --version && uv --version \
    && nvcc --version

# Preserve NVIDIA's entrypoint hooks before injecting agents and starting SSH.
ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh", "/usr/local/bin/dev-env-entrypoint"]
CMD ["bash"]

FROM runtime-common AS ubuntu-runtime

ARG USER_UID=1000
ARG USER_GID=1000

# Reuse the stock ubuntu account and /home/ubuntu. Only change its numeric
# identity when requested, preserving the account's existing supplementary groups.
RUN if [ "${USER_UID}" = "0" ] || [ "${USER_GID}" = "0" ]; then \
        echo "ubuntu mode requires non-zero USER_UID and USER_GID" >&2; \
        exit 1; \
    fi \
    && groupmod --gid "${USER_GID}" ubuntu \
    && usermod --uid "${USER_UID}" --gid "${USER_GID}" ubuntu \
    && printf '%s\n' 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && chown -R ubuntu:ubuntu /home/ubuntu /agent-data

ENV HOME=/home/ubuntu \
    USER=ubuntu \
    LOGNAME=ubuntu \
    NPM_CONFIG_PREFIX=/home/ubuntu/.local \
    PATH=/home/ubuntu/.local/bin:${PATH}

USER ubuntu
WORKDIR /home/ubuntu
RUN install -d -m 0700 "${HOME}/.ssh"

FROM runtime-common AS root-runtime

ENV HOME=/root \
    USER=root \
    LOGNAME=root \
    NPM_CONFIG_PREFIX=/root/.local \
    PATH=/root/.local/bin:${PATH}

USER root
WORKDIR /root
RUN install -d -m 0700 "${HOME}/.ssh"

FROM docker:${DOCKER_CLI_VERSION} AS docker-cli

FROM ubuntu-runtime AS ubuntu-docker-false

FROM ubuntu-runtime AS ubuntu-docker-true
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ \
    /usr/local/libexec/docker/cli-plugins/

FROM root-runtime AS root-docker-false

FROM root-runtime AS root-docker-true
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ \
    /usr/local/libexec/docker/cli-plugins/

FROM ubuntu-docker-false AS final
