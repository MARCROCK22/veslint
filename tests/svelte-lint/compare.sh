#!/usr/bin/env bash
# compare.sh [WORK]: every rule veslint has, with its default options and the types on, on
# thousands of .svelte files, with ESLint 10.15.0 + svelte-eslint-parser 1.10.1 + typescript-eslint's
# parser 8.72.2 (an object, so every file is TypeScript; projectService, extraFileExtensions
# ['.svelte']) and with veslint, compared finding by finding: position, rule, messageId, message,
# fix, suggestions and end (`--fixes` lines). The corpus (tests/svelte-lint/corpus.py, written to
# WORK, build/svelte-lint by default) is the .svelte files of the tests of eslint-plugin-svelte
# (tests/rules/svelte/*/upstream.json) and of svelte-eslint-parser (the JavaScript scripts with
# lang="ts" set), and tests/svelte-lint/fixtures. A file a rule throws on in ESLint is not compared;
# one svelte-eslint-parser rejects is compared on its parsing error. The differences must be those
# of tests/svelte-lint/known.txt, which says why.
#
#   tests/svelte-lint/compare.sh                       # the project service
#   SVELTE_LINT_PROJECT=1 tests/svelte-lint/compare.sh # parserOptions.project, on the groups only:
#                                                      # known-project.txt
#   JOBS=2 tests/svelte-lint/compare.sh /some/dir      # ESLint in 2 processes, the corpus in /some/dir
#
# ESLint's lines are kept in WORK under a key of the corpus, the configuration, the versions and
# tests/eslint_lines.py (which writes them):
# a second run only runs veslint. It needs build/upstream/svelte-deps (eslint-plugin-svelte's
# oracle), build/upstream/vue-deps, build/eval/spider-byte/node_modules (tests/eval_spider_byte.sh),
# build/upstream/perfectionist-deps and build/upstream/seyfert (tests/rules/seyfert/setup.sh), as
# tests/rules/cross.sh. It is not part of `make test`.
set -uo pipefail
cd "$(dirname "$0")/../.."
# The configuration lists the rule directories of tests/rules, which the cache of resolved
# configurations does not see change: it is resolved each time.
export VESLINT_CONFIG_CACHE=0
ROOT=$(pwd)
WORK=$(realpath -m "${1:-build/svelte-lint}")
JOBS=${JOBS:-2}
ESLINT_PACKAGE=$ROOT/build/eval/spider-byte/node_modules/eslint/package.json
KNOWN=$ROOT/tests/svelte-lint/known.txt
mode=service
if [[ ${SVELTE_LINT_PROJECT:-} == 1 ]]; then
	mode=project
	KNOWN=$ROOT/tests/svelte-lint/known-project.txt
fi
for needed in "$ESLINT_PACKAGE" build/upstream/svelte-deps/node_modules/svelte-eslint-parser build/upstream/vue-deps/node_modules/eslint-plugin-vue build/upstream/seyfert/node_modules; do
	[[ -e $needed ]] || { echo "missing $needed (see the header of $0)" >&2; exit 2; }
done
[[ -x ./veslint ]] || { echo "missing ./veslint" >&2; exit 2; }
mkdir -p "$WORK/node_modules"
count=$(python3 tests/svelte-lint/corpus.py "$WORK") || exit 2
# ESLint runs in WORK, with `typescript` in its node_modules, as in a project: svelte-eslint-parser
# makes the JavaScript program of a file without `lang` with the newest `typescript` it reaches from
# the current directory, which, without it, can be veslint's own (7.1.0-beta in the node_modules of
# the checkout, the native compiler, without the JavaScript API: "Cannot read properties of
# undefined (reading 'JavaScriptFile')" on every such file when WORK is under build/).
ln -sfn "$ROOT/build/upstream/svelte-deps/node_modules/typescript" "$WORK/node_modules/typescript"
mapfile -t groups < <(cd "$WORK" && ls -d g[0-9][0-9])
alone=()
# parserOptions.project: the groups only (a program per project of one file is too much memory
# for typescript-eslint).
[[ $mode == project ]] || mapfile -t alone < <(cd "$WORK" && ls -d s[0-9][0-9][0-9][0-9] 2> /dev/null)
# The jobs of ESLint: each group, and the projects of one file by hundreds.
jobs_files=()
for g in "${groups[@]}"; do
	jobs_files+=("$g/src/*.svelte")
done
for ((k = 0; k < ${#alone[@]}; k += 100)); do
	batch=("${alone[@]:k:100}")
	jobs_files+=("${batch[*]/%//src/*.svelte}")
done
# Every rule veslint has: the directories of tests/rules with an expected.txt (not eslint-plugin-svelte's).
python3 - > "$WORK/rules.json" <<'PY'
import json, os
rules = sorted(os.path.relpath(d, 'tests/rules') for d, _, files in os.walk('tests/rules') if 'expected.txt' in files and 'node_modules' not in d and not d.startswith('tests/rules/svelte/'))
required = json.load(open('tests/rules/required_options.json', encoding='utf-8'))
print(json.dumps({'rules': {r: ['error', *required[r]] if r in required else 'error' for r in rules}}))
PY
export SVELTE_LINT_RULES=$WORK/rules.json
key=$( (cd "$WORK" && find "${groups[@]}" "${alone[@]}" -name '*.svelte' -o -name '*.json' -o -name '*.d.ts' | LC_ALL=C sort | xargs cat; cat "$ROOT/tests/svelte-lint/eslint.svelte.config.mjs" "$ROOT/tests/svelte-lint/eslint_each.mjs" "$ROOT/tests/eslint_lines.py" "$WORK/rules.json" "$ESLINT_PACKAGE" "$ROOT/build/upstream/svelte-deps/node_modules/svelte-eslint-parser/package.json" "$WORK/node_modules/typescript/package.json"; echo "$mode") | sha1sum | cut -c1-16)
ESLINT_LINES=$WORK/eslint.$mode.$key.txt
if [[ ! -f $ESLINT_LINES ]]; then
	echo "ESLint lints the $count files in $JOBS processes"
	for j in "${!jobs_files[@]}"; do
		while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do
			wait -n
		done
		# shellcheck disable=SC2086 # the patterns of the job expand in WORK
		(cd "$WORK" && SVELTE_LINT_PROJECT=${SVELTE_LINT_PROJECT:-} node "$ROOT/tests/svelte-lint/eslint_each.mjs" "$ESLINT_PACKAGE" \
			"$ROOT/tests/svelte-lint/eslint.svelte.config.mjs" ${jobs_files[j]} > "$WORK/eslint.$j.json" 2> "$WORK/eslint.$j.err") &
	done
	wait
	for j in "${!jobs_files[@]}"; do
		if [[ ! -s $WORK/eslint.$j.json ]]; then
			echo "FAIL   ESLint gave no results for ${jobs_files[j]}" >&2
			cat "$WORK/eslint.$j.err" >&2
			exit 1
		fi
		(cd "$WORK" && python3 "$ROOT/tests/eslint_lines.py" fixes < "eslint.$j.json")
	done | LC_ALL=C sort > "$ESLINT_LINES.part" && mv "$ESLINT_LINES.part" "$ESLINT_LINES"
fi
# veslint with the same configuration, which ESLint resolves for it through bun.
# shellcheck disable=SC2086 # the patterns expand in WORK
(cd "$WORK" && VESLINT_ESLINT_DIR=$ROOT/build/eval/spider-byte "$ROOT/veslint" --config "$ROOT/tests/svelte-lint/eslint.svelte.config.mjs" --fixes g[0-9][0-9]/src/*.svelte ${alone[@]/%//src/*.svelte} 2> veslint.err) | LC_ALL=C sort > "$WORK/veslint.txt"
python3 - "$ESLINT_LINES" "$WORK/veslint.txt" "$WORK/diff.txt" <<'PY'
import collections, sys
def read(name):
    return [line for line in open(name, encoding='utf-8', errors='replace').read().splitlines() if line.count('\t') >= 3]
def path_of(line):
    return line.split('\t', 1)[0].rsplit(':', 2)[0]
eslint, veslint = read(sys.argv[1]), read(sys.argv[2])
skipped = {}
for line in eslint:
    fields = line.split('\t')
    if fields[1] == 'crash':
        skipped[path_of(line)] = fields
eslint = [l for l in eslint if path_of(l) not in skipped]
veslint = [l for l in veslint if path_of(l) not in skipped]
e, v = collections.Counter(eslint), collections.Counter(veslint)
with open(sys.argv[3], 'w', encoding='utf-8') as out:
    for path in sorted(skipped):
        out.write(f'not compared\t{path}\t{skipped[path][1]}\t{skipped[path][3]}\n')
    for line in sorted((e - v).elements()):
        out.write('only eslint\t' + line + '\n')
    for line in sorted((v - e).elements()):
        out.write('only veslint\t' + line + '\n')
files = {path_of(l) for l in eslint + veslint}
print(f'{len(eslint)} ESLint findings, {len(veslint)} of veslint, {sum((e & v).values())} identical, in {len(files)} files ({len(skipped)} files not compared)')
PY
if [[ ! -f $KNOWN ]]; then
	: > "$KNOWN"
fi
# known.txt has the differences, in groups after `#` lines that say why (compared sorted).
if diff -u <(grep -v '^#' "$KNOWN" | LC_ALL=C sort) <(LC_ALL=C sort "$WORK/diff.txt") > "$WORK/known.diff"; then
	echo "ok     every rule on $count .svelte files ($mode): $(grep -v '^#' "$KNOWN" | grep -vc '^not compared') known differences, $(grep -c '^not compared' "$KNOWN") files not compared"
else
	echo "FAIL   the differences are not those of ${KNOWN#"$ROOT"/} (see $WORK/known.diff)"
	exit 1
fi
