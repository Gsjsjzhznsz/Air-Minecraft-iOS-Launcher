#!/usr/bin/env bash
# Task209 CI 轮询（家法：run 出现 → 等完成 → 报结论；限流退避）
# 用法: bash /home/z/my-project/workspace/Air-Minecraft-iOS-Launcher/scripts/poll_ci_task209.sh
REPO="Gsjsjzhznsz/Air-Minecraft-iOS-Launcher"
SHA="b7220d097e922c859ac902517b7fb21b1159ed8a"
TOKEN="$(git -C /home/z/my-project/workspace/Air-Minecraft-iOS-Launcher remote get-url origin | sed -n 's#https://\([^@]*\)@.*#\1#p')"
OUT=/tmp/ci210.log
: > "$OUT"
api() {
  curl -s --max-time 30 -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/${REPO}/actions/runs?per_page=5"
}
RUN_ID=""
for i in $(seq 1 40); do
  JSON=$(api)
  RUN_ID=$(echo "$JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in d.get('workflow_runs', []):
        if r['head_sha'].startswith('b7220d0'):
            print(r['id']); break
except Exception:
    pass
" 2>/dev/null)
  if [ -n "$RUN_ID" ]; then break; fi
  echo "[$i] run not visible yet (or rate-limited), retry in 30s" >> "$OUT"
  sleep 30
done
if [ -z "$RUN_ID" ]; then
  echo "RUN NOT FOUND after retries" >> "$OUT"
  exit 1
fi
echo "RUN_ID=$RUN_ID" >> "$OUT"
for i in $(seq 1 60); do
  ST=$(curl -s --max-time 30 -H "Authorization: token ${TOKEN}" "https://api.github.com/repos/${REPO}/actions/runs/${RUN_ID}" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('status','?'), d.get('conclusion') or '')
except Exception:
    print('? ?')
" 2>/dev/null)
  echo "[$i] $ST" >> "$OUT"
  case "$ST" in
    completed*) echo "FINAL: $ST" >> "$OUT"; exit 0 ;;
  esac
  sleep 30
done
echo "TIMEOUT waiting for completion" >> "$OUT"
exit 1
