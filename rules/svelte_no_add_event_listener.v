module rules

// Port of the `svelte/no-add-event-listener` rule of eslint-plugin-svelte 3.24.1: a call of
// `x.addEventListener(…)` or `addEventListener(…)` is reported, with a suggestion (a description,
// no messageId) that calls `on` of `svelte/events` with the target as first argument (`window` for
// the bare call). Its condition is `{ svelteVersions: ['5'] }`: it lints every file.

const svnael_messages = {
	'unexpected': 'Do not use `addEventListener`. Use the `on` function from `svelte/events` instead.'
}

fn (mut c Checker) lint_svelte_no_add_event_listener(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() && !c.src.contains('addEventListener') {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	t := e.t
	mut findings := []Finding{}
	for i in e.entered() {
		if t.typ(i) != .call_expression {
			continue
		}
		callee := t.node(i, .callee) or { continue }
		mut target := ''
		if t.typ(callee) == .member_expression {
			property := t.node(callee, .property) or { continue }
			if t.typ(property) != .identifier
				|| (t.string_of(property, .name) or { '' }) != 'addEventListener' {
				continue
			}
			target = c.svsc_text(&e, t.node(callee, .object) or { continue })
		} else if t.typ(callee) == .identifier
			&& (t.string_of(callee, .name) or { '' }) == 'addEventListener' {
			target = 'window'
		} else {
			continue
		}
		mut suggestions := []Suggestion{}
		if open_paren := c.svsc_token_after(root, &e, t.nodes[callee].end) {
			has, fix := c.merge_fixes([
				fix_replace_range(t.nodes[callee].start, t.nodes[callee].end, 'on'),
				fix_insert_at(open_paren.end, '${target}, '),
			]) or { false, Fix{} }
			if has {
				suggestions << Suggestion{
					desc: 'Use `on` from `svelte/events` instead'
					fix:  fix
				}
			}
		}
		findings << Finding{
			...c.svsc_report(&e, i, 'unexpected', {})
			suggestions: suggestions
		}
	}
	return findings
}
