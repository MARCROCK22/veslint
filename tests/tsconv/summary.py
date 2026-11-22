#!/usr/bin/env python3
"""Sums the results of tests/tsconv/run.sh (one line per file: path, status, class of the first
difference, where, tree-sitter's rows, rows identical in the converter's, the kinds of
tree-sitter's rows it lacks, the kinds of its rows tree-sitter lacks).

Usage: summary.py diff.tsv [--classes N] [--kinds N] [--examples CLASS]
"""
import argparse
import collections


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('diff')
    ap.add_argument('--classes', type=int, default=40)
    ap.add_argument('--kinds', type=int, default=25)
    ap.add_argument('--examples', default='')
    args = ap.parse_args()
    status = collections.Counter()
    classes = collections.Counter()
    examples = collections.defaultdict(list)
    rows = same = 0
    rows_compared = same_compared = 0
    missing = collections.Counter()
    extra = collections.Counter()
    with open(args.diff, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 8:
                continue
            path, st, cls, where, n, ok, miss, ext = parts[:8]
            status[st] += 1
            if st in ('diagnostics', 'crash', 'missing'):
                if st == 'crash':
                    classes['crash: ' + cls] += 1
                    examples['crash: ' + cls].append((path, where))
                continue
            rows_compared += int(n)
            same_compared += int(ok)
            if st == 'same':
                continue
            classes[cls] += 1
            examples[cls].append((path, where))
            for item in miss.split():
                k, _, v = item.rpartition('=')
                missing[k] += int(v)
            for item in ext.split():
                k, _, v = item.rpartition('=')
                extra[k] += int(v)
    total = sum(status.values())
    print(f'files: {total}')
    for st, n in status.most_common():
        print(f'  {st}: {n}')
    compared = total - status['diagnostics'] - status['crash'] - status['missing']
    if compared:
        print(f'files compared (TypeScript parses them cleanly): {compared}, identical {status["same"]} '
              f'({100 * status["same"] / compared:.2f} %)')
    if rows_compared:
        print(f'rows of tree-sitter in the compared files: {rows_compared}, with an identical row in the '
              f"converter's: {same_compared} ({100 * same_compared / rows_compared:.3f} %)")
    print(f'\nfirst difference, by class (files), top {args.classes}:')
    for cls, n in classes.most_common(args.classes):
        path, where = examples[cls][0]
        print(f'  {n:6d}  {cls}\n          e.g. {path} {where}')
    print(f'\ntree-sitter rows without an identical converted row, by kind, top {args.kinds}:')
    for k, n in missing.most_common(args.kinds):
        print(f'  {n:8d}  {k}')
    print(f'\nconverted rows without an identical tree-sitter row, by kind, top {args.kinds}:')
    for k, n in extra.most_common(args.kinds):
        print(f'  {n:8d}  {k}')
    if args.examples:
        print(f'\nexamples of {args.examples}:')
        for path, where in examples.get(args.examples, [])[:30]:
            print(f'  {path} {where}')


if __name__ == '__main__':
    main()
