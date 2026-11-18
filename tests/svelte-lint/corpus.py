"""corpus.py WORK: writes the corpus of tests/svelte-lint/compare.sh to WORK: the .svelte files of
the tests of eslint-plugin-svelte (tests/rules/svelte/*/upstream.json) and of svelte-eslint-parser
(build/upstream/svelte-eslint-parser/tests/fixtures) whose script is TypeScript or that have none,
the ones with a JavaScript script with `lang="ts"` set on their <script> tags (veslint lints only
TypeScript: the case is linted as TypeScript, as the JavaScript tests of ESLint core are), and the
fixtures of tests/svelte-lint/fixtures. Each file goes once (the same code in several cases is
linted once), to WORK/gNN/src/<name>.svelte, NN from a hash of the name: a group is a project of
its own (tsconfig.json, node_modules with svelte's types) so that typescript-eslint's programs
stay small. The virtual code of a component is always a module, but typescript-eslint's program
has the other .svelte files of the project as their raw text (only the linted file gets its
virtual code), and the raw text of a file whose script has no import or export declares its
names as globals, which the other files see: such a file is a project alone, WORK/sNNNN/src/
<name>.svelte. Prints the number of files."""
import glob, hashlib, json, os, re, shutil, sys

GROUPS = 16
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TSCONFIG = {
    "compilerOptions": {
        "strict": True,
        "noEmit": True,
        "target": "ES2022",
        "module": "ESNext",
        "moduleResolution": "Bundler",
        "skipLibCheck": True,
        "types": [],
    },
    "include": ["src/**/*.ts", "src/**/*.svelte"],
}

# What `import X from './X.svelte'` is for TypeScript (svelte's own `*.svelte` declaration is not
# in its default types).
SHIM = """declare module '*.svelte' {
  import type { Component } from 'svelte';
  const component: Component<Record<string, unknown>>;
  export default component;
}
"""

SCRIPT_TAG = re.compile(r"<script\b([^>]*)>", re.I)
LANG = re.compile(r"""\blang\s*=\s*(["']?)([^"'\s>]*)\1""", re.I)


def as_typescript(code):
    """Sets lang="ts" on the <script> tags whose lang is not TypeScript."""

    def tag(m):
        attrs = m.group(1)
        found = LANG.search(attrs)
        if found is None:
            return '<script lang="ts"' + attrs + ">"
        if found.group(2).lower() in ("ts", "typescript"):
            return m.group(0)
        return "<script" + attrs[: found.start()] + 'lang="ts"' + attrs[found.end() :] + ">"

    return SCRIPT_TAG.sub(tag, code)


def group_of(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % GROUPS


def write_project(d, svelte_types):
    os.makedirs(os.path.join(d, "src"), exist_ok=True)
    json.dump(TSCONFIG, open(os.path.join(d, "tsconfig.json"), "w"), indent=2)
    open(os.path.join(d, "src", "shims-svelte.d.ts"), "w").write(SHIM)
    os.symlink(svelte_types, os.path.join(d, "node_modules"))


SCRIPT = re.compile(r"<script\b[^>]*>(.*?)</script>", re.S | re.I)
# An import or export declaration at the start of a line (not a dynamic `import(…)`).
MODULE = re.compile(r"^\s*(export\b|import\b(?!\s*[(.]))", re.M)


def is_global_script(code):
    """The scripts of the file have code and no import or export: TypeScript reads the raw file as
    a script whose declarations are global."""
    script = "".join(SCRIPT.findall(code))
    return script.strip() != "" and MODULE.search(script) is None


def safe(name):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", name)


def main():
    work = os.path.abspath(sys.argv[1])
    if os.path.isdir(work):
        for entry in os.listdir(work):
            if re.fullmatch(r"g\d\d|s\d\d\d\d", entry):
                shutil.rmtree(os.path.join(work, entry))
    files = {}  # name -> code
    seen = set()

    def add(name, code):
        if code in seen:
            return
        try:
            code.encode("utf-8")
        except UnicodeEncodeError:
            # A lone surrogate, which a file cannot have.
            return
        seen.add(code)
        files[safe(name)] = code

    cases = []
    for path in sorted(glob.glob(os.path.join(ROOT, "tests/rules/svelte/*/upstream.json"))):
        for case in json.load(open(path, encoding="utf-8"))["cases"]:
            if not case.get("svelte") or not case.get("file", "").endswith(".svelte"):
                continue
            cases.append((case["id"], case["code"]))
    for case_id, code in sorted(cases):
        add(case_id, as_typescript(code))
    parser_fixtures = os.path.join(ROOT, "build/upstream/svelte-eslint-parser/tests/fixtures")
    for path in sorted(glob.glob(os.path.join(parser_fixtures, "**/*.svelte"), recursive=True)):
        rel = os.path.relpath(path, parser_fixtures)
        code = open(path, encoding="utf-8", newline="").read()
        add("parser_" + rel[: -len(".svelte")], as_typescript(code))
    fixtures = os.path.join(ROOT, "tests/svelte-lint/fixtures")
    for name in sorted(os.listdir(fixtures)):
        if name.endswith(".svelte"):
            code = open(os.path.join(fixtures, name), encoding="utf-8", newline="").read()
            files["fixture_" + name[: -len(".svelte")]] = code
    svelte_types = os.path.join(ROOT, "build/upstream/svelte-deps/node_modules")
    for g in range(GROUPS):
        write_project(os.path.join(work, f"g{g:02d}"), svelte_types)
    alone = 0
    for name, code in sorted(files.items()):
        if is_global_script(code):
            d = os.path.join(work, f"s{alone:04d}")
            write_project(d, svelte_types)
            alone += 1
        else:
            d = os.path.join(work, f"g{group_of(name):02d}")
        with open(os.path.join(d, "src", name + ".svelte"), "w", encoding="utf-8", newline="") as out:
            out.write(code)
    print(len(files))


if __name__ == "__main__":
    main()
