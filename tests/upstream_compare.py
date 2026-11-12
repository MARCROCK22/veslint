#!/usr/bin/env python3
"""upstream_compare.py ESLINT_DIR VESLINT_LINES rule...: compares, case by case and in order,
veslint's lines on the cases of typescript-eslint's own tests (tests/upstream_check.py --lines)
with ESLint's results on them (tests/rules/upstream_eslint.mjs writes ESLINT_DIR/<rule>.json):
position, rule, messageId, message, fix and suggestions. The cases tests/upstream/known.txt lists,
for either tool, are left out. Prints each difference and exits with 1 if there is one."""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True  # no __pycache__ in tests/
import eslint_lines  # noqa: E402


def main():
    eslint_dir, veslint_lines, *rules = sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    known = set()
    with open(os.path.join(root, 'tests/upstream/known.txt'), encoding='utf-8') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                known.add(line.split('\t')[1])
    ours = collections.defaultdict(list)
    with open(veslint_lines, encoding='utf-8') as f:
        for line in f.read().splitlines():
            ours[line.split('\t')[0].rsplit(':', 2)[0]].append(line)
    cases = lines = different = 0
    for rule in rules:
        with open(os.path.join(eslint_dir, rule + '.json'), encoding='utf-8') as f:
            results = json.load(f)
        for result in results:
            case = result['filePath']
            if case in known:
                continue
            cases += 1
            theirs = [re.sub('[\ud800-\udfff]', '�', line) for line in eslint_lines.lines([result], True)]
            lines += len(theirs)
            if theirs != ours.get(case, []):
                different += 1
                print(f'{case}:')
                for line in theirs:
                    print(f'  eslint  {line}')
                for line in ours.get(case, []):
                    print(f'  veslint {line}')
    print(f'{cases} cases of {len(rules)} rules: veslint prints the {lines} lines of ESLint, in its order'
          if not different else f'{different} of {cases} cases differ')
    sys.exit(1 if different else 0)


if __name__ == '__main__':
    main()
