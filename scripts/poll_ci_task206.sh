#!/bin/bash
# Task206 CI 轮询（鉴权 API；每 60s 一次，最多 45 次 ≈ 45 分钟）
REPO_URL=$(git remote get-url origin)
TOK=$(printf '%s' "$REPO_URL" | sed -n 's#https://\([^@]*\)@github\.com.*#\1#p')
SHA=$(git rev-parse HEAD)
for i in $(seq 1 45); do
  R=$(curl -s --max-time 20 -H "Authorization: token ${TOK}" \
    "https://api.github.com/repos/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/actions/runs?head_sha=$SHA")
  S=$(echo "$R" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rs=[r for r in d.get('workflow_runs',[]) if r.get('name')=='Development build']
print(rs[0]['status']+'|'+str(rs[0].get('conclusion'))+'|'+str(rs[0]['id']) if rs else 'none')" 2>/dev/null)
  echo "[$i] $(date +%H:%M:%S) $S"
  case "$S" in completed*) echo "FINAL: $S"; exit 0;; esac
  sleep 60
done
echo "TIMEOUT (still: $S)"
