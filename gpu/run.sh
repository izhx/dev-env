#!/usr/bin/env bash
set -e

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if (( $# == 0 )); then
    set -- up -d --build
fi

exec docker compose --env-file "${GPU_ENV_FILE:-.env}" -f compose.yaml "$@"
