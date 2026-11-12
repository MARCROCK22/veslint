module main

import os

// The minipc: two cores with two threads each, CPUs n and n + 2 being the threads of a core.
const minipc_cores = {
	0: '0,2'
	1: '1,3'
	2: '0,2'
	3: '1,3'
}

fn test_choose_cpus_takes_the_current_cpu_and_one_of_another_core() {
	all := [0, 1, 2, 3]
	assert choose_cpus(all, 3, minipc_cores, 2) == [3, 0]
	assert choose_cpus(all, 2, minipc_cores, 2) == [2, 3]
	assert choose_cpus(all, 0, minipc_cores, 2) == [0, 1]
	assert choose_cpus(all, 1, minipc_cores, 2) == [1, 2]
	// The other thread of a core comes after a CPU of each core.
	assert choose_cpus(all, 0, minipc_cores, 3) == [0, 1, 2]
	assert choose_cpus(all, 3, minipc_cores, 1) == [3]
}

fn test_choose_cpus_restricts_nothing() {
	all := [0, 1, 2, 3]
	assert choose_cpus(all, 3, minipc_cores, 0) == []
	assert choose_cpus(all, 3, minipc_cores, 4) == []
	assert choose_cpus(all, 3, minipc_cores, 8) == []
	// Already on that many CPUs or fewer (`taskset -c 3`): there is nothing to take away.
	assert choose_cpus([3], 3, minipc_cores, 2) == []
	assert choose_cpus([2, 3], 3, minipc_cores, 2) == []
}

fn test_choose_cpus_among_the_allowed_ones() {
	// Sixteen CPUs whose cores have the threads n and n + 8 (a Ryzen 7), under `taskset -c 4-15`.
	mut cores := map[int]string{}
	for cpu in 0 .. 16 {
		cores[cpu] = '${cpu % 8},${cpu % 8 + 8}'
	}
	allowed := []int{len: 12, init: index + 4}
	assert choose_cpus(allowed, 9, cores, 2) == [9, 10]
	// From the last allowed CPU it goes round to the first.
	assert choose_cpus(allowed, 15, cores, 2) == [15, 4]
	assert choose_cpus(allowed, 15, cores, 3) == [15, 4, 5]
	// A current CPU that is not allowed, or unknown (-1): from the first allowed one.
	assert choose_cpus(allowed, 0, cores, 2) == [4, 5]
	assert choose_cpus(allowed, -1, cores, 2) == [4, 5]
}

fn test_choose_cpus_without_topology() {
	// Without topology every CPU is a core of its own: the current one and the next ones.
	assert choose_cpus([1, 3, 5, 7], 5, map[int]string{}, 2) == [5, 7]
	assert choose_cpus([1, 3, 5, 7], 7, map[int]string{}, 3) == [7, 1, 3]
	// Every allowed CPU in the same core: its threads.
	same_core := {
		0: '0-2'
		1: '0-2'
		2: '0-2'
	}
	assert choose_cpus([0, 1, 2], 1, same_core, 2) == [1, 2]
}

fn test_cpus_from_env() {
	saved := os.getenv_opt('VESLINT_CPUS')
	defer {
		if value := saved {
			os.setenv('VESLINT_CPUS', value, true)
		} else {
			os.unsetenv('VESLINT_CPUS')
		}
	}
	os.unsetenv('VESLINT_CPUS')
	assert cpus_from_env()! == 2
	os.setenv('VESLINT_CPUS', '', true)
	assert cpus_from_env()! == 2
	for raw, want in {
		'0':   0
		'1':   1
		'3':   3
		' 4 ': 4
	} {
		os.setenv('VESLINT_CPUS', raw, true)
		assert cpus_from_env()! == want
	}
	for raw in ['two', '-1', '1.5', '007', '+2'] {
		os.setenv('VESLINT_CPUS', raw, true)
		if value := cpus_from_env() {
			assert false, '`${raw}` gave ${value}'
		} else {
			assert err.msg().contains('VESLINT_CPUS must be a number of CPUs'), err.msg()
		}
	}
}
