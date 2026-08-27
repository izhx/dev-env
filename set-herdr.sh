#!/bin/bash

HERDR_VERSION="v0.8.2"
CONTAINER_NAME="mycontainer"

mkdir -p ./assets
curl --output ./assets/herdr https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-x86_64

chmod 0755 ./assets/herdr
docker cp ./assets/herdr ${CONTAINER_NAME}:/usr/local/bin/herdr

exit 0

cat <<'EOF' | docker exec -i ${CONTAINER_NAME} sh -c 'cat >> ~/.bashrc'

if [[ "$HERDR_ENV" == "1" ]]; then
    unset COLORTERM
fi
EOF
