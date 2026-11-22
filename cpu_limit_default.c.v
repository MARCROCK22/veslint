module main

import runtime

// limit_cpus does nothing outside Linux: veslint restricts its CPUs and those of tsgo through the
// Linux scheduler (cpu_limit_linux.c.v). VESLINT_CPUS is still read and checked (cpus_from_env).
fn limit_cpus(count int) {}

// usable_cpus is how many CPUs a lint of the command line may run on: VESLINT_CPUS, or
// default_cpu_count; 0 is every CPU.
fn usable_cpus() int {
	count := cpus_from_env(default_cpu_count(false)) or { 0 }
	return if count > 0 { int_min(count, runtime.nr_cpus()) } else { runtime.nr_cpus() }
}
