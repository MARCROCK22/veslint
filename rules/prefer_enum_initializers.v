module rules

import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `prefer-enum-initializers` rule of typescript-eslint 8.62.0 (it has no options), with
// its three suggestions.

const pei_messages = {
	'defineInitializer':           "The value of the member '{{ name }}' should be explicitly defined."
	'defineInitializerSuggestion': 'Can be fixed to {{ name }} = {{ suggested }}'
}

fn (mut c Checker) lint_prefer_enum_initializers(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kind(root, c'enum_declaration') {
		body := node_field(node, 'body') or { continue }
		// The members, without the comments: `index` is the place of a member among them.
		members := named_children(body).filter(node_kind(it) != 'comment')
		for index, member in members {
			checked++
			if node_kind(member) == 'enum_assignment' {
				continue
			}
			name := c.text(member)
			mut suggestions := []Suggestion{}
			for suggested in [index.str(), (index + 1).str(), "'${name}'"] {
				_, suggestion := c.suggestion('defineInitializerSuggestion', {
					'name':      name
					'suggested': suggested
				}, [fix_replace(member, '${name} = ${suggested}')])!
				suggestions << suggestion
			}
			findings << Finding{
				stmt:        position_of(member)
				message_id:  'defineInitializer'
				data:        {
					'name': name
				}
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
