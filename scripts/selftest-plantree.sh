#!/bin/bash
# selftest-plantree.sh — Plan-Tree 全流程自测
# 验证: Plan-Tree 存在 → 决策点可追溯 → Phase 0.6 有效 → 自动化闭环
set -e

REAL_HOME="${REAL_HOME:-/home/agentuser}"
PASS=0
FAIL=0

green() { echo "  ✅ $1"; PASS=$((PASS+1)); }
red()   { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== Plan-Tree 全流程自测 ==="
echo ""

# ─── 1. Plan-Tree 文件存在 ───
echo "1. Plan-Tree 文件"
PLANTREE="$REAL_HOME/wiki-5/萱萱-PlanTree-v4.md"
if [ -f "$PLANTREE" ]; then
  green "存在: $PLANTREE ($(wc -l < "$PLANTREE") lines)"
else
  red "缺失: $PLANTREE"
fi

# ─── 2. 关键结构 ───
echo ""
echo "2. 关键结构"
for kw in "决策点" "跨Agent依赖矩阵" "预测" "流入" "流出"; do
  if grep -q "$kw" "$PLANTREE" 2>/dev/null; then
    green "$kw: 存在"
  else
    red "$kw: 缺失"
  fi
done

# ─── 3. 决策点可追溯 ───
echo ""
echo "3. 决策点可追溯"
DECISIONS=$(grep -c '^| 04-' "$PLANTREE" 2>/dev/null || echo 0)
echo "  记录的决策点: $DECISIONS 条"
if [ "$DECISIONS" -ge 3 ]; then
  green "至少3条决策可追溯"
else
  red "决策点不足 ($DECISIONS)"
fi

# ─── 4. Phase 0.6 自检脚本在 mc-poll.sh 中存在 ───
echo ""
echo "4. Phase 0.6 产物自检"
MC_POLL="$REAL_HOME/.xianqin/mc/mc-poll.sh"
if grep -q "Phase 0.6" "$MC_POLL" 2>/dev/null; then
  green "mc-poll.sh: Phase 0.6 已嵌入"
else
  red "mc-poll.sh: Phase 0.6 缺失"
fi

# ─── 5. GID→DBID 修复在 mc-poll.py 中存在 ───
echo ""
echo "5. GID→DBID 映射"
MC_POLL_PY="$REAL_HOME/.xianqin/mc/mc-poll.py"
if grep -q "GID_TO_DBID" "$MC_POLL_PY" 2>/dev/null; then
  green "mc-poll.py: GID→DBID 映射已修复"
else
  red "mc-poll.py: 映射缺失"
fi

# ─── 6. fleet-snapshot.py UUID+307 修复 ───
echo ""
echo "6. 巡报修复"
SNAPSHOT="$REAL_HOME/.hermes/scripts/fleet-snapshot.py"
if [ -f "$SNAPSHOT" ]; then
  if grep -q "str(x.get" "$SNAPSHOT" 2>/dev/null && grep -q "/api/agents" "$SNAPSHOT" 2>/dev/null; then
    green "fleet-snapshot.py: UUID+307 已修复"
  else
    red "fleet-snapshot.py: 仍需修复"
  fi
else
  red "fleet-snapshot.py: 文件缺失"
fi

# ─── 7. Gateway Hook 存在 ───
echo ""
echo "7. Gateway Hook (agent:end → 自动更新 PlanTree)"
HOOK_DIR="/home/agentuser/.hermes/profiles/xuanxuan/home/.hermes/hooks/update-plantree"
if [ -f "$HOOK_DIR/HOOK.yaml" ] && [ -f "$HOOK_DIR/handler.py" ]; then
  green "hook 已配置"
else
  red "hook 缺失"
fi

# ─── 总评 ───
echo ""
echo "━━━━━━━━━━━━━━━━━"
echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ Plan-Tree 全流程自动化就绪"
  exit 0
else
  echo "⚠️  $FAIL 项需修复"
  exit 1
fi
