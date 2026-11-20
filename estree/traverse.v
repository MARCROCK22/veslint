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

// push_children_reversed pushes the children of `i` (what children gives) in reverse order, without
// the array children makes: steps does it for every node of the file.
fn (t &EsTree) push_children_reversed(i int, mut stack []int) {
	keys := visitor_keys[int(t.nodes[i].typ)]
	for k := keys.len - 1; k >= 0; k-- {
		p := t.prop(i, keys[k]) or { continue }
		match p.kind {
			.node {
				stack << p.idx
			}
			.list {
				items := t.lists[p.idx]
				for j := items.len - 1; j >= 0; j-- {
					if items[j] >= 0 {
						stack << items[j]
					}
				}
			}
			else {}
		}
	}
}

// Step is one event of a traversal: entering or leaving a node.
pub struct Step {
pub:
	node  int
	leave bool
}

// steps are the enter and leave events of a traversal from the root, in order (of the nodes it
// visits: see EsTree.visit).
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
			if t.visits(-2 - top) {
				out << Step{-2 - top, true}
			}
			continue
		}
		if t.visits(top) {
			out << Step{top, false}
		}
		stack << -2 - top
		t.push_children_reversed(top, mut stack)
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
