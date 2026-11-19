module main

import runtime

// limit_cpus does nothing outside Linux: veslint restricts its CPUs and those of tsgo through the
// Linux scheduler (cpu_limit_linux.c.v). VESLINT_CPUS is still read and checked (cpus_from_env).
fn limit_cpus(count int) {}

// usable_cpus is how many CPUs veslint may run on: VESLINT_CPUS, or every CPU.
fn usable_cpus() int {
	count := cpus_from_env() or { 0 }
	return if count > 0 { int_min(count, runtime.nr_cpus()) } else { runtime.nr_cpus() }
}
