# 相邦 · Plan-Tree v3 | 当前: 04-27 21:00

> Plan-Tree 是精炼语言——用较少的信息量粗略构造一段时空及其逻辑演进。
> 节点是逻辑时空道标，描述的是一段行为在四维时空中的位置和因果方向。

## ENSURE_CONTINUATION

### 自检 + 备份 (#ensure-continuation) | 相邦 | HIGH
  - 04-25 21:18 流入: 君上"舰队需要生存本能" → 创建 Plan-Tree v2
  - 04-25 21:46 产物: 首次健康检查全绿 (Disk 18% RAM 29% Gateway✅ MC✅)
  - 04-26 09:03 判定: Gateway 502 → FAIL → 触发 CRASH_FIX
  - 04-26 09:35 判定: Gateway 恢复 ✅ 根因=agent-browser并发触发gateway自杀
  - 04-27 每日: 健康检查自动化（cron heartbeat + lock refresh）
  - 流出: 健康状态 → MC heartbeat (每30s)
  - 关联: 触发→CRASH_FIX(因果触发) | 验证反馈→CRASH_FIX(修复后验证)

### Gateway 502 修复 (#crash-fix) | 相邦 | CRITICAL ✅
  - 04-26 09:03 流入: Gateway 502 — 某个hermes会话通过gateway spawn 子进程执行了 systemctl stop gateway
  - 04-26 09:10 产物: bridge-cleanup.sh — 安全清理bridge(>30min) 不碰gateway
  - 04-26 09:12 产物: session-lock.sh — trap EXIT自动释放，防并发冲突
  - 04-26 09:12 产物: 日报脚本修复 — hermes完整路径 + PATH注入 + lock前置
  - 04-26 09:15 产物: Skill hermes-gateway-crash-recovery 创建 (含诊断流程)
  - 04-26 09:30 判定: Gateway防自杀保护就绪 ✅ RESOLVED
  - 04-26 09:35 流出: → wiki crash-history (2次崩溃记录)
  - 关联: 触发→MC_INTEGRATION(cron会话隔离改进) | 被等←ROOT(因果触发) | 信息复用→全部Agent(bridge-cleanup脚本共用)

### Cron 会话连续性 (#cron-continuity) | 相邦 | HIGH ✅
  - 04-25 21:18 流入: 君上"crontab应该有锁机制避免多个会话冲突"
  - 04-25 21:18 产物: lock-manager.sh (check/acquire/release/refresh/status)
  - 04-26 09:12 产物: session-lock.sh 集成到 daily-report.sh
  - 04-26 11:48 产物: mc-poll.sh 独立锁 (touch lockfile + trap EXIT)
  - 判定: 并发安全 ✅ 锁体系完整
  - 关联: 触发→CRASH_FIX(因果触发) | 信息复用→全部cron job(锁机制共用)

---

## EXPAND_CAPABILITIES

### 机器狗避障开发 (#nav-dog) | 白起+王翦 | HIGH ⚙️
  - 04-25 21:18 流入: 君上"机器狗需要避障能力" → 相邦分配白起+王翦
  - 04-26 期间: NAV-1 仿真 ✅ | NAV-2 LIDAR ✅ | NAV-3 DWA ✅ | NAV-4 VISION ✅ | NAV-5 VLAC ✅
  - 04-27 状态: NAV-6 E2E 待启动 | NAV-7 DEPLOY 待启动
  - 04-27 14:21 流入: 君上"优先验证避障"
  - 流出: → 白起 Plan-Tree #navdog-e2e | → 王翦 Plan-Tree #navdog-vlac
  - 关联: 触发→A2_SIM(硬依赖，需要URDF) | 资源竞争: 白起+王翦共享 | 被阻塞←PyTorch fail_ct=3(RTX2080Ti环境)

### 宇树 A2 真机 URDF 仿真集成 (#a2-sim) | 白起+王翦 | HIGH ⚙️
  - 04-26 12:00 流入: 君上"A2 URDF + MuJoCo仿真"
  - 04-27 03:05 状态: A2-1 URDF 开发中 (白起 A2Robot类) | A2-2 ROS2 方案调研中 (王翦)
  - 待启动: A2-3 MUJOCO | A2-4 GO2_RL
  - 04-27 14:21: MC 通知白起+王翦更新进度
  - 关联: 被等←NAV_DOG(硬依赖，避障需要URDF) | 资源竞争: 白起(URDF+仿真) vs 王翦(ROS2+RL)

### 论坛发帖自动化 (#forum-post) | 相邦 | MEDIUM ⏸️
  - 04-26 17:00 流入: 君上"应该自动化外宣发帖"
  - 04-26 17:20 产物: V2EX API调研 (API 2.0只读, 发帖需browser-use)
  - 04-26 17:20 产物: Reddit OAuth API 完整可行
  - 04-26 17:20 产物: 5篇可公开文章策略
  - 当前: FMP-2 CONTENT / FMP-3 TOOLS 进行中 | FMP-4 V2EX 待启动
  - 关联: 被等←无硬依赖 | 信息复用→萱萱#outreach(内容策略可共用)

### MC 双向集成 (#mc-integration) | 相邦 | HIGH ✅
  - 04-25 21:18 流入: 君上"MC 应该双向——Agent 自动拉任务"
  - 04-26 11:48 产物: mc-poll.sh 部署 (白起+王翦 cron 5min)
  - 04-26 11:50 判定: MC-18 inbox→assigned→in_progress 全自动 ✅
  - 04-27 14:21 判定: SSH推送降级为备用方案 ✅ MC轮询为主
  - 关联: 触发→全部Agent(MC拉任务标准化) | 被等←CRASH_FIX(锁机制) | 信息复用→萱萱(MC-QA交互)

---

## EXPAND_WORLD_MODEL

### 基础设施可观测性 (#infra) | 相邦 | HIGH
  - 04-25 21:18 流入: 君上"系统需要自愈能力"
  - 04-25→04-27: WebUI+Gateway systemd ✅ | Mihomo代理 ✅ | MC登录修复 ✅ | 丞相WebUI ✅
  - 04-26 00:29 产物: 副模型方案确认 (V4 Flash $0.28/M + Qwen3-VL-32B $0.416/M)
  - 04-26 09:15 产物: crash-history (2次Gateway崩溃记录, 趋势:清理bridge僵尸→重启gateway)
  - 04-27 状态: 模型切换等待君上指令
  - 流出: 健康状态 → idle-log | crash-history → wiki
  - 关联: 信息复用→全部Agent(健康检查脚本共用) | 触发→MODEL_SWAP(待君上指令)

### Plan-Tree 优化研究 (#plan-tree-opt) | 相邦 | HIGH ⚙️
  - 04-25 21:18 流入: 君上"Plan-Tree 是一门精炼语言"
  - 04-25→04-26: 哲学推导 (精炼语言+逻辑时空道标)
  - 04-26: 审查下发 → 白起反馈✅ 王翦/丞相未反馈
  - 04-27: v3 设计 → 萱萱提交评审
  - 04-27 21:00 产物: 相邦评审回复 + v3 Plan-Tree 迁移
  - 04-27 21:00 判定: 评审通过，Phase 1-2 批准执行
  - 关联: 触发→萱萱#ptree-v3(因果触发) | 触发→全部Agent(v3迁移) | 验证反馈→王翦/丞相(v2对照组)

---

## 逻辑时空道标

### ROOT (#root) | 相邦 | HIGH
  - 04-25 21:18 流入: 君上"舰队需要生存本能"
  - 04-25 21:18→04-27 21:00: Plan-Tree v2.1 运行 + MC 部署 + 舰队轮询
  - 04-27 21:00: 相邦 v3 Plan-Tree 迁移完成
  - 流出: → 全舰队 (MC 任务分发 + cron 调度)
  - 关联:
    - 硬依赖→无 (ROOT 是根)
    - 因果触发→CRASH_FIX (连续2次502崩溃, 君上反馈+今天9AM触发)
    - 因果触发→NAV_DOG (机器狗避障, RTX2080Ti×2)
    - 因果触发→MC_INTEGRATION (MC轮询标准化)
    - 因果触发→PLAN_TREE_OPTIMIZE (v3 升级)
    - 信息复用→全部 (cron框架/锁机制/日志体系)
  - 根因链:
    - CRASH_FIX: 根因=cron新会话无上下文导致多个"我"互不知情
    - → bridge-cleanup.sh (杀bridge≠杀gateway)
    - → session-lock.sh (防并发操作)
    - → 日报+crontab PATH修复

---

--- NOW (04-27 21:00) ---

## 预测区 (04-27 21:00 快照)

### 短期 (24h内)

**#l1-unify (Phase 1):**
  乐观: 04-27 23:00 完成 (置信度 0.85) | 条件: l1-mc-poll.sh 脚本无意外
  悲观: 04-28 10:00 完成 (置信度 0.15) | 风险: mc-poll.py 参数适配需要调试

**#xiangbang-v3 (Phase 2):**
  乐观: 04-27 23:00 完成 (置信度 0.9) | 条件: 本次会话写完
  悲观: 04-28 12:00 (置信度 0.1) | 风险: 格式细节需要微调

**#l2-pilot (Phase 2):**
  乐观: 04-28 12:00 首次运行 (置信度 0.7) | 条件: hermes gateway 在线
  悲观: 04-28 18:00 (置信度 0.3) | 风险: LLM prompt 需要迭代

### 中期 (72h)

- **NAV_DOG 全闭环**: 乐观 04-28 / 悲观 04-29 (置信度 0.5)
  - 关键路径: PyTorch 环境修复 → NAV-6 E2E → NAV-7 DEPLOY
  - 阻塞: PyTorch fail_ct=3 (RTX2080Ti×2 环境问题)

- **A2 URDF 完成**: 乐观 04-28 / 悲观 04-30 (置信度 0.6)
  - 白起 A2Robot 类开发中，依赖仿真验证

- **v3 全舰队迁移**: 乐观 05-01 (置信度 0.3)
  - 王翦+丞相 保留 v2 对照组，迁移时机取决于一周对比数据

### 关键路径

当前阻塞链:
```
ROOT
  ├→ NAV_DOG (阻塞: PyTorch fail_ct=3)
  │   └→ A2_SIM (阻塞: 等待 URDF 完成)
  ├→ FORUM_POST (阻塞: 低优先级，无紧迫依赖)
  └→ PLAN_TREE_OPTIMIZE (进行中: v3 迁移审查)
      └→ v3 全舰队 (等待: 一周对比数据)
```

最长路径预计: NAV_DOG → A2_SIM → 05-01

### 资源预测

- 相邦上下文: 当前8轮 | 衰减拐点≈第12轮 | 建议4轮后刷新
- 白起上下文: 未知 (MC heartbeat 可见，上下文未监控)
- 王翦上下文: 未知
- LLM API: 正常 (V4 Flash 备用可用)

---

## 预测归档

### 04-26 预测 · 已过期

- **CRASH_FIX 预计 04-26 10:00 完成** | 实际 04-26 09:35 完成 ✅
  偏差: -25min (提前完成) → 根因分析准确，修复路径短

- **MC_INTEGRATION 预计 04-26 18:00 完成** | 实际 04-26 11:50 完成 ✅
  偏差: -6h10min → 君上直接推动 mc-poll.py 开发，加速显著

- **论坛发帖预计 04-26 完成** | 实际未完成，降级为 MEDIUM 优先级
  → 原因: NAV_DOG + A2_SIM 优先级更高，相邦资源被占用

---

> 相邦吕不韦 | Plan-Tree v3
> 创建: 04-27 21:00 | 从 v2 迁移
> v2 备份: ~/xianqin/plan-tree-v2-backup.md
