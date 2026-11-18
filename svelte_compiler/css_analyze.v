module svelte_compiler

// 2-analyze/css/css-analyze.js, css-warn.js and utils.js.

fn is_keyframes_name(name string) bool {
	mut n := name
	for prefix in ['-webkit-', '-moz-', '-o-', '-ms-'] {
		if n.starts_with(prefix) {
			n = n[prefix.len..]
			break
		}
	}
	return n == 'keyframes'
}

fn (z &Analyzer) sels(rel int) []int {
	return z.t.list(rel, .selectors)
}

// is_global (utils.js): `:global(...)` or `:global` with no scoped pseudo class.
fn (z &Analyzer) css_is_global(rel int) bool {
	sels := z.sels(rel)
	if sels.len == 0 {
		return false
	}
	first := sels[0]
	if z.t.typ(first) != 'PseudoClassSelector' || z.t.name(first) != 'global' {
		return false
	}
	if z.t.get(first, .args) < 0 {
		return true
	}
	for s in sels {
		if !z.is_unscoped_pseudo_class(s) && z.t.typ(s) != 'PseudoElementSelector' {
			return false
		}
	}
	return true
}

fn (z &Analyzer) is_unscoped_pseudo_class(s int) bool {
	t := z.t
	if t.typ(s) != 'PseudoClassSelector' {
		return false
	}
	name := t.name(s)
	args := t.get(s, .args)
	if name != 'has' && name != 'is' && name != 'where' && (name != 'not' || args < 0
		|| t.list(args, .children).all(t.list(it, .children).len == 1)) {
		return true
	}
	if args < 0 {
		return true
	}
	for c in t.list(args, .children) {
		for r in t.list(c, .children) {
			if !z.css_is_global(r) {
				return false
			}
		}
	}
	return true
}

fn (z &Analyzer) is_outer_global(rel int) bool {
	sels := z.sels(rel)
	if sels.len == 0 {
		return false
	}
	first := sels[0]
	if z.t.typ(first) != 'PseudoClassSelector' || z.t.name(first) != 'global' {
		return false
	}
	if z.t.get(first, .args) < 0 {
		return true
	}
	for s in sels {
		if z.t.typ(s) !in ['PseudoClassSelector', 'PseudoElementSelector'] {
			return false
		}
	}
	return true
}

fn (z &Analyzer) is_global_block_selector(s int) bool {
	return z.t.typ(s) == 'PseudoClassSelector' && z.t.name(s) == 'global' && z.t.get(s, .args) < 0
}

// ---------------------------------------------------------------------------------------------

struct CssWalk {
mut:
	path []int
}

fn (mut z Analyzer) analyze_css() ! {
	mut w := CssWalk{}
	z.css_visit(z.c.css, -1, mut w)!
}

fn (mut z Analyzer) css_next(node int, rule int, mut w CssWalk) ! {
	w.path << node
	for ch in z.t.children(node) {
		z.css_visit(ch, rule, mut w)!
	}
	w.path.pop()
}

fn (mut z Analyzer) css_child(node int, child int, rule int, mut w CssWalk) ! {
	w.path << node
	z.css_visit(child, rule, mut w)!
	w.path.pop()
}

fn (z &Analyzer) is_unscoped_path(path []int) bool {
	for n in path {
		if z.t.typ(n) == 'Rule' && !z.css_has_global_sel[n] {
			return false
		}
	}
	return true
}

fn (z &Analyzer) is_in_global_block(path []int) bool {
	for n in path {
		if z.t.typ(n) == 'Rule' && z.css_global_block[n] {
			return true
		}
	}
	return false
}

fn (mut z Analyzer) mark_used_under(node int) {
	if z.t.typ(node) == 'ComplexSelector' {
		z.css_used[node] = true
	}
	for ch in z.t.children(node) {
		z.mark_used_under(ch)
	}
}

fn (mut z Analyzer) css_visit(node int, rule int, mut w CssWalk) ! {
	t := z.t
	match t.typ(node) {
		'Atrule' {
			if is_keyframes_name(t.name(node)) {
				prelude := t.text(node, .prelude)
				if !prelude.starts_with('-global-') && !z.is_in_global_block(w.path) {
					z.css_keyframes << prelude
				}
			}
			z.css_next(node, rule, mut w)!
		}
		'ComplexSelector' {
			z.css_next(node, rule, mut w)!
			children := t.list(node, .children)
			mut global := -1
			for ch in children {
				if z.css_is_global(ch) {
					global = ch
					break
				}
			}
			if global >= 0 {
				first := z.sels(global)[0]
				is_nested := w.path.len >= 2 && t.typ(w.path[w.path.len - 2]) == 'PseudoClassSelector'
				if is_nested && t.get(first, .args) < 0 {
					return z.error_at(first, e_css_global_block_invalid_placement())
				}
				idx := children.index(global)
				if t.get(first, .args) >= 0 && idx != 0 && idx != children.len - 1 {
					for i in idx + 1 .. children.len {
						if !z.css_is_global(children[i]) {
							return z.error_at(first, e_css_global_invalid_placement())
						}
					}
				}
			}
			for rel in children {
				sels := z.sels(rel)
				for i, sel in sels {
					if t.typ(sel) == 'PseudoClassSelector' && t.name(sel) == 'global' {
						args := t.get(sel, .args)
						if args >= 0 {
							c0 := t.list(args, .children)[0]
							r0 := t.list(c0, .children)[0]
							if t.typ(z.sels(r0)[0]) == 'TypeSelector' && i != 0 {
								return z.error_at(sel, e_css_global_invalid_selector_list())
							}
						}
						if i + 1 < sels.len && t.typ(sels[i + 1]) == 'TypeSelector' {
							return z.error_at(sels[i + 1], e_css_type_selector_invalid_placement())
						}
						if args >= 0 && t.list(args, .children).len > 1
							&& (children.len > 1 || sels.len > 1) {
							return z.error_at(sel, e_css_global_invalid_selector())
						}
					}
				}
			}
			z.css_rule[node] = rule
			mut all_global := true
			for ch in children {
				if !z.sel_global[ch] && !z.sel_global_like[ch] {
					all_global = false
					break
				}
			}
			z.cplx_global[node] = all_global
			if all_global {
				z.css_used[node] = true
			}
			parent_rule := if rule >= 0 { z.css_parent[rule] or { -1 } } else { -1 }
			if rule >= 0 && parent_rule >= 0 && children.len > 0 {
				s0 := z.sels(children[0])
				if s0.len > 0 && t.typ(s0[0]) == 'NestingSelector' {
					first := if s0.len > 1 { s0[1] } else { -1 }
					no_nesting_scope := t.typ(first) != 'PseudoClassSelector'
						|| z.is_unscoped_pseudo_class(first)
					mut parent_is_global := false
					for c in t.list(t.get(parent_rule, .prelude), .children) {
						cc := t.list(c, .children)
						if cc.len == 1 && z.sel_global[cc[0]] {
							parent_is_global = true
						}
					}
					if no_nesting_scope && parent_is_global {
						z.css_used[node] = true
					}
				}
			}
		}
		'RelativeSelector' {
			parent := w.path.last()
			comb := t.get(node, .combinator)
			parent_rule := if rule >= 0 { z.css_parent[rule] or { -1 } } else { -1 }
			p3 := if w.path.len >= 3 { w.path[w.path.len - 3] } else { -1 }
			if comb >= 0 && parent_rule < 0 && t.list(parent, .children)[0] == node
				&& t.typ(p3) != 'PseudoClassSelector' {
				return z.error_at(comb, e_css_selector_invalid())
			}
			sels := z.sels(node)
			z.sel_global[node] = sels.len >= 1 && z.css_is_global(node)
			if sels.len >= 1 && sels.all(t.typ(it) in ['PseudoClassSelector', 'PseudoElementSelector']) {
				first := sels[0]
				if (t.typ(first) == 'PseudoClassSelector' && t.name(first) == 'host')
					|| (t.typ(first) == 'PseudoElementSelector' && t.name(first) in [
						'view-transition',
						'view-transition-group',
						'view-transition-old',
						'view-transition-new',
						'view-transition-image-pair',
					]) {
					z.sel_global_like[node] = true
				}
			}
			if sels.any(t.typ(it) == 'PseudoClassSelector' && t.name(it) == 'root')
				&& !sels.any(t.typ(it) == 'PseudoClassSelector' && t.name(it) == 'has') {
				z.sel_global_like[node] = true
			}
			if z.sel_global_like[node] || z.sel_global[node] {
				for ch in sels {
					z.mark_used_under(ch)
				}
			}
			z.css_next(node, rule, mut w)!
		}
		'Rule' {
			z.css_parent[node] = rule
			prelude := t.get(node, .prelude)
			for complex in t.list(prelude, .children) {
				mut is_global_block := false
				cc := t.list(complex, .children)
				for selector_idx, child in cc {
					sels := z.sels(child)
					mut idx := -1
					for k, s in sels {
						if z.is_global_block_selector(s) {
							idx = k
							break
						}
					}
					if is_global_block {
						z.sel_global_like[child] = true
					}
					if idx == 0 {
						if sels.len > 1 && selector_idx == 0 && rule < 0 {
							return z.error_at(sels[1], e_css_global_block_invalid_modifier_start())
						} else {
							z.css_global_block[node] = true
							is_global_block = true
							for i in 1 .. sels.len {
								z.mark_used_shallow(sels[i])
							}
							comb := t.get(child, .combinator)
							if comb >= 0 && t.name(comb) != ' ' {
								return z.error_at(child, e_css_global_block_invalid_combinator(t.name(comb)))
							}
							mut declaration := -1
							for b in t.list(t.get(node, .block), .children) {
								if t.typ(b) == 'Declaration' {
									declaration = b
									break
								}
							}
							is_lone_global := cc.len == 1 && z.sels(cc[0]).len == 1
							if is_lone_global && t.list(prelude, .children).len > 1 {
								return z.error_at(prelude, e_css_global_block_invalid_list())
							}
							if declaration >= 0 && t.list(prelude, .children).len == 1
								&& is_lone_global {
								return z.error_at(declaration, e_css_global_block_invalid_declaration())
							}
						}
					} else if idx != -1 {
						return z.error_at(sels[idx], e_css_global_block_invalid_modifier())
					}
				}
				if z.css_global_block[node] && !is_global_block {
					return z.error_at(prelude, e_css_global_block_invalid_list())
				}
			}
			z.css_child(node, prelude, node, mut w)!
			for sel in t.list(prelude, .children) {
				if z.cplx_global[sel] {
					z.css_has_global_sel[node] = true
				} else {
					z.css_has_local_sel[node] = true
				}
			}
			z.css_child(node, t.get(node, .block), node, mut w)!
		}
		'NestingSelector' {
			parent_rule := z.css_parent[rule] or { -1 }
			if parent_rule < 0 {
				children := t.list(t.get(rule, .prelude), .children)
				sels := z.sels(t.list(children[0], .children)[0])
				mut ok := children.len <= 1 && sels.len <= 1 && t.typ(sels[0]) == 'PseudoClassSelector'
					&& t.name(sels[0]) == 'global'
				if ok {
					args := t.get(sels[0], .args)
					ok = false
					if args >= 0 {
						c0 := t.list(args, .children)
						if c0.len > 0 {
							r0 := t.list(c0[0], .children)
							ok = r0.len > 0 && z.sels(r0[0]).len > 0 && z.sels(r0[0])[0] == node
						}
					}
				}
				if !ok {
					return z.error_at(node, e_css_nesting_selector_invalid_placement())
				}
			} else if z.css_global_block[parent_rule] && (z.css_parent[parent_rule] or { -1 }) < 0 {
				pc := t.list(t.get(parent_rule, .prelude), .children)
				if t.list(pc[0], .children).len == 1 && z.sels(t.list(pc[0], .children)[0]).len == 1 {
					return z.error_at(node, e_css_global_block_invalid_modifier_start())
				}
			}
			z.css_next(node, rule, mut w)!
		}
		else {
			z.css_next(node, rule, mut w)!
		}
	}
}

// mark_used_shallow: walk(..., { ComplexSelector(node) { used = true } }) without next(): only
// the outermost ComplexSelectors under `node`.
fn (mut z Analyzer) mark_used_shallow(node int) {
	if z.t.typ(node) == 'ComplexSelector' {
		z.css_used[node] = true
		return
	}
	for ch in z.t.children(node) {
		z.mark_used_shallow(ch)
	}
}

// ---------------------------------------------------------------------------------------------
// css-warn.js

fn (mut z Analyzer) warn_unused() {
	mut path := []int{}
	z.warn_unused_visit(z.c.css, mut path)
}

fn (mut z Analyzer) warn_unused_visit(node int, mut path []int) {
	t := z.t
	match t.typ(node) {
		'Atrule' {
			if is_keyframes_name(t.name(node)) {
				return
			}
		}
		'PseudoClassSelector' {
			if t.name(node) != 'is' && t.name(node) != 'where' {
				return
			}
		}
		'ComplexSelector' {
			p2 := if path.len >= 2 { path[path.len - 2] } else { -1 }
			p4 := if path.len >= 4 { path[path.len - 4] } else { -1 }
			if !z.css_used[node] && (t.typ(p2) != 'PseudoClassSelector' || z.css_used[p4]) {
				start := t.nodes[node].start
				end := t.nodes[node].end
				z.warn(node, w_css_unused_selector(z.c.src[start..end]))
			}
		}
		'Rule' {
			if z.css_global_block[node] {
				path << node
				z.warn_unused_visit(t.get(node, .prelude), mut path)
				path.pop()
				return
			}
		}
		else {}
	}
	path << node
	for ch in t.children(node) {
		z.warn_unused_visit(ch, mut path)
	}
	path.pop()
}
