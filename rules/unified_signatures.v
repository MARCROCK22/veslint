module rules

import json2
import offsets
import time
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent, node_start }

// Port of the `unified-signatures` rule of typescript-eslint 8.62.0, with its options
// `ignoreDifferentlyNamedParameters` and `ignoreOverloadsWithDifferentJSDoc`.

const us_messages = {
	'omittingRestParameter':     '{{failureStringStart}} with a rest parameter.'
	'omittingSingleParameter':   '{{failureStringStart}} with an optional parameter.'
	'singleParameterDifference': '{{failureStringStart}} taking `{{type1}} | {{type2}}`.'
}

struct UsOptions {
	ignore_differently_named_parameters   bool
	ignore_overloads_with_different_jsdoc bool
}

fn us_options(options []json2.Any) !UsOptions {
	o := option_object(unified_signatures, options, ['ignoreDifferentlyNamedParameters',
		'ignoreOverloadsWithDifferentJSDoc'])!
	return UsOptions{
		ignore_differently_named_parameters:   o.bool_value('ignoreDifferentlyNamedParameters')!
		ignore_overloads_with_different_jsdoc: o.bool_value('ignoreOverloadsWithDifferentJSDoc')!
	}
}

// UsParam is a parameter as ESTree has it: its type (Identifier, RestElement, ObjectPattern,
// ArrayPattern, AssignmentPattern or TSParameterProperty), where it starts, its `optional` and
// its type annotation (those of the `parameter` of a TSParameterProperty; an AssignmentPattern
// has neither), and getStaticParameterName.
struct UsParam {
	kind      string
	start     int
	end       int // where the ESTree parameter ends (its annotation or default value included)
	optional  bool
	has_type  bool
	type_node C.TSNode // the type of the annotation, without parentheses
	has_name  bool
	name      string
	is_this   bool // an Identifier named `this`
}

// UsTypeParameter is a TSTypeParameter: its name and the ESTree type of its constraint ('' for
// none).
struct UsTypeParameter {
	name       string
	constraint string
}

// UsSignature is a SignatureDefinition: its parameters, its return type (the text of the
// typeAnnotation of its TSTypeAnnotation), its type parameters, where it starts in ESTree, and
// where the node that getCommentTargetNode gives starts.
struct UsSignature {
	params              []UsParam
	has_return          bool
	return_text         string
	has_type_parameters bool
	type_parameters     []UsTypeParameter
	start               int
	comment_target      int
}

// UsScope holds the overloads of one scope (a class declaration, an interface, a type literal, a
// module block or the program) by key, in the order the keys appear, and the names of the type
// parameters of the class or interface.
struct UsScope {
mut:
	type_parameters []string
	keys            []string
	overloads       map[string][]UsSignature
}

fn (mut c Checker) lint_unified_signatures(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := us_options(c.rule_options(unified_signatures))!
	mut findings := []Finding{}
	mut scopes := []UsScope{}
	mut scope_index := map[u64]int{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['function_signature', 'method_signature',
		'abstract_method_signature', 'call_signature', 'construct_signature'], []) {
		scope_node, holder := us_scope_of(node) or { continue }
		key := c.us_overload_key(node) or { continue }
		checked++
		scope_key := node_key(scope_node)
		if scope_key !in scope_index {
			scope_index[scope_key] = scopes.len
			mut parameter_names := []string{}
			if h := holder {
				if parameters := node_field(h, 'type_parameters') {
					for parameter in named_children(parameters) {
						if name := node_field(parameter, 'name') {
							parameter_names << c.identifier_name(name)
						}
					}
				}
			}
			scopes << UsScope{
				type_parameters: parameter_names
			}
		}
		index := scope_index[scope_key]
		if key !in scopes[index].overloads {
			scopes[index].keys << key
			scopes[index].overloads[key] = []UsSignature{}
		}
		scopes[index].overloads[key] << c.us_signature(node)
	}
	mut lines := offsets.LineStarts{}
	mut has_lines := false
	for scope in scopes {
		for key in scope.keys {
			overloads := scope.overloads[key] or { continue }
			only2 := overloads.len == 2
			for i in 0 .. overloads.len {
				for j in i + 1 .. overloads.len {
					a := overloads[i]
					b := overloads[j]
					if !c.us_can_be_unified(root, a, b, o, scope.type_parameters) {
						continue
					}
					if !has_lines && !only2 {
						lines = offsets.line_starts(c.src)
						has_lines = true
					}
					if a.params.len == b.params.len {
						index := c.us_single_difference(a.params, b.params) or { continue }
						p0 := a.params[index]
						p1 := b.params[index]
						findings << Finding{
							stmt:       c.position_range(p1.start, p1.end)
							message_id: 'singleParameterDifference'
							data:       {
								'failureStringStart': us_failure_start(only2, lines, p0.start)
								'type1':              c.us_param_type_text(p0)
								'type2':              c.us_param_type_text(p1)
							}
						}
						continue
					}
					extra, other := c.us_optional_or_rest_difference(a, b) or { continue }
					findings << Finding{
						stmt:       c.position_range(extra.start, extra.end)
						message_id: if extra.kind == 'RestElement' {
							'omittingRestParameter'
						} else {
							'omittingSingleParameter'
						}
						data:       {
							'failureStringStart': us_failure_start(only2, lines, other.start)
						}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// us_failure_start ports failureStringStart: with more than two overloads it names the line of
// the other one.
fn us_failure_start(only2 bool, lines offsets.LineStarts, other int) string {
	overloads := if only2 {
		'These overloads'
	} else {
		'This overload and the one on line ${lines.line_index(other) + 1}'
	}
	return '${overloads} can be combined into one signature'
}

// us_param_type_text is getText(typeAnnotation?.typeAnnotation) of a parameter: without an
// annotation, getText() gives the whole text of the file.
fn (c &Checker) us_param_type_text(p UsParam) string {
	return if p.has_type { c.text(p.type_node) } else { c.src }
}

// us_scope_of is the scope an overload is added to, and the class or interface whose type
// parameters it has: the overload is a TSDeclareFunction of the Program or of a TSModuleBlock
// (also inside an export), a method without body of a ClassDeclaration (not of a class
// expression), or a member of an interface or a type literal; getters and setters are not
// overloads. none for the others, which no scope takes.
fn us_scope_of(node C.TSNode) ?(C.TSNode, ?C.TSNode) {
	if node_kind(node) == 'function_signature' {
		mut parent := node_parent(node)?
		if node_kind(parent) == 'ambient_declaration' {
			parent = node_parent(parent)?
		}
		if node_kind(parent) == 'export_statement' {
			parent = node_parent(parent)?
		}
		if node_kind(parent) == 'program' || us_is_module_block(parent) {
			return parent, none
		}
		return none
	}
	if has_child_kind(node, 'get') || has_child_kind(node, 'set') {
		return none
	}
	parent := node_parent(node)?
	match node_kind(parent) {
		'class_body' {
			class := node_parent(parent)?
			if node_kind(node) !in ['method_signature', 'abstract_method_signature']
				|| !us_is_class_declaration(class) {
				return none
			}
			return parent, class
		}
		'interface_body' {
			return parent, node_parent(parent)
		}
		'object_type' {
			return parent, none
		}
		else {
			return none
		}
	}
}

// us_is_module_block: the body of a namespace, a module or `global` (a TSModuleBlock).
fn us_is_module_block(n C.TSNode) bool {
	if node_kind(n) != 'statement_block' {
		return false
	}
	holder := node_parent(n) or { return false }
	return node_kind(holder) in ['internal_module', 'module']
		|| (node_kind(holder) == 'ambient_declaration' && has_child_kind(holder, 'global'))
}

// us_is_class_declaration: a ClassDeclaration, also `export default class {}`, which tree-sitter
// has as a class expression.
fn us_is_class_declaration(n C.TSNode) bool {
	match node_kind(n) {
		'class_declaration', 'abstract_class_declaration' {
			return true
		}
		'class' {
			parent := node_parent(n) or { return false }
			return node_kind(parent) == 'export_statement' && has_child_kind(parent, 'default')
		}
		else {
			return false
		}
	}
}

// us_overload_key ports getOverloadKey: the name of a TSDeclareFunction (or the type of the
// export of `export default function (): void;`), and for the others whether the key is computed
// and whether it is static, followed by getOverloadInfo.
fn (c &Checker) us_overload_key(node C.TSNode) ?string {
	match node_kind(node) {
		'function_signature' {
			if name := node_field(node, 'name') {
				return c.identifier_name(name)
			}
			mut parent := node_parent(node)?
			if node_kind(parent) == 'ambient_declaration' {
				parent = node_parent(parent)?
			}
			if node_kind(parent) != 'export_statement' {
				return none
			}
			return if has_child_kind(parent, 'default') {
				'ExportDefaultDeclaration'
			} else {
				'ExportNamedDeclaration'
			}
		}
		'construct_signature' {
			return '11constructor'
		}
		'call_signature' {
			return '11()'
		}
		else {
			key := node_field(node, 'name')?
			computed := node_kind(key) == 'computed_property_name'
			computed_mark := if computed { '0' } else { '1' }
			static_mark := if has_child_kind(node, 'static') { '0' } else { '1' }
			return computed_mark + static_mark + c.us_key_info(key, computed)
		}
	}
}

// us_key_info is getOverloadInfo for a key: `private_identifier_<name>`, `identifier_<name>`, or
// the `raw` of a Literal, which other expressions do not have ('undefined').
fn (c &Checker) us_key_info(key C.TSNode, computed bool) string {
	expression := if computed {
		unwrap_parens(first_named(key) or { return 'undefined' })
	} else {
		key
	}
	return match node_kind(expression) {
		'private_property_identifier' { 'private_identifier_${c.identifier_name(expression)[1..]}' }
		'property_identifier', 'identifier', 'undefined' {
			'identifier_${c.identifier_name(expression)}'
		}
		'string', 'number', 'regex', 'true', 'false', 'null' { c.text(expression) }
		else { 'undefined' }
	}
}

// us_signature reads a SignatureDefinition (for a method, its value: a
// TSEmptyBodyFunctionExpression, which starts at its parameters or its type parameters).
fn (c &Checker) us_signature(node C.TSNode) UsSignature {
	mut params := []UsParam{}
	if list := node_field(node, 'parameters') {
		for p in named_children(list) {
			if node_kind(p) in ['required_parameter', 'optional_parameter'] {
				params << c.us_param(p)
			}
		}
	}
	mut has_return := false
	mut return_text := ''
	if annotation := node_field(node, if node_kind(node) == 'construct_signature' {
		'type'
	} else {
		'return_type'
	}) {
		if inner := first_named(annotation) {
			has_return = true
			return_text = c.text(unwrap_type_parens(inner))
		}
	}
	mut type_parameters := []UsTypeParameter{}
	mut has_type_parameters := false
	if list := node_field(node, 'type_parameters') {
		has_type_parameters = true
		for parameter in named_children(list) {
			name := node_field(parameter, 'name') or { continue }
			mut constraint := ''
			if clause := node_field(parameter, 'constraint') {
				if t := first_named(clause) {
					constraint = c.us_type_kind(unwrap_type_parens(t))
				}
			}
			type_parameters << UsTypeParameter{
				name:       c.identifier_name(name)
				constraint: constraint
			}
		}
	}
	mut start := node_start(node)
	mut comment_target := node_start(node)
	parent := node_parent(node) or { node }
	match node_kind(node) {
		'function_signature' {
			// A declared function starts at its `declare`; getCommentTargetNode gives the export
			// around it.
			if node_kind(parent) == 'ambient_declaration' {
				start = node_start(parent)
				comment_target = start
				if holder := node_parent(parent) {
					if node_kind(holder) == 'export_statement' {
						comment_target = node_start(holder)
					}
				}
			} else if node_kind(parent) == 'export_statement' {
				comment_target = node_start(parent)
			}
		}
		'method_signature', 'abstract_method_signature' {
			if node_kind(parent) == 'class_body' {
				if list := node_field(node, 'type_parameters') {
					start = node_start(list)
				} else if list := node_field(node, 'parameters') {
					start = node_start(list)
				}
			}
		}
		else {}
	}
	return UsSignature{
		params:              params
		has_return:          has_return
		return_text:         return_text
		has_type_parameters: has_type_parameters
		type_parameters:     type_parameters
		start:               start
		comment_target:      comment_target
	}
}

// us_param reads a parameter as typescript-estree converts it.
fn (c &Checker) us_param(p C.TSNode) UsParam {
	pattern := node_field(p, 'pattern') or { node_field(p, 'name') or { p } }
	mut has_value := false
	if _ := node_field(p, 'value') {
		has_value = true
	}
	question := node_kind(p) == 'optional_parameter'
	mut has_type := false
	mut type_node := p
	if annotation := node_field(p, 'type') {
		if t := first_named(annotation) {
			has_type = true
			type_node = unwrap_type_parens(t)
		}
	}
	if has_child_kind(p, 'accessibility_modifier') || has_child_kind(p, 'override_modifier')
		|| has_child_kind(p, 'readonly') {
		// Its `parameter` is the pattern, or an AssignmentPattern without optional nor annotation.
		return UsParam{
			end:       c.es_end(p)
			kind:      'TSParameterProperty'
			start:     node_start(p)
			optional:  question && !has_value
			has_type:  has_type && !has_value
			type_node: type_node
		}
	}
	if node_kind(pattern) == 'rest_pattern' {
		argument := first_named(pattern) or { pattern }
		is_name := node_kind(argument) == 'identifier'
		return UsParam{
			end:       c.es_end(p)
			kind:      'RestElement'
			start:     node_start(p)
			has_type:  has_type
			type_node: type_node
			has_name:  is_name
			name:      if is_name { c.identifier_name(argument) } else { '' }
		}
	}
	if has_value {
		return UsParam{
			end:       c.es_end(p)
			kind:      'AssignmentPattern'
			start:     node_start(pattern)
			type_node: type_node
		}
	}
	kind := match node_kind(pattern) {
		'object_pattern' { 'ObjectPattern' }
		'array_pattern' { 'ArrayPattern' }
		else { 'Identifier' }
	}
	is_this := node_kind(pattern) == 'this'
	return UsParam{
		end:       c.es_end(p)
		kind:      kind
		start:     node_start(pattern)
		optional:  question
		has_type:  has_type
		type_node: type_node
		has_name:  kind == 'Identifier'
		name:      if is_this {
			'this'
		} else if kind == 'Identifier' {
			c.identifier_name(pattern)
		} else {
			''
		}
		is_this:   is_this
	}
}

// us_type_kind is the ESTree type of a type node, as constraintsAreEqual compares them.
fn (c &Checker) us_type_kind(n C.TSNode) string {
	kind := node_kind(n)
	match kind {
		'predefined_type' {
			text := c.text(n)
			return match text {
				'any' { 'TSAnyKeyword' }
				'boolean' { 'TSBooleanKeyword' }
				'never' { 'TSNeverKeyword' }
				'number' { 'TSNumberKeyword' }
				'object' { 'TSObjectKeyword' }
				'string' { 'TSStringKeyword' }
				'symbol' { 'TSSymbolKeyword' }
				'unknown' { 'TSUnknownKeyword' }
				'void' { 'TSVoidKeyword' }
				'intrinsic' { 'TSIntrinsicKeyword' }
				else {
					if text.starts_with('unique') { 'TSTypeOperator' } else { text }
				}
			}
		}
		'type_identifier' {
			return if c.text(n) == 'bigint' { 'TSBigIntKeyword' } else { 'TSTypeReference' }
		}
		'generic_type', 'nested_type_identifier' {
			return 'TSTypeReference'
		}
		'literal_type' {
			inner := first_named(n) or { return 'TSLiteralType' }
			return match node_kind(inner) {
				'null' { 'TSNullKeyword' }
				'undefined' { 'TSUndefinedKeyword' }
				else { 'TSLiteralType' }
			}
		}
		'object_type' {
			if _ := scope_mapped_clause(n) {
				return 'TSMappedType'
			}
			return 'TSTypeLiteral'
		}
		'index_type_query', 'readonly_type' {
			return 'TSTypeOperator'
		}
		else {
			return kind
		}
	}
}

// us_can_be_unified ports signaturesCanBeUnified.
fn (mut c Checker) us_can_be_unified(root C.TSNode, a UsSignature, b UsSignature, o UsOptions, type_parameters []string) bool {
	if o.ignore_differently_named_parameters {
		for i in 0 .. if a.params.len < b.params.len { a.params.len } else { b.params.len } {
			pa := a.params[i]
			pb := b.params[i]
			if pa.kind == pb.kind && (pa.has_name != pb.has_name || pa.name != pb.name) {
				return false
			}
		}
	}
	if o.ignore_overloads_with_different_jsdoc {
		has_a, comment_a := c.us_block_comment(root, a.comment_target)
		has_b, comment_b := c.us_block_comment(root, b.comment_target)
		if has_a != has_b || comment_a != comment_b {
			return false
		}
	}
	return us_types_equal(a.has_return, a.return_text, b.has_return, b.return_text)
		&& us_type_parameters_equal(a, b)
		&& c.us_uses_type_parameter(a, type_parameters) == c.us_uses_type_parameter(b, type_parameters)
}

// us_block_comment ports getBlockCommentForNode: the value of the last block comment right
// before the node.
fn (mut c Checker) us_block_comment(root C.TSNode, start int) (bool, string) {
	comments := c.source_tokens(root).comments_before(start)
	for i := comments.len - 1; i >= 0; i-- {
		if comments[i].kind == .block_comment {
			return true, c.src[comments[i].start + 2..comments[i].end - 2]
		}
	}
	return false, ''
}

// us_types_equal ports typesAreEqual: both without annotation, or the same text.
fn us_types_equal(has_a bool, a string, has_b bool, b string) bool {
	return (!has_a && !has_b) || (has_a && has_b && a == b)
}

fn (c &Checker) us_param_types_equal(a UsParam, b UsParam) bool {
	return us_types_equal(a.has_type, if a.has_type { c.text(a.type_node) } else { '' },
		b.has_type, if b.has_type { c.text(b.type_node) } else { '' })
}

// us_type_parameters_equal: both without type parameters, or the same names with constraints of
// the same ESTree type (typeParametersAreEqual).
fn us_type_parameters_equal(a UsSignature, b UsSignature) bool {
	if !a.has_type_parameters || !b.has_type_parameters {
		return a.has_type_parameters == b.has_type_parameters
	}
	if a.type_parameters.len != b.type_parameters.len {
		return false
	}
	for i, pa in a.type_parameters {
		if pa.name != b.type_parameters[i].name || pa.constraint != b.type_parameters[i].constraint {
			return false
		}
	}
	return true
}

// us_uses_type_parameter ports signatureUsesTypeParameter: the annotation of a parameter is a
// type parameter of the class or interface, through arrays, `keyof`, `readonly` and the values of
// a mapped type.
fn (c &Checker) us_uses_type_parameter(s UsSignature, outer []string) bool {
	if outer.len == 0 {
		return false
	}
	for p in s.params {
		if p.has_type && c.us_contains_type_parameter(p.type_node, outer, 0) {
			return true
		}
	}
	return false
}

fn (c &Checker) us_contains_type_parameter(n C.TSNode, outer []string, depth int) bool {
	if depth > max_expression_depth {
		return false
	}
	node := unwrap_type_parens(n)
	match node_kind(node) {
		'type_identifier' {
			return c.text(node) != 'bigint' && c.identifier_name(node) in outer
		}
		'generic_type' {
			name := node_field(node, 'name') or { return false }
			return node_kind(name) == 'type_identifier' && c.identifier_name(name) in outer
		}
		'array_type', 'index_type_query', 'readonly_type' {
			inner := first_named(node) or { return false }
			return c.us_contains_type_parameter(inner, outer, depth + 1)
		}
		'object_type' {
			// The typeAnnotation of a TSMappedType: the type of its values.
			if _ := scope_mapped_clause(node) {
				for member in named_children(node) {
					for part in named_children(member) {
						if node_kind(part) == 'type_annotation' {
							inner := first_named(part) or { return false }
							return c.us_contains_type_parameter(inner, outer, depth + 1)
						}
					}
				}
			}
			return false
		}
		else {
			return false
		}
	}
}

// us_sigils_equal ports parametersHaveEqualSigils.
fn us_sigils_equal(a UsParam, b UsParam) bool {
	return (a.kind == 'RestElement') == (b.kind == 'RestElement') && a.optional == b.optional
}

fn (c &Checker) us_params_equal(a UsParam, b UsParam) bool {
	return us_sigils_equal(a, b) && c.us_param_types_equal(a, b)
}

// us_is_this_void: an Identifier `this` annotated `void`.
fn (c &Checker) us_is_this_void(params []UsParam) bool {
	if params.len == 0 {
		return false
	}
	p := params[0]
	return p.kind == 'Identifier' && p.is_this && p.has_type
		&& node_kind(p.type_node) == 'predefined_type' && c.text(p.type_node) == 'void'
}

// us_single_difference ports signaturesDifferBySingleParameter (the lists have the same length):
// the index of the only parameter whose type differs, with the same sigils and not a rest one.
fn (c &Checker) us_single_difference(a []UsParam, b []UsParam) ?int {
	if c.us_is_this_void(a) || c.us_is_this_void(b) {
		return none
	}
	mut index := -1
	for i in 0 .. a.len {
		if !c.us_params_equal(a[i], b[i]) {
			index = i
			break
		}
	}
	if index < 0 {
		return none
	}
	for i in index + 1 .. a.len {
		if !c.us_params_equal(a[i], b[i]) {
			return none
		}
	}
	if !us_sigils_equal(a[index], b[index]) || a[index].kind == 'RestElement' {
		return none
	}
	return index
}

// us_optional_or_rest_difference ports signaturesDifferByOptionalOrRestParameter: the last
// parameter of the longer list, which the shorter signature lacks, when both or neither have a
// `this` parameter, the extra parameters after the first one may be missing, the types they share
// are the same, and the shorter list does not end with a rest parameter.
fn (c &Checker) us_optional_or_rest_difference(a UsSignature, b UsSignature) ?(UsParam, UsSignature) {
	sig1 := a.params
	sig2 := b.params
	min_len := if sig1.len < sig2.len { sig1.len } else { sig2.len }
	longer := if sig1.len < sig2.len { sig2 } else { sig1 }
	shorter := if sig1.len < sig2.len { sig1 } else { sig2 }
	shorter_sig := if sig1.len < sig2.len { a } else { b }
	if us_has_this(sig1) != us_has_this(sig2) {
		return none
	}
	if c.us_is_this_void(sig1) || c.us_is_this_void(sig2) {
		return none
	}
	for i := min_len + 1; i < longer.len; i++ {
		if longer[i].kind != 'RestElement' && !longer[i].optional {
			return none
		}
	}
	for i in 0 .. min_len {
		if !c.us_param_types_equal(sig1[i], sig2[i]) {
			return none
		}
	}
	if min_len > 0 && shorter[min_len - 1].kind == 'RestElement' {
		return none
	}
	return longer[longer.len - 1], shorter_sig
}

// us_has_this ports isThisParam for the first parameter.
fn us_has_this(params []UsParam) bool {
	return params.len > 0 && params[0].kind == 'Identifier' && params[0].is_this
}
