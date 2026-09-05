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
- SSH Server 默认启动，仅允许公钥认证；授权公钥从宿主机 SSH 目录复制，也可由环境变量覆盖，SSH host
  key 在镜像构建时生成并随镜像复用。
- `IN_MAINLAND=true` 时使用 CERNET 的 Debian、pip、uv 镜像和 npmmirror
  的 npm registry。
- 时区为 `Asia/Shanghai`，默认工作目录是容器用户的 HOME。
- Claude Code 和 Codex 不在构建时安装；启动时从只读目录复制原生二进制到
  `/usr/local/bin`，dev 和 root 分支使用相同逻辑。
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

两个分支完全独立，不创建 `/workspace -> /root` 软链接。启动脚本位于
`assets/dev-env-entrypoint`，构建时复制进镜像，不会动态推断或改写 HOME。

可在 `.env` 中填写一整行用于登录的 OpenSSH 公钥，覆盖复制的 authorized_keys，例如：

```dotenv
SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@example
```

创建 Compose 所需的二进制源目录和 agent 数据目录：

```bash
mkdir -p ~/.ssh ./agent-bin ./data/claude ./data/codex
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

### Claude Code 和 Codex

在 `.env` 中指定宿主机二进制目录，默认值为：

```dotenv
AGENT_BIN_DIR=./agent-bin
```

将与容器 CPU 架构匹配的 Linux 原生二进制放入该目录，分别命名为 `codex`
和 `claude`。可以只提供其中一个，也可以保留空目录；目录必须预先创建。
请放置实际文件，避免使用指向挂载目录以外的软链接。macOS 二进制和 npm
入口脚本不适用。

Compose 将该目录只读挂载到 `/opt/agent-bin-src`。每次启动时，entrypoint
在启动 SSH 前将存在的二进制复制到 `/usr/local/bin`，设置为 `0755` 权限，
并通过临时文件加重命名替换旧版本；不可读文件或复制失败会中止启动。
dev 分支通过已有的免密码 sudo 完成复制，配置数据仍保存在 `/agent-data`。

更新宿主机源文件后，执行 `docker compose restart dev` 即可在下次启动时
重新复制，无需重建镜像。首次从旧版构建时安装方案迁移，仍需构建并重新创建
容器；修改挂载目录后也需要重新创建容器。缺少某个源文件时跳过该命令，
不会删除同一容器内已复制的旧版本；重新创建容器后只包含当前提供的命令。

如果 HOME 下已有 `~/.local/bin/codex` 或 `claude`，它们仍可能因 PATH
顺序优先使用；可用 `command -v codex` 和 `command -v claude` 检查。

### Docker CLI

Docker CLI 默认关闭，需要时在 `.env` 中设置并重新构建：

```dotenv
INSTALL_DOCKER_CLI=true
DOCKER_CLI_VERSION=28.5.1-cli
```

关闭时设置 `INSTALL_DOCKER_CLI=false`，留空或不设置也按 `false` 处理。
镜像标签保持以下名称：

| 用户模式 | Docker CLI 关闭 | Docker CLI 开启 |
| --- | --- | --- |
| dev | `daily-dev:dev` | `daily-dev:dev-docker` |
| root | `daily-dev:root` | `daily-dev:root-docker` |

Claude Code/Codex 版本由挂载的文件决定，不影响镜像标签。
`compose.yaml` 按开关值从 `assets/compose.images.yaml` 选择镜像名；该文件只提供
配置片段，不会启动额外容器。复制 Compose 配置到其他机器时需一并复制该文件。

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
系统级文件写入，dev 和 root 分支共同继承。用户配置和项目配置仍可覆盖这些系统
默认值。关闭时使用 `IN_MAINLAND=false`，保留各工具的上游默认源。

Debian 的 DEB822/传统源路径和替换规则参考
[CERNET Debian 帮助](https://help.mirrors.cernet.edu.cn/debian/)与
[CERNET Debian Security 帮助](https://help.mirrors.cernet.edu.cn/debian-security/)。
CERNET 文档提醒安全更新镜像可能存在同步延迟；这里按 `IN_MAINLAND=true`
的显式选择同时切换普通仓库和安全更新仓库。

## SSH Server

默认将运行 Compose 的宿主机用户的 `~/.ssh` 只读挂载到 `/opt/ssh-src`。
可在 `.env` 中指定其他已存在的目录：

```dotenv
SSH_SOURCE_DIR=${HOME}/.ssh
```

每次启动时复制目录内容（包括隐藏文件和子目录）到容器用户的 `~/.ssh`：
dev 为 `/workspace/.ssh`，root 为 `/root/.ssh`。复制后归属当前容器用户，
目录权限设为 `0700`，普通文件设为 `0600`；宿主机源文件不会被修改。
软链接原样复制，指向宿主机其他路径的链接需要改成实际文件或容器内有效路径。
SSH config 中的宿主机绝对路径也需要适用于容器。

源目录同名文件会在下次启动时覆盖容器副本；源目录删除的文件不会自动从已有
容器中删除。更新后执行 `docker compose restart dev`；首次应用需重建镜像
并重新创建容器。复制失败会中止启动。

SSH Server 始终启动，只接受 `authorized_keys` 中的公钥；密码认证、键盘交互
认证和空密码均已关闭。root 用户也只能使用密钥登录。默认端口只绑定到宿主机
回环地址。`SSH_PUBLIC_KEY` 为空时保留复制的 `authorized_keys`；非空时覆盖该文件：

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

启动脚本通过 sshd 的 `SetEnv` 显式传入语言、时区、agent 数据目录、uv 和 npm
配置及 PATH，使 SSH 会话使用与当前容器分支相同的开发环境。登录 shell 会通过
`/etc/profile.d/20-dev-env.sh` 恢复开发 PATH。只传入脚本列出的必要变量，代理和
其他未列出的变量不会自动传入 SSH 会话。

挂载 Docker socket 时，启动脚本读取它的实际 GID，为非 root 用户创建或复用
对应组并记录组成员关系，使新 SSH 会话具备访问 socket 的权限；root 分支跳过
此步骤。首次应用这些修改需要重新构建并创建容器，已有 SSH 会话需要重新连接。

如需从其他机器访问，显式设置 `SSH_BIND_IP=0.0.0.0`，并同时配置宿主机和
云平台防火墙，只开放确实需要的来源地址。SSH host key 在镜像构建时生成；
同一镜像启动的容器使用相同 host key，重新构建镜像后 key 可能变化。因为
服务端私钥存在于镜像层中，不应把该镜像发布到不可信的公共仓库。
`assets/dev-env-entrypoint` 会在复制 SSH 文件后处理 `SSH_PUBLIC_KEY` 覆盖。

## HTTP 代理

本项目的 Compose 配置不向构建步骤传入代理参数，也不为运行中的容器设置
标准的 `http_proxy`、`https_proxy`、`no_proxy` 及其大写形式。

`.env` 中保留的代理值仅作为 `back_http_proxy`、`back_https_proxy` 和
`back_no_proxy` 传入容器，供手动参考；项目没有将它们转换为标准代理变量的
逻辑，因此填写这些值不会自动启用代理。不需要时可将它们留空。

`BUILD_NETWORK` 只选择构建步骤使用的网络，默认是 `default`；设置为 `host`
也不会自动启用代理。Docker 客户端或 daemon 自身的外部代理配置由宿主机管理。

## Docker 客户端

`INSTALL_DOCKER_CLI=true` 只加入以下客户端程序：

- Docker CLI
- Docker Compose 插件
- Docker Buildx 插件

当前 Compose 配置会挂载 `/var/run/docker.sock`，并通过 `DOCKER_GID` 为初始
容器进程添加附加组；该值应与宿主机 socket 的 GID 一致。启动脚本另行注册
非 root 用户的组成员关系，供 SSH 登录使用。直接使用 `docker run` 时，需自行
挂载 socket 并配置 `--group-add`。挂载 Docker socket 基本等同于授予容器
宿主机 root 权限，应只在可信环境使用。

### 检查 Docker API

挂载宿主机 Docker socket 后，在容器内执行：

```bash
docker version --format \
  'client={{.Client.Version}} client_api={{.Client.APIVersion}} server={{.Server.Version}} server_api={{.Server.APIVersion}} min_api={{.Server.MinAPIVersion}}'
docker info >/dev/null
```

CLI 与 daemon 版本不必完全一致，Docker 会自动协商双方支持的 API；不要设置
`DOCKER_API_VERSION`，否则会关闭自动协商。
