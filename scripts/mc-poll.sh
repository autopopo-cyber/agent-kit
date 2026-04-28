#!/bin/bash
# MC Task Poller v3 — uses global_id only, no names
set -e

MC_URL="${MC_URL:-http://100.80.136.1:3000}"
MC_API_KEY="${MC_API_KEY:-}"
GID="${MC_AGENT_GLOBAL_ID:-}"

LOCK="$HOME/.xianqin/mc-poll-${GID}.lock"
[ -f "$LOCK" ] && exit 0
touch "$LOCK"
trap 'rm -f "$LOCK"' EXIT

cd "$HOME/.xianqin/mc"
RESULT=$(MC_URL="$MC_URL" MC_API_KEY="$MC_API_KEY" MC_AGENT_GLOBAL_ID="$GID" python3 mc-poll.py 2>/dev/null)
[ -z "$RESULT" ] && exit 0

TASK_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
TITLE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])" 2>/dev/null)
[ -z "$TASK_ID" ] && exit 0

# Mark in_progress
curl -sf -X PUT -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"in_progress\"}" > /dev/null 2>&1

echo "[#$GID] 开始执行任务 #$TASK_ID: $TITLE" >&2

# Execute via hermes
PROMPT="【MC任务 #$TASK_ID】$TITLE。完成后将结果写入 ~/wiki-$GID/raw/task-$TASK_ID-result.md，并执行 git add + git commit 提交代码。"
~/.local/bin/hermes chat -q "$PROMPT" --yolo 2>&1 | tail -5

# ─── Artifact 验证 (反幻觉) ───
RESULT_FILE="$HOME/wiki-${GID}/raw/task-${TASK_ID}-result.md"
VERIFY_OK=1

if [ ! -s "$RESULT_FILE" ]; then
    echo "[#$GID] ⚠️ 产物缺失: $RESULT_FILE 不存在或为空 — 不交 review" >&2
    VERIFY_OK=0
else
    echo "[#$GID] ✅ 产物验证: $RESULT_FILE ($(wc -l < "$RESULT_FILE") lines)" >&2
fi

for repo in ~/repos/vector-os-nano ~/xianqin; do
    if [ -d "$repo/.git" ]; then
        UNSTAGED=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
        if [ "$UNSTAGED" -gt 0 ]; then
            echo "[#$GID] ⚠️ $repo 有 $UNSTAGED 个未提交文件 — 请 git commit" >&2
        fi
    fi
done

if [ $VERIFY_OK -eq 0 ]; then
    echo "[#$GID] ❌ 产物验证失败，任务保持 in_progress" >&2
    exit 0
fi

# Mark review — 产物验证通过后才允许
curl -sf -X PUT -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"review\"}" > /dev/null 2>&1

echo "[#$GID] 任务 #$TASK_ID → review" >&2
