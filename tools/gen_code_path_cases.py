#!/usr/bin/env python3
"""gen_code_path_cases.py MODE ARGS: writes to stdout a TypeScript file of functions that each return a
value on one path, for tests/rules/code_path_diff.sh. `consistent-return` reports a function whose end
is reachable, so its findings show what ESLint's code path analysis and veslint's rules/code_path.v
answer for each function.

  random SEED COUNT TERMINATE  COUNT functions of random statements (blocks end with a `return`, a
                               `throw`, a `break` or a `continue` with probability TERMINATE)
  try PART                     every small nesting of two `try` statements: the inner one in the
                               `try` (0), the `catch` (1) or the `finally` (2) block of the outer
  loop KIND                    every small `try` statement inside `while (c)`, `while (true)` or a
                               labeled block (KIND: while, whiletrue, label)
"""
import itertools
import random
import sys

HEADER = ('declare function foo(): void; declare class K {} declare const x: number;\n'
          'declare const o: { p: number; q: number }; declare const c: boolean; declare const e: Error;\n'
          'declare const v: number; declare const n: number; declare const xs: number[];')


def function(i, body):
    return 'export function f%d() { if (c) { return 1; } %s }' % (i, body)


def random_cases(seed, count, terminate):
    rng = random.Random(seed)
    throwing = ['foo();', 'x;', 'o.p;', 'new K();', 'o["q"];', 'void foo();']
    safe = ['1;', '"s";', 'void 0;', 'true;']

    def block_of(depth, loops, breakables, labels):
        parts = [statement(depth, loops, breakables, labels) for _ in range(rng.randint(1, 3))]
        if rng.random() < terminate:
            options = ['return 1;', 'throw e;']
            if loops:
                options += ['continue;', 'break;']
            elif breakables:
                options += ['break;']
            if labels:
                options += ['break %s;' % rng.choice(labels)[0]]
            parts.append(rng.choice(options))
        return '{ ' + ' '.join(parts) + ' }'

    def statement(depth, loops, breakables, labels):
        choices = ['expr', 'expr', 'safe', 'return', 'throw']
        if loops:
            choices += ['continue', 'break']
        elif breakables:
            choices += ['break']
        if labels:
            choices += ['lbreak']
        if depth < 4:
            choices += ['if', 'ifelse', 'while', 'whiletrue', 'do', 'for', 'forever', 'forof', 'switch',
                        'try', 'tryf', 'tryc', 'label', 'block', 'try', 'tryc', 'tryf']
        kind = rng.choice(choices)
        d = depth + 1
        same = lambda: block_of(d, loops, breakables, labels)
        loop = lambda: block_of(d, True, True, labels)
        if kind == 'expr':
            return rng.choice(throwing)
        if kind == 'safe':
            return rng.choice(safe)
        if kind == 'return':
            return 'return 1;'
        if kind == 'throw':
            return 'throw e;'
        if kind == 'continue':
            loop_labels = [label for label in labels if label[1]]
            if loop_labels and rng.random() < 0.3:
                return 'continue %s;' % rng.choice(loop_labels)[0]
            return 'continue;'
        if kind == 'break':
            return 'break;'
        if kind == 'lbreak':
            return 'break %s;' % rng.choice(labels)[0]
        if kind == 'if':
            return 'if (c) ' + same()
        if kind == 'ifelse':
            return 'if (c) ' + same() + ' else ' + same()
        if kind == 'while':
            return 'while (c) ' + loop()
        if kind == 'whiletrue':
            return 'while (true) ' + loop()
        if kind == 'do':
            return 'do ' + loop() + ' while (c);'
        if kind == 'for':
            return 'for (let i = 0; i < n; i++) ' + loop()
        if kind == 'forever':
            return 'for (;;) ' + loop()
        if kind == 'forof':
            return 'for (const item of xs) ' + loop()
        if kind == 'switch':
            cases = ' '.join('case %d: %s' % (i, block_of(d, loops, True, labels)) for i in range(rng.randint(1, 3)))
            if rng.random() < 0.5:
                cases += ' default: ' + block_of(d, loops, True, labels)
            return 'switch (v) { ' + cases + ' }'
        if kind == 'try':
            return 'try ' + same() + ' catch ' + same() + ' finally ' + same()
        if kind == 'tryf':
            return 'try ' + same() + ' finally ' + same()
        if kind == 'tryc':
            return 'try ' + same() + ' catch (err) ' + same()
        if kind == 'label':
            name = 'L%d' % rng.randint(0, 99999)
            if rng.random() < 0.5:
                return name + ': while (c) ' + block_of(d, True, True, labels + [(name, True)])
            return name + ': ' + block_of(d, loops, breakables, labels + [(name, False)])
        return same()

    print(HEADER)
    for i in range(count):
        print(function(i, block_of(0, False, False, [])))


def block(statements):
    return '{ ' + ' '.join(statements) + ' }'


def try_statement(try_block, catch_block, finally_block):
    text = 'try ' + block(try_block)
    if catch_block is not None:
        text += ' catch ' + block(catch_block)
    if finally_block is not None:
        text += ' finally ' + block(finally_block)
    return text


def try_cases(part):
    leaves = [[], ['foo();'], ['return 1;'], ['throw e;'], ['foo();', 'return 1;']]
    optional = [None] + leaves
    inners = [try_statement(t, c, f) for t, c, f in itertools.product(leaves, optional, optional)
              if c is not None or f is not None]
    print(HEADER)
    i = 0
    for inner in inners:
        for trail, catch_block, finally_block in itertools.product([[], ['return 1;'], ['foo();']], optional, optional):
            if catch_block is None and finally_block is None:
                continue
            if part == 0:
                outer = try_statement([inner] + trail, catch_block, finally_block)
            elif part == 1:
                if catch_block is None:
                    continue
                outer = try_statement(trail, [inner] + catch_block, finally_block)
            else:
                if finally_block is None:
                    continue
                outer = try_statement(trail, catch_block, [inner] + finally_block)
            print(function(i, outer))
            i += 1


def loop_cases(kind):
    leaves = [[], ['foo();'], ['return 1;'], ['throw e;'], ['break L;' if kind == 'label' else 'break;'],
              ['foo();', 'return 1;']]
    if kind != 'label':
        leaves.append(['continue;'])
    optional = [None] + leaves
    print(HEADER)
    i = 0
    for t, c, f, after in itertools.product(leaves, optional, optional, [[], ['foo();'], ['return 1;']]):
        if c is None and f is None:
            continue
        body = try_statement(t, c, f) + ' ' + ' '.join(after)
        if kind == 'while':
            statement = 'while (c) { %s }' % body
        elif kind == 'whiletrue':
            statement = 'while (true) { %s }' % body
        else:
            statement = 'L: { %s }' % body
        print(function(i, statement))
        i += 1


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'random':
        random_cases(int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]))
    elif mode == 'try':
        try_cases(int(sys.argv[2]))
    elif mode == 'loop':
        loop_cases(sys.argv[2])
    else:
        sys.exit('unknown mode: ' + mode)
