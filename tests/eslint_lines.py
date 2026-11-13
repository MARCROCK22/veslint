"""eslint_lines.py [fixes] < eslint.json: ESLint's JSON results as veslint's output lines,
`path:line:col<TAB>rule<TAB>messageId<TAB>message`, with the paths relative to the current
directory. A message without a rule (a directive comment without use, a parse error…) has the
rule `eslint`, and one without a messageId has `fatal`, `error` or `warning` in its place. With
`fixes`, each line also carries the fix, the suggestions and where the problem ends (`end`, its
endLine and endColumn), like `veslint --fixes`. A surrogate
without its pair, which ESLint's JSON has as an escape, is written as U+FFFD: that is what Node
writes for it in UTF-8, on its output and in the file `eslint --fix` leaves."""
import json, os, re, sys


def field(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def lines(results, fixes):
    for f in results:
        path = os.path.relpath(f["filePath"])
        for m in f["messages"]:
            rule = m.get("ruleId") or "eslint"
            level = "fatal" if m.get("fatal") else "error" if m.get("severity") == 2 else "warning"
            line = f"{path}:{m.get('line', 0)}:{m.get('column', 0)}\t{rule}\t{m.get('messageId', level)}\t{field(m['message'])}"
            if fixes:
                if "fix" in m:
                    line += f"\tfix\t{m['fix']['range'][0]}\t{m['fix']['range'][1]}\t{field(m['fix']['text'])}"
                for s in m.get("suggestions", []):
                    line += f"\tsuggestion\t{s['messageId']}\t{field(s['desc'])}\t{s['fix']['range'][0]}\t{s['fix']['range'][1]}\t{field(s['fix']['text'])}"
                if "endLine" in m and m.get("line", 0) > 0:
                    line += f"\tend\t{m['endLine']}\t{m['endColumn']}"
            yield line


if __name__ == "__main__":
    for line in lines(json.load(sys.stdin), "fixes" in sys.argv[1:]):
        print(re.sub("[\ud800-\udfff]", "\ufffd", line))
