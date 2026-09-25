"""Worker RunPod Serverless untuk Pabrik: menjalankan SATU graf ComfyUI API apa adanya.

Pabrik yang menyusun grafnya (prompt, ukuran, seed, LoRA) — worker ini cuma mekanik:
mengunduh berkas masukan, mengantre graf, menunggu, lalu mengunggah keluaran ke Spaces
dan mengembalikan URL bertanda tangan. Klip H3 40–60 MB melewati batas balasan
serverless (20 MB), jadi hasil TIDAK pernah dikembalikan sebagai base64.

Masukan job:
  {
    "graf":   {...},                                   # format API ComfyUI
    "berkas": [{"nama": "kf-00.png", "url": "https://..."}],   # atau {"nama", "base64"}
    "awalan": "job_01XYZ/shot-00"                       # awalan kunci di Spaces
  }
Keluaran:
  {"berkas": [{"nama", "url", "bytes"}], "detikEksekusi": 71.2, "detikSejakWorkerNaik": 38.0 | null}
  atau {"galat": "...", "tetap": true} — galat yang PASTI berulang (graf ditolak, galat
  eksekusi). Sengaja bukan kunci `error`: SDK RunPod menjadikannya status FAILED dan
  tanda `tetap` hilang, sehingga Pabrik mengulang galat yang tidak akan sembuh.
"""
import base64
import os
import subprocess
import time
import uuid

import boto3
import requests
import runpod

COMFY = "http://127.0.0.1:8188"
DIR_COMFY = "/ComfyUI"
AWAL_PROSES = time.time()
_dingin_dilaporkan = False


def mulai_comfy():
    args = ["python", "-u", f"{DIR_COMFY}/main.py", "--listen", "127.0.0.1", "--port", "8188",
            "--extra-model-paths-config", f"{DIR_COMFY}/extra_model_paths.yaml", "--disable-auto-launch"]
    subprocess.Popen(args, cwd=DIR_COMFY)


def tunggu_comfy(batas_detik=600):
    batas = time.time() + batas_detik
    while time.time() < batas:
        try:
            r = requests.get(f"{COMFY}/object_info", timeout=10)
            if r.ok and len(r.json()) > 100:
                return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("ComfyUI tidak naik dalam 10 menit")


def s3():
    return boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        region_name=os.environ.get("S3_REGION", "sgp1"),
        aws_access_key_id=os.environ["S3_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET"],
    )


def simpan_masukan(berkas):
    for b in berkas or []:
        tujuan = os.path.join(DIR_COMFY, "input", b["nama"])
        os.makedirs(os.path.dirname(tujuan), exist_ok=True)
        if b.get("base64"):
            isi = base64.b64decode(b["base64"].split(",")[-1])
        else:
            r = requests.get(b["url"], timeout=300)
            r.raise_for_status()
            isi = r.content
        with open(tujuan, "wb") as f:
            f.write(isi)


def ringkas_galat(status):
    for m in status.get("messages") or []:
        if isinstance(m, list) and m and m[0] == "execution_error":
            d = m[1] or {}
            return f"{d.get('node_type', '?')}: {d.get('exception_message', 'tanpa pesan')}"[:600]
    return "galat eksekusi tanpa rincian"


def detik_eksekusi(status):
    mulai = selesai = None
    for m in status.get("messages") or []:
        if isinstance(m, list) and len(m) > 1 and isinstance(m[1], dict):
            if m[0] == "execution_start":
                mulai = m[1].get("timestamp")
            if m[0] == "execution_success":
                selesai = m[1].get("timestamp")
    return round((selesai - mulai) / 1000, 1) if mulai and selesai else None


def handler(job):
    global _dingin_dilaporkan
    masukan = job["input"]
    graf = masukan["graf"]
    awalan = masukan.get("awalan") or f"lepas/{uuid.uuid4().hex[:8]}"

    simpan_masukan(masukan.get("berkas"))

    r = requests.post(f"{COMFY}/prompt", json={"prompt": graf, "client_id": f"pabrik-{uuid.uuid4().hex[:8]}"}, timeout=120)
    d = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
    if not r.ok or d.get("node_errors"):
        # Graf yang ditolak tidak akan pernah jadi — Pabrik tidak boleh mengulangnya.
        return {"galat": f"graf ditolak: {str(d.get('node_errors') or d or r.text)[:800]}", "tetap": True}
    pid = d["prompt_id"]

    while True:
        time.sleep(1)
        h = requests.get(f"{COMFY}/history/{pid}", timeout=60).json().get(pid)
        if not h:
            continue
        status = h.get("status") or {}
        if status.get("status_str") == "error":
            return {"galat": ringkas_galat(status), "tetap": True}
        if status.get("completed"):
            break

    klien = s3()
    bucket = os.environ["S3_BUCKET"]
    akar = os.environ.get("S3_PREFIX", "pabrik-runpod").strip("/")
    hasil = []
    for keluaran in (h.get("outputs") or {}).values():
        for jenis in ("gifs", "videos", "images", "audio"):
            for f in keluaran.get(jenis) or []:
                if f.get("type", "output") != "output":
                    continue
                path = os.path.join(DIR_COMFY, "output", f.get("subfolder", ""), f["filename"])
                kunci = f"{akar}/{awalan}/{f['filename']}"
                klien.upload_file(path, bucket, kunci)
                url = klien.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": kunci}, ExpiresIn=86400)
                hasil.append({"nama": f["filename"], "url": url, "bytes": os.path.getsize(path)})
                os.remove(path)

    dingin = None
    if not _dingin_dilaporkan:
        dingin = round(time.time() - AWAL_PROSES, 1)
        _dingin_dilaporkan = True
    return {"berkas": hasil, "detikEksekusi": detik_eksekusi(status), "detikSejakWorkerNaik": dingin}


if __name__ == "__main__":
    mulai_comfy()
    tunggu_comfy()
    print(f"[worker] ComfyUI siap dalam {time.time() - AWAL_PROSES:.1f} dtk", flush=True)
    runpod.serverless.start({"handler": handler})
