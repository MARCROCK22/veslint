#!/usr/bin/env python3
"""server_edits.py VESLINT SEED EDITS CWD CONFIG FILE...: random edits of each FILE (relative to
CWD), linted after each edit as unsaved text by two `VESLINT --server`, one that parses each edit
incrementally from the tree of the text before (with VESLINT_INCREMENTAL_CHECK=1, which also parses
it from scratch and reports a different tree on stderr) and answers a request that changes nothing
with its last answer, and one that parses every text from scratch and lints every request
(VESLINT_INCREMENTAL=0): both must answer the same, and the first must find no different tree.
The edits, seeded by SEED: insertions, deletions and replacements anywhere (of snippets with
multi-byte characters, CR LF, comments, braces, or of a piece of the file), edits of whole lines,
which often keep the file without syntax errors, the same text again and the text on disk."""
import json
import os
import random
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(newline='\n')
veslint, seed, edits, cwd, config = sys.argv[1:6]
files = sys.argv[6:]
cwd = os.path.abspath(cwd)
rng = random.Random(int(seed))
SNIPPETS = ['\n', '\r\n', '\r', ' ', ';', '{', '}', '(', ')', '`', '${', '"', "'", '/*', '*/', '//',
            '<', '>', '=>', 'é', '😀', ' ', 'await ', 'const x = 1;\n', '<T>', 'function f() {',
            'if (a) b\n', '<div>{a}</div>', '<script lang="ts">', '</script>', '{#if a}', '{/if}', 'q']


def random_edit(text):
    # The positions are of code points: an editor's edits keep the text UTF-8.
    at = rng.randint(0, len(text))
    end = min(len(text), at + rng.randint(0, 40))
    kind = rng.randint(0, 2)
    if kind == 0:
        insert = rng.choice(SNIPPETS)
    elif kind == 1 and text:
        start = rng.randint(0, len(text))
        insert = text[start:start + rng.randint(0, 60)]
    else:
        insert = ''
    choice = rng.randint(0, 2)
    if choice == 0:
        return text[:at] + insert + text[at:]
    if choice == 1:
        return text[:at] + text[end:]
    return text[:at] + insert + text[end:]


def line_edit(text):
    sep = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(sep)
    i = rng.randrange(len(lines))
    kind = rng.randint(0, 5)
    if kind == 0:
        lines.insert(i, '// note')
    elif kind == 1:
        del lines[i]
    elif kind == 2:
        lines.insert(i, rng.choice(lines))
    elif kind == 3:
        lines[i] += ' '
    elif kind == 4:
        lines.insert(i, '')
    else:
        line = lines[i]
        letters = [k for k, c in enumerate(line) if c.isalpha()]
        if letters:
            k = letters[0]
            lines[i] = line[:k + 1] + 'q' + line[k + 1:]
    return sep.join(lines)


def start(env):
    errors = tempfile.TemporaryFile(mode='w+', encoding='utf-8')
    process = subprocess.Popen([os.path.abspath(veslint), '--server'], cwd=cwd, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=errors, text=True, encoding='utf-8',
                               env={**os.environ, **env})
    return process, errors


def ask(process, request):
    process.stdin.write(json.dumps(request) + '\n')
    process.stdin.flush()
    answer = process.stdout.readline()
    if not answer:
        sys.exit('a server exited without answering')
    return json.loads(answer)


incremental, incremental_errors = start({'VESLINT_INCREMENTAL_CHECK': '1'})
fresh, _ = start({'VESLINT_INCREMENTAL': '0'})
failures = 0
requests = 0
for file in files:
    path = os.path.join(cwd, file)
    # An editor's text is UTF-8: a file that is not (a fixture of tsgo's decoding) is edited as
    # the editor would show it; the requests for the text on disk read it as it is.
    text = open(path, encoding='utf-8', errors='replace', newline='').read()
    for n in range(int(edits)):
        roll = rng.random()
        if roll < 0.05:
            texts = {}  # the text on disk
        else:
            if roll >= 0.1:  # else the same text again
                text = random_edit(text) if rng.random() < 0.5 else line_edit(text)
            texts = {path: text}
        request = {'id': requests, 'config': config, 'files': [file], 'texts': texts, 'fixes': True}
        requests += 1
        got, want = ask(incremental, request), ask(fresh, request)
        if got != want:
            failures += 1
            if failures <= 5:
                print(f'{file}, edit {n}: the incremental parse answers otherwise')
                print(f'  incremental: {json.dumps(got)[:600]}')
                print(f'  from scratch: {json.dumps(want)[:600]}')
for process in (incremental, fresh):
    process.stdin.close()
    process.wait(timeout=60)
incremental_errors.seek(0)
different = [line for line in incremental_errors if 'differs from a parse from scratch' in line]
for line in different[:5]:
    print(line, end='')
print(f'{requests} requests, {failures} different answers, {len(different)} different trees')
sys.exit(1 if failures or different else 0)
