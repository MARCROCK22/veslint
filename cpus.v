module main

import os
import tsgo

// veslint and tsgo answer each other a few hundred times in a lint (475 requests for a lint of
// Spider-Byte's `src/index.ts`), one waiting while the other works. Spread over every CPU, each
// wait lets a CPU fall asleep, and the deep sleep states empty its caches and take more than 0.1 ms
// to leave: on the minipc (four CPUs) the CPUs entered the deepest one about 530 times per lint of
// that file, and the two CPUs veslint and tsgo were kept on about 57 times. A lint after a change
// took 105 to 112 ms on two CPUs instead of 182 to 267, and the 125 files of zod 11 s instead of
// 13 to 25; the first lint of a server, which loads the project with every CPU tsgo has, took
// 0.1 s more. So veslint keeps itself and tsgo on `default_cpus` CPUs; VESLINT_CPUS changes that.
// With TypeScript in veslint's process there is no such wait, and a lint runs a worker per CPU
// (lint_workers.v), which share TypeScript's program and have a checker each: on a command line
// veslint takes every CPU, as tsgolint takes a worker per thread. On an i3-4150T (two cores, four
// threads; median of 3 to 5 alternated runs, veslint 0.44.0) four workers against two (a CPU of
// each core): the TypeScript compiler 11.28 -> 10.01 s with the 23 type-aware rules of
// recommendedTypeChecked (1,737 -> 1,887 MB), 3.22 -> 2.88 s with no-floating-promises, 3.60 ->
// 3.11 s without types; recharts 3.69 -> 3.53, 0.64 -> 0.61 and 0.48 -> 0.43 s; zod 2.03 ->
// 1.87 s and 0.45 -> 0.43 s, but 0.50 -> 0.56 s with no-floating-promises (each checker resolves
// zod's types again, about a fifth more instructions there). A worker on the other thread of a
// core runs at about half its speed, its checker repeats little (on the TypeScript compiler 0.2 G
// of the 6.5 G instructions four workers add; the collectors of V and Go take most of the rest),
// and the work is shared to the end (the workers finished within 0.1 s of each other). Two
// workers sharing a checker per core, each holding it for a request, took 10.75 s there: they wait
// for each other about as long as the checker works. A server (one file at a time) keeps two
// CPUs.
// limit_cpus does it on Linux (cpu_limit_linux.c.v); elsewhere it does nothing
// (cpu_limit_default.c.v), and VESLINT_CPUS is only checked.
const default_cpus = 2

// cpus_from_env is how many CPUs veslint and tsgo may use: VESLINT_CPUS, or `default_count` (see
// default_cpu_count). 0 means all of them.
fn cpus_from_env(default_count int) !int {
	raw := os.getenv('VESLINT_CPUS').trim_space()
	if raw == '' {
		return default_count
	}
	value := raw.int()
	if value < 0 || value.str() != raw {
		return error('VESLINT_CPUS must be a number of CPUs, or 0 for all of them (got `${raw}`)')
	}
	return value
}

// default_cpu_count is how many CPUs veslint takes without VESLINT_CPUS: all of them (0) for a
// lint with TypeScript in this process, default_cpus for a server or the `tsc --api` process.
fn default_cpu_count(server bool) int {
	transport := tsgo.transport_from_env() or { tsgo.Transport.process }
	if server || transport != .inproc {
		return default_cpus
	}
	return 0
}

// choose_cpus picks `count` of the `allowed` CPUs: `current` first and then, going round from it,
// a CPU of each core not taken yet before the other threads of a core. `cores` names the core of
// each CPU (the threads of a core share their caches and its execution units); a CPU without one
// is a core of its own. An empty result means that nothing is to be restricted: `count` is 0 or
// at least the allowed CPUs.
fn choose_cpus(allowed []int, current int, cores map[int]string, count int) []int {
	if count <= 0 || count >= allowed.len {
		return []int{}
	}
	start := if current in allowed { allowed.index(current) } else { 0 }
	mut order := []int{cap: allowed.len}
	for i in 0 .. allowed.len {
		order << allowed[(start + i) % allowed.len]
	}
	mut chosen := []int{cap: count}
	mut taken := map[string]bool{}
	for cpu in order {
		core := cores[cpu] or { 'cpu ${cpu}' }
		if core in taken {
			continue
		}
		taken[core] = true
		chosen << cpu
		if chosen.len == count {
			return chosen
		}
	}
	for cpu in order {
		if cpu !in chosen {
			chosen << cpu
			if chosen.len == count {
				break
			}
		}
	}
	return chosen
}
