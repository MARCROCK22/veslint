#!/usr/bin/env python3
"""server.py TOOL DIR CONFIG_DIR FILE SET EDITS: the editor case of the benchmark (tests/bench/run.sh).
Starts TOOL's long-lived process in DIR, opens FILE (relative to DIR) and waits for its problems
(`first`, from the start of the process), then edits it EDITS times (a comment appended at the end,
unsaved text) and times each edit until its problems come back. Prints one JSON object: first_ms,
edits_ms, the problems of the last answer and the memory of the process tree at the end (MiB).

TOOL: veslint (`--server`, JSON lines), eslint (tests/bench/eslint_server.mjs: one ESLint instance
and lintText, as the VS Code ESLint extension), oxlint (`--lsp`, with `typeAware` for the sets with
types) or biome (`lsp-proxy`, the biome.json of DIR). The LSP servers get the text with
didOpen/didChange (full text) and answer with textDocument/publishDiagnostics."""
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BENCH = os.path.join(ROOT, 'build', 'bench')
ESLINT = os.path.join(ROOT, 'build', 'eval', 'spider-byte', 'node_modules', 'eslint', 'package.json')
sys.path.insert(0, os.path.dirname(__file__))
from tree_memory import children_of, rss_kib  # noqa: E402


def tree_mib(pid):
    children, tree, stack = children_of(), [], [pid]
    while stack:
        p = stack.pop()
        tree.append(p)
        stack.extend(children.get(p, []))
    return round(sum(rss_kib(p) for p in tree) / 1024)


class Lines:
    """A server that answers each JSON line with one JSON line."""

    def __init__(self, command, cwd, request):
        self.process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
        self.request = request

    def lint(self, version, text):
        self.process.stdin.write(json.dumps(self.request(version, text)) + '\n')
        self.process.stdin.flush()
        return self.count(json.loads(self.process.stdout.readline()))

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=60)


class Lsp:
    """A language server over stdio (Content-Length framing)."""

    def __init__(self, command, cwd, uri, init_options, settings):
        self.process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL)
        self.uri, self.settings, self.next_id = uri, settings, 1
        root = 'file://' + cwd
        self.call('initialize', {
            'processId': os.getpid(), 'rootUri': root, 'workspaceFolders': [{'uri': root, 'name': 'bench'}],
            'capabilities': {'textDocument': {'publishDiagnostics': {'versionSupport': True},
                                              'synchronization': {'didSave': True}},
                             'workspace': {'configuration': True, 'workspaceFolders': True}},
            'initializationOptions': init_options,
        })
        self.notify('initialized', {})
        if settings is not None:
            self.notify('workspace/didChangeConfiguration', {'settings': settings})

    def send(self, message):
        body = json.dumps(message).encode('utf-8')
        self.process.stdin.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
        self.process.stdin.flush()

    def receive(self):
        length = 0
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise EOFError('the language server exited')
            if line in (b'\r\n', b'\n'):
                break
            if line.lower().startswith(b'content-length:'):
                length = int(line.split(b':')[1])
        message = json.loads(self.process.stdout.read(length))
        # Requests of the server: configuration, capabilities, progress.
        if 'method' in message and 'id' in message:
            result = None
            if message['method'] == 'workspace/configuration':
                result = [self.settings for _ in message['params']['items']]
            self.send({'jsonrpc': '2.0', 'id': message['id'], 'result': result})
        return message

    def call(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self.send({'jsonrpc': '2.0', 'id': request_id, 'method': method, 'params': params})
        while True:
            message = self.receive()
            if message.get('id') == request_id and 'method' not in message:
                return message.get('result')

    def notify(self, method, params):
        self.send({'jsonrpc': '2.0', 'method': method, 'params': params})

    def lint(self, version, text):
        if version == 1:
            self.notify('textDocument/didOpen', {'textDocument': {'uri': self.uri, 'languageId': 'typescript',
                                                                  'version': 1, 'text': text}})
        else:
            self.notify('textDocument/didChange', {'textDocument': {'uri': self.uri, 'version': version},
                                                   'contentChanges': [{'text': text}]})
        while True:
            message = self.receive()
            if message.get('method') != 'textDocument/publishDiagnostics':
                continue
            params = message['params']
            if params['uri'] != self.uri or params.get('version', version) != version:
                continue
            return len(params['diagnostics'])

    def close(self):
        try:
            self.call('shutdown', None)
            self.notify('exit', None)
            self.process.wait(timeout=30)
        except Exception:  # noqa: BLE001 - the measures are taken; a server slow to exit is killed
            self.process.kill()


def main():
    tool, cwd, config_dir, file, rule_set, edits = sys.argv[1:7]
    cwd, config_dir = os.path.abspath(cwd), os.path.abspath(config_dir)
    path = os.path.join(cwd, file)
    original = open(path, encoding='utf-8').read()
    start = time.perf_counter()
    if tool == 'veslint':
        server = Lines([os.path.join(ROOT, 'veslint'), '--server'], cwd, lambda version, text: {
            'id': version, 'files': [file], 'config': os.path.join(config_dir, 'eslint.config.mjs'),
            'texts': {path: text}, 'fixes': False})
        server.count = lambda answer: len(answer['stdout'].splitlines())
    elif tool == 'eslint':
        server = Lines(['node', os.path.join(ROOT, 'tests', 'bench', 'eslint_server.mjs'), ESLINT,
                        os.path.join(config_dir, 'eslint.config.mjs')], cwd,
                       lambda version, text: {'file': path, 'text': text})
        server.count = lambda answer: answer['problems']
    elif tool == 'oxlint':
        # oxlint's language server takes the .oxlintrc.json of the workspace (run.sh copies it there).
        options = {'run': 'onType', 'typeAware': rule_set != 'syntactic'}
        server = Lsp([os.path.join(BENCH, 'node_modules', '.bin', 'oxlint'), '--lsp'], cwd, 'file://' + path,
                     [{'workspaceUri': 'file://' + cwd, 'options': options}], {'oxc': options})
    else:
        server = Lsp([os.path.join(BENCH, 'node_modules', '.bin', 'biome'), 'lsp-proxy'], cwd,
                     'file://' + path, None, None)
    problems = server.lint(1, original)
    first_ms = (time.perf_counter() - start) * 1000
    edits_ms = []
    for n in range(2, int(edits) + 2):
        text = original + ''.join(f'\n// edit {k}' for k in range(2, n + 1)) + '\n'
        t0 = time.perf_counter()
        problems = server.lint(n, text)
        edits_ms.append((time.perf_counter() - t0) * 1000)
    memory = tree_mib(server.process.pid)
    server.close()
    print(json.dumps({'first_ms': round(first_ms, 1), 'edits_ms': [round(t, 1) for t in edits_ms],
                      'problems': problems, 'memoryMiB': memory}))


if __name__ == '__main__':
    main()
