module tsgo

import json2
import os

// The package of each platform, as Node names it: `process.platform` and `process.arch` of the
// machines the `typescript` package has a compiler for, from what `uname` answers on each.
struct PlatformCase {
	sysname string
	machine string
	bits    int  = 64
	little  bool = true
	android bool
	pkg     string
}

const platform_cases = [
	PlatformCase{
		sysname: 'Linux'
		machine: 'x86_64'
		pkg:     'linux-x64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'aarch64'
		pkg:     'linux-arm64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'armv7l'
		bits:    32
		pkg:     'linux-arm'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'armv6l'
		bits:    32
		pkg:     'linux-arm'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'loongarch64'
		pkg:     'linux-loong64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'mips64'
		pkg:     'linux-mips64el'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'ppc64le'
		pkg:     'linux-ppc64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'riscv64'
		pkg:     'linux-riscv64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 's390x'
		little:  false
		pkg:     'linux-s390x'
	},
	PlatformCase{
		sysname: 'Darwin'
		machine: 'arm64'
		pkg:     'darwin-arm64'
	},
	PlatformCase{
		sysname: 'Darwin'
		machine: 'x86_64'
		pkg:     'darwin-x64'
	},
	PlatformCase{
		sysname: 'Windows_NT'
		machine: 'AMD64'
		pkg:     'win32-x64'
	},
	PlatformCase{
		sysname: 'Windows_NT'
		machine: 'ARM64'
		pkg:     'win32-arm64'
	},
	PlatformCase{
		sysname: 'FreeBSD'
		machine: 'amd64'
		pkg:     'freebsd-x64'
	},
	PlatformCase{
		sysname: 'FreeBSD'
		machine: 'arm64'
		pkg:     'freebsd-arm64'
	},
	PlatformCase{
		sysname: 'OpenBSD'
		machine: 'amd64'
		pkg:     'openbsd-x64'
	},
	PlatformCase{
		sysname: 'OpenBSD'
		machine: 'arm64'
		pkg:     'openbsd-arm64'
	},
	PlatformCase{
		sysname: 'NetBSD'
		machine: 'amd64'
		pkg:     'netbsd-x64'
	},
	PlatformCase{
		sysname: 'NetBSD'
		machine: 'evbarm'
		pkg:     'netbsd-arm64'
	},
	PlatformCase{
		sysname: 'SunOS'
		machine: 'i86pc'
		pkg:     'sunos-x64'
	},
	PlatformCase{
		sysname: 'AIX'
		machine: '00F84C0C4C00'
		little:  false
		pkg:     'aix-ppc64'
	},
	PlatformCase{
		sysname: 'Linux'
		machine: 'aarch64'
		android: true
		pkg:     'android-arm64'
	},
]

fn case_host(c PlatformCase) Host {
	return Host{
		sysname:       c.sysname
		machine:       c.machine
		pointer_bits:  c.bits
		little_endian: c.little
		android:       c.android
	}
}

fn test_platform_package_of_each_host() {
	for c in platform_cases {
		host := case_host(c)
		assert platform_package(host) == 'typescript-${c.pkg}', '${c.sysname} ${c.machine}'
		assert has_platform_package(host), '${c.sysname} ${c.machine}'
		exe := if c.sysname == 'Windows_NT' { 'tsc.exe' } else { 'tsc' }
		assert binary_rel_path_for(host) == 'node_modules/@typescript/typescript-${c.pkg}/lib/${exe}'
	}
}

// Every package typescript lists is reached from some host, and the list is the one of the
// installed package.json (optionalDependencies).
fn test_platform_packages_are_those_of_typescript() {
	reached := platform_cases.map(it.pkg)
	for name in platform_packages {
		assert name in reached, 'no host case gives ${name}'
	}
	manifest := os.read_file(os.join_path(@VMODROOT, 'node_modules/typescript/package.json')) or {
		panic(err)
	}
	root := json2.decode[json2.Any](manifest) or { panic(err) }
	optional := (root.as_map()['optionalDependencies'] or { panic('no optionalDependencies') }).as_map()
	mut listed := []string{}
	for name, _ in optional {
		assert name.starts_with('@typescript/typescript-'), name
		listed << name.all_after('@typescript/typescript-')
	}
	listed.sort()
	mut ours := platform_packages.clone()
	ours.sort()
	assert listed == ours
}

fn test_hosts_without_a_package() {
	// A 32-bit x86 Linux, a big-endian mips64 and a system typescript does not know have no
	// compiler: the name getExePath
	// would look for is still built, and it is not in the list.
	for host in [Host{
		sysname:      'Linux'
		machine:      'i686'
		pointer_bits: 32
	}, Host{
		sysname:       'Linux'
		machine:       'mips64'
		little_endian: false
	}, Host{
		sysname: 'Haiku'
		machine: 'x86_64'
	}] {
		assert !has_platform_package(host), platform_package(host)
	}
	assert platform_package(Host{ sysname: 'Linux', machine: 'i686', pointer_bits: 32 }) == 'typescript-linux-ia32'
	err := missing_binary_error('/x/tsc', Host{ sysname: 'Haiku', machine: 'x86_64' })
	assert err.msg().contains('has no native compiler for haiku-x64')
	assert missing_binary_error('/x/tsc', Host{ sysname: 'Linux', machine: 'x86_64' }).msg().contains('run `make deps`')
}

// This machine: the path is the one of the installed package, and the binary is there.
fn test_this_machine() {
	host := current_host()
	assert has_platform_package(host), platform_package(host)
	assert rel_path == binary_rel_path_for(host)
	assert os.is_file(os.join_path(@VMODROOT, rel_path)), rel_path
}
