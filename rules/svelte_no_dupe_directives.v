module rules

// Ports of the `svelte/no-dupe-on-directives` and `svelte/no-dupe-use-directives` rules of
// eslint-plugin-svelte 3.24.1: in a start tag, `on:` (by event) or `use:` (by key text) directives
// with the same expression (the same tokens, or both without one) are all reported, each naming
// the line of another one.

const snddo_messages = {
	'duplication': 'This `on:{{type}}` directive is the same and duplicate directives in L{{lineNo}}.'
}

const snddu_messages = {
	'duplication': 'This `{{keyText}}` directive is the same and duplicate directives in L{{lineNo}}.'
}

// SnddGroup is the directives of a start tag with one key and the same expression.
struct SnddGroup {
	key        string
	expression int = -1
mut:
	nodes []int
}

// sndd_check reports the duplicate directives of each start tag: those of kind `kind`, keyed by
// the event name (`on:`) or the key text (`use:`); `data_key` names the key in the message.
fn (mut c Checker) sndd_check(kind string, data_key string) []Finding {
	doc := c.svelte.doc
	mut findings := []Finding{}
	for tag in c.sv_snodes_of(.start_tag) {
		mut groups := []SnddGroup{}
		for a in doc.nodes[tag].attributes {
			n := doc.nodes[a]
			if n.typ != .directive || n.kind != kind {
				continue
			}
			key := if kind == 'EventHandler' {
				c.sv_directive_key_name(a)
			} else {
				c.sv_attribute_key_text(a)
			}
			expression := if n.expression.es { n.expression.idx } else { -1 }
			mut found := -1
			for k, g in groups {
				if g.key != key {
					continue
				}
				same := if g.expression < 0 || expression < 0 {
					g.expression == expression
				} else {
					x := doc.es.nodes[g.expression]
					y := doc.es.nodes[expression]
					c.sv_equal_tokens(x.start, x.end, y.start, y.end)
				}
				if same {
					found = k
					break
				}
			}
			if found >= 0 {
				groups[found].nodes << a
			} else {
				groups << SnddGroup{
					key:        key
					expression: expression
					nodes:      [a]
				}
			}
		}
		for g in groups {
			if g.nodes.len < 2 {
				continue
			}
			for node in g.nodes {
				other := if g.nodes[0] != node { g.nodes[0] } else { g.nodes[1] }
				findings << c.sv_report_snode(node, 'duplication', {
					data_key: g.key
					'lineNo': c.sv_line(doc.nodes[other].start).str()
				})
			}
		}
	}
	return findings
}

fn (mut c Checker) lint_svelte_no_dupe_on_directives(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	return c.sndd_check('EventHandler', 'type')
}

fn (mut c Checker) lint_svelte_no_dupe_use_directives(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	return c.sndd_check('Action', 'keyText')
}
