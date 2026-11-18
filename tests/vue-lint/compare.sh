#!/usr/bin/env bash
# compare.sh [WORK]: every rule veslint has, with its default options and the types on, on the
# script of thousands of .vue files, with ESLint 10.15.0 + vue-eslint-parser 10.4.2 +
# typescript-eslint's parser 8.72.2 (projectService, extraFileExtensions ['.vue']) and with
# veslint, compared finding by finding: position, rule, messageId, message, fix, suggestions and
# end (`--fixes` lines). The corpus (tests/vue-lint/corpus.py, written to WORK, build/vue-lint by
# default) is the SFCs of the tests of eslint-plugin-vue (tests/rules/vue/*/upstream.json; the
# JavaScript scripts with lang="ts" added) and tests/vue-lint/fixtures. A file ESLint cannot parse
# (vue-eslint-parser throws for a script with syntax errors), or that a rule throws on, is not
# compared. The differences must be those of tests/vue-lint/known.txt, which says why.
#
#   tests/vue-lint/compare.sh                    # the project service
#   VUE_LINT_PROJECT=1 tests/vue-lint/compare.sh # parserOptions.project, on the groups only (a
#                                                # program per project of one SFC is too much
#                                                # memory for typescript-eslint): known-project.txt
#   JOBS=2 tests/vue-lint/compare.sh /some/dir   # ESLint in 2 processes, the corpus in /some/dir
#
# ESLint's lines are kept in WORK under a key of the corpus, the configuration and the versions:
# a second run only runs veslint. It needs build/upstream/vue-deps (eslint-plugin-vue's oracle),
# build/eval/spider-byte/node_modules (tests/eval_spider_byte.sh), build/upstream/perfectionist-deps
# and build/upstream/seyfert (tests/rules/seyfert/setup.sh), as tests/rules/cross.sh. It is not
# part of `make test`.
set -uo pipefail
cd "$(dirname "$0")/../.."
# The configuration lists the rule directories of tests/rules, which the cache of resolved
# configurations does not see change: it is resolved each time.
export VESLINT_CONFIG_CACHE=0
ROOT=$(pwd)
WORK=$(realpath -m "${1:-build/vue-lint}")
JOBS=${JOBS:-$(nproc 2> /dev/null || echo 2)}
ESLINT_PACKAGE=$ROOT/build/eval/spider-byte/node_modules/eslint/package.json
KNOWN=$ROOT/tests/vue-lint/known.txt
mode=service
if [[ ${VUE_LINT_PROJECT:-} == 1 ]]; then
	mode=project
	KNOWN=$ROOT/tests/vue-lint/known-project.txt
fi
for needed in "$ESLINT_PACKAGE" build/upstream/vue-deps/node_modules/vue-eslint-parser build/upstream/seyfert/node_modules; do
	[[ -e $needed ]] || { echo "missing $needed (see the header of $0)" >&2; exit 2; }
done
[[ -x ./veslint ]] || { echo "missing ./veslint" >&2; exit 2; }
mkdir -p "$WORK"
count=$(python3 tests/vue-lint/corpus.py "$WORK") || exit 2
# The jobs of ESLint: each group, and the projects of one SFC by hundreds.
mapfile -t groups < <(cd "$WORK" && ls -d g[0-9][0-9])
alone=()
[[ $mode == project ]] || mapfile -t alone < <(cd "$WORK" && ls -d s[0-9][0-9][0-9][0-9] 2> /dev/null)
veslint_files=('g[0-9][0-9]/src/*.vue')
[[ $mode == project ]] || veslint_files+=('s[0-9][0-9][0-9][0-9]/src/*.vue')
jobs_files=()
for g in "${groups[@]}"; do
	jobs_files+=("$g/src/*.vue")
done
for ((k = 0; k < ${#alone[@]}; k += 100)); do
	batch=("${alone[@]:k:100}")
	jobs_files+=("${batch[*]/%//src/*.vue}")
done
# Every rule veslint has: the directories of tests/rules with an expected.txt.
python3 - > "$WORK/rules.json" <<'PY'
import json, os
rules = sorted(os.path.relpath(d, 'tests/rules') for d, _, files in os.walk('tests/rules') if 'expected.txt' in files and 'node_modules' not in d)
required = json.load(open('tests/rules/required_options.json', encoding='utf-8'))
print(json.dumps({'rules': {r: ['error', *required[r]] if r in required else 'error' for r in rules}}))
PY
key=$( (cd "$WORK" && find g[0-9][0-9] "${alone[@]}" -name '*.vue' -o -name '*.json' -o -name '*.d.ts' | LC_ALL=C sort | xargs cat; cat "$ROOT/tests/vue-lint/eslint.vue.config.mjs" "$ROOT/tests/vue-lint/eslint_each.mjs" "$WORK/rules.json" "$ESLINT_PACKAGE" "$ROOT/build/upstream/vue-deps/node_modules/vue-eslint-parser/package.json"; echo "$mode") | sha1sum | cut -c1-16)
ESLINT_LINES=$WORK/eslint.$mode.$key.txt
if [[ ! -f $ESLINT_LINES ]]; then
	echo "ESLint lints the $count SFCs in $JOBS processes"
	for j in "${!jobs_files[@]}"; do
		while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do
			wait -n
		done
		# shellcheck disable=SC2086 # the patterns of the job expand in WORK
		(cd "$WORK" && VUE_LINT_PROJECT=${VUE_LINT_PROJECT:-} node "$ROOT/tests/vue-lint/eslint_each.mjs" "$ESLINT_PACKAGE" \
			"$ROOT/tests/vue-lint/eslint.vue.config.mjs" ${jobs_files[j]} > "$WORK/eslint.$j.json" 2> "$WORK/eslint.$j.err") &
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
(cd "$WORK" && VESLINT_ESLINT_DIR=$ROOT/build/eval/spider-byte "$ROOT/veslint" --config "$ROOT/tests/vue-lint/eslint.vue.config.mjs" --fixes ${veslint_files[*]} 2> veslint.err) | LC_ALL=C sort > "$WORK/veslint.txt"
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
    if fields[1] in ('eslint', 'crash') and fields[2] == 'fatal':
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
	echo "ok     every rule on $count SFCs ($mode): $(grep -v '^#' "$KNOWN" | grep -vc '^not compared') known differences, $(grep -c '^not compared' "$KNOWN") files not compared"
else
	echo "FAIL   the differences are not those of ${KNOWN#"$ROOT"/} (see $WORK/known.diff)"
	exit 1
fi
