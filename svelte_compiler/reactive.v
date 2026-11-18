module svelte_compiler

// order_reactive_statements (2-analyze/index.js) as far as it can fail: a cycle between `$:`
// statements (utils/check_graph_for_cycles.js).

fn (mut z Analyzer) order_reactive_statements() ! {
	mut edges := [][]string{}
	for rs in z.reactive_statements {
		for a in rs.assignments {
			for d in rs.dependencies {
				if d !in rs.assignments {
					edges << [z.t.name(z.s.bindings[a].node), z.t.name(z.s.bindings[d].node)]
				}
			}
		}
	}
	cycle := check_graph_for_cycles(edges)
	if cycle.len == 0 {
		return
	}
	for k, rs in z.reactive_statements {
		for a in rs.assignments {
			if z.t.name(z.s.bindings[a].node) == cycle[0] {
				return z.error_at(z.reactive_nodes[k], e_reactive_declaration_cycle(cycle.join(' → ')))
			}
		}
	}
}

fn check_graph_for_cycles(edges [][]string) []string {
	mut order := []string{}
	mut graph := map[string][]string{}
	for e in edges {
		for v in e {
			if v !in graph {
				graph[v] = []string{}
				order << v
			}
		}
		graph[e[0]] << e[1]
	}
	mut visited := map[string]bool{}
	mut on_stack := []string{}
	mut cycles := [][]string{}
	for v in order {
		if v !in visited {
			cycle_visit(v, graph, mut visited, mut on_stack, mut cycles)
		}
	}
	return if cycles.len > 0 { cycles[0] } else { []string{} }
}

fn cycle_visit(v string, graph map[string][]string, mut visited map[string]bool, mut on_stack []string, mut cycles [][]string) {
	visited[v] = true
	on_stack << v
	for w in graph[v] or { []string{} } {
		if w !in visited {
			cycle_visit(w, graph, mut visited, mut on_stack, mut cycles)
		} else if w in on_stack {
			mut c := on_stack.clone()
			c << w
			cycles << c
		}
	}
	on_stack.delete(on_stack.index(v))
}
