"""corpus.py WORK: writes the corpus of tests/vue-lint/compare.sh to WORK: the SFCs of the tests of
eslint-plugin-vue (tests/rules/vue/*/upstream.json) whose script is TypeScript or that have none,
the ones with a JavaScript script with `lang="ts"` added to their <script> tags (veslint lints
only TypeScript: the case is linted as TypeScript, as the JavaScript tests of ESLint core are), and
the fixtures of tests/vue-lint/fixtures. Each SFC goes once (the same code in several cases is
linted once), to WORK/gNN/src/<case id>.vue, NN from a hash of the id: a group is a project of its
own (tsconfig.json, a `*.vue` shim, node_modules with vue's types) so that typescript-eslint's
programs stay small. A script that is not a module (no import or export) declares globals, which
the other files of its program see: ESLint's program has the other .vue files as the text of the
file (or as the code of the ones it linted before), veslint's has the code of all of them. Such an
SFC is a project alone, WORK/sNNNN/src/<case id>.vue. Prints the number of files."""
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
        "jsx": "preserve",
        "types": [],
    },
    "include": ["src/**/*.ts", "src/**/*.vue"],
}

SHIM = """declare module '*.vue' {
  const component: { name?: string };
  export default component;
}
"""

SCRIPT_TAG = re.compile(r"<script\b([^>]*)>", re.I)
LANG = re.compile(r"""\blang\s*=\s*(["']?)([^"'\s>]*)\1""", re.I)


def as_typescript(code):
    """Adds lang="ts" to the <script> tags without a lang (lang="js" and "jsx" become "ts" and
    "tsx")."""

    def tag(m):
        attrs = m.group(1)
        found = LANG.search(attrs)
        if found is None:
            return "<script lang=\"ts\"" + attrs + ">"
        lang = found.group(2).lower()
        new = {"js": "ts", "jsx": "tsx", "": "ts"}.get(lang, lang)
        return "<script" + attrs[: found.start()] + f'lang="{new}"' + attrs[found.end() :] + ">"

    return SCRIPT_TAG.sub(tag, code)


def group_of(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % GROUPS


SCRIPT = re.compile(r"<script\b[^>]*>(.*?)</script>", re.S | re.I)
# An import or export declaration at the start of a line (not a dynamic `import(…)`).
MODULE = re.compile(r"^\s*(export\b|import\b(?!\s*[(.]))", re.M)


def is_global_script(code):
    """The scripts of the SFC have code and no import or export: TypeScript reads them as a script
    whose declarations are global."""
    script = "".join(SCRIPT.findall(code))
    return script.strip() != "" and MODULE.search(script) is None


def write_project(d, vue_types):
    os.makedirs(os.path.join(d, "src"), exist_ok=True)
    json.dump(TSCONFIG, open(os.path.join(d, "tsconfig.json"), "w"), indent=2)
    open(os.path.join(d, "src", "shims-vue.d.ts"), "w").write(SHIM)
    os.symlink(vue_types, os.path.join(d, "node_modules"))


def main():
    work = os.path.abspath(sys.argv[1])
    if os.path.isdir(work):
        for entry in os.listdir(work):
            if re.fullmatch(r"g\d\d|s\d\d\d\d", entry):
                shutil.rmtree(os.path.join(work, entry))
    files = {}  # name -> code
    seen = set()
    cases = []
    for path in sorted(glob.glob(os.path.join(ROOT, "tests/rules/vue/*/upstream.json"))):
        for case in json.load(open(path, encoding="utf-8"))["cases"]:
            if not case.get("sfc"):
                continue
            script = case.get("script")
            code = case["code"]
            if script == "js":
                code = as_typescript(code)
            elif script not in ("ts", "none"):
                continue
            cases.append((case["id"], code))
    for case_id, code in sorted(cases):
        if code in seen:
            continue
        try:
            code.encode("utf-8")
        except UnicodeEncodeError:
            # A lone surrogate, which a file cannot have.
            continue
        seen.add(code)
        files[re.sub(r"[^A-Za-z0-9_.-]", "_", case_id)] = code
    fixtures = os.path.join(ROOT, "tests/vue-lint/fixtures")
    for name in sorted(os.listdir(fixtures)):
        if name.endswith(".vue"):
            code = open(os.path.join(fixtures, name), encoding="utf-8", newline="").read()
            files["fixture_" + name[:-4]] = code
    vue_types = os.path.join(ROOT, "build/upstream/vue-deps/node_modules")
    for g in range(GROUPS):
        write_project(os.path.join(work, f"g{g:02d}"), vue_types)
    alone = 0
    for name, code in sorted(files.items()):
        if is_global_script(code):
            d = os.path.join(work, f"s{alone:04d}")
            write_project(d, vue_types)
            alone += 1
        else:
            d = os.path.join(work, f"g{group_of(name):02d}")
        with open(os.path.join(d, "src", name + ".vue"), "w", encoding="utf-8", newline="") as out:
            out.write(code)
    print(len(files))


if __name__ == "__main__":
    main()
