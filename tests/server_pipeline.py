#!/usr/bin/env python3
"""server_pipeline.py VESLINT: requests written to `VESLINT --server` before the answers to the
previous ones, as an editor sends one for each change of a file. In tests/config, ten requests for
base.ts, each with another unsaved text, and one for other/a.ts among them, written at once. The
answers must come in order, and the one for other/a.ts and the last one for base.ts must be what
a server answers to each alone. The others for base.ts may be given up (a later request lints the
same file), with an empty answer and `cancelled`; at least one of them must be, since all ten are
read before the first ends. A request that is not given up is answered in full. Prints what is
wrong and exits with 1."""
import json
import os
import subprocess
import sys

veslint = os.path.abspath(sys.argv[1])
cwd = os.path.abspath('tests/config')
base = os.path.join(cwd, 'base.ts')
other = os.path.join(cwd, 'other/a.ts')
text = open(base, encoding='utf-8', newline='').read()
requests = [{'config': 'resolved.json', 'files': [base], 'texts': {base: text + f'\nPromise.resolve({i});\n'}}
            for i in range(10)]
requests.insert(5, {'config': 'resolved.json', 'files': [other]})
for i, request in enumerate(requests):
    request['id'] = i + 1


def start():
    return subprocess.Popen([veslint, '--server'], cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding='utf-8')


def answer_of(server):
    return json.loads(server.stdout.readline())


# What a server answers to each request alone.
alone = start()
expected = []
for request in requests:
    alone.stdin.write(json.dumps(request) + '\n')
    alone.stdin.flush()
    expected.append(answer_of(alone))
alone.stdin.close()
alone.wait()

server = start()
server.stdin.write(''.join(json.dumps(request) + '\n' for request in requests))
server.stdin.flush()
answers = [answer_of(server) for _ in requests]
server.stdin.close()
code = server.wait()

problems = []
if code != 0:
    problems.append(f'the server exited with code {code}')
last_base = max(i for i, request in enumerate(requests) if request['files'] == [base])
cancelled = 0
for i, (request, answer, want) in enumerate(zip(requests, answers, expected)):
    if answer.get('id') != request['id']:
        problems.append(f'answer {i + 1} is for request {answer.get("id")}, not {request["id"]}')
        continue
    if answer.get('cancelled'):
        cancelled += 1
        if request['files'] != [base] or i == last_base:
            problems.append(f'request {request["id"]} was given up, and no later request lints its file')
        elif (answer.get('code'), answer.get('stdout'), answer.get('stderr')) != (0, '', ''):
            problems.append(f'request {request["id"]} was given up with an answer that is not empty: {answer}')
        continue
    if answer != want:
        problems.append(f'request {request["id"]}: {answer} instead of {want}')
if cancelled == 0:
    problems.append('no request was given up, although nine of them have a later request for the same file')
for problem in problems:
    print(problem)
sys.exit(1 if problems else 0)
