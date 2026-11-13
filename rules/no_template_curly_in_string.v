module rules

import time
import treesitter { position_of }

// Port of the `no-template-curly-in-string` rule of ESLint 10.6.0 (it has no options).

const ntcis_messages = {
	'unexpectedTemplateExpression': 'Unexpected template string expression.'
}

fn (mut c Checker) lint_no_template_curly_in_string(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string'], []) {
		stats.checked++
		value := c.literal_name(node) or { continue }
		// /\$\{[^}]+\}/: `${`, something that is not `}`, and `}`.
		mut found := false
		mut from := 0
		for {
			at := value.index_after('\${', from) or { break }
			end := value.index_after('}', at + 2) or { break }
			if end > at + 2 {
				found = true
				break
			}
			from = at + 1
		}
		if found {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpectedTemplateExpression'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
