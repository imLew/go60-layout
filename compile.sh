#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Match the workflow's fresh checkouts
git submodule update --init --recursive
git -C src fetch origin main
git -C src checkout --detach origin/main

export NIX_PATH=nixpkgs=channel:nixos-22.05

nix-build config -o combined
