#!/bin/bash

set -Eeuo pipefail

TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY:-""}
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-"ollama-gpupods1"}

# Ollama
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_HOST=0.0.0.0:11434

# --- 1. Ollama setup ---
# アーキテクチャを自動判定
export ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        export OLLAMA_ARCH="amd64" ;;
  aarch64|arm64) export OLLAMA_ARCH="arm64" ;;
  *)             echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ワークスペースに ollama 用のディレクトリを作成
mkdir -p /workspace/ollama/bin
mkdir -p /workspace/ollama/models

pushd "/workspace/ollama/bin"
if [ ! -f "ollama" ]; then
    # バイナリを /workspace/ollama へ展開
    curl -L https://ollama.com/download/ollama-linux-${OLLAMA_ARCH}.tgz \
    | tar -xzf - -C /workspace/ollama
fi
popd

# PATH を通す
echo 'export PATH="/workspace/ollama/bin:$PATH"' >> ~/.bashrc
echo 'export OLLAMA_MODELS="/workspace/ollama/models"' >> ~/.bashrc
source ~/.bashrc

# --- 2. Tailscale setup ---
if [ -z "${TAILSCALE_AUTHKEY}" ] || [ -z "${TAILSCALE_HOSTNAME}" ] || [ "${TAILSCALE_HOSTNAME}" == "disabled" ]; then
    echo "TAILSCALE_AUTHKEY or TAILSCALE_HOSTNAME is not set. Skipping Tailscale setup."
else
    echo "TAILSCALE_AUTHKEY and TAILSCALE_HOSTNAME are set. Setting up Tailscale..."
    # Tailscale を利用するため起動
    tailscaled --tun=userspace-networking --state=/tmp/tailscale.state || exit 1 &
    #起動完了まで少し待つ
    sleep 3

    tailscale up \
    --authkey=${TAILSCALE_AUTHKEY} \
    --hostname=${TAILSCALE_HOSTNAME} \
    --advertise-tags=tag:ollama-running-on-gpupods \
    --accept-routes \
    --reset

    tailscale wait

    echo "Tailscale setup completed. Current IPs:"
    tailscale ip -4

    # Ollamaのホストとポートを環境変数で設定
    export OLLAMA_HOST=127.0.0.1:11434

    tailscale serve http://${OLLAMA_HOST}
fi

ollama serve
