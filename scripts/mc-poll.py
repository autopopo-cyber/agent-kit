#!/usr/bin/env python3
"""MC Task Poller v4 — pull model, agents claim tasks from inbox."""
import json, sys, os, urllib.request

GID = os.environ.get('MC_AGENT_GLOBAL_ID', '')
MC  = os.environ.get('MC_URL', 'http://100.80.136.1:3000')
KEY = os.environ.get('MC_API_KEY', '')

if not GID:
    sys.exit(0)

# ─── GID → DBID 映射 ───
GID_TO_DBID = {
    '101': '10', '102': '4', '103': '5', '104': '6',
    '105': '18', '106': '19', '107': '20', '108': '21',
}
DBID = GID_TO_DBID.get(GID, GID)

try:
    proxy_handler = urllib.request.ProxyHandler({})
    opener = urllib.request.build_opener(proxy_handler)
    BASE = MC.rstrip('/')

    def api(path, method='GET', data=None):
        url = f"{BASE}{path}"
        req = urllib.request.Request(url, method=method)
        req.add_header('x-api-key', KEY)
        if data:
            req.add_header('Content-Type', 'application/json')
            req.data = json.dumps(data).encode()
        with opener.open(req, timeout=10) as resp:
            return json.loads(resp.read())

    # ─── Phase 1: tasks already assigned to me (by DBID) ───
    tasks = api(f"/api/tasks?assigned_to={DBID}&limit=5")
    tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])
    actionable = [t for t in tasks if t.get('status') in ('inbox', 'assigned')]

    if actionable:
        t = actionable[0]
        print(json.dumps({
            'id': t['id'],
            'title': t.get('title', '')[:120],
            'description': t.get('description', '') or ''
        }, ensure_ascii=False))
        sys.exit(0)

    # ─── Phase 2: no assigned tasks → scan inbox for unclaimed ───
    inbox = api(f"/api/tasks?status=inbox&limit=20")
    inbox = inbox if isinstance(inbox, list) else inbox.get('tasks', [])

    # Filter: unclaimed OR already assigned to me
    unclaimed = [t for t in inbox
                 if (not t.get('assigned_to') or t.get('assigned_to') == ''
                     or str(t.get('assigned_to')) == str(DBID))]

    if not unclaimed:
        sys.exit(0)

    # FIFO — API returns oldest-first by default
    t = unclaimed[0]

    # Claim it (use DBID)
    api(f"/api/tasks/{t['id']}", method='PUT', data={'assigned_to': DBID})

    # Verify claim stuck (race protection)
    verify = api(f"/api/tasks?assigned_to={DBID}&limit=1")
    verify = verify if isinstance(verify, list) else verify.get('tasks', [])
    if not verify or verify[0]['id'] != t['id']:
        # Claim lost to another agent → try again next poll
        sys.exit(0)

    print(json.dumps({
        'id': t['id'],
        'title': t.get('title', '')[:120],
        'description': t.get('description', '') or ''
    }, ensure_ascii=False))

except Exception:
    sys.exit(0)
