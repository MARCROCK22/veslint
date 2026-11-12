module tsgo

import os

// Which native compiler the `typescript` package brings for a platform. It ports getExePath
// (lib/getExePath.js of typescript 7.1.0-beta): the binary is `lib/tsc` (`lib/tsc.exe` on Windows) of the
// optional dependency `@typescript/typescript-<process.platform>-<process.arch>`, and npm only
// installs the one of the platform it runs on.

// platform_packages are the platforms typescript 7.1.0-beta has a package for (the
// optionalDependencies of its package.json), as `<process.platform>-<process.arch>`.
const platform_packages = ['aix-ppc64', 'android-arm64', 'darwin-arm64', 'darwin-x64', 'freebsd-arm64',
	'freebsd-x64', 'linux-arm', 'linux-arm64', 'linux-loong64', 'linux-mips64el', 'linux-ppc64',
	'linux-riscv64', 'linux-s390x', 'linux-x64', 'netbsd-arm64', 'netbsd-x64', 'openbsd-arm64',
	'openbsd-x64', 'sunos-x64', 'win32-arm64', 'win32-x64']

// Host describes the machine veslint runs on, as uname gives it.
pub struct Host {
pub:
	sysname       string // 'Linux', 'Darwin', 'Windows_NT', 'FreeBSD'…
	machine       string // 'x86_64', 'aarch64', 'arm64', 'AMD64'…
	pointer_bits  int  = 64
	little_endian bool = true
	// Android, whose uname says `Linux` and whose Node says `android` (process.platform).
	android bool
}

// host_platform is Node's process.platform for a host: `android` on Android, otherwise the one of
// its system name.
pub fn host_platform(host Host) string {
	return if host.android { 'android' } else { node_platform(host.sysname) }
}

// node_platform is Node's process.platform for the system name of uname: the name in lower case,
// but for Windows.
pub fn node_platform(sysname string) string {
	name := sysname.to_lower()
	if name.starts_with('windows') || name.starts_with('mingw') || name.starts_with('msys') {
		return 'win32'
	}
	return name
}

// node_arch is Node's process.arch for a host. Each system names the same processor in its own
// way: `x86_64` is `amd64` on the BSDs, `AMD64` on Windows and `i86pc` on SunOS; `aarch64` is
// `arm64` on macOS and FreeBSD, and `evbarm` (also the 32-bit one) on NetBSD. On AIX the machine is
// a serial number, and its only processor is ppc64.
pub fn node_arch(host Host) string {
	if host_platform(host) == 'aix' {
		return 'ppc64'
	}
	machine := host.machine.to_lower()
	return match machine {
		'x86_64', 'amd64', 'x64' {
			'x64'
		}
		'i86pc' {
			if host.pointer_bits == 64 { 'x64' } else { 'ia32' }
		}
		'aarch64', 'arm64' {
			'arm64'
		}
		'evbarm' {
			if host.pointer_bits == 64 { 'arm64' } else { 'arm' }
		}
		'i386', 'i486', 'i586', 'i686', 'x86' {
			'ia32'
		}
		'ppc64', 'ppc64le' {
			'ppc64'
		}
		'loongarch64' {
			'loong64'
		}
		'mips64' {
			if host.little_endian { 'mips64el' } else { 'mips64' }
		}
		'mips' {
			if host.little_endian { 'mipsel' } else { 'mips' }
		}
		else {
			if machine.starts_with('arm') {
				'arm'
			} else {
				// riscv64, s390x… are the same in both.
				machine
			}
		}
	}
}

// platform_package is the name of the package with the compiler of a host, without its scope
// (`typescript-linux-x64`), whether typescript has it or not: what getExePath looks for.
pub fn platform_package(host Host) string {
	return 'typescript-${host_platform(host)}-${node_arch(host)}'
}

// has_platform_package tells whether typescript 7.1.0-beta has a package for that host.
pub fn has_platform_package(host Host) bool {
	return platform_package(host).all_after('typescript-') in platform_packages
}

// binary_rel_path_for is the path of the compiler of a host inside the directory that has
// `node_modules`.
pub fn binary_rel_path_for(host Host) string {
	exe := if host_platform(host) == 'win32' { 'tsc.exe' } else { 'tsc' }
	return 'node_modules/@typescript/${platform_package(host)}/lib/${exe}'
}

// current_host asks the system which machine this is.
pub fn current_host() Host {
	uname := os.uname()
	probe := u16(1)
	return Host{
		sysname:       uname.sysname
		machine:       uname.machine
		pointer_bits:  int(sizeof(voidptr)) * 8
		little_endian: unsafe { *(&u8(&probe)) } == 1
		android:       $if android { true } $else { false }
	}
}

// binary_rel_path is the path of the compiler of this machine inside the directory that has
// `node_modules`.
pub fn binary_rel_path() string {
	return binary_rel_path_for(current_host())
}

// path_key is a path as tsgo compares it, to match a path of veslint with one of tsgo's answers:
// on Windows TypeScript writes `\` as `/` and ignores case (its project ids are lowercased paths).
pub fn path_key(path string) string {
	$if windows {
		return path.replace('\\', '/').to_lower()
	}
	return path
}

// missing_binary_error explains why the compiler is not at `bin`: the dependencies are not
// installed, or typescript has no package for this machine.
fn missing_binary_error(bin string, host Host) IError {
	if !has_platform_package(host) {
		return error('TypeScript 7 binary not found at ${bin}: typescript 7.1.0-beta has no native compiler for ${host_platform(host)}-${node_arch(host)} (it has: ${platform_packages.join(', ')})')
	}
	return error('TypeScript 7 binary not found at ${bin}; run `make deps`')
}
