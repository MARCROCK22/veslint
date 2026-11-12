#!/usr/bin/env bash
# Fake tsgo for the robustness tests of tests/run.sh and tsgo/client_nix_test.v (PROMPT.md §9);
# on Windows they use tests/fake_tsgo.v, which has the same modes (keep them in step).
# Usage: fake_tsgo.sh MODE [tsc arguments...]
# Processes left waiting are renamed `fake-tsgo-<FAKE_TSGO_TAG>-*` so each run can find its own.
set -u
mode=$1
shift

if [[ ${1:-} == --version ]]; then
	case $mode in
	version-mismatch)
		echo "Version 6.0.3"
		;;
	version-hang)
		# Never answers.
		exec -a "fake-tsgo-${FAKE_TSGO_TAG:-untagged}-version" sleep 600
		;;
	version-linger)
		# Answers, and neither closes its output nor exits.
		echo "Version 7.1.0-beta"
		exec -a "fake-tsgo-${FAKE_TSGO_TAG:-untagged}-version" sleep 600
		;;
	*)
		echo "Version 7.1.0-beta"
		;;
	esac
	exit 0
fi

cwd=/
while [[ $# -gt 0 ]]; do
	if [[ $1 == --cwd ]]; then
		cwd=$2
		shift
	fi
	shift
done

# bin_header LENGTH: MessagePack bin8 or bin16 header, as printf escapes.
bin_header() {
	if (($1 < 256)); then
		printf '\\xc4\\x%02x' "$1"
	else
		printf '\\xc5\\x%02x\\x%02x' $(($1 >> 8)) $(($1 & 255))
	fi
}

# frame TYPE METHOD PAYLOAD: writes a [type, method, payload] message in MessagePack.
# Method and payload must be ASCII shorter than 65536 bytes.
frame() {
	local typ
	typ=$(printf '\\x%02x' "$1")
	printf "\\x93\\xcc${typ}$(bin_header ${#2})%s$(bin_header ${#3})%s" "$2" "$3"
}

initialize='{"caseSensitivity":1,"currentDirectory":"/"}'

case $mode in
die-on-start)
	echo "fake-tsgo: simulated failure at startup" >&2
	exit 3
	;;
cpus)
	# Fails at startup saying how many CPUs it may run on (veslint keeps itself and tsgo on a few).
	echo "fake-tsgo: simulated failure on CPUs: $(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)." >&2
	exit 3
	;;
silent)
	# Never answers and does not care about stdin being closed: forces SIGKILL.
	exec -a "fake-tsgo-${FAKE_TSGO_TAG:-untagged}-silent" sleep 600
	;;
no-read)
	# Answers initialize and createSnapshot without reading anything, and stops reading stdin.
	cfg="$cwd/tsconfig.json"
	frame 4 initialize "$initialize"
	frame 4 createSnapshot "{\"snapshot\":1,\"projects\":[{\"id\":\"$cfg\",\"configFileName\":\"$cfg\",\"parsedCommandLine\":{\"options\":{}}}]}"
	exec -a "fake-tsgo-${FAKE_TSGO_TAG:-untagged}-noread" sleep 600
	;;
flood)
	# After the initialize response, floods messages nobody asked for.
	frame 4 initialize "$initialize"
	for _ in $(seq 1 60); do
		frame 4 bogus null
	done
	exec cat > /dev/null
	;;
wrong-method)
	frame 4 bogus null
	exec cat > /dev/null
	;;
no-projects)
	frame 4 initialize "$initialize"
	frame 4 createSnapshot '{"snapshot":1,"projects":[]}'
	exec cat > /dev/null
	;;
callback)
	frame 6 readFile '{}'
	exec cat > /dev/null
	;;
*)
	echo "fake-tsgo: unknown mode: $mode" >&2
	exit 2
	;;
esac
