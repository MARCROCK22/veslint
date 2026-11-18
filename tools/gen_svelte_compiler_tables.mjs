// Generates svelte_compiler/tables.v, the data of the Svelte 5.56.0 compiler that
// svelte_compiler/ ports: the messages of src/compiler/warnings.js and errors.js (one V function
// per code, its message built as the generated JavaScript builds it), the warning codes, the
// a11y constants (src/compiler/phases/2-analyze/visitors/shared/a11y/constants.js with the
// aria-query and axobject-query data they come from), the binding properties
// (phases/bindings.js), the element lists of src/utils.js and the autoclosing rules of
// src/html-tree-validation.js.
//
//   node tools/gen_svelte_compiler_tables.mjs svelte_compiler/tables.v && v fmt -w svelte_compiler/tables.v
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dirname, '..');
const NM = path.join(ROOT, 'build/upstream/svelte-deps/node_modules');
const SVELTE = path.join(NM, 'svelte');
const require = createRequire(path.join(NM, 'x.js'));
const acorn = require('acorn');
const version = JSON.parse(fs.readFileSync(path.join(SVELTE, 'package.json'), 'utf8')).version;

const q = s => `'${String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n').replace(/\t/g, '\\t')}'`;
const list = a => `[${a.map(q).join(', ')}]`;
const strList = a => (a.length ? list(a) : '[]string{}');
// Parameter names V reserves get a `_`.
const V_RESERVED = new Set(['rune', 'type', 'string', 'int', 'map', 'fn', 'struct', 'return', 'match', 'module', 'import', 'as', 'in', 'is', 'or', 'mut', 'go', 'spawn', 'const', 'enum', 'interface', 'union', 'select', 'lock', 'rlock', 'defer', 'unsafe', 'sizeof', 'typeof', 'none', 'nil', 'true', 'false', 'assert', 'asm', 'atomic', 'shared', 'static', 'volatile', 'pub', 'global', 'if', 'else', 'for', 'break', 'continue', 'goto', 'dump']);
const vName = n => (V_RESERVED.has(n) ? n + '_' : n);

// ---------------------------------------------------------------------------------------------
// Messages: each exported function of warnings.js / errors.js calls w(node, code, message) or
// e(node, code, message) with a template literal, possibly after `const x = …;` statements.

function vExpr(node, locals) {
  switch (node.type) {
    case 'TemplateLiteral': {
      const parts = [];
      node.quasis.forEach((quasi, i) => {
        if (quasi.value.cooked) parts.push(q(quasi.value.cooked));
        if (i < node.expressions.length) parts.push(vExpr(node.expressions[i], locals));
      });
      return parts.length ? parts.join(' + ') : "''";
    }
    case 'Literal':
      return q(node.value);
    case 'Identifier':
      if (locals.has(node.name)) return `(${locals.get(node.name)})`;
      return vName(node.name);
    case 'ConditionalExpression':
      if (node.test.type !== 'Identifier') throw new Error('test ' + node.test.type);
      return `(if ${vExpr(node.test, locals)} != '' { ${vExpr(node.consequent, locals)} } else { ${vExpr(node.alternate, locals)} })`;
    default:
      throw new Error('unsupported ' + node.type);
  }
}

function messages(file, callee, prefix) {
  const src = fs.readFileSync(path.join(SVELTE, 'src/compiler', file), 'utf8');
  const ast = acorn.parse(src, { ecmaVersion: 'latest', sourceType: 'module' });
  const out = [];
  for (const st of ast.body) {
    if (st.type !== 'ExportNamedDeclaration' || st.declaration?.type !== 'FunctionDeclaration') continue;
    const fn = st.declaration;
    const params = fn.params.slice(1).map(p => vName(p.name));
    const locals = new Map();
    let call = null;
    for (const s of fn.body.body) {
      if (s.type === 'VariableDeclaration') {
        for (const d of s.declarations) locals.set(d.id.name, vExpr(d.init, locals));
      } else if (s.type === 'ExpressionStatement' && s.expression.type === 'CallExpression' && s.expression.callee.name === callee) {
        call = s.expression;
      }
    }
    if (!call) throw new Error('no call in ' + fn.id.name);
    const code = call.arguments[1].value;
    const sig = params.map(p => `${p} string`).join(', ');
    out.push(`fn ${prefix}_${fn.id.name}(${sig}) Diag {`);
    out.push('\treturn Diag{');
    out.push(`\t\tcode:    ${q(code)}`);
    out.push(`\t\tmessage: ${vExpr(call.arguments[2], locals)}`);
    out.push('\t}', '}', '');
  }
  return out;
}

// constArray / constObject evaluate a private `const NAME = [...]` / `{...}` of a source file.
function balanced(src, from, open, close) {
  let depth = 0;
  for (let i = from; i < src.length; i++) {
    if (src[i] === open) depth++;
    else if (src[i] === close && --depth === 0) return src.slice(from, i + 1);
  }
  throw new Error('unterminated');
}
function constArray(src, name) {
  const at = src.indexOf(`const ${name} = `);
  if (at < 0) throw new Error('no ' + name);
  return eval(balanced(src, src.indexOf('[', at), '[', ']'));
}
function constObject(src, name, scope = {}) {
  const at = src.indexOf(`const ${name} = `);
  if (at < 0) throw new Error('no ' + name);
  const body = balanced(src, src.indexOf('{', at), '{', '}');
  return new Function(...Object.keys(scope), `return (${body});`)(...Object.values(scope));
}

// ---------------------------------------------------------------------------------------------

const lines = [];
lines.push(`// Code generated by tools/gen_svelte_compiler_tables.mjs from svelte ${version}; DO NOT EDIT.`);
lines.push('module svelte_compiler', '');

const warningsSrc = fs.readFileSync(path.join(SVELTE, 'src/compiler/warnings.js'), 'utf8');
const codes = eval(balanced(warningsSrc, warningsSrc.indexOf('[', warningsSrc.indexOf('export const codes = ')), '[', ']'));
const constants = await import(pathToFileURL(path.join(SVELTE, 'src/constants.js')));
lines.push('// warning_codes are the codes of warnings.js (w.codes), ignorable_runtime_warnings');
lines.push('// IGNORABLE_RUNTIME_WARNINGS of src/constants.js: what svelte-ignore comments may name.');
lines.push(`const warning_codes = ${list(codes)}`, '');
lines.push(`const ignorable_runtime_warnings = ${list(constants.IGNORABLE_RUNTIME_WARNINGS)}`, '');
lines.push('// The messages of warnings.js (w_*) and errors.js (e_*).');
lines.push(...messages('warnings.js', 'w', 'w'), ...messages('errors.js', 'e', 'e'));

// Lists of src/utils.js.
const utilsSrc = fs.readFileSync(path.join(SVELTE, 'src/utils.js'), 'utf8');
const utils = await import(pathToFileURL(path.join(SVELTE, 'src/utils.js')));
lines.push('// Element and name lists of src/utils.js.');
lines.push(`const void_element_names = ${list(constArray(utilsSrc, 'VOID_ELEMENT_NAMES'))}`, '');
lines.push(`const svg_elements = ${list(constArray(utilsSrc, 'SVG_ELEMENTS'))}`, '');
lines.push(`const mathml_elements = ${list(constArray(utilsSrc, 'MATHML_ELEMENTS'))}`, '');
lines.push(`const reserved_words = ${list(constArray(utilsSrc, 'RESERVED_WORDS'))}`, '');
lines.push(`const rune_names = ${list(utils.RUNES)}`, '');
lines.push(`const content_editable_bindings = ${list(constArray(utilsSrc, 'CONTENT_EDITABLE_BINDINGS'))}`, '');

// Binding properties.
const { binding_properties } = await import(pathToFileURL(path.join(SVELTE, 'src/compiler/phases/bindings.js')));
lines.push('// BindingProperty is an entry of binding_properties (phases/bindings.js), in its order:');
lines.push('// `valid` (valid_elements) and `invalid` (invalid_elements), has_* when the list is given.');
lines.push('struct BindingProperty {', '\tname        string', '\thas_valid   bool', '\tvalid       []string', '\thas_invalid bool', '\tinvalid     []string', '}', '');
lines.push('const binding_properties = [');
for (const [name, p] of Object.entries(binding_properties)) {
  lines.push(`\tBindingProperty{name: ${q(name)}, has_valid: ${!!p.valid_elements}, valid: ${strList(p.valid_elements ?? [])}, has_invalid: ${!!p.invalid_elements}, invalid: ${strList(p.invalid_elements ?? [])}},`);
}
lines.push(']', '');

// html-tree-validation.js: disallowed_children (private).
const htvSrc = fs.readFileSync(path.join(SVELTE, 'src/html-tree-validation.js'), 'utf8');
const autoclosing = constObject(htvSrc, 'autoclosing_children');
const disallowed = constObject(htvSrc, 'disallowed_children', { autoclosing_children: autoclosing });
lines.push('// Disallowed is an entry of disallowed_children (html-tree-validation.js).');
lines.push('struct Disallowed {', '\tparent         string', '\thas_direct     bool', '\tdirect         []string', '\thas_descendant bool', '\tdescendant     []string', '\thas_reset_by   bool', '\treset_by       []string', '\thas_only       bool', '\tonly           []string', '}', '');
lines.push('const disallowed_children = [');
for (const [name, d] of Object.entries(disallowed)) {
  const f = k => `has_${k}: ${k in d && !!d[k]}, ${k}: ${strList(d[k] ?? [])}`;
  lines.push(`\tDisallowed{parent: ${q(name)}, ${f('direct')}, ${f('descendant')}, ${f('reset_by')}, ${f('only')}},`);
}
lines.push(']', '');

// a11y constants.
const a11y = await import(pathToFileURL(path.join(SVELTE, 'src/compiler/phases/2-analyze/visitors/shared/a11y/constants.js')));
const ariaQuery = require('aria-query');
const axobject = require('axobject-query');
lines.push('// a11y constants (2-analyze/visitors/shared/a11y/constants.js).');
lines.push(`const aria_attributes = ${list(a11y.aria_attributes)}`, '');
lines.push('const a11y_required_attributes = {');
for (const [k, v] of Object.entries(a11y.a11y_required_attributes)) lines.push(`\t${q(k)}: ${list(v)}`);
lines.push('}', '');
for (const name of ['a11y_distracting_elements', 'a11y_required_content', 'a11y_labelable', 'a11y_interactive_handlers', 'a11y_recommended_interactive_handlers']) {
  lines.push(`const ${name} = ${list(a11y[name])}`, '');
}
const mapOut = (name, m) => {
  lines.push(`const ${name} = {`);
  for (const [k, v] of m) lines.push(`\t${q(k)}: ${q(v)}`);
  lines.push('}', '');
};
mapOut('a11y_nested_implicit_semantics', a11y.a11y_nested_implicit_semantics);
mapOut('a11y_implicit_semantics', a11y.a11y_implicit_semantics);
mapOut('menuitem_type_to_implicit_role', a11y.menuitem_type_to_implicit_role);
mapOut('input_type_to_implicit_role', a11y.input_type_to_implicit_role);
lines.push('const a11y_non_interactive_element_to_interactive_role_exceptions = {');
for (const [k, v] of Object.entries(a11y.a11y_non_interactive_element_to_interactive_role_exceptions)) lines.push(`\t${q(k)}: ${list(v)}`);
lines.push('}', '');
for (const name of ['combobox_if_list', 'address_type_tokens', 'autofill_field_name_tokens', 'contact_type_tokens', 'autofill_contact_field_name_tokens', 'invisible_elements', 'aria_roles', 'abstract_roles', 'non_interactive_roles', 'interactive_roles', 'presentation_roles']) {
  lines.push(`const ${name} = ${list([...a11y[name]])}`, '');
}
lines.push('// Schema is an element schema of aria-query / axobject-query: the element name and the');
lines.push('// attributes it must have (`value` when has_value).');
lines.push('struct SchemaAttr {', '\tname      string', '\thas_value bool', '\tvalue     string', '}', '');
lines.push('struct Schema {', '\tname           string', '\thas_attributes bool', '\tattributes     []SchemaAttr', '}', '');
const schemaV = s => {
  const attrs = (s.attributes ?? []).map(a => `SchemaAttr{name: ${q(a.name)}, has_value: ${a.value !== undefined}, value: ${q(a.value ?? '')}}`);
  return `Schema{name: ${q(s.name)}, has_attributes: ${!!s.attributes}, attributes: ${attrs.length ? `[${attrs.join(', ')}]` : '[]SchemaAttr{}'}}`;
};
for (const name of ['interactive_element_role_schemas', 'non_interactive_element_role_schemas', 'interactive_element_ax_object_schemas', 'non_interactive_element_ax_object_schemas']) {
  lines.push(`const ${name} = [`);
  for (const s of a11y[name]) lines.push(`\t${schemaV(s)},`);
  lines.push(']', '');
}
lines.push("// AriaProp is an entry of aria-query's `aria` map: its type and allowed values (as strings).");
lines.push('struct AriaProp {', '\tname   string', '\ttyp    string', '\tvalues []string', '}', '');
lines.push('const aria_props = [');
for (const [name, def] of ariaQuery.aria.entries()) lines.push(`\tAriaProp{name: ${q(name)}, typ: ${q(def.type)}, values: ${strList((def.values ?? []).map(String))}},`);
lines.push(']', '');
lines.push("// RoleDef is an entry of aria-query's `roles` map: the keys of its props and requiredProps.");
lines.push('struct RoleDef {', '\tname     string', '\tprops    []string', '\trequired []string', '}', '');
lines.push('const role_defs = [');
for (const [name, def] of ariaQuery.roles.entries()) lines.push(`\tRoleDef{name: ${q(name)}, props: ${strList(Object.keys(def.props))}, required: ${strList(Object.keys(def.requiredProps))}},`);
lines.push(']', '');
lines.push("// ElementAx is an entry of axobject-query's elementAXObjects: an element schema and the roles");
lines.push('// of its AX objects (AXObjectRoles), in their order.');
lines.push('struct ElementAx {', '\tschema Schema', '\troles  []string', '}', '');
lines.push('const element_ax_objects = [');
for (const [schema, names] of axobject.elementAXObjects.entries()) {
  const roles = [];
  for (const n of names) for (const r of axobject.AXObjectRoles.get(n) ?? []) roles.push(r.name);
  lines.push(`\tElementAx{schema: ${schemaV(schema)}, roles: ${strList(roles)}},`);
}
lines.push(']', '');

fs.writeFileSync(process.argv[2], lines.join('\n') + '\n');
