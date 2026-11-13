module esquery

import estree

// ESLint 10.6.0's handling of selectors (lib/linter/esquery.js and source-code-traverser.js): a
// listener name may end with `:exit`, `*` and plain names skip esquery's parser, every selector
// has a specificity, and on each node the selectors that may match its type are tried in order of
// specificity.

// EslintSelector is ESLint's ESQueryParsedSelector.
pub struct EslintSelector {
pub:
	source  string // the listener name, `:exit` included
	is_exit bool
	root    Selector
	// node_types are the types a matched node may have; none: any type.
	node_types       ?[]string
	attribute_count  int
	identifier_count int
}

// parse_eslint ports ESLint's parse of a listener name.
pub fn parse_eslint(source string) !EslintSelector {
	clean := if source.ends_with(':exit') { source[..source.len - 5] } else { source }
	root := if clean == '*' {
		Selector{
			kind:  .wildcard
			value: '*'
		}
	} else if clean.len > 0 && clean.bytes().all(it.is_letter()) {
		Selector{
			kind:  .identifier
			value: clean
		}
	} else {
		parse(clean) or {
			if err is SelectorError && err.offset >= 0 {
				return error('Syntax error in selector "${clean}" at position ${err.offset}: ${err.msg()}')
			}
			return err
		}
	}
	if root.kind == .empty {
		// esquery.parse gives undefined, which analyzeParsedSelector cannot read.
		return error("Cannot read properties of undefined (reading 'type')")
	}
	mut a := Analysis{}
	types := a.analyze(root)
	return EslintSelector{
		source:           source
		is_exit:          source.ends_with(':exit')
		root:             root
		node_types:       types
		attribute_count:  a.attributes
		identifier_count: a.identifiers
	}
}

// compare ports ESQueryParsedSelector.compare: by attributes, then identifiers, then the source
// (which compares as JavaScript strings).
pub fn (a &EslintSelector) compare(b &EslintSelector) int {
	if a.attribute_count != b.attribute_count {
		return a.attribute_count - b.attribute_count
	}
	if a.identifier_count != b.identifier_count {
		return a.identifier_count - b.identifier_count
	}
	return if !units_less(utf16_units(b.source), utf16_units(a.source)) { -1 } else { 1 }
}

struct Analysis {
mut:
	attributes  int
	identifiers int
}

// analyze ports analyzeParsedSelector's analyzeSelector.
fn (mut a Analysis) analyze(sel &Selector) ?[]string {
	match sel.kind {
		.identifier {
			a.identifiers++
			return [sel.value]
		}
		.not {
			for s in sel.selectors {
				a.analyze(s)
			}
			return none
		}
		.matches {
			mut all := [][]string{}
			mut typed := true
			for s in sel.selectors {
				if types := a.analyze(s) {
					all << types
				} else {
					typed = false
				}
			}
			if !typed {
				return none
			}
			mut out := []string{}
			for types in all {
				for typ in types {
					if typ !in out {
						out << typ
					}
				}
			}
			return out
		}
		.compound {
			mut all := [][]string{}
			for s in sel.selectors {
				// `.filter(t => t)` drops the nulls; an empty array stays.
				if types := a.analyze(s) {
					all << types
				}
			}
			if all.len == 0 {
				return none
			}
			mut out := []string{}
			for typ in all[0] {
				if typ !in out {
					out << typ
				}
			}
			for types in all[1..] {
				out = out.filter(it in types)
			}
			return out
		}
		.attribute, .field, .nth_child, .nth_last_child {
			a.attributes++
			return none
		}
		.child, .descendant, .sibling, .adjacent {
			a.analyze(sel.selectors[0])
			return a.analyze(sel.selectors[1])
		}
		.class {
			if sel.name == 'function' {
				return ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression']
			}
			return none
		}
		else {
			return none
		}
	}
}

// may_match: ESLint tries the selector on a node of that type.
fn (s &EslintSelector) may_match(typ string) bool {
	if types := s.node_types {
		return typ in types
	}
	return true
}

// Match is a listener call: the selector (its index in the list given to run) on the node, when
// entering it or, for an `:exit` selector, leaving it.
pub struct Match {
pub:
	node     int
	selector int
	exit     bool
}

// run ports what ESLint's SourceCodeTraverser calls for listeners named by `sources` (as rules
// like no-restricted-syntax register them): every (node, selector) match, in the order of the
// traversal and, on one node, of the specificity of the selectors. A name given twice is one
// listener, the last one. It fails like ESLint: for a selector it cannot parse, or when matching
// throws.
pub fn run(t &estree.EsTree, sources []string) ![]Match {
	mut parsed := []EslintSelector{}
	mut indexes := []int{}
	for i, source in sources {
		k := parsed.map(it.source).index(source)
		if k >= 0 {
			indexes[k] = i
			continue
		}
		parsed << parse_eslint(source)!
		indexes << i
	}
	return run_parsed(t, parsed, indexes)
}

// run_parsed is run with parsed selectors; `indexes` are what each one is reported as.
pub fn run_parsed(t &estree.EsTree, selectors []EslintSelector, indexes []int) ![]Match {
	mut order := []int{len: selectors.len, init: index}
	order.sort_with_compare(fn [selectors] (a &int, b &int) int {
		return selectors[*a].compare(selectors[*b])
	})
	mut out := []Match{}
	mut ancestry := []int{}
	for step in t.steps() {
		node := step.node
		if step.leave {
			ancestry.delete(0)
		}
		typ := t.typ(node).type_name()
		for k in order {
			s := &selectors[k]
			if s.is_exit != step.leave || !s.may_match(typ) {
				continue
			}
			if matches(t, node, s.root, ancestry)! {
				out << Match{
					node:     node
					selector: indexes[k]
					exit:     step.leave
				}
			}
		}
		if !step.leave {
			ancestry.insert(0, node)
		}
	}
	return out
}

// match_all lists the nodes a selector matches, in the order of the traversal (on enter), as
// esquery.matches tells them with the ancestry ESLint gives.
pub fn match_all(t &estree.EsTree, sel &Selector) ![]int {
	mut out := []int{}
	mut ancestry := []int{}
	for step in t.steps() {
		if step.leave {
			ancestry.delete(0)
			continue
		}
		if matches(t, step.node, sel, ancestry)! {
			out << step.node
		}
		ancestry.insert(0, step.node)
	}
	return out
}
