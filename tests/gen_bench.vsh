#!/usr/bin/env -S v run

// Generates the synthetic project of PROMPT.md §8: 200 files with 100 declarations each, the same
// as the one used as the reference with the official JS client.
// Usage: v run tests/gen_bench.vsh [output directory, build/bench by default]
import os

const files = 200
const reps = 25 // 4 declarations per repetition: 100 per file

out := if os.args.len > 1 { os.args[1] } else { 'build/bench' }
src_dir := os.join_path(out, 'src')
os.mkdir_all(src_dir)!
for i in 0 .. files {
	mut lines := []string{}
	if i > 0 {
		lines << 'import { f${i - 1}, type T${i - 1} } from "./m${i - 1}";'
	}
	prev := if i > 0 { 'T${i - 1}' } else { 'number' }
	lines << 'export interface T${i} { a: number; b: string; c: ${prev}[] }'
	lines << 'export function f${i}(x: number): T${i} { return { a: x, b: String(x), c: [] }; }'
	for j in 0 .. reps {
		lines << 'const v${i}_${j} = f${i}(${j});'
		lines << 'let w${i}_${j} = [1, 2, 3].map(n => n * ${j});'
		lines << 'const s${i}_${j} = `hola \${v${i}_${j}.b}`;'
		if i > 0 {
			lines << 'const o${i}_${j} = { k: v${i}_${j}, prev: f${i - 1}(${j}), p: Promise.resolve(w${i}_${j}) };'
		} else {
			lines << 'const o${i}_${j} = { k: v${i}_${j}, p: Promise.resolve(w${i}_${j}) };'
		}
	}
	os.write_file(os.join_path(src_dir, 'm${i}.ts'), lines.join('\n') + '\n')!
}
os.write_file(os.join_path(out, 'tsconfig.json'), '{"compilerOptions":{"strict":true,"noEmit":true,"target":"es2022","lib":["es2022"],"module":"esnext","moduleResolution":"bundler"},"include":["src/*.ts"]}\n')!
println('synthetic project: ${files} files in ${src_dir}')
