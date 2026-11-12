module main

import os

#include <sys/syscall.h>
#include <unistd.h>

fn C.syscall(number i64, args ...voidptr) i64

// cpu_mask_words is the size of the CPU masks given to the kernel in 64-bit words: 1,024 CPUs, as
// glibc's cpu_set_t.
const cpu_mask_words = 16

// limit_cpus keeps every thread of veslint on `count` of the CPUs it may use (choose_cpus), so
// that tsgo, started after it, inherits them, and Go gives it as many processors. It does nothing
// with 0 or when the kernel does not answer.
fn limit_cpus(count int) {
	allowed := allowed_cpus() or { return }
	chosen := choose_cpus(allowed, current_cpu(), cpu_cores(allowed), count)
	if chosen.len > 0 {
		restrict_threads(chosen)
	}
}

// allowed_cpus are the CPUs this thread may run on, in order.
fn allowed_cpus() ![]int {
	mut mask := [cpu_mask_words]u64{}
	if C.syscall(C.SYS_sched_getaffinity, unsafe { nil }, voidptr(uint(sizeof(mask))),
		voidptr(&mask[0])) < 0 {
		return error('sched_getaffinity failed')
	}
	mut cpus := []int{}
	for word in 0 .. cpu_mask_words {
		for bit in 0 .. 64 {
			if mask[word] & (u64(1) << bit) != 0 {
				cpus << word * 64 + bit
			}
		}
	}
	return cpus
}

// current_cpu is the CPU this thread runs on, or -1.
fn current_cpu() int {
	mut cpu := u32(0)
	if C.syscall(C.SYS_getcpu, voidptr(&cpu), unsafe { nil }, unsafe { nil }) < 0 {
		return -1
	}
	return int(cpu)
}

// cpu_cores names the core of each CPU by the list of its threads (`core_cpus_list`, formerly
// `thread_siblings_list`), which the threads of a core share. A CPU the kernel says nothing about
// is left out.
fn cpu_cores(cpus []int) map[int]string {
	mut cores := map[int]string{}
	for cpu in cpus {
		dir := '/sys/devices/system/cpu/cpu${cpu}/topology'
		list := os.read_file('${dir}/core_cpus_list') or {
			os.read_file('${dir}/thread_siblings_list') or { continue }
		}
		cores[cpu] = list.trim_space()
	}
	return cores
}

// restrict_threads keeps every thread of veslint on `cpus`: this one, which starts tsgo, and the
// others it already has (those of the garbage collector). A thread that ended meanwhile is skipped.
fn restrict_threads(cpus []int) {
	mut mask := [cpu_mask_words]u64{}
	for cpu in cpus {
		mask[cpu / 64] |= u64(1) << (cpu % 64)
	}
	size := voidptr(uint(sizeof(mask)))
	if C.syscall(C.SYS_sched_setaffinity, unsafe { nil }, size, voidptr(&mask[0])) < 0 {
		return
	}
	tasks := os.ls('/proc/self/task') or { return }
	for task in tasks {
		tid := task.int()
		if tid > 0 {
			C.syscall(C.SYS_sched_setaffinity, voidptr(uint(tid)), size, voidptr(&mask[0]))
		}
	}
}
