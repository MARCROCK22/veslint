module rules

import codepath
import estree
import time
import treesitter { node_end, node_start }

// Port of the `promise/no-multiple-resolved` rule of eslint-plugin-promise 7.3.0 (it has no
// options), on the code path events of the codepath module.

const prm_no_multiple_resolved_messages = {
	'alreadyResolved':            'Promise should not be resolved multiple times. Promise is already resolved on line {{line}}.'
	'potentiallyAlreadyResolved': 'Promise should not be resolved multiple times. Promise is potentially resolved on line {{line}}.'
}

// PrmSegmentInfo is a CodePathSegmentInfo: `resolved` and `potentially` are the callee (an
// identifier node) of the call that resolved the promise on the segment, -1 for null.
struct PrmSegmentInfo {
	segment int
mut:
	resolved    int = -1
	potentially int = -1
}

// PrmPathInfo is a CodePathInfo: the infos of its segments in the order they were made (a Map),
// how many times one was resolved (resolvedCount) and the current segments (a Set).
struct PrmPathInfo {
mut:
	infos            []PrmSegmentInfo
	index_of         map[int]int
	resolved_count   int
	current_segments []int
}

// PrmResolvedData is AlreadyResolvedData (null when not `found`): the callee that resolved the
// promise before, and whether it is `certain`.
struct PrmResolvedData {
	found    bool
	resolved int
	certain  bool
}

struct PrmMultipleResolved {
	an &codepath.Analysis
mut:
	// resolved_try_segments: PromiseCodePathContext's resolvedSegmentIds.
	resolved_try_segments []int
}

fn (mut p PrmPathInfo) set_resolved(k int, identifier int) {
	p.infos[k].resolved = identifier
	p.resolved_count++
}

// segment_info ports getCurrentSegmentInfos for one segment: its info, made on first use.
fn (mut p PrmPathInfo) segment_info(segment int) int {
	if k := p.index_of[segment] {
		return k
	}
	p.infos << PrmSegmentInfo{
		segment: segment
	}
	p.index_of[segment] = p.infos.len - 1
	return p.infos.len - 1
}

// already_resolved_data ports _getAlreadyResolvedData; `with_context` is false when the rule calls
// it without its PromiseCodePathContext, and reading it then is the TypeError the rule throws (an
// error here: ESLint stops linting the file).
fn (mut m PrmMultipleResolved) already_resolved_data(mut p PrmPathInfo, segment int, with_context bool) !PrmResolvedData {
	all_prev := m.an.segments[segment].prev_segments
	if all_prev.len > 0 && !with_context {
		return error('promise/no-multiple-resolved throws')
	}
	prev_segments := all_prev.filter(it !in m.resolved_try_segments)
	if prev_segments.len == 0 {
		return PrmResolvedData{}
	}
	mut prev_infos := []int{}
	for prev in prev_segments {
		prev_infos << m.processed_segment_info(mut p, prev, with_context)!
	}
	if prev_infos.all(p.infos[it].resolved >= 0) {
		return PrmResolvedData{
			found:    true
			resolved: p.infos[prev_infos[0]].resolved
			certain:  true
		}
	}
	for k in prev_infos {
		info := p.infos[k]
		if info.resolved >= 0 {
			return PrmResolvedData{
				found:    true
				resolved: info.resolved
			}
		}
		if info.potentially >= 0 {
			mut potential := false
			nexts := m.an.segments[info.segment].next_segments
			if nexts.len == 1 {
				potential = true
			} else if own := p.index_of[segment] {
				resolved := p.infos[own].resolved
				if resolved >= 0 {
					potential = true
					for next in nexts {
						n := p.index_of[next] or {
							potential = false
							break
						}
						if p.infos[n].resolved != resolved {
							potential = false
							break
						}
					}
				}
			}
			if potential {
				return PrmResolvedData{
					found:    true
					resolved: info.potentially
				}
			}
		}
	}
	if same_route := m.same_route_path_segment(segment) {
		k := m.processed_segment_info(mut p, same_route, false)!
		if p.infos[k].potentially >= 0 {
			return PrmResolvedData{
				found:    true
				resolved: p.infos[k].potentially
			}
		}
	}
	return PrmResolvedData{}
}

// processed_segment_info ports _getProcessedSegmentInfo.
fn (mut m PrmMultipleResolved) processed_segment_info(mut p PrmPathInfo, segment int, with_context bool) !int {
	if k := p.index_of[segment] {
		return k
	}
	k := p.segment_info(segment)
	data := m.already_resolved_data(mut p, segment, with_context)!
	if data.found {
		if data.certain {
			p.set_resolved(k, data.resolved)
		} else {
			p.infos[k].potentially = data.resolved
		}
	}
	return k
}

// prev_routes ports iterateAllPrevPathSegments: every route back from the segment to a segment
// without previous segments, the closest segment first.
fn (m &PrmMultipleResolved) prev_routes(segment int, processed []int, mut out [][]int) {
	if segment in processed {
		return
	}
	mut next_processed := [segment]
	next_processed << processed
	for prev in m.an.segments[segment].prev_segments {
		if m.an.segments[prev].prev_segments.len == 0 {
			out << [prev]
		} else {
			mut routes := [][]int{}
			m.prev_routes(prev, next_processed, mut routes)
			for route in routes {
				mut full := [prev]
				full << route
				out << full
			}
		}
	}
}

// has_route_without tells whether one of the routes iterateAllNextPathSegments gives from the
// segment does not go through `target` (`has` is whether the route so far does).
fn (m &PrmMultipleResolved) has_route_without(segment int, processed []int, target int, has bool) bool {
	if segment in processed {
		return false
	}
	mut next_processed := [segment]
	next_processed << processed
	for next in m.an.segments[segment].next_segments {
		with_target := has || next == target
		if m.an.segments[next].next_segments.len == 0 {
			if !with_target {
				return true
			}
		} else if m.has_route_without(next, next_processed, target, with_target) {
			return true
		}
	}
	return false
}

// same_route_path_segment ports findSameRoutePathSegment: the segment every route to the segment
// goes through and from which every route goes through it.
fn (m &PrmMultipleResolved) same_route_path_segment(segment int) ?int {
	mut routes := [][]int{}
	m.prev_routes(segment, [], mut routes)
	mut route_segments := []int{}
	for route in routes {
		if route_segments.len == 0 {
			for s in route {
				if s !in route_segments {
					route_segments << s
				}
			}
			continue
		}
		route_segments = route_segments.filter(it in route)
	}
	for route_segment in route_segments {
		if !m.has_route_without(route_segment, [], segment, false) {
			return route_segment
		}
	}
	return none
}

fn (mut c Checker) lint_promise_no_multiple_resolved(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	mut m := PrmMultipleResolved{
		an: an
	}
	mut reported := map[int]bool{}
	mut path_stack := []PrmPathInfo{}
	// resolverReferencesStack: the references of the resolvers of each executor around, by the
	// range of their identifier (the closest executor last; the bottom set is empty).
	mut resolver_stack := [map[u64]bool{}]
	mut last_throwable := -1
	for ev in an.events {
		match ev.kind {
			.enter_node, .leave_node {
				node := ev.node
				typ := t.typ(node)
				if typ in [.function_expression, .arrow_function_expression]
					&& prm_is_promise_constructor_with_inline_executor(t, t.nodes[node].parent) {
					if ev.kind == .leave_node {
						resolver_stack.delete_last()
						continue
					}
					mut references := map[u64]bool{}
					ts := t.ts_node(node) or { continue }
					scope := tree.get_scope(ts)
					for param in t.list(node, .params) or { []int{} } {
						if t.typ(param) != .identifier {
							continue
						}
						v := tree.own_variable(scope, prm_name(t, param))
						if v < 0 {
							continue
						}
						for r in tree.variables[v].references {
							identifier := tree.references[r].identifier
							references[prm_range_key(node_start(identifier), node_end(identifier))] = true
						}
					}
					resolver_stack << references
					continue
				}
				if ev.kind != .leave_node {
					continue
				}
				if typ in [.call_expression, .member_expression, .new_expression, .import_expression,
					.yield_expression] {
					last_throwable = node
				}
				if typ != .call_expression {
					continue
				}
				// 'CallExpression:exit'
				stats.checked++
				callee := prm_child(t, node, .callee)
				if !prm_is_resolver_reference(t, resolver_stack.last(), callee) {
					continue
				}
				top := path_stack.len - 1
				mut infos := []int{}
				for segment in path_stack[top].current_segments {
					infos << path_stack[top].segment_info(segment)
				}
				for k in infos {
					resolved := path_stack[top].infos[k].resolved
					if resolved >= 0 {
						prm_report_resolved(c, t, mut findings, mut reported, callee, resolved,
							true)
						continue
					}
					path_stack[top].set_resolved(k, callee)
				}
			}
			.code_path_start {
				path_stack << PrmPathInfo{}
			}
			.code_path_end {
				mut info := path_stack.pop()
				if info.resolved_count > 1 {
					// iterateReports: the infos resolved when it starts.
					targets := info.infos.filter(it.resolved >= 0)
					for target in targets {
						data := m.already_resolved_data(mut info, target.segment, true) or {
							return []Finding{}
						}
						if !data.found {
							continue
						}
						prm_report_resolved(c, t, mut findings, mut reported, target.resolved,
							data.resolved, data.certain)
					}
				}
			}
			.segment_start, .unreachable_segment_start {
				top := path_stack.len - 1
				if ev.segment !in path_stack[top].current_segments {
					path_stack[top].current_segments << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				node := ev.node
				if ev.kind == .segment_end && t.typ(node) == .catch_clause && last_throwable >= 0
					&& t.typ(last_throwable) == .call_expression {
					try_statement := t.nodes[node].parent
					if t.typ(try_statement) == .try_statement
						&& t.nodes[try_statement].start <= t.nodes[last_throwable].start
						&& t.nodes[last_throwable].end <= t.nodes[try_statement].end
						&& prm_is_resolver_reference(t, resolver_stack.last(), prm_child(t,
							last_throwable, .callee)) {
						m.resolved_try_segments << ev.segment
					}
				}
				top := path_stack.len - 1
				k := path_stack[top].current_segments.index(ev.segment)
				if k >= 0 {
					path_stack[top].current_segments.delete(k)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn prm_range_key(start int, end int) u64 {
	return (u64(start) << 32) | u64(end)
}

// prm_is_resolver_reference: `resolverReferences.has(node)`, the node is the identifier of a
// reference of a resolver.
fn prm_is_resolver_reference(t &estree.EsTree, references map[u64]bool, node int) bool {
	return node >= 0 && t.typ(node) == .identifier
		&& prm_range_key(t.nodes[node].start, t.nodes[node].end) in references
}

// prm_report_resolved ports report: once per callee, the call it is the callee of, with the line
// of the call that resolved the promise before.
fn prm_report_resolved(c &Checker, t &estree.EsTree, mut findings []Finding, mut reported map[int]bool, node int, resolved int, certain bool) {
	if node in reported {
		return
	}
	reported[node] = true
	line, _ := t.line_column(t.nodes[resolved].start)
	findings << Finding{
		stmt:       c.es_tree_position(t, t.nodes[node].parent)
		message_id: if certain { 'alreadyResolved' } else { 'potentiallyAlreadyResolved' }
		data:       {
			'line': line.str()
		}
	}
}
