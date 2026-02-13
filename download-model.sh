#!/usr/bin/env bash
set -euo pipefail

# --- DYNAMIC PATH RESOLUTION ---
# Get the directory where THIS script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/cache/huggingface"

DEFAULT_MODEL="Intel/Qwen3-Coder-Next-int4-AutoRound"

usage() {
  cat <<USAGE
Usage: ./$(basename "$0") [MODEL_ID]

Downloads a Hugging Face model to a local cache relative to the script.

Target Cache: $CACHE_DIR

Options:
  MODEL_ID    The HF Model ID (default: $DEFAULT_MODEL)
  --help      Show this help section

Examples:
  ./$(basename "$0")
  ./$(basename "$0") Qwen/Qwen2.5-Coder-32B-Instruct-GPTQ

Note: Requires 'uv' (or 'uvx') to be installed.
USAGE
}

# --- ARGUMENT PARSING ---
if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

MODEL_ID="${1:-$DEFAULT_MODEL}"

echo "🚀 Starting download for: $MODEL_ID"
echo "📂 Target Cache: $CACHE_DIR"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# --- EXECUTION ---
# Set HF_HOME so the internal hub logic stays confined to your folder
export HF_HOME="$CACHE_DIR"

# Use uvx to run the downloader in an isolated transient environment
uvx --from huggingface-hub hf download \
    "$MODEL_ID" \
    --cache-dir "$CACHE_DIR" \
    --max-workers 8

echo "✅ Download complete! Your Docker mount should now see this in ./cache/huggingface"

