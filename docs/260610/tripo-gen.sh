#!/usr/bin/env bash
# Tripo3D image-to-3D pipeline — run this yourself with the ! prefix so it can see
# your shell's $TRIPO_API_KEY (Claude's Bash calls don't inherit it).
#
#   ! bash docs/260610/tripo-gen.sh
#
# Stages: upload image -> create image_to_model task -> poll -> download GLB.
# Endpoints/flow verified from the official VAST-AI-Research/tripo-python-sdk source.
set -euo pipefail

API="https://api.tripo3d.ai/v2/openapi"
IMG="assets/04-portrait-source.png"
OUT="assets/04-portrait.glb"

if [ -z "${TRIPO_API_KEY:-}" ]; then
  echo "ERROR: TRIPO_API_KEY not set in this shell. Run the export one-liner first." >&2
  exit 3
fi
if [ ! -f "$IMG" ]; then
  echo "ERROR: source image not found: $IMG" >&2
  exit 4
fi

echo "== 0. balance check =="
curl -s -H "Authorization: Bearer $TRIPO_API_KEY" "$API/user/balance" \
  | sed -E 's/(api[_-]?key|token)[^,]*/\1:<hidden>/Ig'
echo

echo "== 1. upload image ($IMG) =="
UP_JSON=$(curl -s -H "Authorization: Bearer $TRIPO_API_KEY" -F "file=@${IMG};type=image/png" "$API/upload")
echo "$UP_JSON"
# image_token lives at .data.image_token
# NB: every extraction below carries `|| true` — under `set -euo pipefail` a no-match
# grep would otherwise kill the script before the friendly error checks run.
IMG_TOKEN=$(printf '%s' "$UP_JSON" | grep -oE '"image_token"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"image_token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') || true
if [ -z "$IMG_TOKEN" ]; then echo "ERROR: no image_token in upload response" >&2; exit 5; fi
echo "image_token: ${IMG_TOKEN:0:8}... (ok)"
echo

echo "== 2. create image_to_model task =="
TASK_BODY=$(printf '{"type":"image_to_model","file":{"type":"png","file_token":"%s"}}' "$IMG_TOKEN")
TASK_JSON=$(curl -s -H "Authorization: Bearer $TRIPO_API_KEY" -H "Content-Type: application/json" -d "$TASK_BODY" "$API/task")
echo "$TASK_JSON"
TASK_ID=$(printf '%s' "$TASK_JSON" | grep -oE '"task_id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"task_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') || true
if [ -z "$TASK_ID" ]; then echo "ERROR: no task_id in task response" >&2; exit 6; fi
echo "task_id: $TASK_ID"
echo

echo "== 3. poll until success =="
GLB_URL=""
for i in $(seq 1 60); do
  T=$(curl -s -H "Authorization: Bearer $TRIPO_API_KEY" "$API/task/$TASK_ID")
  STATUS=$(printf '%s' "$T" | grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') || true
  PROG=$(printf '%s' "$T" | grep -oE '"progress"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | sed -E 's/.*:([0-9]+)/\1/') || true
  echo "  [$i] status=$STATUS progress=${PROG:-?}"
  if [ "$STATUS" = "success" ]; then
    # GLB url is in output.pbr_model (fallback: output.model)
    GLB_URL=$(printf '%s' "$T" | grep -oE '"pbr_model"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"pbr_model"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') || true
    if [ -z "$GLB_URL" ]; then
      GLB_URL=$(printf '%s' "$T" | grep -oE '"[a-z_]*model"[[:space:]]*:[[:space:]]*"https[^"]+"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/') || true
    fi
    echo "  full task payload:"; echo "$T"
    break
  fi
  if [ "$STATUS" = "failed" ] || [ "$STATUS" = "cancelled" ] || [ "$STATUS" = "banned" ]; then
    echo "TASK $STATUS:"; echo "$T"; exit 7
  fi
  sleep 5
done

if [ -z "$GLB_URL" ]; then echo "ERROR: no GLB url (timeout or unexpected payload)" >&2; exit 8; fi
echo
echo "== 4. download GLB =="
echo "GLB url: $GLB_URL"
# -f: an expired signed URL (403) must abort, not save the error body as the GLB
curl -sfL -o "$OUT" "$GLB_URL" -w "saved $OUT : HTTP %{http_code} / %{size_download} bytes\n"
echo "DONE: $OUT"
