#!/bin/bash

mkdir -p ./agent-bin

# Claude Code
curl -fL \
  "https://github.com/anthropics/claude-code/releases/latest/download/claude-linux-x64.tar.gz" \
  -o /tmp/claude.tar.gz

tar -xzf /tmp/claude.tar.gz -C ./agent-bin
rm /tmp/claude.tar.gz

# # Codex CLI
# curl -fL \
#   "https://github.com/openai/codex/releases/latest/download/codex-x86_64-unknown-linux-musl.tar.gz" \
#   -o /tmp/codex.tar.gz

# tar -xzf /tmp/codex.tar.gz -C ./agent-bin
# mv ./agent-bin/codex-x86_64-unknown-linux-musl ./agent-bin/codex
# rm /tmp/codex.tar.gz
