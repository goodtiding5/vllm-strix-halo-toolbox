# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder - Build vLLM and AITER wheels
# =============================================================================

# Use Ubuntu 24.04 as base (same as toolbox)
FROM docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1 AS builder

LABEL maintainer="ken@epenguin.com" \
      description="vLLM and AITER wheels builder for AMD gfx1151"

# Create workspace directory
WORKDIR /workspace

# Copy entire project to workspace
COPY . /workspace/

# Make scripts executable
RUN chmod +x /workspace/*.sh

# Set environment variables (fallback if .toolbox.env is not available)
# Note: Running as root, so SUDO="" (no sudo needed)
# Note: CPU-only environment, no GPU detection available
ENV SUDO="" \
    SKIP_VERIFICATION=true \
    VENV_DIR=/opt/venv \
    ROCM_HOME=/opt/rocm \
    WORK_DIR=/workspace \
    GPU_TARGET=gfx1151 \
    GFX_VERSION=11.5.1 \
    VLLM_VERSION=main \
    AITER_VERSION=main \
    FA_VERSION=main_perf

# Build vLLM wheel
RUN /workspace/02-build-vllm.sh --wheel

# Build AITER wheel
RUN /workspace/03-build-aiter.sh --wheel

# Build Flash Attention wheel
RUN /workspace/04-build-fa.sh --wheel

# Set output path for easy access
ENV WHEELS_DIR=/workspace/wheels

# Show what was built
RUN echo "=== Build Complete ===" \
 && echo "" \
 && echo "Built wheels:" \
 && ls -lh ${WHEELS_DIR}/

# =============================================================================
# Note: This is a BUILDER image only
# To use the wheels:
#   1. Run: docker run --rm -v $(pwd)/wheels:/output <image> bash -c "cp /workspace/wheels/*.whl /output/"
#   2. Then install in your ROCm environment: pip install /output/*.whl
# =============================================================================
