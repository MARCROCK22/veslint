// Generates tests/fix_tokens_cases.json for rules/fix_tokens_test.v: for each ESTree node of each
// program below (its byte range and type), what the original functions return for it inside
// ESLint: eslint-utils' isParenthesized, and typescript-eslint's getTextWithParentheses,
// isStartOfExpressionStatement, needsPrecedingSemicolon, isStrongPrecedenceNode,
// isWeakPrecedenceParent, getMovedNodeCode (the node moved to its own place) and getWrappingFixer
// (without `wrap`, and wrapping the node in `[…]` and in `!…`). They are what rules/fix_tokens.v
// and rules/fix_wrapping.v port. Dev-time only: run `node tools/gen_fix_tokens_cases.mjs` after
// adding programs; it uses the node_modules that tests/eval_spider_byte.sh installs.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = path.join(import.meta.dirname, '..');
const nodeModules = path.join(root, 'build/eval/spider-byte/node_modules');
const require = createRequire(nodeModules + '/');
const { Linter } = require('eslint');
const parser = require('@typescript-eslint/parser');
const { ASTUtils } = require('@typescript-eslint/utils');
const util = file => require(path.join(nodeModules, '@typescript-eslint/eslint-plugin/dist/util', file));
const { getTextWithParentheses } = util('getTextWithParentheses.js');
const { isStartOfExpressionStatement } = util('isStartOfExpressionStatement.js');
const { needsPrecedingSemicolon } = util('needsPrecedingSemiColon.js');
const { getWrappingFixer, getMovedNodeCode, isStrongPrecedenceNode, isWeakPrecedenceParent } = util('getWrappingFixer.js');
const version = pkg => JSON.parse(fs.readFileSync(path.join(nodeModules, pkg, 'package.json'), 'utf8')).version;

const programs = [
  // Parentheses that are syntax and parentheses that are not.
  `(a);
((b));
f(c); f((d)); f(e, g); f((h), i); new F(j); new F((k)); new F;
f<(x: number) => void>(l);
if (m) n; if ((o)) p; while (q) r; while ((s)) t;
do u; while (v); do w; while ((x));
switch (y) { case (z): aa; }
switch ((ab)) {}
import(ac); import((ad));
try {} catch (ae) {}
function fp(af) {}
const q1 = (ag) => ag; const q2 = (ah) => (ah);
`,
  `(a).b; (c)(); (d)\`t\`; -(e); (g) + h; i + (j); (k) ? l : m;
async function w() { await (n); await o; }
(p?.q).r; (s?.t); f(u?.v); f((w?.x)); y?.(z); (aa?.ab)(); (ac?.ad)\`t\`;
ba = (bb); bc = (bd, be);
[(bf)]; ({ k: (bg) }); \`\${(bh)}\`; \`\${bi}\`;
(bj as T); <T>(bk); (bl)!; bm!; (bn satisfies T);
(/* c */ bo /* d */);
type X = (string)[]; type Y = (A | B)[]; type Z = keyof T; type U = Array<string>; type V = A.B; type W = readonly string[];
for ((bp);;) {}
for (const k of (bq)) {}
new (br)(); new bs.bt(); new (bu.bv);
typeof (bw); void bx; !by; delete bz.ca; ++cb; cc--;
cd ? (ce) : (cg); (ch, ci);
x1 = { a: 1 }; x2 = [1]; x3 = this; x4 = 'str'; x5 = 1n; x6 = /re/; x7 = null; x8 = true; x9 = undefined;
x10 = f<string>; x11 = import('m'); x12 = tag\`t\`; x13 = new K(); x14 = class {}; x15 = function () {}; x16 = \`t\`;
const o1 = () => ({ a: 1 }); const o2 = () => a.b; const o3 = () => [1];
`,
  // Statements that start right after another one, with and without a semicolon.
  `const a = 1
b.c()
let d
;[1].e
f
++g
function h() {}
i()
class K {}
j\`t\`
{
  k()
  l()
}
if (m) n()
label: o()
p ? q : r
s + t
u = v
w()()
x?.y();
(z);
\`aa\`;
import 'ab'
ac()
export * from 'ad'
ae()
export { af } from 'ag'
ah()
`,
  `function fn() {
  a()
  return
  b()
}
do c(); while (d)
e()
for (;;) g()
outer: for (;;) { break outer
  h() }
inner: for (;;) { continue inner
  i() }
var o = {}
j()
var fe = function () {}
k()
var ce = class {}
l()
class C { m() {} }
m()
var str = 'x'
n()
var num = 1
p()
var re = /x/
q()
var tpl = \`x\`
r()
var tt = true
s()
var nu = null
t()
u++
v()
w--
x()
var arrow = () => {}
y()
debugger
z()
`,
  `namespace N { a()
  b() }
class S { static { c()
  d() } }
if (e) {} else g
h()
typeof i
j()
for (const k of l) {}
m()
for (const n in o) {}
p()
while (q) {}
r()
if (s) {}
t()
var obj = { method() {} }
u()
var arr = [1]
v()
var call = w()
x()
var idx = y[0]
z()
var ty: string
aa()
var as1 = ab as string
ac()
var nn = ad!
ae()
var th = this
af()
var sp = [...ag]
ah()
function* gen() { yield
  ai()
  yield aj
  ak() }
async function asy() { await al
  am() }
var neg = -an
ao()
var kw = ap.return
aq()
var kw2 = ar.do
as1()
`,
  `for (const k of l) m()
for (const n in o) p()
while (q) r()
if (s) t(); else u()
class G { get v() { return 1 } set v(x) {} static w = () => {} }
y()
var blk
{ }
z()
var ge = function* () {}
aa()
var asf = async () => {}
ab()
var ao = { get p() { return 1 } }
ac()
enum E { A }
ad()
interface I { a: string }
ae()
type T1 = { a: string }
af()
declare const dc: number
ag()
abstract class AC { abstract m(): void }
ah()
`,
  `f<T>(a); f<T>((b)); new F<T>(c); new F<T>((d)); g?.h<T>(i); g?.h<T>((j));
k(/* c */ (l) /* d */); k( (m) , n); k(...(o)); k(...p);
q = async (r) => (s); t = async u => u; v = (w = (x)) => w;
y = { [(z)]: 1, aa: (ab), ...(ac) }; [ad = (ae)] = af; ({ ag = (ah) } = ai);
aj\`a\${(ak)}b\${al}c\`;
am ? an : ao ? ap : aq; ar ?? as0; at || au && av; aw ** ax; ay instanceof az; ba in bb;
bc.bd.be; bc[bf][bg]; bh()(); bi().bj; bk.bl(); bm?.bn.bo(); bp?.[bq]; br!.bs; bt!(); (bu as T).bv; (<T>bw).bx;
class CL extends (by) { m = (bz); [(ca)]() {} }
if (cb) { } else if ((cc)) { }
for (cd = (ce); (cf); (cg)) { }
throw (ch);
function rf() { return (ci); }
function* yf() { yield (cj); yield* (ck); }
export default (cl);
`,
  // Non-ASCII text before the nodes and CRLF line ends.
  "const ñ = '😀' // 日本語\r\n(a).b\r\nf((c)) /* ñ */\r\n`${(d)}`\r\n",
];

// The ESTree types whose nodes have a tree-sitter node with the same range (see fix_token_kinds in
// the test).
const types = new Set(['Identifier', 'Literal', 'MemberExpression', 'CallExpression', 'ChainExpression', 'TaggedTemplateExpression', 'NewExpression', 'BinaryExpression', 'LogicalExpression', 'UnaryExpression', 'UpdateExpression', 'ConditionalExpression', 'AwaitExpression', 'YieldExpression', 'ArrayExpression', 'ObjectExpression', 'ArrowFunctionExpression', 'FunctionExpression', 'ClassExpression', 'TemplateLiteral', 'TSAsExpression', 'TSSatisfiesExpression', 'TSNonNullExpression', 'TSTypeAssertion', 'AssignmentExpression', 'SequenceExpression', 'ThisExpression', 'SpreadElement', 'ImportExpression', 'TSInstantiationExpression', 'TSTypeReference', 'TSTypeOperator', 'TSStringKeyword', 'TSArrayType', 'TSUnionType']);

const cases = [];
let current = 0;
const rule = {
  meta: { type: 'problem', schema: [] },
  create(context) {
    const sourceCode = context.sourceCode;
    const code = sourceCode.text;
    const bytes = index => Buffer.byteLength(code.slice(0, index));
    const fixer = { replaceText: (node, text) => text };
    return {
      '*'(node) {
        if (!types.has(node.type)) return;
        // An Identifier with a type annotation or a `?` includes them, and the FunctionExpression of
        // a method starts at its parameters: tree-sitter has no node with those ranges.
        if (node.type === 'Identifier' && (node.typeAnnotation || node.optional)) return;
        if (node.type === 'FunctionExpression' && !/^(async\s+)?function/.test(code.slice(node.range[0]))) return;
        cases.push({
          program: current,
          start: bytes(node.range[0]),
          end: bytes(node.range[1]),
          type: node.type,
          parenthesized: ASTUtils.isParenthesized(node, sourceCode),
          withParentheses: getTextWithParentheses(sourceCode, node),
          startOfStatement: isStartOfExpressionStatement(node),
          needsSemicolon: needsPrecedingSemicolon(sourceCode, node),
          strong: isStrongPrecedenceNode(node),
          weak: isWeakPrecedenceParent(node),
          inner: getWrappingFixer({ node, sourceCode })(fixer),
          moved: getMovedNodeCode({ nodeToMove: node, destinationNode: node, sourceCode }),
          bracket: getWrappingFixer({ node, sourceCode, wrap: inner => `[${inner}]` })(fixer),
          bang: getWrappingFixer({ node, sourceCode, wrap: inner => `!${inner}` })(fixer),
        });
      },
    };
  },
};
const linter = new Linter({ configType: 'flat' });
const config = [{ files: ['**/*.ts'], languageOptions: { parser, sourceType: 'module' }, plugins: { x: { rules: { dump: rule } } }, rules: { 'x/dump': 'error' } }];
for (const [index, code] of programs.entries()) {
  current = index;
  for (const message of linter.verify(code, config, { filename: 'case.ts' })) {
    throw new Error(`program ${index}: ${message.message}`);
  }
}
const file = path.join(root, 'tests/fix_tokens_cases.json');
const versions = { eslint: version('eslint'), 'typescript-eslint': version('@typescript-eslint/eslint-plugin'), 'eslint-utils': version('@eslint-community/eslint-utils') };
// One program and one case per line.
const lines = list => list.map(item => JSON.stringify(item)).join(',\n');
fs.writeFileSync(file, `{"versions": ${JSON.stringify(versions)},\n"programs": [\n${lines(programs)}\n],\n"cases": [\n${lines(cases)}\n]}\n`);
console.log(`${programs.length} programs, ${cases.length} nodes`);
