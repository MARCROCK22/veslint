#!/usr/bin/env python3
"""upstream_check.py VESLINT FIXTURES CONFIGS [--lines OUT] [rule...]: runs typescript-eslint's own
tests of the ported rules (tests/rules/<rule>/upstream.json, see tests/upstream/README.md) on
veslint, the way RuleTester runs them. Every case goes through one `VESLINT --server`: its code is
the text of its file in the fixtures directory FIXTURES (prepared by tests/upstream/setup.sh), the
rule runs with the options of the case, and the configurations go to the directory CONFIGS. As in
upstream, where each test file runs in a process of its own, the texts the cases of one test file
gave the fixtures are forgotten before the next test file.

What each case expects is checked as RuleTester checks it:
- a valid case has no problem;
- an invalid case has as many problems as its errors, each with the messageId, the message (as
  written, or built from the data and meta.messages), the line, the column and the suggestions
  (messageId, description and the text each one leaves) the test gives;
- the fixes leave the output the test gives, pass after pass, applied as ESLint's SourceCodeFixer
  applies them (ranges in UTF-16 units).
endLine and endColumn are not checked: veslint prints where a problem starts.

The cases listed for veslint in tests/upstream/known.txt must fail; any other failure, or a listed
case that passes, makes the exit code 1. With --lines, veslint's output lines (with --fixes, the id
of the case in the place of the file path) go to OUT, for tests/rules/reference.sh. Without rules,
every rule with an upstream.json runs."""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOM = '﻿'
PLACEHOLDER = re.compile(r'\{\{([^{}]+?)\}\}')


def test_file_of(case_id):
    """The test file a case comes from: its id without the case and the run
    (`<file>[/r<n>]/<v|i><n>`)."""
    parts = case_id.split('/')[:-1]
    if parts and re.fullmatch(r'r\d+', parts[-1]):
        parts = parts[:-1]
    return '/'.join(parts)


def js_string(value):
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if value is None:
        return 'null'
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def interpolate(text, data):
    """ESLint's interpolate: {{ name }} is the value of name in data, when data has it."""
    def replace(match):
        term = match.group(1).strip()
        return js_string(data[term]) if term in data else match.group(0)
    return PLACEHOLDER.sub(replace, text)


def unescape(text):
    """The inverse of the escaping of veslint's output fields (\\\\, \\n, \\r, \\t)."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == '\\' and i + 1 < len(text):
            out.append({'\\': '\\', 'n': '\n', 'r': '\r', 't': '\t'}.get(text[i + 1], '\\' + text[i + 1]))
            i += 2
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def parse_line(line, prefix):
    """A line of `veslint --fixes`: position, rule, messageId, message, then the fix and the
    suggestions, each a range in UTF-16 units and a text."""
    head, rule, message_id, message, *rest = line.split('\t')
    line_number, column = head[len(prefix):].split(':')
    finding = {'line': int(line_number), 'column': int(column), 'rule': rule, 'messageId': message_id,
               'message': unescape(message), 'fix': None, 'suggestions': []}
    i = 0
    while i < len(rest):
        if rest[i] == 'fix':
            finding['fix'] = (int(rest[i + 1]), int(rest[i + 2]), unescape(rest[i + 3]))
            i += 4
        elif rest[i] == 'suggestion':
            finding['suggestions'].append({'messageId': rest[i + 1], 'desc': unescape(rest[i + 2]),
                                           'fix': (int(rest[i + 3]), int(rest[i + 4]), unescape(rest[i + 5]))})
            i += 6
        else:
            raise ValueError(f'unexpected field {rest[i]!r} in {line!r}')
    return finding


def utf16(text):
    return text.encode('utf-16-le', 'surrogatepass')


def apply_fixes(code, fixes):
    """ESLint's SourceCodeFixer.applyFixes: the fixes in the order of their ranges, each one that
    does not overlap the ones before."""
    bom = BOM if code.startswith(BOM) else ''
    text = utf16(code[len(bom):])
    out = utf16(bom)
    last = None
    for start, end, fix_text in sorted(fixes, key=lambda fix: (fix[0], fix[1])):
        if (last is not None and last >= start) or start > end:
            continue
        if start < 0 <= end or (start == 0 and fix_text.startswith(BOM)):
            out = b''
        out += text[2 * (0 if last is None else max(0, last)):2 * max(0, start)] + utf16(fix_text)
        last = end
    out += text[2 * (0 if last is None else max(0, last)):]
    return out.decode('utf-16-le', 'surrogatepass')


class Server:
    def __init__(self, veslint):
        self.process = subprocess.Popen([veslint, '--server'], cwd=ROOT, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, text=True, encoding='utf-8', bufsize=1)
        self.next_id = 0

    def request(self, request):
        self.next_id += 1
        request['id'] = self.next_id
        self.process.stdin.write(json.dumps(request) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def close(self):
        self.process.stdin.close()
        return self.process.wait()


class Runner:
    def __init__(self, veslint, fixtures, configs):
        self.server = Server(veslint)
        self.fixtures = fixtures
        self.configs = configs
        self.served = set()
        self.test_file = None

    def config_path(self, rule, case):
        language = dict(case.get('languageOptions', {}))
        if case.get('parserOptions'):
            language['parserOptions'] = case['parserOptions']
        config = {'languageOptions': language, 'linterOptions': {'reportUnusedDisableDirectives': 1},
                  'rules': {rule: ['error', *case.get('options', [])]}}
        text = json.dumps(config, sort_keys=True)
        path = os.path.join(self.configs, hashlib.sha1(text.encode()).hexdigest()[:16] + '.json')
        if not os.path.exists(path):
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text)
        return path

    def start_case(self, case):
        test_file = test_file_of(case['id'])
        if test_file != self.test_file:
            if self.served:
                self.server.request({'forget': sorted(self.served)})
                self.served.clear()
            self.test_file = test_file

    def project_of(self, case, file):
        """The tsconfig the case is linted with. An `allowDefaultProject` file of the project
        service (`via: default`) is a program of its own, with the options of `defaultProject`: a
        tsconfig next to that one that extends it and has only the file."""
        tsconfig = os.path.join(self.fixtures, case['tsconfig'])
        if case.get('via') != 'default':
            return tsconfig
        directory = os.path.dirname(tsconfig)
        relative = os.path.relpath(file, directory)
        path = os.path.join(directory, f'tsconfig.default-{hashlib.sha1(relative.encode()).hexdigest()[:12]}.json')
        if not os.path.exists(path):
            with open(path, 'w', encoding='utf-8') as f:
                json.dump({'extends': './' + os.path.basename(tsconfig), 'files': [relative], 'include': []}, f)
        return path

    def lint(self, rule, case, code):
        """veslint's answer for the case with this code: (exit code, lines, stderr)."""
        base = os.path.join(self.fixtures, case.get('root', ''))
        file = os.path.join(self.fixtures, case['file']) if case.get('tsconfig') else os.path.join(base, case['file'])
        tsconfig = case.get('tsconfig')
        self.served.add(file)
        answer = self.server.request({'config': self.config_path(rule, case),
                                      'project': self.project_of(case, file) if tsconfig else '',
                                      'files': [file], 'texts': {file: code}, 'fixes': True})
        return answer['code'], file, answer['stdout'].splitlines(), answer['stderr']


def check_project(veslint, fixtures, configs, project):
    """A project the upstream test lints on disk (`projects` of upstream.json, from the
    `lintProject` of @slipher/eslint-plugin's tests): written as that test writes it (its
    tsconfig.json, its files, seyfert linked into its node_modules), linted by the command line with
    its rules, and veslint's problems in each file must be those ESLint gave."""
    root = os.path.join(configs, 'projects', project['id'])
    if os.path.exists(root):
        shutil.rmtree(root)
    os.makedirs(os.path.join(root, 'node_modules'))
    os.symlink(os.path.realpath(os.path.join(fixtures, 'node_modules/seyfert')), os.path.join(root, 'node_modules/seyfert'))
    with open(os.path.join(root, 'tsconfig.json'), 'w', encoding='utf-8') as f:
        json.dump(project['tsconfig'], f)
    for name, text in project['files'].items():
        os.makedirs(os.path.dirname(os.path.join(root, name)), exist_ok=True)
        with open(os.path.join(root, name), 'w', encoding='utf-8') as f:
            f.write(text)
    with open(os.path.join(root, 'veslint.config.json'), 'w', encoding='utf-8') as f:
        json.dump({'rules': project['rules']}, f)
    run = subprocess.run([veslint, '--config', 'veslint.config.json', '--project', 'tsconfig.json', *project['files']],
                         cwd=root, capture_output=True, text=True, encoding='utf-8')
    if run.returncode > 1:
        return [f'veslint exited with {run.returncode}: {run.stderr.strip()}']
    got = {name: [] for name in project['files']}
    for line in run.stdout.splitlines():
        head, rule, message_id, message, *_ = line.split('\t')
        file, line_number, column = head.rsplit(':', 2)
        got.setdefault(file, []).append({'ruleId': rule, 'messageId': message_id, 'message': unescape(message),
                                         'line': int(line_number), 'column': int(column)})
    problems = []
    for result in project['results']:
        wanted = [{key: m.get(key) for key in ('ruleId', 'messageId', 'message', 'line', 'column')} for m in result['messages']]
        if got.get(result['file'], []) != wanted:
            problems.append(f"{result['file']}: veslint gives {json.dumps(got.get(result['file'], []))}, ESLint {json.dumps(wanted)}")
    return problems


def fix_passes(lint, code, findings, max_passes=10):
    """The outputs of RuleTester's passes of fixes: at most 10 (typescript-eslint's RuleTester; ESLint's,
    for its core rules, makes one), each on the text the last left."""
    outputs = []
    pass_number = 1
    while findings:
        fixes = [f['fix'] for f in findings if f['fix']]
        new = apply_fixes(code, fixes)
        if new == code:
            break
        code = new
        outputs.append(code)
        if not fixes or pass_number >= max_passes:
            break
        pass_number += 1
        findings = lint(code)
    return outputs


def check(case, messages, findings, outputs):
    problems = []
    if case['kind'] == 'valid':
        if findings:
            problems.append(f"valid, but {len(findings)} problem(s): {', '.join(f['messageId'] for f in findings)}")
        return problems
    errors = case['errors']
    count = errors if isinstance(errors, int) else len(errors)
    if len(findings) != count:
        problems.append(f'{len(findings)} problem(s), expected {count}')
    if not isinstance(errors, int):
        for i, (expected, found) in enumerate(zip(errors, findings)):
            if isinstance(expected, str):
                if found['message'] != expected:
                    problems.append(f'error {i}: message {found["message"]!r}, expected {expected!r}')
                continue
            if 'messageId' in expected and found['messageId'] != expected['messageId']:
                problems.append(f'error {i}: messageId {found["messageId"]}, expected {expected["messageId"]}')
            if 'message' in expected and found['message'] != expected['message']:
                problems.append(f'error {i}: message {found["message"]!r}, expected {expected["message"]!r}')
            if 'data' in expected and expected.get('messageId') in messages:
                wanted = interpolate(messages[expected['messageId']], expected['data'])
                if found['message'] != wanted:
                    problems.append(f'error {i}: message {found["message"]!r}, the data expect {wanted!r}')
            for key in ('line', 'column'):
                if key in expected and found[key] != expected[key]:
                    problems.append(f'error {i}: {key} {found[key]}, expected {expected[key]}')
            if 'suggestions' in expected:
                wanted_suggestions = expected['suggestions'] or []
                if len(found['suggestions']) != len(wanted_suggestions):
                    problems.append(f'error {i}: {len(found["suggestions"])} suggestion(s), expected {len(wanted_suggestions)}')
                for j, (want, got) in enumerate(zip(wanted_suggestions, found['suggestions'])):
                    if 'messageId' in want and got['messageId'] != want['messageId']:
                        problems.append(f'error {i} suggestion {j}: messageId {got["messageId"]}, expected {want["messageId"]}')
                    if 'desc' in want and got['desc'] != want['desc']:
                        problems.append(f'error {i} suggestion {j}: desc {got["desc"]!r}, expected {want["desc"]!r}')
                    if 'data' in want and want.get('messageId') in messages:
                        desc = interpolate(messages[want['messageId']], want['data'])
                        if got['desc'] != desc:
                            problems.append(f'error {i} suggestion {j}: desc {got["desc"]!r}, the data expect {desc!r}')
                    if 'output' in want:
                        output = apply_fixes(case['code'], [got['fix']])
                        if output != want['output']:
                            problems.append(f'error {i} suggestion {j}: output {output!r}, expected {want["output"]!r}')
    if 'output' in case:
        output = case['output']
        if output is None:
            if outputs and outputs[0] != case['code']:
                problems.append('fixed, but the test expects no fix')
        elif isinstance(output, str):
            if outputs != [output]:
                problems.append(f'output {outputs!r}, expected {[output]!r}')
        elif outputs != output:
            problems.append(f'outputs {outputs!r}, expected {output!r}')
    return problems


def known_cases(tool):
    known = {}
    with open(os.path.join(ROOT, 'tests/upstream/known.txt'), encoding='utf-8') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                who, case_id, reason = line.rstrip('\n').split('\t', 2)
                if who == tool:
                    known[case_id] = reason
    return known


def main():
    args = sys.argv[1:]
    lines_out = None
    if '--lines' in args:
        i = args.index('--lines')
        lines_out = args[i + 1]
        del args[i:i + 2]
    veslint, fixtures, configs = (os.path.abspath(a) for a in args[:3])
    # A rule is named by its id, the path of its directory in tests/rules
    # (`@typescript-eslint/await-thenable`).
    rules = args[3:] or sorted(os.path.relpath(d, os.path.join(ROOT, 'tests/rules'))
                               for d, _, files in os.walk(os.path.join(ROOT, 'tests/rules')) if 'upstream.json' in files)
    os.makedirs(configs, exist_ok=True)
    known = known_cases('veslint')
    runner = Runner(veslint, fixtures, configs)
    all_lines = []
    unexpected = 0
    failing = set()
    total = 0
    for rule in rules:
        with open(os.path.join(ROOT, 'tests/rules', rule, 'upstream.json'), encoding='utf-8') as f:
            data = json.load(f)
        messages = data['messages']
        cases = [c for c in data['cases'] if not c.get('skip')]
        failed = 0
        for case in cases:
            runner.start_case(case)
            code, file, out, stderr = runner.lint(rule, case, case['code'])
            if code > 1:
                problems = [f'veslint exited with {code}: {stderr.strip()}']
                findings = []
            else:
                prefix = file + ':'
                findings = [parse_line(line, prefix) for line in out if line.startswith(prefix)]
                all_lines.extend(case['id'] + ':' + line[len(prefix):] for line in out if line.startswith(prefix))

                def relint(text, case=case):
                    _, _, lines, _ = runner.lint(rule, case, text)
                    return [parse_line(line, prefix) for line in lines if line.startswith(prefix)]

                # After the passes, the file keeps the text the last one left, as in RuleTester
                # and in tests/rules/upstream_eslint.mjs.
                outputs = fix_passes(relint, case['code'], findings, 10 if '/' in rule else 1) if case['kind'] == 'invalid' and 'output' in case else []
                problems = check(case, messages, findings, outputs)
            if problems:
                failing.add(case['id'])
                if case['id'] not in known:
                    failed += 1
                    unexpected += 1
                    print(f"  {case['id']}: " + '\n    '.join(problems))
        projects = data.get('projects', [])
        for project in projects:
            problems = check_project(veslint, fixtures, configs, project)
            if problems:
                failing.add(project['id'])
                if project['id'] not in known:
                    failed += 1
                    unexpected += 1
                    print(f"  {project['id']}: " + '\n    '.join(problems))
        count = len(cases) + len(projects)
        total += count
        status = 'ok    ' if failed == 0 else 'FAIL  '
        print(f'{status}{rule}: {count - failed} of {count} cases as the upstream test expects')
    # The ids of the cases start with the name of the rule's test file upstream, the rule's name.
    names = {rule.rsplit('/', 1)[-1] for rule in rules}
    stale = [case_id for case_id in known if test_file_of(case_id).split('/')[0] in names and case_id not in failing]
    for case_id in stale:
        print(f'  {case_id} is listed in tests/upstream/known.txt but passes')
    if lines_out:
        with open(lines_out, 'w', encoding='utf-8') as f:
            f.write(''.join(line + '\n' for line in all_lines))
    if runner.server.close() != 0:
        print('veslint --server did not exit cleanly')
        unexpected += 1
    listed = len([case_id for case_id in failing if case_id in known])
    print(f'{total} cases; {unexpected} unexpected failure(s); {listed} known difference(s) (tests/upstream/known.txt)')
    sys.exit(1 if unexpected or stale else 0)


if __name__ == '__main__':
    main()
