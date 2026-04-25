#!/bin/bash

set -Eeuo pipefail

TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY:-""}
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-"ollama"}
TAILSCALE_TAG=${TAILSCALE_TAG:-"cloud-gpu-pods"}

# Ollama innstallation version
export OLLAMA_VERSION=v0.21.2

# Ollama environment variables
export OLLAMA_PORT=11434
export OLLAMA_HOST=127.0.0.1:${OLLAMA_PORT}
export OLLAMA_MAX_LOADED_MODELS=2
export OLLAMA_KEEP_ALIVE=-1        # モデルをVRAMに常駐
export OLLAMA_HOME=/workspace/ollama
export OLLAMA_MODELS=${OLLAMA_HOME}/models
export OLLAMA_ORIGINS="*"

# --- 1. Ollama setup ---

# アーキテクチャを自動判定
export ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        export OLLAMA_ARCH="amd64" ;;
  aarch64|arm64) export OLLAMA_ARCH="arm64" ;;
  *)             echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ワークスペースに ollama 用のディレクトリを作成
mkdir -p "${OLLAMA_MODELS}"

pushd "${OLLAMA_HOME}"
if [ ! -f "./bin/ollama" ]; then
    curl -L -o /tmp/ollama.tar.zst \
        "https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-${OLLAMA_ARCH}.tar.zst" \
    && tar --use-compress-program=unzstd -xf /tmp/ollama.tar.zst -C ./ \
    && rm /tmp/ollama.tar.zst \
    || exit 1
fi
popd

export PATH="${OLLAMA_HOME}/bin:$PATH"

ollama --version || { echo "Failed to verify Ollama installation."; exit 1; }

# --- 2. Tailscale setup ---
# 証明書保存用ディレクトリを作成
mkdir -p /workspace/tailscale-state

# tailscaled 起動
tailscaled \
--tun=userspace-networking \
--statedir=/workspace/tailscale-state &

tailscale up \
--authkey=${TAILSCALE_AUTHKEY} \
--hostname=${TAILSCALE_HOSTNAME} \
--advertise-tags=tag:${TAILSCALE_TAG} \
--reset

tailscale wait

echo "Tailscale setup completed. Current IPs:"
tailscale ip -4

tailscale serve --bg --tcp ${OLLAMA_PORT} tcp://${OLLAMA_HOST}
ollama serve
