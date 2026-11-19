#!/usr/bin/env python3
"""parity.py ROOT ESLINT_JSON TOOL OUTPUT [RULES_JSON]: how many of a tool's problems ESLint reports
too, at the same place (file, line, column) for the same rule. Prints `problems matching
eslint_problems`. TOOL is eslint (ESLint's JSON), veslint (its lines), oxlint (`--format json`) or
biome (`--reporter=json`); RULES_JSON (tests/bench/syntactic-rules.json) names Biome's rules as
ESLint's. Problems that are not of a rule (unused directives, directives for rules that do not exist,
parsing errors) are left out."""
import collections
import json
import os
import re
import sys

# Biome's names of the rules (`<group>/<rule>`), as ESLint names them.
BIOME = {'nursery/noFloatingPromises': '@typescript-eslint/no-floating-promises'}


def eslint_keys(root, path):
    keys = collections.Counter()
    for result in json.load(open(path, encoding='utf-8')):
        file = os.path.relpath(result['filePath'], root)
        for message in result['messages']:
            rule = message.get('ruleId')
            # A directive comment naming a rule of a plugin that is not loaded is not a problem of a rule.
            if rule and not message['message'].startswith('Definition for rule'):
                keys[(file, message['line'], message['column'], rule)] += 1
    return keys


def veslint_keys(path):
    keys = collections.Counter()
    for line in open(path, encoding='utf-8'):
        fields = line.rstrip('\n').split('\t')
        place = re.fullmatch(r'(.+):(\d+):(\d+)', fields[0])
        if place and len(fields) > 3 and fields[1] != 'eslint' and not fields[3].startswith('Definition for rule'):
            keys[(os.path.normpath(place[1]), int(place[2]), int(place[3]), fields[1])] += 1
    return keys


def oxlint_keys(path):
    keys = collections.Counter()
    for diagnostic in json.load(open(path, encoding='utf-8'))['diagnostics']:
        # `eslint(no-debugger)`, `typescript(no-explicit-any)`.
        rule = re.fullmatch(r'(eslint|typescript)\((.+)\)', diagnostic.get('code') or '')
        if rule and diagnostic.get('labels'):
            span = diagnostic['labels'][0]['span']
            name = rule[2] if rule[1] == 'eslint' else f'@typescript-eslint/{rule[2]}'
            keys[(os.path.normpath(diagnostic['filename']), span['line'], span['column'], name)] += 1
    return keys


def biome_keys(path):
    keys = collections.Counter()
    for diagnostic in json.load(open(path, encoding='utf-8'))['diagnostics']:
        name = diagnostic.get('category', '').removeprefix('lint/')
        if diagnostic.get('category', '').startswith('lint/') and name in BIOME:
            start = diagnostic['location']['start']
            keys[(os.path.normpath(diagnostic['location']['path']), start['line'], start['column'], BIOME[name])] += 1
    return keys


def main():
    root, eslint_json, tool, output = sys.argv[1:5]
    if len(sys.argv) > 5:
        for rule in json.load(open(sys.argv[5], encoding='utf-8'))['rules']:
            for name in rule['biome']:
                BIOME[name] = rule['eslint']
    reference = eslint_keys(root, eslint_json)
    keys = {'eslint': lambda p: eslint_keys(root, p), 'veslint': veslint_keys, 'oxlint': oxlint_keys,
            'biome': biome_keys}[tool](output)
    matching = sum((keys & reference).values())
    print(sum(keys.values()), matching, sum(reference.values()))


if __name__ == '__main__':
    main()
