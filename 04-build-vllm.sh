#!/usr/bin/env bash
set -euo pipefail

# 04-build-vllm.sh
# Build vLLM from source for ROCm with gfx1151 support

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-${WORK_DIR}/venv}"
VLLM_DIR="${WORK_DIR}/vllm"
WHEEL_DIR="${WORK_DIR}/wheels"

# Set SUDO based on whether running as root (Docker) or non-root (distrobox)
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "[04] Building vLLM from source for ROCm gfx1151..."

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Initialize ROCm SDK
rocm-sdk init

# Get ROCm SDK paths
ROCM_ROOT=$(python3 -m rocm_sdk path --root)
ROCM_BIN=$(python3 -m rocm_sdk path --bin)

# Set device library path
export HIP_DEVICE_LIB_PATH="${ROCM_ROOT}/lib/llvm/amdgcn/bitcode"
export ROCM_PATH="${ROCM_ROOT}"
export ROCM_HOME="${ROCM_ROOT}"

echo "  ROCm Root: ${ROCM_ROOT}"
echo "  Device Lib Path: ${HIP_DEVICE_LIB_PATH}"

# Ensure /opt/rocm symlink exists for compatibility
if [ ! -L "/opt/rocm" ]; then
    echo "  Creating /opt/rocm symlink..."
    ${SUDO} mkdir -p /opt
    ${SUDO} ln -sf "${ROCM_ROOT}" /opt/rocm
fi

# Step 1: Clone vLLM
echo "[04a] Checking vLLM repository..."
if [ ! -d "${VLLM_DIR}" ]; then
    echo "  Cloning vLLM..."
    git clone --depth=1 https://github.com/vllm-project/vllm.git "${VLLM_DIR}"
fi
cd "${VLLM_DIR}"

# Step 2: Configure to use existing PyTorch
echo "[04b] Configuring vLLM..."
python3 use_existing_torch.py

# Step 3: Set build environment
echo "[04c] Setting build environment..."
export PYTORCH_ROCM_ARCH=gfx1151
export GPU_ARCHS=gfx1151
export MAX_JOBS=$(nproc)

# Important: Set compiler flags to find device libraries
export HIPFLAGS="--rocm-device-lib-path=${HIP_DEVICE_LIB_PATH}"

echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  HIPFLAGS=${HIPFLAGS}"

# Step 4: Build vLLM wheel
echo "[04d] Building vLLM wheel..."
mkdir -p "${WHEEL_DIR}"

# Build wheel (tcmalloc is preloaded system-wide via /etc/ld.so.preload)
pip wheel . --no-deps --no-build-isolation -w "${WHEEL_DIR}"

# Find the built wheel
VLLM_WHEEL=$(ls -t "${WHEEL_DIR}"/vllm-*.whl 2>/dev/null | head -1)
if [ -z "${VLLM_WHEEL}" ]; then
    echo "ERROR: Failed to find built vLLM wheel"
    exit 1
fi

echo "  ✓ Wheel built: ${VLLM_WHEEL}"

# Step 5: Install vLLM
echo "[04e] Installing vLLM..."
pip install "${VLLM_WHEEL}"

echo ""
echo "[04] vLLM build complete!"
echo "  Installation: $(pip show vllm | grep Location)"
echo ""
echo "To use vLLM:"
echo "  distrobox enter vllm-toolbox"
echo "  source ${VENV_DIR}/bin/activate"
echo "  vllm --help"
