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
// veslint takes a CPU of each core (core_count), as many workers as cores. On the minipc (two
// cores, four threads) the TypeScript compiler took 43 s with one worker (2.0 GiB), 30.5 s with
// two (2.3 GiB) and 30.7 s with four (2.8 GiB): a worker on the other thread of a core gains
// nothing, and each worker costs the types of its checker. A server (one file at a time) keeps
// two CPUs.
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

// default_cpu_count is how many CPUs veslint takes without VESLINT_CPUS: a CPU of each core for a
// lint with TypeScript in this process, default_cpus for a server or the `tsc --api` process.
fn default_cpu_count(server bool) int {
	transport := tsgo.transport_from_env() or { tsgo.Transport.process }
	if server || transport != .inproc {
		return default_cpus
	}
	return core_count()
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
