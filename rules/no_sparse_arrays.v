module rules

import time
import treesitter { node_start }

// Port of the `no-sparse-arrays` rule of ESLint 10.6.0 (it has no options).

const nsa2_messages = {
	'unexpectedSparseArray': 'Unexpected comma in middle of array.'
}

fn (mut c Checker) lint_no_sparse_arrays(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	tokens := c.source_tokens(root)
	for node in c.nodes_of_kinds(root, ['array'], []) {
		stats.checked++
		elements := es_array_elements(node)
		if !elements.any(it.hole) {
			continue
		}
		// The comma after each element, or after the comma before a hole.
		mut after := node_start(node) + 1
		for i, element in elements {
			if i == elements.len - 1 && !element.hole {
				break
			}
			if !element.hole {
				after = c.es_end(element.node)
			}
			mut comma := tokens.after(after, false) or { break }
			for c.src[comma.start..comma.end] != ',' {
				comma = tokens.after(comma.end, false) or { break }
			}
			after = comma.end
			if element.hole {
				findings << Finding{
					stmt:       c.position_at(comma.start)
					message_id: 'unexpectedSparseArray'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
