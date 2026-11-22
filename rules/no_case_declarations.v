module rules

import time
import treesitter { children, node_kind, position_of }

// Port of the `no-case-declarations` rule of ESLint 10.15.0, with its suggestion (it has no
// options).

const ncd_messages = {
	'addBrackets': 'Add {} brackets around the case block.'
	'unexpected':  'Unexpected lexical declaration in case block.'
}

fn (mut c Checker) lint_no_case_declarations(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['switch_case', 'switch_default'], []) {
		stats.checked++
		consequent := ncd_consequent(node)
		for statement in consequent {
			if !ncd_is_lexical(statement) {
				continue
			}
			_, suggestion := c.suggestion('addBrackets', map[string]string{}, [
				fix_insert_before(consequent[0], '{ '),
				fix_insert_at(c.es_end(consequent.last()), ' }'),
			])!
			findings << Finding{
				stmt:        position_of(statement)
				message_id:  'unexpected'
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ncd_consequent are the statements of a case clause: the named children after its `:`, comments
// aside.
fn ncd_consequent(clause C.vt_node) []C.vt_node {
	mut out := []C.vt_node{}
	mut after_colon := false
	for child in children(clause) {
		if !after_colon {
			after_colon = node_kind(child) == ':'
			continue
		}
		if C.vt_node_is_named(child) && node_kind(child) != 'comment' {
			out << child
		}
	}
	return out
}

// ncd_is_lexical ports isLexicalDeclaration: a function or class declaration, or a variable
// declaration that is not `var` (`declare const` is one too).
fn ncd_is_lexical(n C.vt_node) bool {
	return match node_kind(n) {
		'function_declaration', 'generator_function_declaration', 'class_declaration',
		'abstract_class_declaration', 'lexical_declaration' {
			true
		}
		'ambient_declaration' {
			inner := first_named(n) or { return false }
			node_kind(inner) in ['lexical_declaration', 'class_declaration',
				'abstract_class_declaration']
		}
		else {
			false
		}
	}
}
