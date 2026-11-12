module main

import os

// veslint and tsgo answer each other a few hundred times in a lint (475 requests for a lint of
// Spider-Byte's `src/index.ts`), one waiting while the other works. Spread over every CPU, each
// wait lets a CPU fall asleep, and the deep sleep states empty its caches and take more than 0.1 ms
// to leave: on the minipc (four CPUs) the CPUs entered the deepest one about 530 times per lint of
// that file, and the two CPUs veslint and tsgo were kept on about 57 times. A lint after a change
// took 105 to 112 ms on two CPUs instead of 182 to 267, and the 125 files of zod 11 s instead of
// 13 to 25; the first lint of a server, which loads the project with every CPU tsgo has, took
// 0.1 s more. So veslint keeps itself and tsgo on `default_cpus` CPUs; VESLINT_CPUS changes that.
// limit_cpus does it on Linux (cpu_limit_linux.c.v); elsewhere it does nothing
// (cpu_limit_default.c.v), and VESLINT_CPUS is only checked.
const default_cpus = 2

// cpus_from_env is how many CPUs veslint and tsgo may use: VESLINT_CPUS, or default_cpus. 0 means
// all of them.
fn cpus_from_env() !int {
	raw := os.getenv('VESLINT_CPUS').trim_space()
	if raw == '' {
		return default_cpus
	}
	value := raw.int()
	if value < 0 || value.str() != raw {
		return error('VESLINT_CPUS must be a number of CPUs, or 0 for all of them (got `${raw}`)')
	}
	return value
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
