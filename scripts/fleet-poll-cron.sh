#!/bin/bash
# Fleet Poll Cron Wrapper — 锁 + 调副模型skill
# Cron: */10 * * * * MC_AGENT_GLOBAL_ID=102 MC_API_KEY=xxx bash fleet-poll-cron.sh
set -e

GID="${MC_AGENT_GLOBAL_ID:-}"
[ -z "$GID" ] && exit 1

LOCK="$HOME/.xianqin/mc-poll-${GID}.lock"
[ -f "$LOCK" ] && exit 0
touch "$LOCK"
trap 'rm -f "$LOCK"' EXIT

exec ~/.local/bin/hermes chat -q "使用 fleet-poll 技能执行巡逻。严格按6步协议：1查任务→2扫inbox→3无则打卡→4执行→5验证→6打卡交review。不分析、不发散、不提问。现在开始。" --yolo --model deepseek-v4-flash
