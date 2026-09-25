# pabrik-runpod-worker

Worker RunPod Serverless untuk Pabrik: ComfyUI v0.37.0 + MiniMax H3 Ultra Speed + Qwen-Image 2.1.
Model dibaca dari network volume (`/runpod-volume/models`), hasil diunggah ke Spaces.

- `Dockerfile` — hanya yang dipanggil graf Pabrik; tanpa xformers (tidak punya kernel sm120).
- `handler.py` — satu job = satu graf API ComfyUI; lihat docstring untuk bentuk masukan/keluaran.
- `.github/workflows/build.yml` — push ke `main` → `ghcr.io/opikpun/pabrik-runpod-worker:latest`.

Env endpoint: `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_KEY`, `S3_SECRET`, `S3_PREFIX`.
