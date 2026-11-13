module regexpp

// GroupSpecifiersAsES2018 and GroupSpecifiersAsES2025 (with BranchID) in one type: `es2025` picks the behaviour.

struct BranchId {
	parent int
	base   int
}

struct GroupSpecifiers {
	es2025 bool
mut:
	branches   []BranchId
	branch_id  int
	group_name map[string][]int
}

fn new_group_specifiers(es2025 bool) GroupSpecifiers {
	mut g := GroupSpecifiers{
		es2025: es2025
	}
	g.clear()
	return g
}

fn (mut g GroupSpecifiers) new_branch(parent int, base int) int {
	id := g.branches.len
	g.branches << BranchId{
		parent: parent
		base:   if base < 0 { id } else { base }
	}
	return id
}

fn (mut g GroupSpecifiers) clear() {
	g.branches = []BranchId{}
	g.group_name = map[string][]int{}
	g.branch_id = g.new_branch(-1, -1)
}

fn (g &GroupSpecifiers) is_empty() bool {
	return g.group_name.len == 0
}

fn (mut g GroupSpecifiers) enter_disjunction() {
	if g.es2025 {
		g.branch_id = g.new_branch(g.branch_id, -1)
	}
}

fn (mut g GroupSpecifiers) enter_alternative(index int) {
	if g.es2025 && index != 0 {
		b := g.branches[g.branch_id]
		g.branch_id = g.new_branch(b.parent, b.base)
	}
}

fn (mut g GroupSpecifiers) leave_disjunction() {
	if g.es2025 {
		g.branch_id = g.branches[g.branch_id].parent
	}
}

fn (g &GroupSpecifiers) has_in_pattern(name string) bool {
	return name in g.group_name
}

fn (g &GroupSpecifiers) separated_from(a int, other int) bool {
	ba := g.branches[a]
	bo := g.branches[other]
	if ba.base == bo.base && a != other {
		return true
	}
	if bo.parent >= 0 && g.separated_from(a, bo.parent) {
		return true
	}
	if ba.parent >= 0 {
		return g.separated_from(ba.parent, other)
	}
	return false
}

fn (g &GroupSpecifiers) has_in_scope(name string) bool {
	if !g.es2025 {
		return g.has_in_pattern(name)
	}
	branches := g.group_name[name] or { return false }
	for branch in branches {
		if !g.separated_from(branch, g.branch_id) {
			return true
		}
	}
	return false
}

fn (mut g GroupSpecifiers) add_to_scope(name string) {
	if name in g.group_name {
		g.group_name[name] << g.branch_id
		return
	}
	g.group_name[name] = [g.branch_id]
}
