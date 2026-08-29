#!/bin/bash

set -euo pipefail

IMAGE=go60-zmk-config-docker
BRANCH="${1:-main}"

podman build -t "$IMAGE" .
podman run --rm -v "$PWD:/config" -e UID="$(id -u)" -e GID="$(id -g)" -e BRANCH="$BRANCH" "$IMAGE"
