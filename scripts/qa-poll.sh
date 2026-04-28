#!/bin/bash
# QA Task Poller — picks up review tasks, audits code & tests, approves or rejects
set -e

MC_URL="${MC_URL:-http://100.80.136.1:3000}"
MC_API_KEY="${MC_API_KEY:-}"
GID="${MC_AGENT_GLOBAL_ID:-}"

LOCK="$HOME/.xianqin/qa-poll-${GID}.lock"
[ -f "$LOCK" ] && exit 0
touch "$LOCK"
trap 'rm -f "$LOCK"' EXIT

cd "$HOME/.xianqin/mc"

# 1. Find a review task
RESULT=$(MC_URL="$MC_URL" MC_API_KEY="$MC_API_KEY" MC_AGENT_GLOBAL_ID="$GID" python3 qa-poll.py 2>/dev/null)
[ -z "$RESULT" ] && exit 0

TASK_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
TITLE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])" 2>/dev/null)
DEVELOPER=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['developer'])" 2>/dev/null)
PROJECT=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['project'])" 2>/dev/null)
[ -z "$TASK_ID" ] && exit 0

# 2. Mark as in_progress (QA working on it)
curl -sf -X PUT -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"in_progress\"}" > /dev/null 2>&1

echo "[QA#$GID] 审计任务 #$TASK_ID: $TITLE (开发者 #$DEVELOPER)" >&2

# 3. Run QA audit via hermes
AUDIT_PROMPT="【QA审计 #$TASK_ID】$TITLE | 开发者=$DEVELOPER | 项目=$PROJECT

你是仙秦舰队的QA审计员。按以下清单审计此任务，输出结论到 ~/wiki-${GID}/raw/qa-audit-${TASK_ID}.md：

## QA 审计清单

### 1. 代码提交验证
- git log 中是否有对应任务的提交？提交信息是否关联任务号？
- 代码文件是否存在且内容非空？

### 2. 单元测试验证
- 是否有测试文件？测试是否可运行？
- 运行测试：ALL PASS？覆盖率？
- 无测试 → 标注为严重缺陷

### 3. 接口兼容性检查
- 输入/输出是否符合设计文档的接口定义？
- 参考设计文档: ~/xianqin/navdog-redesign-v1.md

### 4. 结果文档验证
- ~/wiki-{developer_GID}/raw/task-${TASK_ID}-result.md 是否存在？
- 内容是否完整（做了什么、怎么做的、结果如何）？

### 5. 代码质量
- 是否有明显bug、硬编码、缺少错误处理？
- 代码风格是否合理？

## 输出格式
在 ~/wiki-${GID}/raw/qa-audit-${TASK_ID}.md 中按以下格式输出：

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 代码提交 | PASS/FAIL | ... |
| 单元测试 | PASS/FAIL | ... |
| 接口兼容 | PASS/FAIL | ... |
| 结果文档 | PASS/FAIL | ... |
| 代码质量 | PASS/FAIL | ... |

## 最终判定
- 全部 PASS → 输出 FINAL:APPROVED
- 有任何 FAIL → 输出 FINAL:REJECTED + 打回原因"

$HOME/.local/bin/hermes chat -q "$AUDIT_PROMPT" --yolo 2>&1 | tail -10

# 4. Read audit result — 强验证: 文件必须包含审计清单
AUDIT_FILE="$HOME/wiki-${GID}/raw/qa-audit-${TASK_ID}.md"
if [ -f "$AUDIT_FILE" ] && [ -s "$AUDIT_FILE" ]; then
    # 强验证: 审计文件必须包含至少 3 个检查项（防止 QA 幻觉——只写 FINAL 不走流程）
    CHECK_COUNT=$(grep -c 'PASS\|FAIL' "$AUDIT_FILE" 2>/dev/null || echo 0)
    if [ "$CHECK_COUNT" -lt 3 ]; then
        echo "[QA#$GID] ⚠️ 审计文件疑似幻觉: 仅有 $CHECK_COUNT 个 PASS/FAIL 判定 — 保持 review" >&2
        exit 0
    fi
    
    if grep -q "FINAL:APPROVED" "$AUDIT_FILE"; then
        # Approved: mark done + add comment
        curl -sf -X PUT -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID" \
          -H "Content-Type: application/json" \
          -d "{\"status\":\"done\"}" > /dev/null 2>&1
        
        curl -sf -X POST -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID/comments" \
          -H "Content-Type: application/json" \
          -d "{\"content\":\"✅ QA审计通过 (#$GID)。详见 $(basename $AUDIT_FILE)\"}" > /dev/null 2>&1
        
        echo "[QA#$GID] ✅ 任务 #$TASK_ID 审计通过 → done" >&2
    else
        # Rejected: back to in_progress + comment with reason
        REASON=$(grep "FINAL:REJECTED" "$AUDIT_FILE" | head -1 | cut -d- -f2-)
        [ -z "$REASON" ] && REASON="QA审计不通过，详见 $(basename $AUDIT_FILE)"
        
        curl -sf -X PUT -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID" \
          -H "Content-Type: application/json" \
          -d "{\"status\":\"in_progress\"}" > /dev/null 2>&1
        
        curl -sf -X POST -H "x-api-key: $MC_API_KEY" "$MC_URL/api/tasks/$TASK_ID/comments" \
          -H "Content-Type: application/json" \
          -d "{\"content\":\"❌ QA审计不通过 (#$GID): $REASON\"}" > /dev/null 2>&1
        
        echo "[QA#$GID] ❌ 任务 #$TASK_ID 打回 → in_progress: $REASON" >&2
    fi
else
    echo "[QA#$GID] ⚠️ 审计文件未生成，保持 review 状态" >&2
fi
