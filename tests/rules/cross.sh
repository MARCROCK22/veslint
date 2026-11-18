#!/usr/bin/env bash
# Runs the ported rules together, with their default options, on every fixture of tests/rules, with
# ESLint 10.15.0 + typescript-eslint 8.72.2 (and @slipher/eslint-plugin 1.1.0 for the `seyfert/*`
# rules) and with veslint, and compares the findings (position, rule, messageId and message).
# reference.sh only runs each rule on its own fixtures; this also tells what a rule reports on the
# code written for the others. ESLint lints each file on its own (cross_eslint.mjs), since a rule of
# typescript-eslint that throws stops a whole run: such a file, and one ESLint cannot parse, is not
# compared. The differences must be the ones of cross.known.txt, which internals.md explains. Like
# reference.sh, it is outside `make test` and needs the dependencies tests/eval_spider_byte.sh
# installs and build/upstream/seyfert (tests/rules/seyfert/setup.sh).
set -uo pipefail
cd "$(dirname "$0")/../.."
if [[ ! -d build/eval/spider-byte/node_modules/typescript-eslint ]]; then
	echo "missing build/eval/spider-byte/node_modules: run tests/eval_spider_byte.sh first" >&2
	exit 2
fi
tests/rules/seyfert/setup.sh || exit 2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mapfile -t cases < <(find tests/rules -name cases.ts -o -name cases.tsx -o -name cases.vue -o -name cases.svelte | sort)
python3 - > "$TMP/rules.json" <<'PY'
import json, os
# The directory of a rule is the one with an expected.txt, and its path is the rule's id.
rules = sorted(os.path.relpath(d, 'tests/rules') for d, _, files in os.walk('tests/rules') if 'expected.txt' in files)
required = json.load(open('tests/rules/required_options.json', encoding='utf-8'))
print(json.dumps({'rules': {r: ['error', *required[r]] if r in required else 'error' for r in rules}}))
PY
# ESLint's lines of a rule directory are kept in build/eslint-cache/cross under the key of its files,
# the rules that run (rules.json), this configuration and the versions of ESLint and its plugins
# (tests/rules/eslint_cache.mjs): ESLint lints only the cases of the directories without them.
CROSS_CACHE=build/eslint-cache/cross
all_cases=("${cases[@]}")
node tests/rules/eslint_cache.mjs plan "$TMP/rules.json" tests/rules/eslint.cross.config.mjs tests/rules/cross_eslint.mjs \
	tests/eslint_lines.py tests/rules/eslint_cache.mjs -- "${all_cases[@]}" > "$TMP/plan.tsv" || exit 2
cases=()
: > "$TMP/eslint.cached"
: > "$TMP/plan.linted"
declare -A cached_dir=()
while IFS=$'\t' read -r file dir key; do
	if [[ -n $key && -n ${cached_dir[$dir]:-} ]]; then
		continue
	elif [[ -n $key && -f $CROSS_CACHE/$key.txt ]]; then
		cached_dir[$dir]=1
		cat "$CROSS_CACHE/$key.txt" >> "$TMP/eslint.cached"
	else
		cases+=("$file")
		printf '%s\t%s\t%s\n' "$file" "$dir" "$key" >> "$TMP/plan.linted"
	fi
done < "$TMP/plan.tsv"
echo "ESLint lints ${#cases[@]} of the ${#all_cases[@]} fixtures (the others: $CROSS_CACHE)"
# ESLint in JOBS processes at a time (the CPUs by default), each on a group of consecutive files
# (the fixtures of a rule, with their tsconfig.json, stay together).
JOBS=${JOBS:-$(nproc 2> /dev/null || echo 2)}
[[ $JOBS -ge 1 ]] || JOBS=1
# A group has at most CROSS_GROUP_SIZE files: with the project service, typescript-eslint 8.72 keeps
# a program for each fixture directory (about 45 MB each), and ESLint's heap is 2 GB.
CROSS_GROUP_SIZE=${CROSS_GROUP_SIZE:-15}
size=$(((${#cases[@]} + JOBS - 1) / JOBS))
[[ $size -le $CROSS_GROUP_SIZE ]] || size=$CROSS_GROUP_SIZE
pids=()
for ((k = 0; k * size < ${#cases[@]}; k++)); do
	while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do
		wait -n
	done
	node tests/rules/cross_eslint.mjs tests/rules/eslint.cross.config.mjs "${cases[@]:k*size:size}" \
		> "$TMP/eslint.$k.json" 2> "$TMP/eslint.$k.err" &
	pids+=($!)
done
wait
for k in "${!pids[@]}"; do
	if [[ ! -s "$TMP/eslint.$k.json" ]]; then
		echo "FAIL   ESLint produced no results"
		cat "$TMP/eslint.$k.err"
		exit 1
	fi
done
for k in "${!pids[@]}"; do
	python3 tests/eslint_lines.py < "$TMP/eslint.$k.json"
done > "$TMP/eslint.linted"
node tests/rules/eslint_cache.mjs store "$CROSS_CACHE" .txt "$TMP/eslint.linted" "$TMP/plan.linted" || exit 2
sort "$TMP/eslint.cached" "$TMP/eslint.linted" > "$TMP/eslint.txt"
./veslint --config "$TMP/rules.json" "${all_cases[@]}" 2> "$TMP/veslint.err" | sort > "$TMP/veslint.txt"
python3 - "$TMP" <<'PY'
import collections, sys
tmp = sys.argv[1]
def read(name):
    out = []
    for line in open(f'{tmp}/{name}', encoding='utf-8', errors='replace').read().splitlines():
        parts = line.split('\t')
        if len(parts) >= 4:
            out.append(tuple(parts[:4]))
    return out
def path_of(finding):
    return finding[0].rsplit(':', 2)[0]
eslint, veslint = read('eslint.txt'), read('veslint.txt')
skipped = {path_of(f): f for f in eslint if f[1] in ('eslint', 'crash') and f[2] == 'fatal'}
eslint = [f for f in eslint if path_of(f) not in skipped]
veslint = [f for f in veslint if path_of(f) not in skipped]
e, v = collections.Counter(eslint), collections.Counter(veslint)
with open(f'{tmp}/diff.txt', 'w') as out:
    for path in sorted(skipped):
        out.write(f'not compared\t{path}\t{skipped[path][1]}\t{skipped[path][3]}\n')
    for f in sorted((e - v).elements()):
        out.write('only eslint\t' + '\t'.join(f) + '\n')
    for f in sorted((v - e).elements()):
        out.write('only veslint\t' + '\t'.join(f) + '\n')
print(f'{len(eslint)} ESLint findings, {len(veslint)} of veslint, {sum((e & v).values())} identical, in {len({path_of(f) for f in eslint + veslint})} files')
PY
if diff -u tests/rules/cross.known.txt "$TMP/diff.txt" > "$TMP/known.diff"; then
	echo "ok     every rule on every fixture: $(wc -l < tests/rules/cross.known.txt) known differences"
else
	echo "FAIL   the differences are not those of tests/rules/cross.known.txt"
	cat "$TMP/known.diff"
	exit 1
fi
