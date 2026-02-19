# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder - Build vLLM, AITER, and Flash Attention wheels
# =============================================================================

FROM docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1 AS builder

LABEL maintainer="ken@epenguin.com" \
      description="vLLM wheels builder for AMD gfx1151"

# Build arguments for version control (can be overridden in docker-compose)
ARG VLLM_VERSION=main
ARG AITER_VERSION=main
ARG FA_VERSION=main_perf

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
    VLLM_VERSION=${VLLM_VERSION} \
    AITER_VERSION=${AITER_VERSION} \
    FA_VERSION=${FA_VERSION}

# Build vLLM wheel (with BUILD_FA=0 for gfx1151 compatibility)
RUN /workspace/02-build-vllm.sh --wheel

# Build AITER wheel
RUN /workspace/03-build-aiter.sh --wheel

# Build Flash Attention wheel
RUN /workspace/04-build-fa.sh --wheel

# Show what was built
RUN echo "=== Build Complete ===" \
 && echo "" \
 && echo "Built wheels:" \
 && ls -lh /workspace/wheels/

# =============================================================================
# Stage 2: Release - Runtime image with installed wheels
# =============================================================================

FROM docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1 AS release

LABEL maintainer="ken@epenguin.com" \
      description="vLLM runtime for AMD gfx1151 (Strix Halo)"

# Set runtime environment variables for ROCm
ENV GPU_TARGET=gfx1151 \
    GFX_VERSION=11.5.1 \
    HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    PYTORCH_ROCM_ARCH=gfx1151 \
    ROCM_HOME=/opt/rocm \
    VENV_DIR=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

# Copy wheels from builder stage
COPY --from=builder /workspace/wheels/*.whl /tmp/wheels/

# Install wheels in dependency order:
# 1. Flash Attention (base kernel library)
# 2. AITER (AMD optimized kernels)
# 3. vLLM (main package)
RUN . /opt/venv/bin/activate \
 && echo "Installing Flash Attention..." \
 && pip install --no-cache-dir /tmp/wheels/flash_attn-*.whl \
 && echo "Installing AITER..." \
 && pip install --no-cache-dir /tmp/wheels/amd_aiter-*.whl \
 && echo "Installing vLLM..." \
 && pip install --no-cache-dir /tmp/wheels/vllm-*.whl \
 && echo "Cleaning up..." \
 && rm -rf /tmp/wheels \
 && pip cache purge

# Verify installation
RUN echo "=== Verifying Installation ===" \
 && . /opt/venv/bin/activate \
 && python -c "import vllm; print(f'vLLM version: {vllm.__version__}')" \
 && pip show flash-attn | grep Version \
 && python -c "import aiter; print(f'AITER installed')" \
 && echo "=== All components verified ==="

# Default command
CMD ["/bin/bash"]
