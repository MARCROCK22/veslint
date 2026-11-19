#!/usr/bin/env python3
"""tree_memory.py OUT COMMAND...: runs COMMAND (its output to OUT) and prints the peak of the summed
resident memory of the process and all its descendants, in MiB, sampled every 20 ms from /proc.
veslint (with tsgo) and oxlint (with tsgolint) run as two processes, ESLint as one: hyperfine reports
the largest single process, this reports what the whole run holds at its peak."""
import os
import subprocess
import sys
import time


def children_of():
    """Maps each pid to the pids whose parent it is."""
    children = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/stat', encoding='utf-8') as f:
                # The command name is in parentheses and may hold spaces: the fields after it.
                fields = f.read().rsplit(')', 1)[1].split()
        except OSError:
            continue
        children.setdefault(int(fields[1]), []).append(int(entry))
    return children


def rss_kib(pid):
    try:
        with open(f'/proc/{pid}/status', encoding='utf-8') as f:
            for line in f:
                if line.startswith('VmRSS:'):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def main():
    out, command = sys.argv[1], sys.argv[2:]
    with open(out, 'wb') as sink:
        process = subprocess.Popen(command, stdout=sink, stderr=subprocess.DEVNULL)
        peak = 0
        while process.poll() is None:
            children = children_of()
            tree, stack = [], [process.pid]
            while stack:
                pid = stack.pop()
                tree.append(pid)
                stack.extend(children.get(pid, []))
            peak = max(peak, sum(rss_kib(pid) for pid in tree))
            time.sleep(0.02)
    print(round(peak / 1024))


if __name__ == '__main__':
    main()
