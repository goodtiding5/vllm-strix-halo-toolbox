# vLLM for AMD Strix Halo (gfx1151) toolbox

Complete toolkit for building and running vLLM with AMD ROCm support for Strix Halo GPUs (gfx1151).

## Overview

This repository provides two workflows for vLLM on AMD ROCm:

1. **Docker** - Production-ready containerized deployment
2. **Distrobox/Toolbox** - Development environment with full build control

Both workflows target AMD Strix Halo (gfx1151) GPUs and are based on ROCm 7.2 with PyTorch 2.9.1.

## Quick Start

### Docker (Recommended for Production)

```bash
# Build and run vLLM container
docker compose up --build

# Test the API
./test.sh
```

### Distrobox/Toolbox (For Development)

```bash
# 1. Create toolbox container
./00-provision-toolbox.sh
distrobox enter vllm-toolbox

# 2. Build vLLM
./99-build-vllm.sh
```

## Scripts

### 00-provision-toolbox.sh

Creates a distrobox container for vLLM development.

**Usage:**
```bash
./00-provision-toolbox.sh [-f|--force] [container-name]
```

**Options:**
- `-f, --force` - Destroy existing toolbox and recreate
- `container-name` - Custom toolbox name (default: `vllm-toolbox`)

**Environment Variables** (via `.toolbox.env`):
- `BASE_IMAGE` - ROCm/PyTorch base image (default: `docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1`)

### 99-build-vllm.sh

Builds and installs vLLM from source with ROCm support.

**Usage:**
```bash
./99-build-vllm.sh [-f|--force] [--wheel]
```

**Options:**
- `-f, --force` - Remove existing venv and vllm directory, rebuild from scratch
- `--wheel` - Build wheel package (default: in-place install)

**Environment Variables** (via `.toolbox.env`):
- `WORK_DIR` - Workspace directory (default: `/workspace`)
- `VLLM_VERSION` - vLLM version/branch (default: `main`)
- `VENV_DIR` - Virtual environment path (default: `${WORK_DIR}/venv`)
- `FORCE_REBUILD` - Force rebuild flag (default: `0`)
- `BUILD_WHEEL` - Build wheel flag (default: `0`)
- `PYTORCH_ROCM_ARCH` - GPU architecture (default: `gfx1151`)
- `HSA_OVERRIDE_GFX_VERSION` - GPU version override (default: `11.5.1`)
- `MAX_JOBS` - Parallel build jobs (default: `nproc`)

### download-model.sh

Downloads Hugging Face models to local cache for Docker mounts.

**Usage:**
```bash
./download-model.sh [MODEL_ID]
```

**Examples:**
```bash
./download-model.sh                                    # Downloads default model
./download-model.sh Qwen/Qwen2.5-Coder-32B-Instruct    # Specific model
```

**Cache Location:** `./cache/huggingface`

### test.sh

Tests the vLLM OpenAI-compatible API server.

**Usage:**
```bash
./test.sh
```

## Docker Configuration

### docker-compose.yml

Defines the vLLM runtime service with:

- **Base Image:** `rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1`
- **Target GPU:** gfx1151 (Strix Halo)
- **Ports:** 8080 (API server)
- **Volumes:** `./cache/huggingface:/root/.cache/huggingface`

**Key Environment Variables:**
- `VLLM_TARGET_DEVICE=rocm` - Force ROCm device detection
- `PYTORCH_ROCM_ARCH=gfx1151` - GPU architecture
- `HSA_OVERRIDE_GFX_VERSION=11.5.1` - ISA version override
- `VLLM_USE_TRITON_FLASH_ATTN=0` - Disable Triton attention

**Build Arguments:**
- `VLLM_BRANCH` - vLLM branch to build (default: `main`)
- `MAX_JOBS` - Parallel build jobs (default: `32`)

### Dockerfile

Multi-stage build with three stages:

1. **base** - ROCm/PyTorch environment setup
2. **builder** - Compiles vLLM wheel from source
3. **runtime** - Production image with vLLM installed

**Build Stages:**
```bash
# Build only (no runtime)
docker build --target builder -t vllm-builder:latest .

# Full build (production)
docker build -t vllm-rocm-gfx1151:latest .
```

## Configuration

### .toolbox.env.sample

Environment configuration template for toolbox workflow. Copy to `.toolbox.env` and customize:

```bash
WORK_DIR=/workspace
VLLM_VERSION=main
VENV_DIR=/workspace/venv
FORCE_REBUILD=0
BUILD_WHEEL=0
PYTORCH_ROCM_ARCH=gfx1151
HSA_OVERRIDE_GFX_VERSION=11.5.1
MAX_JOBS=
```

### Docker Compose Configuration

Edit `docker-compose.yml` to customize:

```yaml
services:
  vllm-strix:
    environment:
      - MAX_JOBS=32  # Adjust for your CPU
    command: >
      vllm serve your-model-name
      --host 0.0.0.0
      --port 8080
      --gpu-memory-utilization 0.95
      --enforce-eager
```

## Model Management

Models are cached in `./cache/huggingface/` and mounted into containers.

**Download a model:**
```bash
./download-model.sh Qwen/Qwen2.5-0.5B-Instruct
```

**Use a different model in Docker:**
Edit `docker-compose.yml` command line:
```yaml
command: vllm serve Qwen/Qwen2.5-0.5B-Instruct --host 0.0.0.0 --port 8080
```

## API Usage

vLLM provides an OpenAI-compatible API:

**Chat Completions:**
```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**Health Check:**
```bash
curl http://localhost:8080/health
```

## Hardware Requirements

- **GPU:** AMD Strix Halo (gfx1151) or compatible RDNA3+ GPU
- **RAM:** 16GB+ minimum, 32GB+ recommended
- **Disk:** 20GB+ for ROCm SDK, PyTorch, and vLLM
- **CPU:** Multi-core for parallel builds

## Development Workflow

For custom vLLM modifications or debugging:

```bash
# 1. Setup toolbox environment
./00-provision-toolbox.sh -f  # Force fresh start
distrobox enter vllm-toolbox

# 2. Configure build (edit .toolbox.env as needed)
cp .toolbox.env.sample .toolbox.env
# Edit .toolbox.env with your settings

# 3. Build vLLM
./99-build-vllm.sh --force  # Clean rebuild

# 4. Test inside toolbox
source /workspace/venv/bin/activate
python -c "import vllm; print(vllm.__version__)"
```

## Troubleshooting

### GPU Not Detected

**Symptom:** vLLM fails to detect ROCm GPU

**Solutions:**
1. Verify ROCm installation: `rocm-smi`
2. Check GPU architecture: `rocminfo | grep gfx`
3. Ensure `HSA_OVERRIDE_GFX_VERSION` matches your GPU

### Build Failures

**Symptom:** CMake or compilation errors

**Solutions:**
1. Use ROCm's compiler: `export CC=/opt/rocm/llvm/bin/clang CXX=/opt/rocm/llvm/bin/clang++`
2. Increase build jobs: `export MAX_JOBS=4` (reduce if OOM)
3. Clean build: `./99-build-vllm.sh --force`

### Docker Permission Issues

**Symptom:** Cannot access `/dev/kfd` or `/dev/dri`

**Solution:**
```bash
sudo usermod -a -G video,render $USER
# Logout and login again
```

## Directory Structure

```
.
├── 00-provision-toolbox.sh    # Create toolbox container
├── 99-build-vllm.sh           # Build vLLM from source
├── download-model.sh           # Download Hugging Face models
├── test.sh                     # Test API endpoint
├── docker-compose.yml          # Docker service definition
├── Dockerfile                  # Multi-stage build
├── .toolbox.env.sample         # Environment template
├── cache/
│   └── huggingface/           # Model cache (mounted to Docker)
└── README.md                   # This file
```

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for using any Linux distribution
