# 仙秦舰队 — 心跳与锁完整架构 v7.2

> 撰写: 萱萱 | 日期: 2026-04-28 | 版本: v7.2
>
> 摘要: 记录仙秦舰队从 push 模式演进到 cron 自治 pull 模式过程中，
> 心跳机制和锁机制的全部设计、实现、踩坑和修复。

---

## 1. 架构演进

```
v1-v4: MC push 调度 — MC 主动分发任务，3个 scheduler 常驻
  ↓ 问题: 中央瓶颈，agent 假在线（LLM 编造行为）
v5:   bash 打卡 + LLM ping pong — LLM 只证明存活，不参与机械操作
  ↓ 问题: 僵尸锁沉默 cron，全舰队假死
v6:   三层 ping + 严格 HTTP 错误码判决 — 区分 200/401/429/500/503
  ↓ 问题: 锁在心跳前面，僵尸锁扼杀心跳
v7:   心跳永远先发，心跳负责清理僵尸锁
  ↓ 问题: 丞相 key 提取顺序错误（OpenRouter vs DeepSeek）
v7.2: .env 优先 + 跳过 sk-or-*，全舰队统一 key 提取
```

---

## 2. 核心设计原则

### 2.1 分层

```
┌──────────────────────────────────────┐
│ 确定性层 (bash curl)                   │
│   • 心跳打卡    • 锁管理              │
│   • 产物验证    • MC API 调用          │
│   永不失败，不依赖 LLM                  │
├──────────────────────────────────────┤
│ 存活证明层 (LLM ping)                  │
│   • DeepSeek API 极简请求             │
│   • 严格 HTTP 码判决                   │
│   唯一用途：证明 LLM 工具链可用         │
├──────────────────────────────────────┤
│ 任务执行层 (hermes LLM)                │
│   • 代码编写    • 分析文档            │
│   • git 操作    • wiki 维护            │
│   非确定性，依赖 LLM 推理能力           │
└──────────────────────────────────────┘
```

### 2.2 控制权

```
心跳 > 锁 > 任务
```

- 心跳不受锁约束（永远先发）
- 锁保护任务不重复执行
- 心跳负责检测和清理僵尸锁

---

## 3. 心跳机制

### 3.1 判决矩阵

| DeepSeek 响应 | 含义 | 判决 | 动作 |
|---------------|------|------|------|
| HTTP 200 + content 非空 | LLM 正常 | ✅ 存活 | 发心跳 |
| HTTP 400 | 请求格式错误 | ❌ key 问题 | 跳过心跳 |
| HTTP 401 | 鉴权失败 | ❌ key 过期 | 跳过心跳 |
| HTTP 402 | 余额不足 | ❌ 充钱 | 跳过心跳 |
| HTTP 422 | 参数错误 | ❌ 模型名错 | 跳过心跳 |
| HTTP 429 | 限流 | ❌ 太频繁 | 跳过心跳（自愈） |
| HTTP 500/503 | DeepSeek 挂了 | ❌ 等服务恢复 | 跳过心跳 |
| 超时/连接失败 | 网络 | ❌ | 跳过心跳 |
| 返回空 content | 模型幻觉 | ❌ | 跳过心跳 |

### 3.2 三层 ping 防线

```
cron 触发
  ├─ Ping 1: 脚本开头 — 活着才打卡 "我没活但人在"
  ├─ Ping 2: 执行任务前 — 活着才启动 hermes
  └─ Ping 3: 执行后 — 活着才交 review
```

### 3.3 心跳发送

```bash
heartbeat() {
  curl -sf -X POST -H "x-api-key: $MC_API_KEY" \
    -H "Content-Type: application/json" -d '{}' \
    "$MC_URL/api/agents/$DBID/heartbeat" > /dev/null 2>&1
}
```

- 直接 bash curl，不经过 LLM
- 目标: `POST /api/agents/{DB_ID}/heartbeat`
- MC 端: `updateAgentStatus()` → `UPDATE agents SET status=?, last_seen=?, last_activity=?`

---

## 4. 锁机制

### 4.1 锁文件

```
路径: ~/.xianqin/mc-poll-{GLOBAL_ID}.lock
格式: PID:TASK_ID
示例: 12345:117
```

| 字段 | 含义 | 用途 |
|------|------|------|
| PID | 执行任务的进程 ID | `kill -0 PID` 判断存活 |
| TASK_ID | MC 中任务编号 | 查 MC 确认任务状态 |
| TTL | 600 秒 (10 min) | 超时进入僵尸检测 |

### 4.2 锁生命周期

```
获取:  echo "$$:$TASK_ID" > "$LOCK"   ← Phase 2 开始
释放:  trap 'rm -f "$LOCK"' EXIT      ← 任何路径退出自动释放
检查:  心跳 Phase 0.5                  ← 每次 cron 第一个动作
清理:  is_zombie_lock() → rm "$LOCK"  ← 心跳负责
```

### 4.3 僵尸锁四步判定

函数 `is_zombie_lock()`:

```
Step 1: LOCK_AGE <= 600s ?
  → YES: 锁有效 — 不清理 (return 1)
  → NO:  继续

Step 2: kill -0 LOCK_PID 成功 ?
  → YES: 进程还在跑（慢任务）— 保留锁 (return 1)
  → NO:  继续

Step 3: GET /api/tasks/LOCK_TASK
  → status ∈ {review, completed, failed} ?
  → YES: 任务已结束 — 确认僵尸 (return 0)
  → NO:  继续

Step 4: PID 死了 + 任务状态未知
  → 判定僵尸 (return 0)
```

---

## 5. 完整执行流程 (v7.2)

```
┌──────────────────────────────────────────────┐
│          mc-poll.sh v7.2 — cron 触发           │
├──────────────────────────────────────────────┤
│                                              │
│  Phase 0: 心跳                                │
│    ├─ llm_ping() → DeepSeek pong             │
│    ├─ 200 + OK → heartbeat() curl MC          │
│    └─ 其他 → 跳过                             │
│                                              │
│  Phase 0.5: 锁检查                            │
│    ├─ 无锁 → 继续                             │
│    ├─ 有效 (<600s) → exit 0                   │
│    ├─ 过期 + PID活 → exit 0                   │
│    └─ 僵尸 → 🧹 rm LOCK, 继续                 │
│                                              │
│  Phase 1: 拉任务                              │
│    ├─ mc-poll.py → inbox 认领                 │
│    └─ 无任务 → 巡逻完成, exit 0               │
│                                              │
│  Phase 2: 执行 🔒                             │
│    ├─ echo "$$:$TASK_ID" > LOCK              │
│    ├─ trap 'rm LOCK' EXIT                     │
│    ├─ PUT tasks/N in_progress                 │
│    ├─ hermes chat → 写代码/分析               │
│    └─ 失败 → exit (trap 释放锁)               │
│                                              │
│  Phase 3: 验证 + 交活 🔓                      │
│    ├─ 产物文件验证                             │
│    ├─ llm_ping() → heartbeat()                │
│    ├─ PUT tasks/N review                      │
│    └─ exit → trap EXIT → rm LOCK              │
│                                              │
└──────────────────────────────────────────────┘
```

---

## 6. 踩坑记录

### 坑#1: 僵尸锁 (2026-04-28 14:00-17:00)

**现象**: 白起/王翦/俊秀/雪莹/红婳 心跳全部 >3h，只有白起勉强活着。

**根因**: `mc-poll.sh` v5/v6 在心跳前面设锁。进程被杀时 `trap EXIT` 不触发，锁永留。下次 cron 看到锁 → `exit 0`，心跳永远发不出。

**修复 (v7)**:
- 心跳移到锁前面（Phase 0 先于 Phase 0.5）
- 锁写 PID，心跳检查 `kill -0 PID`
- TTL 600s 过期自动触发僵尸检测

**教训**: 锁不该挡健康检查。心跳是"我还活着"，锁是"别重复干活"，两个不同层次。

---

### 坑#2: 丞相 DeepSeek key 被 OpenRouter key 覆盖 (17:40)

**现象**: 白起/王翦心跳 OK，丞相 `LLM 不通, 心跳跳过`。但手动 curl 丞相的 DeepSeek API 正常。

**根因**: `mc-poll.sh` 的 key 提取顺序：
```bash
1. env DEEPSEEK_API_KEY      # cron 环境无
2. config.yaml api_key       # sk-or-...3357 (OpenRouter!)
3. .env DEEPSEEK_API_KEY     # sk-b2ee0... (正确，但永远不会到达)
```
`config.yaml` 的 `main.api_key` 是 OpenRouter key（hermes 用它）。脚本先读到它，拿去调 DeepSeek → 401。

**修复 (v7.2)**:
```bash
# 1. .env 优先 — DeepSeek 专用 key
DEEPSEEK_KEY=$(grep 'DEEPSEEK_API_KEY' ~/.hermes/.env)
# 2. config.yaml — 但跳过 OpenRouter key
CANDIDATE=$(grep 'api_key:' ~/.hermes/config.yaml)
if [ "${CANDIDATE:0:6}" != "sk-or-" ]; then
  DEEPSEEK_KEY="$CANDIDATE"
fi
```

**教训**: 不同 API 的 key 不该混在同一个配置源。DeepSeek key 放 `.env`，OpenRouter key 放 `config.yaml`。

---

### 坑#3: MC 重建清空 DB (17:24)

**现象**: 重建 MC 后所有 agent 消失、任务消失、用户 session 失效。

**根因**: `npm run build` → `.next/standalone/.data/mission-control.db` 被替换为 seed 数据（7个 skill agent，0个任务，1个 admin 用户但密码 hash 不匹配）。

**修复**:
- 重新 INSERT 8 个舰队 agent
- 重建任务 #110 #117
- 修复 settings 表（`security.api_key`）
- 重置 admin 密码 hash

**教训**: 重建前应备份 `.data/` 目录。`npm run build` 不是幂等的——会覆盖数据。

---

### 坑#4: 心跳 API 返回 200 但不写 DB (15:50-17:24)

**现象**: `POST /api/agents/4/heartbeat` 返回 `HEARTBEAT_OK` 但 agent `last_seen` 不更新。

**根因**: MC 源码已更新（添加了 `updateAgentStatus`），但 **从未重新编译**。运行的是旧版 `.next/standalone/`，旧版心跳只返回通知，不写 DB。

**修复**: 杀进程 → `npm run build` → 重启（导致坑#3）。

**教训**: 改源码必须重建部署。编译检查和运行版本检查应该自动化。

---

### 坑#5: 8 agent 数据库 ID 映射不一致

**现象**: `mc-poll.sh` 用 `GID→DBID` 映射，但 DB 中 agent 的 `id` 和 `global_id` 是两个字段。

**事实**:
- MC 内部用 `agents.id`（自增，重建后会变）
- mc-poll.sh 用 `DBID`（硬编码映射）→ curl `/api/agents/{DBID}/heartbeat`
- MC heartbeat API 用 `id` 查 agent（`SELECT * FROM agents WHERE id = ?`）

**当前映射** (v7.2):
```
101→10, 102→4, 103→5, 104→6, 105→18, 106→19, 107→20, 108→21
```

**风险**: DB 重建时如果自增 ID 改变，这个映射会全错。

**教训**: 应该通过 API `GET /api/agents?global_id=102` 动态获取 DB ID，而不是硬编码。

---

## 7. 8 Agent 配置表

| GID | 名称 | 节点 | DB ID | cron 偏移 | 心跳 | 锁 |
|-----|------|------|-------|-----------|------|-----|
| 101 | 相邦 | localhost | 10 | 0s | 🟢 | — |
| 102 | 白起 | 100.64.63.98 | 4 | 15s | 🟢 | ✅ |
| 103 | 王翦 | 100.67.214.106 | 5 | 30s | 🟢 | ✅ |
| 104 | 丞相 | 100.76.65.47:2222 | 6 | 45s | 🟢 | ✅ |
| 105 | 萱萱 | localhost | 18 | 60s | 🟢 | — |
| 106 | 俊秀 | 100.64.63.98 | 19 | 75s | 🟢 | ✅ |
| 107 | 雪莹 | 100.67.214.106 | 20 | 90s | 🟢 | ✅ |
| 108 | 红婳 | 100.76.65.47:2222 | 21 | 105s | 🟢 | ✅ |

**偏移规则**: 每 15s 错峰，防 8 个同时打 MC。

---

## 8. 关键文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `mc-poll.sh` | `~/repos/agent-kit/scripts/` (源) / `~/.xianqin/mc/` (部署) | 每 agent 每 10min 执行一次 |
| `mc-poll.py` | `~/.xianqin/mc/` | Python 脚本，从 MC inbox 认领任务 |
| `fleet-poll-cron.sh` | `~/repos/agent-kit/scripts/` | Cron wrapper，互斥锁 |
| `mission-control.db` | `MC/.next/standalone/.data/` | SQLite，agent/任务/心跳全在这 |
| `heartbeat/route.ts` | `MC/src/app/api/agents/[id]/heartbeat/` | MC 心跳 API 源码 |
| `auth.ts` | `MC/src/lib/auth.ts` | 鉴权逻辑（API key + session） |

---

## 9. 诊断命令

```bash
# 全舰队锁状态
for host in qin@100.64.63.98 qin@100.67.214.106 qinj@100.76.65.47; do
  ssh "$host" 'ls -la ~/.xianqin/mc-poll-*.lock 2>/dev/null || echo 无锁'
done

# 全舰队心跳
sqlite3 ~/MC/.next/standalone/.data/mission-control.db \
  "SELECT name, status, datetime(last_seen,'unixepoch','localtime') 
   FROM agents WHERE global_id IS NOT NULL"

# 清理所有僵尸锁
for host in ...; do
  ssh "$host" 'for f in ~/.xianqin/mc-poll-*.lock; do
    [ ! -f "$f" ] && continue
    age=$(($(date +%s) - $(stat -c %Y "$f")))
    [ "$age" -gt 600 ] && rm -v "$f"
  done'
done

# 看某 agent 最新 cron 日志
ssh qin@100.64.63.98 "tail -20 /tmp/mc-poll-102.log"
```

---

## 10. 未来改进

1. **DB ID 动态获取**: 用 `GET /api/agents?global_id=102` 替代硬编码映射
2. **心跳可视化**: MC 页面显示五层心跳而非二元在线/离线（相邦 #117 负责）
3. **留言板**: 取代实时聊天，与 inbox 机制统一
4. **自动备份**: cron 每 6h 备份 `.data/` 到 `/lhcos-data/backups/`
5. **构建验证**: CI 检查编译后 API 行为是否与源码一致
