# dev-env

一个面向日常开发的通用容器镜像。默认提供完整的 Python、Node.js 和常用
Linux 开发工具，并允许按需加入 Claude Code、Codex 和 Docker 客户端。

## 设计概览

- 基于 `python:3.12-bookworm`，包含 Python 3.12、pip、venv、编译器和常见
  开发库。
- 从官方 Node.js 镜像复制 Node.js 和 npm。
- 从 Astral 官方镜像复制 `uv` 和 `uvx`。
- 提供 Git、OpenSSH Client、curl、wget、ripgrep、sudo、zip/unzip、xz、
  procps 和 psmisc 等日常工具。
- 时区为 `Asia/Shanghai`，默认工作目录是容器用户的 HOME。
- Claude Code 和 Codex 默认不安装；启用后以最终容器用户安装到
  `~/.local`，可以不使用 sudo 临时升级。
- Docker CLI、Compose 和 Buildx 默认不安装。关闭时不会解析或下载
  `docker:*` 供体镜像；开启时也只加入客户端，不包含 Docker daemon。
- 不挂载代码或 workspace，只持久化 `~/.claude` 和 `~/.codex`。

基础镜像的默认用户是 `root:0:0`。如果通过环境变量指定其他用户，构建时
会创建同名用户和用户组，并配置免密码 sudo。

## 快速使用

复制环境变量模板：

```bash
cp .env.example .env
```

根据服务器用户修改以下四项。四项应一起设置：

```dotenv
USER_NAME=zhang
USER_UID=1001
USER_GID=1001
USER_HOME=/home/zhang
```

可以通过下面的命令查看当前宿主机用户信息：

```bash
id -un
id -u
id -g
```

如果希望保留基础镜像的 root 用户，则使用：

```dotenv
USER_NAME=root
USER_UID=0
USER_GID=0
USER_HOME=/root
```

在首次启动前创建 Claude/Codex 的宿主机目录，并确保容器 UID/GID 可写：

```bash
set -a
. ./.env
set +a

sudo install -d -m 0755 -o "$USER_UID" -g "$USER_GID" \
  "$DEV_DATA_ROOT/$USER_NAME/claude" \
  "$DEV_DATA_ROOT/$USER_NAME/codex"
```

构建并进入容器：

```bash
docker compose build
docker compose run --rm dev
```

容器默认进入 `${USER_HOME}`，退出 shell 后临时容器会被删除；挂载的
Claude/Codex 配置和会话仍保留在宿主机。

## 可选组件

在 `.env` 中启用需要的组件，然后重新执行 `docker compose build`：

```dotenv
INSTALL_CLAUDE_CODE=true
INSTALL_CODEX=true
INSTALL_DOCKER_CLI=true
```

关闭组件时应将对应变量留空，不要写成 `false`。Compose 根据变量是否为空
自动为镜像标签增加后缀：

| 启用的组件 | 镜像标签示例 |
| --- | --- |
| 无 | `daily-dev:zhang` |
| Docker | `daily-dev:zhang-docker` |
| Claude Code | `daily-dev:zhang-claude` |
| Codex | `daily-dev:zhang-codex` |
| 全部 | `daily-dev:zhang-docker-claude-codex` |

也可以固定版本：

```dotenv
CLAUDE_CODE_VERSION=latest
CODEX_VERSION=latest
DOCKER_CLI_VERSION=28.2.2-cli
```

Claude Code 和 Codex 的自动更新默认关闭。可以在运行中的容器里使用 npm
手动更新，但这种 CLI 更新位于容器可写层，删除容器后不会保留；需要永久
升级时应更新版本变量并重建镜像。

## Docker 客户端

`INSTALL_DOCKER_CLI=true` 只加入以下客户端程序：

- Docker CLI
- Docker Compose 插件
- Docker Buildx 插件

Compose 配置不会自动挂载 `/var/run/docker.sock`。如需操作宿主机 Docker，
应在启动容器时显式挂载 socket，并处理容器用户与 socket 的组权限。挂载
Docker socket 基本等同于授予容器宿主机 root 权限，应只在可信环境使用。

## 持久化目录

Compose 使用以下映射：

| 宿主机 | 容器内 |
| --- | --- |
| `${DEV_DATA_ROOT}/${USER_NAME}/claude` | `${USER_HOME}/.claude` |
| `${DEV_DATA_ROOT}/${USER_NAME}/codex` | `${USER_HOME}/.codex` |

`CLAUDE_CONFIG_DIR` 和 `CODEX_HOME` 已显式指向上述目录，因此认证信息、配置
和相关状态可以随挂载目录一起保留。宿主机源目录必须预先存在，Compose
不会自动创建。
