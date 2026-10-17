# GPU dev-env

独立的 CUDA 开发镜像，基于 `nvidia/cuda:13.0.2-devel-ubuntu24.04`。
构建上下文、Compose、启动脚本都在本目录内，与同级的 [CPU 版本](../cpu/README.md) 独立。

提供 Python 3.12、pip/venv、Node.js/npm、uv/uvx、Git、CMake/Ninja、SSH
Server 和常用命令。CUDA 编译器、库及 NCCL 来自 NVIDIA 基础镜像；不额外安装
PyTorch、cuDNN 或训练框架，由项目管理自己的依赖。

基础镜像已经安装 `build-essential`（含 GCC/G++/make）、`ca-certificates`、
`libatomic1`、`libstdc++6`、`procps`、`xz-utils`，Dockerfile 不再显式安装这些包。
Git、curl、wget、Python、SSH、sudo、CMake/Ninja 等在该基础镜像中缺失，需额外
安装。Node.js/npm 和 uv/uvx 继续从供体镜像复制。

## 快速使用

宿主机需要 NVIDIA 驱动和可用的 NVIDIA Container Toolkit。先确认 GPU 挂载：

```bash
docker run --rm --gpus all nvidia/cuda:13.0.2-devel-ubuntu24.04 nvidia-smi
```

在本目录初始化：

```bash
cd /data8-2/zhangxin/teleai/dev-env/gpu
test -f .env || cp .env.example .env
mkdir -p ~/.ssh ./agent-bin ./data/claude ./data/codex
id -u
id -g
getent group docker
```

将 `.env` 中的 `USER_UID`、`USER_GID` 和 `DOCKER_GID` 改为宿主机对应的数字
身份，`WORKSPACE_DIR` 设置为已有项目目录的绝对路径，并确认数据目录允许该
UID/GID 读写。镜像内的 `chown` 不会改变宿主机 bind mount 的权限。构建和启动：

```bash
cd /data8-2/zhangxin/teleai/dev-env/gpu
./run.sh
./run.sh exec dev bash
```

`run.sh` 加载 `.env` 和主 `compose.yaml`，默认执行 `docker compose up -d --build`。
有参数时直接转交给 Compose，例如 `./run.sh logs --tail 50 dev` 和 `./run.sh down`。
挂载源目录需按 `.env` 提前准备；配置和挂载错误由 Compose/Docker 直接报告。

默认 Compose 项目名是 `dev-env-gpu`，镜像为 `daily-dev-gpu:ubuntu`。主配置默认
使用 host 网络，不需要额外的网络覆盖文件，也没有 `ports` 映射。SSH 直接监听
宿主机的 `127.0.0.1:2223`。需要启动多个环境时，用 `COMPOSE_PROJECT_NAME` 或
`docker compose -p <项目名>` 区分，并为每个环境配置不同端口和数据目录。

`WORKSPACE_DIR` 按相同绝对路径挂载，并作为容器工作目录；不覆盖整个 HOME。
除显式挂载的目录外，容器内修改在删除容器后不会保留。

## 用户与镜像

| USER_MODE | INSTALL_DOCKER_CLI | 镜像 | HOME |
| --- | --- | --- | --- |
| ubuntu | false | daily-dev-gpu:ubuntu | /home/ubuntu |
| ubuntu | true | daily-dev-gpu:ubuntu-docker | /home/ubuntu |
| root | false | daily-dev-gpu:root | /root |
| root | true | daily-dev-gpu:root-docker | /root |

默认直接复用 Ubuntu 基础镜像中的普通账户 `ubuntu`，保留 `/home/ubuntu`、
原有 shell 和附加组，不删除或重建账户，也不创建 `dev` 用户。原始 UID/GID
均为 1000，可通过 `USER_UID`/`USER_GID` 修改为宿主机的数字身份；这两个值
不能为 0，也不能与其他账户或组冲突。镜像额外配置免密码 sudo，并同步 HOME
和 Agent 数据目录的属主。
`root` 是独立分支，忽略 UID/GID 参数；切换模式后需要重新构建并创建容器。
Compose 服务仍名为 `dev`，这是服务名称，与容器内的登录用户名无关。

## Codex 与 Claude Code

将匹配容器 CPU 架构的 Linux 原生二进制放到 `AGENT_BIN_DIR`，分别命名为
`codex` 和 `claude`。可以只提供一个，也可以保留空目录。可在 `.env` 中设置
`AGENT_BIN_DIR=../cpu/agent-bin` 复用 CPU 版本的二进制目录。

二进制目录只读挂载到 `/opt/agent-bin-src`，每次启动时复制到
`/usr/local/bin`，设置 `0755` 权限，并通过临时文件和重命名完成替换。输入应是
实际原生可执行文件；不要复制依赖外部文件的 npm 入口脚本，或指向挂载范围外的
软链接。复制失败会中止启动。

数据使用独立的读写挂载：

| 宿主机变量 | 容器目录 | 程序变量 |
| --- | --- | --- |
| CLAUDE_DATA_DIR | /agent-data/claude | CLAUDE_CONFIG_DIR |
| CODEX_DATA_DIR | /agent-data/codex | CODEX_HOME |

空数据目录需要首次登录或准备相应配置，不会自动导入宿主机的认证状态。
Agent 数据目录必须可写；不要用 root 运行后直接切换成无权访问这些文件的 ubuntu
用户。代理和 API 密钥等未列入白名单的环境变量不会自动进入 SSH 会话。

更新宿主机二进制后执行 `docker compose restart dev`，无需重建镜像。
删除源二进制不会清理同一容器中已复制的旧版本；重新创建容器后只保留当前提供
的程序。`~/.local/bin` 位于 PATH 前面，如有同名程序，用 `command -v codex`
和 `command -v claude` 确认实际执行位置。

## SSH

与 CPU 版本采用相同的 SSH 行为：

- 构建时安装 SSH Server 并生成 host key，同一镜像的容器复用 host key；不在
  首次启动时生成，也不添加 host key 持久化卷。
- `SSH_SOURCE_DIR` 默认指向宿主机 `~/.ssh`，只读挂载后复制到当前容器用户的
  `~/.ssh`，目录权限为 `0700`，普通文件为 `0600`，属主为当前用户。
- `SSH_PUBLIC_KEY` 非空时覆盖复制的 `authorized_keys`；为空则保留它。
  只有 `.pub` 文件而没有 `authorized_keys` 不会自动授予登录权限。
- 仅允许公钥认证，包括 root；密码及键盘交互认证关闭。
- 源目录的同名文件在重启时覆盖容器副本，源目录已删除的文件不会从旧容器
  自动清理。软链接原样保留，SSH config 中的路径也必须适用于容器。

配置好公钥并启动后：

```bash
ssh -p 2223 ubuntu@127.0.0.1
```

root 模式改用 `root@127.0.0.1`。从其他机器直接连接需自行调整
`SSH_BIND_IP` 和宿主机访问策略。host key 私钥属于镜像内容，应按这个约定分发
镜像。

启动脚本用 sshd `SetEnv` 传递 Agent 目录、Node/npm、uv、PATH 及 CUDA 环境，
并通过 `/etc/profile.d/20-dev-env.sh` 恢复登录 shell 的 PATH。CUDA 白名单包括
`CUDA_HOME`、`CUDA_PATH`、`CUDA_VERSION`、`LD_LIBRARY_PATH`、`LIBRARY_PATH`、
`CUDA_VISIBLE_DEVICES`、`NVIDIA_VISIBLE_DEVICES` 和 `NVIDIA_DRIVER_CAPABILITIES`。
不自动传递任意容器环境变量。

## GPU 和 CUDA

保留 NVIDIA 原入口脚本，先执行其初始化钩子，再执行开发环境入口脚本。
保留基础镜像的 CUDA PATH 和库路径，另设置 `CUDA_HOME` 与 `CUDA_PATH` 为
`/usr/local/cuda`。宿主机驱动通过 NVIDIA Container Toolkit 提供，不在镜像内
安装内核驱动。

`GPU_COUNT=all` 默认开放全部 GPU，也可设置正整数限制数量。这是设备可见性
配置，不会独占所选 GPU。要指定设备，请把 `compose.yaml` 中的 `count` 改成
`device_ids`，两者不能同时设置：

```yaml
devices:
  - driver: nvidia
    device_ids: ["0", "2"]
    capabilities: [gpu]
```

`SHM_SIZE` 设置共享内存上限，通用默认值为 `8gb`，当前本机 `.env` 配为 `64gb`，
可按任务需要调整。GPU 支持与 Docker CLI 开关独立，不需要挂载 Docker socket。

## Docker CLI 与宿主机 socket

默认 `INSTALL_DOCKER_CLI=false`：不安装 Docker CLI/Compose/Buildx，不挂载
宿主机 Docker socket。`DOCKER_GID` 独立作为附加组加入容器用户，并注册到
`/etc/group`，使 SSH 会话也保留该组；添加用户组本身不会挂载 socket。

设为 `true` 后，同时安装三个客户端并挂载 `/var/run/docker.sock`。
将 `DOCKER_GID` 设置为 `stat -c %g /var/run/docker.sock` 的结果，然后重新构建
并创建容器。启动脚本还会按实际 socket GID 注册 ubuntu 的组成员关系，以便 SSH
会话使用 Docker。这里连接宿主机 daemon，不在容器中运行 Docker daemon。

## Python、软件源与代理

Python 来自 Ubuntu 系统包，项目依赖建议放入虚拟环境：

```bash
# 在容器内、自己的项目目录中执行。
uv venv .venv
. .venv/bin/activate
uv pip install <包名>
```

`IN_MAINLAND=true` 将 Ubuntu 普通/安全更新源切换到 CERNET，ARM64 使用
ubuntu-ports；保留 NVIDIA CUDA 仓库。pip/uv 使用 CERNET PyPI，npm 使用
npmmirror。配置位于 `/etc/pip.conf`、`/etc/uv/uv.toml`、`/etc/npmrc`，root 和 ubuntu
共用；用户及项目配置可覆盖。`false` 保留上游默认源。

`.env` 中的代理值仅作为 `back_http_proxy`、`back_https_proxy`、`back_no_proxy`
传入，供手动参考；不会自动启用构建代理或运行代理。`BUILD_NETWORK=host` 也
只是构建网络选择。外部 Docker 客户端或 daemon 的代理配置由宿主机管理。

## 检查

```bash
cd /data8-2/zhangxin/teleai/dev-env/gpu
docker compose config
docker compose exec dev python3 --version
docker compose exec dev node --version
docker compose exec dev uv --version
docker compose exec dev nvcc --version
docker compose exec dev nvidia-smi
```

配置 Agent 二进制和 SSH 登录后，还应在 SSH 会话检查 `codex --version`、
`claude --version`、`nvcc --version`、`nvidia-smi`，并实际编译运行一个 CUDA
程序。仅 `nvidia-smi` 成功不代表项目框架或 CUDA kernel 已通过验证。

## verl GSM8K Quickstart

当前工作区的 `verl/.venv` 已配置 vLLM + FSDP，数据在 `verl/dataset/gsm8k`，模型在
`data/models/Qwen2.5-0.5B-Instruct`。训练脚本位于 `verl/playground/`，直接在容器内运行：

```bash
cd /data8-2/zhangxin/teleai/verl
.venv/bin/wandb login
CUDA_VISIBLE_DEVICES=4 bash playground/gsm8k/train-gsm8k-ppo.sh
```

脚本使用一张 GPU、16 个 Ray CPU 调度资源，沿用 Quickstart 的 batch 256、
输入/输出各 512 token、15 epochs；每 10 步保存和评测，actor、critic 各保留
最近 2 份 checkpoint。GPU 默认是宿主机 4 号卡，启动前确认该卡仍空闲。
W&B 首次使用时登录一次即可；曲线记录到登录账户下的 `verl_gsm8k` 项目，
脚本通过 `setsid` 在后台启动，终端打印 PID 和日志路径；W&B run 链接写入
`train.log`。本地 W&B 日志写入输出目录，console 日志也会保留。
Ray workers 使用相同的 `uv run --frozen --all-packages --extra vllm --extra fsdp`
环境。末尾可追加 Hydra 参数，例如 `bash playground/gsm8k/train-gsm8k-ppo.sh trainer.total_epochs=1`。

输出目录固定为 `verl/playground/gsm8k/qwen2.5-0.5b-ppo/`，包含 `train.log`、
`hydra/` 配置和 `checkpoints/`。再次运行时，verl 默认从该目录的最新 checkpoint
恢复。数据、模型和输出路径可直接在脚本开头修改。

仅检查配置而不训练：

```bash
cd /data8-2/zhangxin/teleai/verl
bash playground/gsm8k/train-gsm8k-ppo.sh --cfg job
```

GSM8K 数据是 Parquet，每行包含 `data_source`、聊天消息列表 `prompt`、`ability`、
`reward_model` 和 `extra_info`。`reward_model.ground_truth` 存储最终数字答案；
模型生成 `#### <答案>` 后，由 GSM8K 规则函数判分。`extra_info.answer` 是原始
解题过程元数据，默认不会拼进训练提示词。
