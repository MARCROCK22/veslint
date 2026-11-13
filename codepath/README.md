# codepath: ESLint's code path analysis on the estree module

A port of `lib/linter/code-path-analysis/` of ESLint 10.6.0 (`code-path-analyzer.js`,
`code-path-state.js`, `code-path.js`, `code-path-segment.js`, `fork-context.js` and
`id-generator.js`), driven the way `SourceCode#traverse` drives it.
`codepath.analyze(&tree)` returns an `Analysis`:

- `events`: every call ESLint makes to rule listeners, in ESLint's order. Each event has a `kind`
  (`enter_node`, `leave_node`, `code_path_start`, `code_path_end`, `segment_start`,
  `segment_end`, `unreachable_segment_start`, `unreachable_segment_end`, `segment_loop`), the
  `node` argument, the `code_path`, the `segment` (`fromSegment` of a loop) and `to_segment`.
- `code_paths` and `segments`: arenas. Code paths and segments are referred to by index.
  `an.code_path_id(cp)` and `an.segment_id(seg)` give ESLint's ids (`s2`, `s2_3`).

ESLint computes all the events of a file before it runs any rule, so a listener always sees the
final state of segments and code paths. The arenas hold that final state, so a rule reads them
directly from any event.

| ESLint | here |
| --- | --- |
| `codePath.id`, `origin`, `upper`, `childCodePaths` | `an.code_path_id(cp)`, `.origin` (`.str()` gives `class-field-initializer`…), `.upper` (-1 for none), `.child_code_paths` |
| `initialSegment`, `finalSegments`, `returnedSegments`, `thrownSegments` | fields of `an.code_paths[cp]` with the same names |
| `segment.reachable`, `nextSegments`, `prevSegments`, `allNextSegments`, `allPrevSegments` | fields of `an.segments[seg]` |
| `segment.internal.used`, `internal.loopedPrevSegments` | `.used`, `.looped_prev_segments` |
| `segment.isLoopedPrevSegment(prev)` | `an.is_looped_prev_segment(seg, prev)` |
| `isAnySegmentReachable(segments)` (code-path-utils) | `an.is_any_reachable(segments)` |
| `codePath.traverseSegments(options, (segment, controller) => …)` | `an.traverse_segments(cp, TraverseOptions{first, last}, fn (seg int, mut w SegmentWalker))`, or the iterator `mut w := an.walk_segments(cp, opts)` with `w.next()`, `w.skip()` and `w.stop()` (`controller.break()`) |

`CodePath#currentSegments` is gone since ESLint 9. Rules track the current segments themselves:
a set per code path, filled on `onCodePathSegmentStart` and `onUnreachableCodePathSegmentStart`,
and emptied on the matching end events. You can port that bookkeeping line by line, as the
example below does. `codepath.Tracker` also does it: call `tr.apply(ev)` before you handle each
event, then read `tr.current()`.

## Porting a rule

A rule's `create()` turns into one loop over `an.events` with a `match` on the kind. Each
listener of the original becomes one branch. Node selectors become `enter_node` and `leave_node`
branches that test `t.typ(ev.node)`. The rule's own state (often a `funcInfo` stack) is a V
array that you push on `code_path_start` and pop on `code_path_end`.

`cmd/getter_return_check/getter_return.v` is getter-return ported this way, with the parts of
ast-utils it needs (getStaticPropertyName, isSpecificMemberAccess, getFunctionNameWithKind and
getFunctionHeadLoc on byte offsets):

```v
for ev in an.events {
	top := stack.len - 1
	match ev.kind {
		.code_path_start { stack << FuncInfo{code_path: ev.code_path, should_check: is_getter(t, ev.node), node: ev.node} }
		.code_path_end { stack.delete_last() }
		.segment_start, .unreachable_segment_start { stack[top].current_segments << ev.segment }
		.segment_end, .unreachable_segment_end { /* remove ev.segment */ }
		.enter_node { if t.typ(ev.node) == .return_statement { /* ReturnStatement(node) */ } }
		.leave_node {
			if t.typ(ev.node) in [.function_expression, .arrow_function_expression] {
				// checkLastSegment
				if stack[top].should_check && an.is_any_reachable(stack[top].current_segments) { … }
			}
		}
		else {}
	}
}
```

When several rules run on the same file, run `analyze` once and give each rule the same
`Analysis`.
