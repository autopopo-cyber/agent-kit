#!/usr/bin/env python3
"""QA Task Poller v3 — queries review tasks (no name filter), uses GID only."""
import json, sys, os, urllib.request

GID = os.environ.get('MC_AGENT_GLOBAL_ID', '')
MC = os.environ.get('MC_URL', 'http://100.80.136.1:3000')
KEY = os.environ.get('MC_API_KEY', '')

if not GID:
    sys.exit(0)

try:
    url = f"{MC}/api/tasks?status=review&limit=1"
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
        'description': t.get('description', '') or '',
        'developer': t.get('assigned_to', ''),   # now a GID
        'project': t.get('project_name', 'unknown')
    }, ensure_ascii=False))

except Exception:
    sys.exit(0)
