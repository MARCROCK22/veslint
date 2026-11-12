module rules

import time
import treesitter { node_end, position_of }

// Port of the `no-non-null-asserted-optional-chain` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestion.

const nnnaoc_messages = {
	'noNonNullOptionalChain': 'Optional chain expressions can return undefined by design - using a non-null assertion is unsafe and wrong.'
	'suggestRemovingNonNull': 'You should remove the non-null assertion.'
}

fn (mut c Checker) lint_no_non_null_asserted_optional_chain(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut assertions := 0
	for node in c.nodes_of_kind(root, c'non_null_expression') {
		assertions++
		// The suggestion removes the `!` of the assertion.
		_, suggestion := c.suggestion('suggestRemovingNonNull', map[string]string{}, [
			fix_remove_range(node_end(node) - 1, node_end(node)),
		])!
		// `x?.y!`: the `!` ends the chain (ChainExpression > TSNonNullExpression), the node
		// reported.
		if is_estree_chain_root(node) {
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'noNonNullOptionalChain'
				suggestions: [suggestion]
			}
			continue
		}
		// `(x?.y)!`: the `!` of a chain in parentheses (TSNonNullExpression > ChainExpression), the
		// chain reported.
		child := first_named(node) or { continue }
		inner := unwrap_parens(child)
		if node_key(inner) != node_key(child) && is_chain_element(inner)
			&& is_estree_chain_root(inner) {
			findings << Finding{
				stmt:        position_of(inner)
				message_id:  'noNonNullOptionalChain'
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += assertions
	return findings
}
