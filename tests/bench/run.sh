#!/usr/bin/env bash
# Benchmark of veslint against ESLint + typescript-eslint, oxlint (with oxlint-tsgolint, --type-aware)
# and Biome on rules that need type information, on the sources of real projects. Not part of
# `make test`; the README's "Speed" section shows its results (tools/bench_chart.mjs draws them).
#
#   tests/bench/run.sh                     # zod, recharts and the TypeScript compiler
#   tests/bench/run.sh zod                 # one project
#   RUNS=10 WARMUP=2 tests/bench/run.sh    # hyperfine's runs and warmup runs (5 and 1)
#
# Two sets of rules:
#   - floating: @typescript-eslint/no-floating-promises alone, which every tool has (Biome's
#     nursery/noFloatingPromises, which infers types itself, without TypeScript);
#   - typed: the 23 rules of typescript-eslint's recommendedTypeChecked that need types (Biome has 3
#     of them: it is left out).
# Every tool lints the same files with the same tsconfig.json (oxlint takes the tsconfig.json closest
# to each file, so the projects are copied, with hard links, into build/bench/projects with one
# tsconfig.json each) and its default number of threads. ESLint uses typescript-eslint's project
# service, veslint its default (tsgo's), oxlint tsgolint, Biome its own inference.
#
# It needs hyperfine, node, the projects of tests/eval_project.sh in build/eval (run it once for each),
# the ESLint of build/eval/spider-byte (tests/eval_spider_byte.sh) and the other tools, installed in
# build/bench by `npm ci` of tests/bench/package.json (done here when missing). It writes
# build/bench/results/ and build/bench/results.json.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
BENCH=$ROOT/build/bench
OUT=$BENCH/results
RUNS=${RUNS:-5}
WARMUP=${WARMUP:-1}
ESLINT_DIR=$ROOT/build/eval/spider-byte/node_modules
PROJECTS=("$@")
[[ ${#PROJECTS[@]} -gt 0 ]] || PROJECTS=(zod recharts typescript)

command -v hyperfine > /dev/null || { echo "hyperfine is needed" >&2; exit 2; }
[[ -x $ROOT/veslint ]] || { echo "build veslint first (make veslint)" >&2; exit 2; }
if [[ ! -x $BENCH/node_modules/.bin/oxlint ]]; then
	mkdir -p "$BENCH"
	cp tests/bench/package.json tests/bench/package-lock.json "$BENCH/"
	(cd "$BENCH" && npm ci --no-audit --no-fund)
fi
BIN=$BENCH/node_modules/.bin
export OXLINT_TSGOLINT_PATH=$BENCH/node_modules/@oxlint-tsgolint/linux-x64/tsgolint
mkdir -p "$OUT"

# The configurations of each set of rules, one per tool.
for set in floating typed; do
	mkdir -p "$BENCH/configs/$set"
	node - "$ESLINT_DIR" "$BENCH/configs/$set" "$set" << 'JS'
const { createRequire } = require('node:module');
const fs = require('node:fs');
const path = require('node:path');
const [eslintDir, dir, set] = process.argv.slice(2);
const plugin = createRequire(path.join(eslintDir, 'typescript-eslint/package.json'))('@typescript-eslint/eslint-plugin');
const rules = set === 'floating'
  ? ['@typescript-eslint/no-floating-promises']
  : Object.keys(plugin.configs['recommended-type-checked-only'].rules).filter(rule => rule.startsWith('@typescript-eslint/')).sort();
const write = (file, value) => fs.writeFileSync(path.join(dir, file), JSON.stringify(value, null, 1) + '\n');
write('rules.json', { rules: Object.fromEntries(rules.map(rule => [rule, 'error'])) });
write('.oxlintrc.json', {
  categories: { correctness: 'off' },
  plugins: ['typescript'],
  rules: Object.fromEntries(rules.map(rule => [`typescript/${rule.slice('@typescript-eslint/'.length)}`, 'error'])),
});
write('biome.json', {
  formatter: { enabled: false },
  assist: { enabled: false },
  vcs: { enabled: false },
  files: { includes: ['src/**'] },
  linter: { enabled: true, rules: { preset: 'none', nursery: { noFloatingPromises: 'error' } } },
});
fs.writeFileSync(path.join(dir, 'eslint.config.mjs'), `import fs from 'node:fs';
import tseslint from ${JSON.stringify(path.join(eslintDir, 'typescript-eslint/dist/index.js'))};
const { rules } = JSON.parse(fs.readFileSync(new URL('./rules.json', import.meta.url), 'utf8'));
export default [{
  files: ['**/*.ts', '**/*.tsx'],
  languageOptions: { parser: tseslint.parser, parserOptions: { projectService: true, tsconfigRootDir: process.cwd() } },
  plugins: { '@typescript-eslint': tseslint.plugin },
  rules,
}];
`);
JS
done

# The copy of a project (hard links) whose tsconfig.json is the one tests/eval_project.sh lints it
# with, and no other tsconfig.json under its sources.
prepare() {
	local project=$1 source=$ROOT/build/eval/$1 copy=$BENCH/projects/$1
	[[ -d $source ]] || { echo "build/eval/$project is missing: run tests/eval_project.sh $project once" >&2; exit 2; }
	[[ -d $copy ]] || cp -al "$source" "$copy"
	case $project in
	zod) DIR=$copy/packages/zod ;;
	*) DIR=$copy ;;
	esac
	rm -f "$DIR/tsconfig.json"
	cp "$DIR/tsconfig.veslint.json" "$DIR/tsconfig.json"
	if [[ $project == typescript ]]; then
		find "$DIR/src" -name tsconfig.json -delete
	fi
	# Biome reads the biome.json of the project (from it, its scanner builds the module graph its
	# type inference needs; with --config-path it does not): the copy's own Biome configurations go.
	find "$copy" -maxdepth 3 -name 'biome.json*' -not -path '*/node_modules/*' -delete
}

# The files tests/eval_project.sh lints.
sources() {
	case $1 in
	zod) find src -name '*.ts' -not -name '*.test.ts' -not -path '*/tests/*' -not -path '*/benchmarks/*' | LC_ALL=C sort ;;
	recharts) find src \( -name '*.ts' -o -name '*.tsx' \) -not -name '*.d.ts' | LC_ALL=C sort ;;
	typescript) find src -name '*.ts' -not -path 'src/lib/*' -not -name '*.d.ts' | LC_ALL=C sort ;;
	esac
}

for project in "${PROJECTS[@]}"; do
	prepare "$project"
	cd "$DIR"
	mapfile -t FILES < <(sources "$project")
	lines=$(cat "${FILES[@]}" | wc -l)
	echo "{\"project\": \"$project\", \"files\": ${#FILES[@]}, \"lines\": $lines}" > "$OUT/$project.json"
	for set in floating typed; do
		C=$BENCH/configs/$set
		declare -A COMMANDS=(
			[eslint]="node $ESLINT_DIR/eslint/bin/eslint.js --config $C/eslint.config.mjs --format json ${FILES[*]}"
			[veslint]="$ROOT/veslint --config $C/rules.json ${FILES[*]}"
			[oxlint]="$BIN/oxlint --type-aware -c $C/.oxlintrc.json --format json ${FILES[*]}"
		)
		tools=(eslint veslint oxlint)
		if [[ $set == floating ]]; then
			cp "$C/biome.json" "$DIR/biome.json"
			COMMANDS[biome]="$BIN/biome lint --reporter=json --max-diagnostics=none ${FILES[*]}"
			tools+=(biome)
		fi
		# One run each for the problems and the memory of the whole process tree.
		for tool in "${tools[@]}"; do
			# shellcheck disable=SC2086
			python3 "$ROOT/tests/bench/tree_memory.py" "$OUT/$project-$set-$tool.out" ${COMMANDS[$tool]} > "$OUT/$project-$set-$tool.memory"
		done
		for tool in "${tools[@]}"; do
			python3 "$ROOT/tests/bench/parity.py" "$DIR" "$OUT/$project-$set-eslint.out" "$tool" "$OUT/$project-$set-$tool.out" > "$OUT/$project-$set-$tool.parity"
		done
		args=()
		for tool in "${tools[@]}"; do args+=(-n "$tool" "${COMMANDS[$tool]}"); done
		echo "${tools[*]}" > "$OUT/$project-$set.tools"
		hyperfine -N -i --warmup "$WARMUP" --runs "$RUNS" --export-json "$OUT/$project-$set.hyperfine.json" "${args[@]}"
		unset COMMANDS
	done
	cd "$ROOT"
done

# build/bench/results.json: the machine, the versions and every measure.
node - "$ROOT" "$OUT" "$BENCH/results.json" << 'JS'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const [root, out, file] = process.argv.slice(2);
const version = (pkg, base) => JSON.parse(fs.readFileSync(path.join(base, pkg, 'package.json'), 'utf8')).version;
const eslint = path.join(root, 'build/eval/spider-byte/node_modules');
const bench = path.join(root, 'build/bench/node_modules');
const results = [];
for (const name of fs.readdirSync(out).filter(f => f.endsWith('.hyperfine.json')).sort()) {
  const [project, set] = name.replace('.hyperfine.json', '').split('-');
  // hyperfine's results are in the order of the commands, which is the order of the tools.
  const tools = fs.readFileSync(path.join(out, `${project}-${set}.tools`), 'utf8').trim().split(' ');
  for (const [i, r] of JSON.parse(fs.readFileSync(path.join(out, name), 'utf8')).results.entries()) {
    const stem = path.join(out, `${project}-${set}-${tools[i]}`);
    const [problems, matching, eslintProblems] = fs.readFileSync(`${stem}.parity`, 'utf8').trim().split(' ').map(Number);
    results.push({
      project, set, tool: tools[i],
      // hyperfine 2's summary: wall-clock and CPU time (user + system) in seconds.
      mean: r.summary.time_wall_clock.mean, stddev: r.summary.time_wall_clock.stddev,
      median: r.summary.time_wall_clock.median, min: r.summary.time_wall_clock.min, max: r.summary.time_wall_clock.max,
      cpu: r.summary.time_cpu.mean, runs: r.summary.time_wall_clock.count,
      memoryMiB: Number(fs.readFileSync(`${stem}.memory`, 'utf8').trim()),
      problems, matching, eslintProblems,
    });
  }
}
const projects = Object.fromEntries(fs.readdirSync(out).filter(f => /^[a-z]+\.json$/.test(f)).map(f => {
  const p = JSON.parse(fs.readFileSync(path.join(out, f), 'utf8'));
  return [p.project, { files: p.files, lines: p.lines }];
}));
fs.writeFileSync(file, JSON.stringify({
  date: new Date().toISOString().slice(0, 10),
  machine: { cpu: os.cpus()[0].model, cpus: os.cpus().length, memoryGiB: Math.round(os.totalmem() / 2 ** 30), os: `${os.type()} ${os.release()}`, node: process.version },
  versions: {
    veslint: execFileSync(path.join(root, 'veslint'), ['--version'], { encoding: 'utf8' }).trim().split(' ').pop(),
    tsgo: version('typescript', path.join(root, 'node_modules')),
    eslint: version('eslint', eslint), 'typescript-eslint': version('typescript-eslint', eslint), typescript: version('typescript', eslint),
    oxlint: version('oxlint', bench), 'oxlint-tsgolint': version('oxlint-tsgolint', bench), biome: version('@biomejs/biome', bench),
  },
  projects, results,
}, null, 1) + '\n');
console.log(`${file}: ${results.length} measures`);
JS
