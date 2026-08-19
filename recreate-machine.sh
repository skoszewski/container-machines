#!/usr/bin/env bash

set -euo pipefail

CONTAINER_MACHINES_REGISTRY="container-machines"
if [[ -f $HOME/.config/container-machines.env ]]; then
    source "$HOME/.config/container-machines.env"
fi

MACHINE_NAME="${1:-ubuntu}"
UBUNTU_VERSION="${2:-24.04}"

case "${UBUNTU_VERSION}" in
    24.04) UBUNTU_CODENAME="noble" ;;
    26.04) UBUNTU_CODENAME="resolute" ;;
    *) echo "Unsupported Ubuntu version: $UBUNTU_VERSION" >&2; exit 1 ;;
esac

container machine stop "${MACHINE_NAME}" >/dev/null 2>&1 || true
container machine rm "${MACHINE_NAME}" >/dev/null 2>&1 || true
container machine create --name "${MACHINE_NAME}" --cpus 5 --memory 4G --home-mount rw --set-default "${CONTAINER_MACHINES_REGISTRY}/${MACHINE_NAME}:${UBUNTU_VERSION}"
