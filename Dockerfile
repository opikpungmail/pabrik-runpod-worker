# Worker RunPod Serverless untuk Pabrik — ComfyUI + MiniMax H3 Ultra Speed + Qwen-Image 2.1.
#
# Model TIDAK ada di image: dibaca dari network volume (/runpod-volume/models), supaya
# image kecil dan worker baru cepat naik. Yang dipasang di sini hanya yang dipanggil graf
# Pabrik (assets/ultra-speed-api.json, assets/qwen/*.json) — bukan seluruh isi pasang-kilat.sh.
#
# Tanpa xformers, sengaja. Terukur 25 Sep 2026 di RTX 5090: xformers bawaan template vast
# tidak punya kernel sm120, dan KSampler Qwen-Image mati dengan "No operator found for
# memory_efficient_attention_forward". H3 tidak kena karena memakai patch sage sendiri.
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1 PIP_ROOT_USER_ACTION=ignore

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ffmpeg libgl1 libglib2.0-0 curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# torch cu130: satu-satunya yang cocok dengan wheel SageAttention di bawah (dikompilasi
# untuk torch 2.10.0+cu130, Python 3.12, sm120) dan jalan di Blackwell (5090 / PRO 6000).
RUN pip install torch==2.10.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

ARG COMFY_REF=v0.37.0
RUN git clone --depth 1 --branch ${COMFY_REF} https://github.com/comfyanonymous/ComfyUI /ComfyUI \
 && pip install -r /ComfyUI/requirements.txt

# Node yang dipanggil graf: DualClock/sage patch (T8), VHS_VideoCombine, dan KJNodes.
WORKDIR /ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/T8mars/comfyui-minimax-h3-audio-T8 \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite \
 && git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes \
 && for d in */; do if [ -f "$d/requirements.txt" ]; then pip install -r "$d/requirements.txt"; fi; done

RUN curl -fsSL -o /tmp/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
      https://sprinthub.id/srikandi-alat/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
 && pip install /tmp/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
 && rm /tmp/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl

RUN pip install runpod boto3 requests imageio-ffmpeg \
 && (pip uninstall -y xformers || true)

COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml
COPY handler.py /handler.py

WORKDIR /
CMD ["python", "-u", "/handler.py"]
