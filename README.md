# dev-env

一个面向日常开发的通用容器镜像。默认提供完整的 Python、Node.js、SSH
Server 和常用 Linux 开发工具，并允许按需加入 Claude Code、Codex 和 Docker
客户端。

## 设计概览

- 基于 `python:3.12-bookworm`，包含 Python 3.12、pip、venv、编译器和常见
  开发库。
- 从官方 Node.js 镜像复制 Node.js 和 npm。
- 从 Astral 官方镜像复制 `uv` 和 `uvx`。
- 提供 Git、OpenSSH Client、curl、wget、ripgrep、sudo、zip/unzip、xz、
  procps 和 psmisc 等日常工具。
- SSH Server 默认启动，仅允许公钥认证；授权公钥由环境变量注入，SSH host
  key 在镜像构建时生成并随镜像复用。
- `IN_MAINLAND=true` 时使用 CERNET 的 Debian、pip、uv 镜像和 npmmirror
  的 npm registry。
- 时区为 `Asia/Shanghai`，默认工作目录是容器用户的 HOME。
- Claude Code 和 Codex 默认不安装；启用后在公共阶段安装到 `/usr/local`，
  dev 和 root 分支共用同一份镜像内 CLI。dev 仍可在 `~/.local` 临时安装新版
  并通过 PATH 优先使用。
- Docker CLI、Compose 和 Buildx 默认不安装。关闭时不会解析或下载
  `docker:*` 供体镜像；开启时也只加入客户端，不包含 Docker daemon。
- Claude Code 和 Codex 数据分别固定在 `/agent-data/claude` 和
  `/agent-data/codex`，与 root/dev 的 HOME 无关。

默认构建固定的非 root 账户 `dev`，HOME 为 `/workspace`，并配置免密码
sudo。只需要让它的数字 UID/GID 与宿主机用户一致，不要求用户名一致。
root 是独立的多阶段构建分支，HOME 始终为 `/root`。

## 快速使用

复制环境变量模板：

```bash
cp .env.example .env
```

默认使用 dev 分支。根据服务器用户修改 UID/GID；容器内用户名固定为
`dev`，HOME 固定为 `/workspace`：

```dotenv
USER_MODE=dev
USER_UID=1001
USER_GID=1001
```

可以通过下面的命令查看当前宿主机用户信息：

```bash
id -u
id -g
```

如果需要 root 镜像，只切换构建分支即可；该分支忽略 `USER_UID` 和
`USER_GID`：

```dotenv
USER_MODE=root
```

两个分支完全独立，不创建 `/workspace -> /root` 软链接，Dockerfile 构建时
生成的启动脚本也不会动态推断或改写 HOME。

在 `.env` 中填写一整行用于登录的 OpenSSH 公钥，例如：

```dotenv
SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@example
```

创建 Compose 所需的 agent 数据目录：

```bash
mkdir -p ./data/claude ./data/codex
```

在远程 Linux 主机上使用 dev 分支时，目录应允许配置的 UID/GID 读写。
然后构建并进入容器：

```bash
docker compose build
docker compose run --rm dev
```

root 容器默认进入 `/root`，非 root 容器默认进入 `/workspace`。Compose 将
Claude Code 和 Codex 数据绑定到固定的 `/agent-data` 子目录，所以两种模式
使用完全相同的挂载目标；其他容器内状态不会随容器删除而保留。

## 可选组件

Claude Code、Codex 和 Docker CLI 都默认关闭。需要时在 `.env` 中分别启用，
然后重新执行 `docker compose build`：

```dotenv
INSTALL_CLAUDE=true
INSTALL_CODEX=true
INSTALL_DOCKER_CLI=true
```

关闭组件时将对应变量留空。Compose 根据非空的启用变量为镜像标签增加后缀：

| 启用的组件 | 镜像标签示例 |
| --- | --- |
| 无 | `daily-dev:dev` |
| Docker | `daily-dev:dev-docker` |
| Claude Code | `daily-dev:dev-claude` |
| Codex | `daily-dev:dev-codex` |
| 全部 | `daily-dev:dev-docker-claude-codex` |

也可以固定版本：

```dotenv
CLAUDE_VERSION=latest
CODEX_VERSION=latest
DOCKER_CLI_VERSION=28.5.1-cli
```

Claude Code 和 Codex 的自动更新默认关闭。镜像内版本由 root 安装到
`/usr/local`，应通过更新版本变量并重建镜像永久升级。dev 也可以在运行中的
容器里临时覆盖：

```bash
npm install -g \
  --allow-scripts="@anthropic-ai/claude-code" \
  @anthropic-ai/claude-code@latest
npm install -g @openai/codex@latest
hash -r
```

新版会安装到 `/workspace/.local`；该路径优先于 `/usr/local/bin`，但这种临时
覆盖位于容器可写层，删除容器后不会保留。

## 中国大陆镜像

在 `.env` 中启用：

```dotenv
IN_MAINLAND=true
```

启用后会进行以下配置：

| 工具 | 配置 |
| --- | --- |
| Debian | `https://mirrors.cernet.edu.cn/debian` 和 `https://mirrors.cernet.edu.cn/debian-security` |
| pip | `/etc/pip.conf` 中的 CERNET `global.index-url` |
| uv | `/etc/uv/uv.toml` 中的默认 CERNET index |
| npm | `/etc/npmrc` 中的 npmmirror registry |

Debian 源在安装系统包之前切换。pip、uv 和 npm 配置在公共 runtime 阶段以
系统级文件写入，dev 和 root 分支共同继承，其中 npm registry 也会用于构建
阶段可选的 Claude Code/Codex 安装。用户配置和项目配置仍可覆盖这些系统
默认值。关闭时使用 `IN_MAINLAND=false`，保留各工具的上游默认源。

Debian 的 DEB822/传统源路径和替换规则参考
[CERNET Debian 帮助](https://help.mirrors.cernet.edu.cn/debian/)与
[CERNET Debian Security 帮助](https://help.mirrors.cernet.edu.cn/debian-security/)。
CERNET 文档提醒安全更新镜像可能存在同步延迟；这里按 `IN_MAINLAND=true`
的显式选择同时切换普通仓库和安全更新仓库。

## SSH Server

SSH Server 始终启动，只接受 `authorized_keys` 中的公钥；密码认证、键盘交互
认证和空密码均已关闭。root 用户也只能使用密钥登录。默认端口只绑定到宿主机
回环地址。`SSH_PUBLIC_KEY` 可以为空，此时 SSH Server 仍会启动，但镜像不会
注入任何可用于登录的公钥：

```dotenv
SSH_BIND_IP=127.0.0.1
SSH_HOST_PORT=2222
SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@example
```

使用 `docker compose up -d` 启动长期容器后，可以从宿主机连接：

```bash
ssh -p 2222 dev@127.0.0.1
```

root 模式则使用 `root@127.0.0.1`。

如需从其他机器访问，显式设置 `SSH_BIND_IP=0.0.0.0`，并同时配置宿主机和
云平台防火墙，只开放确实需要的来源地址。SSH host key 在镜像构建时生成；
同一镜像启动的容器使用相同 host key，重新构建镜像后 key 可能变化。因为
服务端私钥存在于镜像层中，不应把该镜像发布到不可信的公共仓库。Dockerfile
生成的启动脚本会在每次启动时重写当前用户的 `~/.ssh/authorized_keys`。

## HTTP 代理

如果服务器访问外网需要 HTTP 代理，在 `.env` 中配置：

```dotenv
http_proxy=http://proxy.example.com:7890
https_proxy=http://proxy.example.com:7890
no_proxy=localhost,127.0.0.1,::1
```

Compose 会同时把大小写形式的代理变量传给镜像构建步骤和运行中的开发
容器，因此 `apt-get`、npm、Claude Code 和 Codex 都可以读取。代理值不会
通过 Dockerfile `ENV` 固化进镜像，但会出现在运行中容器的环境配置里；包含
账号密码时不要提交 `.env`。仓库的 `.gitignore` 和 `.dockerignore` 都排除了
`.env`，避免它进入 Git 或 Docker build context。

如果代理只监听在 Linux 宿主机的 `127.0.0.1`，构建容器默认无法访问它。
此时可以让构建步骤使用宿主机网络：

```dotenv
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
BUILD_NETWORK=host
```

`BUILD_NETWORK=host` 只作用于镜像构建。运行后的容器仍不能通过容器自身的
`127.0.0.1` 访问宿主机代理；运行阶段如需代理，应使用容器可达的宿主机地址，
或另外为服务配置 host 网络。代理可以从 Docker bridge 网络直接访问时，保留
默认的 `BUILD_NETWORK=default`。

## Docker 客户端

`INSTALL_DOCKER_CLI=true` 只加入以下客户端程序：

- Docker CLI
- Docker Compose 插件
- Docker Buildx 插件

Compose 配置不会自动挂载 `/var/run/docker.sock`。如需操作宿主机 Docker，
应在启动容器时显式挂载 socket，并处理容器用户与 socket 的组权限。挂载
Docker socket 基本等同于授予容器宿主机 root 权限，应只在可信环境使用。

### 检查 Docker API

挂载宿主机 Docker socket 后，在容器内执行：

```bash
docker version --format \
  'client={{.Client.Version}} client_api={{.Client.APIVersion}} server={{.Server.Version}} server_api={{.Server.APIVersion}} min_api={{.Server.MinAPIVersion}}'
docker info >/dev/null
```

CLI 与 daemon 版本不必完全一致，Docker 会自动协商双方支持的 API；不要设置
`DOCKER_API_VERSION`，否则会关闭自动协商。
