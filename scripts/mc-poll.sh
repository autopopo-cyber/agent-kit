#!/bin/bash
# MC Task Poller v8.0 — MC适配层 + 超时检测 + 看门狗
set -e

export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1,10.0.0.0/8,100.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

MC_URL="${MC_URL:-http://localhost:3000}"
GID="${MC_AGENT_GLOBAL_ID:-}"
LLM_MODEL="${MC_AGENT_LLM_MODEL:-deepseek-chat}"
ADAPTER="$HOME/.xianqin/mc/mc-adapter.py"

LOCK="$HOME/.xianqin/mc-poll-${GID}.lock"
LOCK_TTL=600
STUCK_TIMEOUT="${MC_STUCK_TIMEOUT:-1800}"
HERMES_TIMEOUT="${MC_HERMES_TIMEOUT:-600}"
PROGRESS_CHECK_INTERVAL=60

# ─── GID→DBid ───
case "$GID" in
  101) DBID=10 ;; 102) DBID=4 ;; 103) DBID=5 ;; 104) DBID=6 ;;
  105) DBID=18 ;; 106) DBID=19 ;; 107) DBID=20 ;; 108) DBID=21 ;;
  *)   DBID="" ;;
esac

# ─── API key ───
DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-}"
[ -z "$DEEPSEEK_KEY" ] && DEEPSEEK_KEY=$(grep 'DEEPSEEK_API_KEY' "$HOME/.hermes/.env" 2>/dev/null | cut -d= -f2)
[ -z "$DEEPSEEK_KEY" ] && { CANDIDATE=$(grep -A2 'main:' "$HOME/.hermes/config.yaml" 2>/dev/null | grep 'api_key:' | awk '{print $2}'); [ -n "$CANDIDATE" ] && [ "${CANDIDATE:0:6}" != "sk-or-" ] && DEEPSEEK_KEY="$CANDIDATE"; }

# ─── MC Adapter wrapper ───
mc_call() {
  MC_URL="$MC_URL" MC_API_KEY="$MC_API_KEY" python3 "$ADAPTER" "$@" 2>/dev/null
}

# ─── 解析锁文件 ───
parse_lock() {
  [ ! -f "$LOCK" ] && return 1
  local content=$(cat "$LOCK" 2>/dev/null)
  LOCK_PID=$(echo "$content" | cut -d: -f1)
  LOCK_TASK=$(echo "$content" | cut -d: -f2)
  LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0)))
  return 0
}

# ─── LLM ping ───
llm_ping() {
  [ -z "$DEEPSEEK_KEY" ] && { echo "[#$GID] 无 API key" >&2; return 0; }
  local resp=$(curl -sf -w '\n%{http_code}' -m 10 \
    -H "Authorization: Bearer $DEEPSEEK_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$LLM_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"pong\"}],\"max_tokens\":3}" \
    "https://api.deepseek.com/v1/chat/completions" 2>/dev/null) || return 1
  local http_code=$(echo "$resp" | tail -1)
  [ "$http_code" != "200" ] && { echo "[#$GID] LLM ping HTTP $http_code" >&2; return 1; }
  local body=$(echo "$resp" | sed '$d')
  local ok=$(echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); print('OK' if d.get('choices',[{}])[0].get('message',{}).get('content','') else 'EMPTY')" 2>/dev/null)
  [ "$ok" != "OK" ] && { echo "[#$GID] LLM ping 异常($ok)" >&2; return 1; }
  echo "[#$GID] LLM ping OK" >&2; return 0
}

# ─── heartbeat ───
heartbeat() {
  mc_call heartbeat "$GID" > /dev/null 2>&1 && echo "[#$GID] 心跳已发" >&2
}

# ─── 僵尸锁判定 ───
is_zombie_lock() {
  [ "$LOCK_AGE" -le "$LOCK_TTL" ] && { echo "  → 锁有效(${LOCK_AGE}s)" >&2; return 1; }
  [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null && { echo "  → 锁过期但进程在跑" >&2; return 1; }
  echo "  → 僵尸锁: task=#$LOCK_TASK" >&2; return 0
}

# ─── 诊断写入 ───
write_diagnostic() {
  local task_id="$1" reason="$2" extra="${3:-}"
  # 上报 MC
  mc_call report "$task_id" "failed" "$reason: $(echo "$extra" | cut -c1-150)" > /dev/null 2>&1 || true
  echo "[#$GID] 📋 诊断: T$task_id $reason" >&2
}

# ═══════════════════════════════════════════
# Phase 0: 心跳
# ═══════════════════════════════════════════
echo "[#$GID] $(date '+%H:%M:%S') cron 触发" >&2
llm_ping && heartbeat || echo "[#$GID] LLM不通,心跳跳过" >&2

# ═══ context refresh ═══
MC_API_KEY="$MC_API_KEY" python3 "$HOME/.xianqin/packages/context-engine/assemble-v2.py" "$GID" 2>/dev/null || true

# ═══════════════════════════════════════════
# Phase 0.5: 锁检查
# ═══════════════════════════════════════════
if parse_lock; then
  echo "[#$GID] 发现锁: pid=$LOCK_PID task=#$LOCK_TASK age=${LOCK_AGE}s" >&2
  if is_zombie_lock; then
    rm -f "$LOCK"
  else
    exit 0
  fi
fi

# ═══════════════════════════════════════════
# Phase 0.6: 产物自检
# ═══════════════════════════════════════════
WIKI_DIR="$HOME/wiki-${GID}/raw"
if [ -d "$WIKI_DIR" ] && [ -n "$MC_API_KEY" ]; then
  for rf in "$WIKI_DIR"/task-*-result.md; do
    [ -f "$rf" ] || continue
    tid=$(basename "$rf" | sed 's/task-\([0-9]*\)-result\.md/\1/')
    [ -z "$tid" ] && continue
    ts=$(mc_call my-tasks "$GID" 2>/dev/null | python3 -c "
import json,sys
tasks=json.load(sys.stdin).get('active',[])
match=[t for t in tasks if str(t.get('id'))=='$tid']
print(match[0]['status'] if match else '')
" 2>/dev/null || echo "")
    if [ "$ts" = "in_progress" ]; then
      mc_call report "$tid" "review" "产物已生成" > /dev/null 2>&1 && \
        echo "[#$GID] 📤 产物自检: task=#$tid → review" >&2
    fi
  done
fi

# ═══════════════════════════════════════════
# Phase 1: 拉任务（用适配器）
# ═══════════════════════════════════════════
TASK_JSON=$(mc_call pull-task "$GID" 2>/dev/null)
[ -z "$TASK_JSON" ] && { echo "[#$GID] 巡逻完成(无任务)" >&2; exit 0; }

TASK_ID=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
TITLE=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title','')[:120])" 2>/dev/null)
[ -z "$TASK_ID" ] && { echo "[#$GID] 无有效任务" >&2; exit 0; }

echo "$$:$TASK_ID" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
echo "[#$GID] 🔒 获取锁 pid=$$ task=#$TASK_ID" >&2

# ═══════════════════════════════════════════
# Phase 2: 执行
# ═══════════════════════════════════════════
RESULT_FILE="$HOME/wiki-${GID}/raw/task-${TASK_ID}-result.md"

echo "[#$GID] ▶ 执行任务 #$TASK_ID: $TITLE (超时=${HERMES_TIMEOUT}s)" >&2

PROMPT="【MC任务 #$TASK_ID】$TITLE。

1. 完成代码/测试/文档，写入 ~/wiki-$GID/raw/task-$TASK_ID-result.md（含 ## 决策点 小节）
2. 完成后执行上报: python3 ~/.xianqin/mc/mc-adapter.py report $TASK_ID review
3. 然后 git add + git commit"

PLANTREE_FILE="$HOME/plan-tree-v4.md"
if [ -f "$PLANTREE_FILE" ]; then
  PLANTREE_CTX=$(head -100 "$PLANTREE_FILE" 2>/dev/null | grep -E "决策|依赖|预测|关联|状态|in_progress|inbox" | head -20 | sed 's/^/  /')
  [ -n "$PLANTREE_CTX" ] && PROMPT="$PROMPT

【Plan-Tree 上下文】
$PLANTREE_CTX"
fi

HERMES_BIN="${HERMES_BIN:-$HOME/.local/bin/hermes}"
[ ! -x "$HERMES_BIN" ] && { echo "[#$GID] hermes 不可用" >&2; rm -f "$LOCK"; exit 0; }

# 后台执行 + 看门狗
HX=0; HERMES_PID=""; WATCHDOG_PID=""

timeout "$HERMES_TIMEOUT" "$HERMES_BIN" chat -q "$PROMPT" --yolo --model "$LLM_MODEL" &
HERMES_PID=$!
echo "[#$GID] 🚀 hermes started (pid=$HERMES_PID)" >&2

(
  STAGNANT=0; LAST_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo 0)
  while kill -0 "$HERMES_PID" 2>/dev/null; do
    sleep "$PROGRESS_CHECK_INTERVAL"
    CURR_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo 0)
    if [ "$CURR_MTIME" -gt "$LAST_MTIME" ]; then LAST_MTIME="$CURR_MTIME"; STAGNANT=0
    else STAGNANT=$((STAGNANT + PROGRESS_CHECK_INTERVAL)); fi
    if [ "$STAGNANT" -ge "$STUCK_TIMEOUT" ]; then
      echo "[#$GID] ⏰ 急停! ${STAGNANT}s无更新" >&2
      kill -TERM "$HERMES_PID" 2>/dev/null; sleep 5
      kill -0 "$HERMES_PID" 2>/dev/null && kill -KILL "$HERMES_PID" 2>/dev/null
      write_diagnostic "$TASK_ID" "STUCK" "产物${STAGNANT}s无更新"
      echo "STUCK" > "$HOME/.xianqin/mc-poll-${GID}-stuck.flag"; break
    fi
  done
) &
WATCHDOG_PID=$!

set +e; wait "$HERMES_PID" 2>/dev/null; HX=$?; set -e
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true

[ -f "$HOME/.xianqin/mc-poll-${GID}-stuck.flag" ] && { rm -f "$HOME/.xianqin/mc-poll-${GID}-stuck.flag"; exit 0; }
[ "$HX" -eq 124 ] && { write_diagnostic "$TASK_ID" "TIMEOUT" "超${HERMES_TIMEOUT}s"; exit 0; }
[ "$HX" -ne 0 ] && { write_diagnostic "$TASK_ID" "HERMES_EXIT_$HX" "退出码=$HX"; exit 0; }

# ═══════════════════════════════════════════
# Phase 3: 验证 + 交活
# ═══════════════════════════════════════════
[ ! -s "$RESULT_FILE" ] && { write_diagnostic "$TASK_ID" "NO_RESULT" "无产物"; exit 0; }
echo "[#$GID] 📄 产物: $RESULT_FILE ($(wc -l < "$RESULT_FILE") lines)" >&2

if llm_ping; then
  heartbeat
  mc_call report "$TASK_ID" "review" > /dev/null 2>&1
  echo "[#$GID] ✅ → review" >&2
  # Phase 3.5: PlanTree 增量
  DECISIONS=$(sed -n '/^## 决策点/,/^## /p' "$RESULT_FILE" 2>/dev/null | grep -E '^\|' | head -10)
  if [ -n "$DECISIONS" ]; then
    [ ! -f "$PLANTREE_FILE" ] && printf "# $GID Plan-Tree v4\n\n> 更新: $(date '+%Y-%m-%d %H:%M')\n\n## 决策点\n\n| 时间 | 决策 | 选项 | 选择 | 理由 |\n|------|------|------|------|------|\n" > "$PLANTREE_FILE"
    echo "$DECISIONS" >> "$PLANTREE_FILE"
    echo "[#$GID] 🌲 PlanTree 增量更新" >&2
  fi
else
  echo "[#$GID] ⚠️ LLM不通" >&2
fi

# Phase 4: 提交
SUBMIT_HOST="${MC_SUBMIT_HOST:-100.80.136.1}"
SUBMIT_USER="${MC_SUBMIT_USER:-agentuser}"
SUBMIT_DIR="${MC_SUBMIT_DIR:-workspace/reviews}"
SUBMIT_NAME="GID${GID}-T${TASK_ID}-$(date '+%H%M').md"
if [ -s "$RESULT_FILE" ]; then
  if [ "$GID" = "105" ]; then
    cp "$RESULT_FILE" "$HOME/$SUBMIT_DIR/$SUBMIT_NAME" 2>/dev/null && echo "[#$GID] 📤 已提交" >&2
  else
    scp -o ConnectTimeout=5 "$RESULT_FILE" "${SUBMIT_USER}@${SUBMIT_HOST}:${SUBMIT_DIR}/${SUBMIT_NAME}" 2>/dev/null && echo "[#$GID] 📤 已提交" >&2 || echo "[#$GID] ⚠️ 提交失败" >&2
  fi
fi
