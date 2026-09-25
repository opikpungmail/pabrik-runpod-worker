# Mengisi network volume RunPod dengan model yang DIPANGGIL graf Pabrik — tidak lebih.
# Dijalankan sebagai perintah mulai pod CPU sementara (ubuntu:24.04) yang me-mount volume
# di /workspace; env PUBLIC_KEY dipasang supaya bisa diperiksa lewat SSH. Selesai →
# /workspace/models/.ISI-SELESAI berisi lama unduh dan ukuran. Pod lalu dihapus manual.
#
# 10 berkas, ±69 GiB (25 Sep 2026):
#   H3 Ultra (graf 1-pass showcase): Singularity Pruned int8, encoder qwen3vl 32B int8,
#     VAE video fp16, VAE audio, LoRA turbo 1.0 → LMS 0.5 → realism 1.0
#   Qwen-Image 2.1 (keyframe): DiT int8, encoder qwen3vl 8B int8, VAE
set -u
apt-get update -qq && apt-get install -y -qq openssh-server aria2 curl python3 >/dev/null 2>&1
mkdir -p /root/.ssh /run/sshd && echo "$PUBLIC_KEY" > /root/.ssh/authorized_keys \
  && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
/usr/sbin/sshd

M=/workspace/models
mkdir -p $M/diffusion_models $M/text_encoders $M/vae/Minimax $M/loras
H=https://huggingface.co
B=$H/Comfy-Org/MiniMax-H3/resolve/main
Q=$H/Comfy-Org/Qwen-Image-2.1/resolve/main
A="aria2c -x16 -s16 -k 16M --file-allocation=none --console-log-level=warn --summary-interval=0 -c"

T=$(date +%s)
# Pruned (20,97 GB) disimpan dengan nama tanpa "Pruned" — nama yang dipakai graf.
$A -d $M/diffusion_models -o Minimax-h3_Singularity_ref2va_v1.3_int8.safetensors \
   $H/WarmBloodAban/Minimax-h3_Singularity/resolve/main/Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors > /workspace/unduh-1.log 2>&1 &
$A -d $M/text_encoders -o qwen3vl_32b_minimax_h3_int8_convrot.safetensors \
   $B/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors > /workspace/unduh-2.log 2>&1 &
$A -d $M/vae/Minimax -o minimax_h3_video_vae_fp16.safetensors $B/vae/minimax_h3_video_vae_fp16.safetensors > /workspace/unduh-3.log 2>&1 &
$A -d $M/vae -o minimax_h3_audio_vae_fp32.safetensors $B/vae/minimax_h3_audio_vae_fp32.safetensors > /workspace/unduh-4.log 2>&1 &
$A -d $M/loras -o minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors \
   $B/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors > /workspace/unduh-5.log 2>&1 &
$A -d $M/loras -o minimax_h3_lms_v1.0_r64.safetensors \
   $H/RunningHubAI/rh-minimax-h3-lms-v1.0-r64.safetensors-lora/resolve/main/minimax_h3_lms_v1.0_r64.safetensors > /workspace/unduh-6.log 2>&1 &
$A -d $M/loras -o h3-realism-people-t2v-i2v-r2v.safetensors \
   $H/fal/MiniMax-H3-Realism-People-LoRA/resolve/main/h3-realism-people-t2v-i2v-r2v.safetensors > /workspace/unduh-7.log 2>&1 &
$A -d $M/diffusion_models -o qwen_image_2.1_int8_convrot.safetensors \
   $Q/diffusion_models/qwen_image_2.1_int8_convrot.safetensors > /workspace/unduh-8.log 2>&1 &
$A -d $M/text_encoders -o qwen3vl_8b_int8_convrot.safetensors \
   $Q/text_encoders/qwen3vl_8b_int8_convrot.safetensors > /workspace/unduh-9.log 2>&1 &
$A -d $M/vae -o qwen_image_2.1_vae_bf16.safetensors $Q/vae/qwen_image_2.1_vae_bf16.safetensors > /workspace/unduh-10.log 2>&1 &
wait

echo "$(( $(date +%s) - T )) dtk" > $M/.ISI-SELESAI
du -sh $M >> $M/.ISI-SELESAI
ls -la $M/*/ $M/vae/Minimax/ >> $M/.ISI-SELESAI
sleep infinity
