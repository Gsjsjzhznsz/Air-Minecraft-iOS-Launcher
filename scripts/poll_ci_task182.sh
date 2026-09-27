#!/bin/bash
# Task182 CI 轮询（限 API 压力：每 60s 一次，最多 40 次）
SHA=$(git rev-parse HEAD)
for i in $(seq 1 40); do
  R=$(curl -s --max-time 20 "https://api.github.com/repos/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/actions/runs?head_sha=$SHA" 2>/dev/null)
  S=$(echo "$R" | python3 -c "import json,sys; d=json.load(sys.stdin); rs=d.get('workflow_runs',[]); print(rs[0]['status']+'|'+str(rs[0].get('conclusion')) if rs else 'none')" 2>/dev/null)
  echo "[$i] $S"
  case "$S" in completed*|completed\|*) echo "FINAL: $S"; exit 0;; esac
  sleep 60
done
echo "TIMEOUT (still: $S)"
