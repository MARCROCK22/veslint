module rules

import estree
import math
import regexpp

// extractCapturingGroupReferences of eslint-plugin-regexp 3.3.3 (lib/utils/
// extract-capturing-group-references.ts) and getCapturingGroupReferences of the RegExpContext, for
// the `regexp/*` rules (regexp_utils.v): how the capturing groups of a regular expression are used
// (indexes and names of the results of match, matchAll and exec, `$1` `$<name>` of a replacement,
// the parameters of a replacer function…). Each generator of the source is a list here, with its
// early returns.

// RxCgRefType is the `type` of a CapturingGroupReference.
enum RxCgRefType {
	unknown_usage
	without_ref
	array_ref
	replacement_ref
	replacer_function_ref
	split
	unknown_ref
}

// RxCgRef is a CapturingGroupReference: `kind` ('index', 'name', 'unknown', 'array',
// 'replacerFunction'), `ref` (a number when has_num, a name when has_name, else null), the
// expression `node`, `on` (the method), the property reference `prop` (when has_prop), the
// parameter `arg` (-1 for none) and the range of a replacement (bytes, when has_range).
struct RxCgRef {
	typ       RxCgRefType
	kind      string
	ref_num   f64
	has_num   bool
	ref_name  string
	has_name  bool
	node      int = -1
	on        string
	prop      RxPropRef
	has_prop  bool
	arg       int = -1
	start     int
	end       int
	has_range bool
}

struct RxCgCtx {
	flags       RxFlags
	count       int
	strict      bool
	abs_path    string
}

// The methods of WELL_KNOWN_ARRAY_METHODS: their element parameters and what they give.
struct RxArrayMethod {
	element_parameters []int
	result             string
}

const rx_well_known_array_methods = {
	'toString':       RxArrayMethod{}
	'toLocaleString': RxArrayMethod{}
	'pop':            RxArrayMethod{
		result: 'element'
	}
	'push':           RxArrayMethod{}
	'concat':         RxArrayMethod{
		result: 'array'
	}
	'join':           RxArrayMethod{}
	'reverse':        RxArrayMethod{
		result: 'array'
	}
	'shift':          RxArrayMethod{
		result: 'element'
	}
	'slice':          RxArrayMethod{
		result: 'array'
	}
	'sort':           RxArrayMethod{
		element_parameters: [0, 1]
		result:             'array'
	}
	'splice':         RxArrayMethod{
		result: 'array'
	}
	'unshift':        RxArrayMethod{}
	'indexOf':        RxArrayMethod{}
	'lastIndexOf':    RxArrayMethod{}
	'every':          RxArrayMethod{
		element_parameters: [0]
	}
	'some':           RxArrayMethod{
		element_parameters: [0]
	}
	'forEach':        RxArrayMethod{
		element_parameters: [0]
	}
	'map':            RxArrayMethod{
		element_parameters: [0]
	}
	'filter':         RxArrayMethod{
		element_parameters: [0]
		result:             'array'
	}
	'reduce':         RxArrayMethod{
		element_parameters: [1]
	}
	'reduceRight':    RxArrayMethod{
		element_parameters: [1]
	}
	'find':           RxArrayMethod{
		element_parameters: [0]
		result:             'element'
	}
	'findIndex':      RxArrayMethod{
		element_parameters: [0]
	}
	'fill':           RxArrayMethod{}
	'copyWithin':     RxArrayMethod{
		result: 'array'
	}
	'entries':        RxArrayMethod{}
	'keys':           RxArrayMethod{}
	'values':         RxArrayMethod{
		result: 'iterator'
	}
	'includes':       RxArrayMethod{}
	'flatMap':        RxArrayMethod{
		element_parameters: [0]
	}
	'flat':           RxArrayMethod{}
	'at':             RxArrayMethod{
		result: 'element'
	}
	'findLast':       RxArrayMethod{
		element_parameters: [0]
		result:             'element'
	}
	'findLastIndex':  RxArrayMethod{
		element_parameters: [0]
	}
	'toReversed':     RxArrayMethod{
		result: 'array'
	}
	'toSorted':       RxArrayMethod{
		element_parameters: [0, 1]
		result:             'array'
	}
	'toSpliced':      RxArrayMethod{
		result: 'array'
	}
	'with':           RxArrayMethod{
		result: 'array'
	}
	'toArray':        RxArrayMethod{
		result: 'array'
	}
	'take':           RxArrayMethod{
		result: 'iterator'
	}
	'drop':           RxArrayMethod{
		result: 'iterator'
	}
}

// The names WELL_KNOWN_ARRAY_METHODS[name] also finds on Object.prototype: known methods that give
// nothing.
const rx_object_prototype_names = ['constructor', 'hasOwnProperty', 'isPrototypeOf',
	'propertyIsEnumerable', 'valueOf', '__proto__', '__defineGetter__', '__defineSetter__',
	'__lookupGetter__', '__lookupSetter__']

// rx_capturing_group_references ports getCapturingGroupReferences of the RegExpContext.
fn (mut c Checker) rx_capturing_group_references(root C.vt_node, t &estree.EsTree, abs_path string, re &RxRegExp, strict_types bool) []RxCgRef {
	ctx := RxCgCtx{
		flags:    re.flags
		count:    rx_capturing_groups(&re.ast).len
		strict:   strict_types
		abs_path: abs_path
	}
	mut out := []RxCgRef{}
	for ref in c.rx_expression_references(root, t, re.regexp_node) {
		if ref.kind == .argument {
			out << c.rxcg_for_argument(root, t, ref.other, ref.node, ctx)
		} else if ref.kind == .member {
			out << c.rxcg_for_member(root, t, ref.other, ref.node, ctx)
		} else {
			out << RxCgRef{
				typ:  .unknown_usage
				node: ref.node
			}
		}
	}
	return out
}

fn (mut c Checker) rxcg_is_string(root C.vt_node, t &estree.EsTree, ctx RxCgCtx, node int) bool {
	return if ctx.strict {
		c.rx_is_string(root, t, ctx.abs_path, node)
	} else {
		c.rx_maybe_string(root, t, ctx.abs_path, node)
	}
}

fn (mut c Checker) rxcg_for_argument(root C.vt_node, t &estree.EsTree, call int, argument int, ctx RxCgCtx) []RxCgRef {
	methods := {
		'match':      1
		'search':     1
		'replace':    2
		'replaceAll': 2
		'matchAll':   1
		'split':      1
	}
	if !rx_is_known_method_call(t, call, methods) {
		return []
	}
	args := t.list(call, .arguments) or { return [] }
	if args[0] != argument {
		return []
	}
	object := t.node(t.node(call, .callee) or { return [] }, .object) or { return [] }
	if !c.rxcg_is_string(root, t, ctx, object) {
		return [RxCgRef{
			typ:  .unknown_usage
			node: argument
		}]
	}
	match rx_method_name(t, call) {
		'match' {
			return c.rxcg_for_string_match(root, t, call, argument, ctx)
		}
		'search' {
			return [RxCgRef{
				typ:  .without_ref
				node: argument
				on:   'search'
			}]
		}
		'replace', 'replaceAll' {
			return c.rxcg_for_string_replace(root, t, call, argument, ctx, rx_method_name(t,
				call))
		}
		'matchAll' {
			return c.rxcg_for_string_match_all(root, t, call, argument, ctx)
		}
		'split' {
			return [RxCgRef{
				typ:  .split
				node: call
			}]
		}
		else {
			return []
		}
	}
}

fn (mut c Checker) rxcg_for_member(root C.vt_node, t &estree.EsTree, member int, object int, ctx RxCgCtx) []RxCgRef {
	parent := rxcg_call_of_callee(t, member)
	if parent < 0 || !rx_is_known_method_call(t, parent, {
		'test': 1
		'exec': 1
	}) {
		return []
	}
	if rx_method_name(t, parent) == 'test' {
		return [RxCgRef{
			typ:  .without_ref
			node: object
			on:   'test'
		}]
	}
	// exec
	mut out := c.rxcg_for_exec_result(root, t, parent)
	if out.len == 0 {
		out << RxCgRef{
			typ:  .without_ref
			node: object
			on:   'exec'
		}
	}
	return out
}

fn (mut c Checker) rxcg_for_string_match(root C.vt_node, t &estree.EsTree, call int, argument int, ctx RxCgCtx) []RxCgRef {
	if ctx.flags.global {
		return [RxCgRef{
			typ:  .without_ref
			node: argument
			on:   'match'
		}]
	}
	mut out := c.rxcg_for_exec_result(root, t, call)
	if out.len == 0 {
		out << RxCgRef{
			typ:  .without_ref
			node: argument
			on:   'match'
		}
	}
	return out
}

fn (mut c Checker) rxcg_for_string_replace(root C.vt_node, t &estree.EsTree, call int, argument int, ctx RxCgCtx, on string) []RxCgRef {
	args := t.list(call, .arguments) or { []int{} }
	replacement := if args.len > 1 { args[1] } else { -1 }
	if replacement >= 0 && t.typ(replacement) in [.function_expression, .arrow_function_expression] {
		return c.rxcg_for_replacer_function(root, t, replacement, argument, on, ctx)
	}
	if replacement < 0 {
		return [RxCgRef{
			typ:  .unknown_usage
			node: argument
			on:   on
		}]
	}
	mut out := []RxCgRef{}
	if t.typ(replacement) == .literal {
		// verifyForReplaceReplacementLiteral
		for element in c.rx_parse_replacements(t, replacement) {
			if element.kind == .reference {
				out << rxcg_replacement_ref(element, true)
			}
		}
	} else {
		evaluated := c.rx_static_value(root, t, replacement)
		if !evaluated.found || evaluated.value.kind != .string_ {
			return [RxCgRef{
				typ:  .unknown_usage
				node: argument
				on:   on
			}]
		}
		// verifyForReplaceReplacement: the replacement string's characters (code points).
		mut chars := []RxStrToken{}
		for r in regexpp.utf16_to_wtf8(evaluated.value.units).runes() {
			chars << RxStrToken{
				value: rx_from_code_point(u32(r))
			}
		}
		for element in rx_base_parse_replacements(chars) {
			if element.kind == .reference {
				out << rxcg_replacement_ref(element, false)
			}
		}
	}
	if out.len == 0 {
		out << RxCgRef{
			typ:  .without_ref
			node: argument
			on:   on
		}
	}
	return out
}

fn rxcg_replacement_ref(element RxReplacement, with_range bool) RxCgRef {
	return RxCgRef{
		typ:       .replacement_ref
		kind:      if element.ref_is_num { 'index' } else { 'name' }
		ref_num:   f64(element.ref_num)
		has_num:   element.ref_is_num
		ref_name:  element.ref_name
		has_name:  !element.ref_is_num
		start:     element.start
		end:       element.end
		has_range: with_range
	}
}

fn (mut c Checker) rxcg_for_string_match_all(root C.vt_node, t &estree.EsTree, call int, argument int, ctx RxCgCtx) []RxCgRef {
	mut out := []RxCgRef{}
	mut use_ret := false
	for iteration_ref in c.rx_property_references(root, t, call) {
		if iteration_ref.sub == .none {
			out << RxCgRef{
				typ:  .unknown_usage
				node: argument
				on:   'matchAll'
			}
			return out
		}
		if iteration_ref.kind in [.member, .destructuring] {
			if iteration_ref.kind == .member && rxcg_is_well_known_array_method(iteration_ref.name) {
				method_call := rxcg_call_of_callee(t, iteration_ref.node)
				if method_call >= 0 {
					for cg_ref in c.rxcg_for_array_method_of_match_all(root, t, method_call,
						iteration_ref.name, argument, ctx)
					{
						use_ret = true
						out << cg_ref
						if cg_ref.typ == .unknown_ref {
							return out
						}
					}
				}
				continue
			}
			if math.is_nan(js_string_to_number(iteration_ref.name)) {
				continue
			}
		}
		for ref in c.rx_property_references_of(root, t, iteration_ref) {
			for cg_ref in c.rxcg_for_match_array_reference(root, t, ref) {
				use_ret = true
				out << cg_ref
				if cg_ref.typ == .unknown_ref {
					return out
				}
			}
		}
	}
	if !use_ret {
		out << RxCgRef{
			typ:  .without_ref
			node: argument
			on:   'matchAll'
		}
	}
	return out
}

fn (mut c Checker) rxcg_for_exec_result(root C.vt_node, t &estree.EsTree, call int) []RxCgRef {
	mut out := []RxCgRef{}
	for ref in c.rx_property_references(root, t, call) {
		for cg_ref in c.rxcg_for_match_array_reference(root, t, ref) {
			out << cg_ref
			if cg_ref.typ == .unknown_ref {
				return out
			}
		}
	}
	return out
}

fn (mut c Checker) rxcg_for_replacer_function(root C.vt_node, t &estree.EsTree, f int, argument int, on string, ctx RxCgCtx) []RxCgRef {
	params := t.list(f, .params) or { []int{} }
	if params.len < 2 && !params.any(t.typ(it) == .rest_element) {
		return [RxCgRef{
			typ:  .without_ref
			node: argument
			on:   on
		}]
	}
	mut out := []RxCgRef{}
	for index, arg in params {
		if t.typ(arg) == .rest_element {
			out << RxCgRef{
				typ:  .unknown_ref
				kind: 'replacerFunction'
				arg:  arg
			}
			return out
		}
		if index == 0 {
			continue
		} else if index <= ctx.count {
			out << RxCgRef{
				typ:     .replacer_function_ref
				kind:    'index'
				ref_num: f64(index)
				has_num: true
				arg:     arg
			}
		} else if ctx.count + 3 == index {
			if t.typ(arg) in [.identifier, .object_pattern] {
				for ref in c.rx_property_references_for_pattern(root, t, arg) {
					if ref.kind in [.member, .destructuring] {
						out << RxCgRef{
							typ:      .replacer_function_ref
							kind:     'name'
							ref_name: ref.name
							has_name: true
							prop:     ref
							has_prop: true
						}
					} else {
						out << RxCgRef{
							typ:      .replacer_function_ref
							kind:     'name'
							prop:     ref
							has_prop: true
						}
					}
				}
			} else {
				out << RxCgRef{
					typ:  .replacer_function_ref
					kind: 'name'
					arg:  arg
				}
			}
		}
	}
	return out
}

fn (mut c Checker) rxcg_for_match_array_reference(root C.vt_node, t &estree.EsTree, ref RxPropRef) []RxCgRef {
	if ref.kind !in [.member, .destructuring] {
		return [RxCgRef{
			typ:      .unknown_ref
			kind:     'array'
			prop:     ref
			has_prop: true
		}]
	}
	mut out := []RxCgRef{}
	if ref.name == 'groups' {
		for named_ref in c.rx_property_references_of(root, t, ref) {
			out << rxcg_named_array_ref(named_ref)
		}
	} else if ref.name == 'indices' {
		for indices_ref in c.rx_property_references_of(root, t, ref) {
			// iterateForRegExpIndicesArrayReference
			if indices_ref.kind in [.member, .destructuring] {
				if indices_ref.name == 'groups' {
					for named_ref in c.rx_property_references_of(root, t, indices_ref) {
						out << rxcg_named_array_ref(named_ref)
					}
				} else {
					out << rxcg_index_array_ref(indices_ref)
				}
			} else {
				out << RxCgRef{
					typ:      .unknown_ref
					kind:     'array'
					prop:     indices_ref
					has_prop: true
				}
			}
		}
	} else {
		if ref.name in ['input', 'index'] {
			return out
		}
		out << rxcg_index_array_ref(ref)
	}
	return out
}

fn (mut c Checker) rxcg_for_array_method_of_match_all(root C.vt_node, t &estree.EsTree, call int, method string, argument int, ctx RxCgCtx) []RxCgRef {
	array_method := rx_well_known_array_methods[method] or { RxArrayMethod{} }
	mut out := []RxCgRef{}
	args := t.list(call, .arguments) or { []int{} }
	if array_method.element_parameters.len > 0 && args.len > 0
		&& t.typ(args[0]) in [.function_expression, .arrow_function_expression] {
		params := t.list(args[0], .params) or { []int{} }
		for index in array_method.element_parameters {
			if index < params.len {
				for ref in c.rx_property_references_for_pattern(root, t, params[index]) {
					out << c.rxcg_for_match_array_reference(root, t, ref)
				}
			}
		}
	}
	if array_method.result == 'element' {
		for ref in c.rx_property_references(root, t, call) {
			out << c.rxcg_for_match_array_reference(root, t, ref)
		}
	} else if array_method.result in ['array', 'iterator'] {
		out << c.rxcg_for_string_match_all(root, t, call, argument, ctx)
	}
	return out
}

// rxcg_is_well_known_array_method ports isWellKnownArrayMethodName.
fn rxcg_is_well_known_array_method(name string) bool {
	return name in rx_well_known_array_methods || name in rx_object_prototype_names
}

// rxcg_index_array_ref ports getIndexArrayRef.
fn rxcg_index_array_ref(ref RxPropRef) RxCgRef {
	num := js_string_to_number(ref.name)
	finite := !math.is_nan(num) && !math.is_inf(num, 0)
	return RxCgRef{
		typ:      .array_ref
		kind:     'index'
		ref_num:  if finite { num } else { 0 }
		has_num:  finite
		prop:     ref
		has_prop: true
	}
}

// rxcg_named_array_ref ports getNamedArrayRef.
fn rxcg_named_array_ref(ref RxPropRef) RxCgRef {
	named := ref.kind in [.member, .destructuring]
	return RxCgRef{
		typ:      .array_ref
		kind:     'name'
		ref_name: if named { ref.name } else { '' }
		has_name: named
		prop:     ref
		has_prop: true
	}
}

// rxcg_call_of_callee ports getCallExpressionFromCalleeExpression: the call whose callee the
// expression is; -1 if none.
fn rxcg_call_of_callee(t &estree.EsTree, expression int) int {
	parent := rx_parent(t, expression)
	if parent < 0 || t.typ(parent) != .call_expression || (t.node(parent, .callee) or { -1 }) != expression {
		return -1
	}
	return parent
}
