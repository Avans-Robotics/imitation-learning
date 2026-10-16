#!/bin/bash
# Makes the GPU usable in robotis/physical-ai-server:1.0.0 on this JetPack 7 / L4T R39 Orin.
#  1. The image puts /usr/local/cuda/compat (CUDA 12.8 compat libcuda) first in LD_LIBRARY_PATH,
#     which shadows the host Orin driver -> "CUDA error 801" / "driver too old (12080)".
#     Fixed by overriding LD_LIBRARY_PATH in ~/.bashrc (server is always started via bash -i).
#  2. torch is upgraded to the CUDA 13 aarch64 wheels (sm_80 kernels run on Orin sm_87).
# Only needed again after the physical_ai_server container is recreated.

set -e

GREEN='\033[0;32m'
NC='\033[0m'

docker exec physical_ai_server bash -c 'grep -q "cuda/compat fix" /root/.bashrc || echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64  # cuda/compat fix: use host Orin driver, not bundled CUDA 12.8 compat libcuda" >> /root/.bashrc'

if docker exec physical_ai_server bash -c 'LD_LIBRARY_PATH=/usr/local/cuda/lib64 /opt/venv/bin/python3 -c "import torch,sys; sys.exit(0 if torch.version.cuda.startswith(\"13\") and torch.cuda.is_available() else 1)"' 2>/dev/null; then
    echo -e "${GREEN}CUDA 13 torch already working in physical_ai_server${NC}"
    exit 0
fi

echo -e "${GREEN}Installing CUDA 13 torch into physical_ai_server (several GB)${NC}"
docker exec physical_ai_server /opt/venv/bin/pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu130 \
    "torch==2.9.1" "torchvision==0.24.1" "torchaudio==2.9.1"

docker exec physical_ai_server bash -c 'LD_LIBRARY_PATH=/usr/local/cuda/lib64 /opt/venv/bin/python3 -c "import torch; print(\"torch\", torch.__version__, \"cuda\", torch.cuda.is_available())"'

echo -e "${GREEN}Restarting physical_ai_server container${NC}"
docker restart physical_ai_server
