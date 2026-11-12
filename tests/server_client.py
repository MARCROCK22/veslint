#!/usr/bin/env python3
"""server_client.py VESLINT CWD REQUESTS: starts `VESLINT --server` in CWD, sends it the requests
of the file REQUESTS (one JSON object per line), and prints its answers (one JSON object per line)
in order, with the absolute path of CWD written <cwd>. A request may use the placeholder <cwd> too.
A line {"write": PATH, "text": TEXT} is not sent: it writes TEXT to PATH, to change a file on disk
between two requests. The server must answer every request and exit with code 0 when its stdin
ends."""
import json
import os
import subprocess
import sys

# The answers are compared byte for byte: `\n` also on Windows, where Python would write `\r\n`.
sys.stdout.reconfigure(newline='\n')
veslint, cwd, requests_file = sys.argv[1:4]
cwd = os.path.abspath(cwd)
server = subprocess.Popen([os.path.abspath(veslint), '--server'], cwd=cwd, stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
for line in open(requests_file, encoding='utf-8'):
    if not line.strip():
        continue
    line = line.replace('<cwd>', cwd)
    request = json.loads(line) if line.lstrip().startswith('{') else None
    if isinstance(request, dict) and 'write' in request:
        with open(request['write'], 'w', encoding='utf-8', newline='') as f:
            f.write(request['text'])
        continue
    server.stdin.write(line if line.endswith('\n') else line + '\n')
    server.stdin.flush()
    answer = server.stdout.readline()
    if not answer:
        sys.exit(f'the server exited without answering: {server.stderr.read()}')
    print(json.dumps(json.loads(answer), ensure_ascii=False).replace(cwd, '<cwd>'))
server.stdin.close()
code = server.wait(timeout=30)
rest = server.stdout.read()
if code != 0 or rest:
    sys.exit(f'the server ended with code {code} and printed {rest!r}; stderr: {server.stderr.read()}')
