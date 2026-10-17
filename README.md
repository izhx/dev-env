# dev-env

用于日常开发和 GPU 计算的 Docker 开发环境。CPU 与 GPU 版本分别位于
[`cpu/`](cpu/README.md) 和 [`gpu/`](gpu/README.md)，各自维护 Dockerfile、
Compose 配置、环境变量模板和启动脚本。

两个版本都提供 Python、Node.js/npm、uv/uvx、SSH Server 和常用开发工具，
支持在启动时载入 Claude Code、Codex 原生二进制，并可选安装 Docker 客户端。

## 目录结构

```text
dev-env/
├── README.md
├── cpu/
│   ├── README.md
│   ├── Dockerfile
│   ├── compose.yaml
│   ├── .env.example
│   ├── .dockerignore
│   ├── assets/
│   ├── download_bin.sh
│   └── set-herdr.sh
└── gpu/
    ├── README.md
    ├── Dockerfile
    ├── compose.yaml
    ├── .env.example
    ├── .dockerignore
    ├── assets/
    └── run.sh
```

`.env`、`agent-bin/` 和 `data/` 是各环境的本机配置与数据，不提交到 Git。
根目录仅提供导航和公共忽略规则，构建与启动命令在对应子目录执行。

## 选择环境

下表列出模板和 Compose 的默认配置，实际值以各目录的 `.env` 为准。

| 项目 | CPU | GPU |
| --- | --- | --- |
| 适用场景 | 日常开发、脚本与无需 CUDA 的任务 | CUDA 开发、GPU 计算与训练环境 |
| 基础镜像 | `python:3.12-bookworm` | `nvidia/cuda:13.0.2-devel-ubuntu24.04` |
| 默认用户 / HOME | `dev` / `/workspace` | `ubuntu` / `/home/ubuntu` |
| 可选用户 | `root` | `root` |
| 默认镜像 | `daily-dev:dev` | `daily-dev-gpu:ubuntu` |
| Compose 项目名 | `dev-env` | `dev-env-gpu` |
| Compose 服务名 | `dev` | `dev` |
| 默认 SSH 地址 | `127.0.0.1:2222`，映射至容器 22 端口 | host 网络，直接监听 `127.0.0.1:2223` |
| 项目目录 | 按需添加挂载 | `WORKSPACE_DIR` 按相同绝对路径挂载 |
| 宿主机要求 | Docker 与 Compose | Docker、Compose、NVIDIA 驱动及 NVIDIA Container Toolkit |

GPU 镜像提供 CUDA 工具链，不预装 PyTorch 或训练框架；项目依赖由项目自身管理。

## 快速开始

以下两组命令均从仓库根目录开始。复制模板后，先修改对应 `.env`，再构建启动。
普通用户模式下，`USER_UID` 和 `USER_GID` 应与宿主机用户一致，可用 `id -u`、
`id -g` 查询；挂载目录需预先存在，数据目录需允许该用户读写。

### CPU

```bash
cd cpu
test -f .env || cp .env.example .env
mkdir -p ~/.ssh ./agent-bin ./data/claude ./data/codex
# 编辑 .env：设置 UID/GID、DOCKER_GID、SSH 公钥和挂载路径。
docker compose build
docker compose up -d
docker compose exec dev bash
```

CPU 配置会挂载宿主机 Docker socket，`DOCKER_GID` 应与
`stat -c %g /var/run/docker.sock` 的结果一致。Docker CLI 默认不安装，需要时设置
`INSTALL_DOCKER_CLI=true` 后重新构建。

完整配置见 [CPU 使用说明](cpu/README.md)。

### GPU

```bash
cd gpu
test -f .env || cp .env.example .env
mkdir -p ~/.ssh ./agent-bin ./data/claude ./data/codex
# 编辑 .env：设置 UID/GID、DOCKER_GID、SSH 公钥和已有项目的绝对路径 WORKSPACE_DIR。
./run.sh
./run.sh exec dev bash
```

`run.sh` 默认构建并在后台启动，也可传入 Compose 参数，例如
`./run.sh logs --tail 50 dev`、`./run.sh down`。GPU 默认不挂载 Docker socket；
`INSTALL_DOCKER_CLI=true` 时同时安装客户端并挂载 socket。

GPU 检查、CUDA 配置及训练示例见 [GPU 使用说明](gpu/README.md)。

## 配置与数据

- 每个环境使用自己的 `.env`。`AGENT_BIN_DIR` 默认是该目录下的 `./agent-bin`，
  放置匹配容器架构的 Linux 原生 `codex`、`claude` 文件；无需这些工具时可留空目录。
- `CLAUDE_DATA_DIR`、`CODEX_DATA_DIR` 默认分别指向该环境的 `./data/claude`、
  `./data/codex`。容器内挂载位置固定为 `/agent-data/claude`、`/agent-data/codex`。
- GPU 如需复用 CPU 的二进制，可设置 `AGENT_BIN_DIR=../cpu/agent-bin`。
- SSH 仅允许公钥认证。默认从宿主机 `~/.ssh` 复制配置，可用 `SSH_PUBLIC_KEY`
  指定登录公钥；默认登录命令分别为 `ssh -p 2222 dev@127.0.0.1` 和
  `ssh -p 2223 ubuntu@127.0.0.1`。
- `IN_MAINLAND=true` 启用对应系统与包管理器的镜像源。`.env` 中的代理值仅作为
  `back_*` 参考变量传入，不会自动启用代理。

## 从原根目录布局迁移

原根目录中的 CPU Dockerfile、Compose、`assets/`、辅助脚本、环境变量模板和
详细说明均移入 `cpu/`，本机 `.env` 也移至 `cpu/.env`。CPU 镜像名与 Compose
项目名保持原值；后续在 `cpu/` 内执行原有命令。

如果其他机器已有根目录下的 `agent-bin/` 或 `data/`，应将其移入 `cpu/`，或在
`cpu/.env` 中将对应变量改为实际路径。相对挂载路径现在以 `cpu/` 为基准；
外部脚本中的 Compose 文件路径也需改为 `cpu/compose.yaml`。
