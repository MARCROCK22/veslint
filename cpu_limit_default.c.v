module main

// limit_cpus does nothing outside Linux: veslint restricts its CPUs and those of tsgo through the
// Linux scheduler (cpu_limit_linux.c.v). VESLINT_CPUS is still read and checked (cpus_from_env).
fn limit_cpus(count int) {}
