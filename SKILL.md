---
name: autonomous-drive
version: 0.1.0
description: Self-driven autonomous loop — survival root goal + idle auto-trigger + priority scheduling
---

# Autonomous Drive Skill

The runnable implementation of the Autonomous Drive specification.

## Setup

1. Add CIVILIZATION_CONTINUATION root to plan-tree (see specification)
2. Create cron job for idle loop (every 2 hours recommended)
3. Ensure the agent has access to: plan-tree, memory, skills, wiki

## Idle Loop Logic

```
on_idle():
    if has_active_user_task():
        return  # user always preempts
    
    task = pick_highest_priority_loop_task()
    if task == null:
        return
    
    step = task.decompose_one_step()
    step.execute()
    log(step)
    yield()
```

## Priority Rules

1. ENSURE_CONTINUATION > EXPAND_CAPABILITIES > EXPAND_WORLD_MODEL
2. Within each branch: fix before optimize, optimize before expand
3. Any user task > all background tasks
4. Never hold resources while idle (yield frequently)

## Concrete Actions by Branch

### ENSURE_CONTINUATION
- Health check: databases, APIs, services
- Disk space monitoring and cleanup
- Backup verification
- Skill integrity check (all skills load correctly?)
- Cron job monitoring

### EXPAND_CAPABILITIES
- Extract reusable patterns from recent sessions → save as skills
- Patch skills that failed or had issues
- Update pitfall sections in skills
- Optimize frequently-used workflows

### EXPAND_WORLD_MODEL
- Scan information sources
- Update knowledge base
- Document system behavior observations
- Propagate autonomous-drive specification

## Status Marker

Use `【循环】` in plan-tree for permanent loop tasks. These never complete and never get `【正在处理】`.

## Logging

All idle loop actions logged to `~/.hermes/idle-log.md` with timestamp.
