module estree

// Traversal in the order of ESLint's Traverser (lib/shared/traverser.js) with the visitor keys of
// typescript-eslint: per node, its keys in visitor_keys order; an array is visited in order,
// skipping its holes.

// keys_of are the visitor keys of a node type.
pub fn keys_of(typ NodeType) []Key {
	return visitor_keys[int(typ)]
}

// children are the child nodes of `i` in traversal order.
pub fn (t &EsTree) children(i int) []int {
	mut out := []int{}
	for key in visitor_keys[int(t.nodes[i].typ)] {
		p := t.prop(i, key) or { continue }
		match p.kind {
			.node {
				out << p.idx
			}
			.list {
				for item in t.lists[p.idx] {
					if item >= 0 {
						out << item
					}
				}
			}
			else {}
		}
	}
	return out
}

// Step is one event of a traversal: entering or leaving a node.
pub struct Step {
pub:
	node  int
	leave bool
}

// steps are the enter and leave events of a traversal from the root, in order.
pub fn (t &EsTree) steps() []Step {
	mut out := []Step{cap: t.nodes.len * 2}
	if t.root < 0 {
		return out
	}
	// The stack holds nodes to enter, and the leave events (as -2 - index) to emit after their
	// children.
	mut stack := [t.root]
	for stack.len > 0 {
		top := stack.pop()
		if top < -1 {
			out << Step{-2 - top, true}
			continue
		}
		out << Step{top, false}
		stack << -2 - top
		kids := t.children(top)
		for k := kids.len - 1; k >= 0; k-- {
			stack << kids[k]
		}
	}
	return out
}

// traverse calls `enter` and `leave` with each node and its parent (-1 for the root), in the
// order of ESLint's Traverser.
pub fn (t &EsTree) traverse(enter fn (node int, parent int), leave fn (node int, parent int)) {
	for step in t.steps() {
		parent := t.nodes[step.node].parent
		if step.leave {
			leave(step.node, parent)
		} else {
			enter(step.node, parent)
		}
	}
}
