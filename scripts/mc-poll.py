#!/usr/bin/env python3
"""MC Task Poller v3 — uses global_id only (no names)."""
import json, sys, os, urllib.request

GID = os.environ.get('MC_AGENT_GLOBAL_ID', '')
MC = os.environ.get('MC_URL', 'http://100.80.136.1:3000')
KEY = os.environ.get('MC_API_KEY', '')

if not GID:
    sys.exit(0)

try:
    # Query by global_id only — no names, no URL encoding issues
    url = f"{MC}/api/tasks?assigned_to={GID}&status=inbox&limit=1"
    req = urllib.request.Request(url)
    req.add_header('x-api-key', KEY)
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    
    tasks = data if isinstance(data, list) else data.get('tasks', [])
    if not tasks:
        sys.exit(0)
    
    t = tasks[0]
    print(json.dumps({
        'id': t['id'],
        'title': t.get('title', '')[:120],
        'description': t.get('description', '') or ''
    }, ensure_ascii=False))

except Exception:
    sys.exit(0)
