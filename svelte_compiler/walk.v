module svelte_compiler

// zimmerframe's walk visits every property of a node whose value is a node or an array of nodes,
// in the order of the object's keys (the order acorn and the Svelte parser create them in).
// child_keys gives that order per node type; children the child nodes in it.

fn child_keys(typ string) []Key {
	return match typ {
		// ESTree (acorn's key order)
		'Program', 'BlockStatement', 'StaticBlock', 'ClassBody' { [Key.body] }
		'ExpressionStatement', 'ChainExpression', 'ParenthesizedExpression' { [Key.expression] }
		'WithStatement' { [Key.object, .body] }
		'ReturnStatement', 'ThrowStatement', 'UnaryExpression', 'UpdateExpression', 'SpreadElement',
		'RestElement', 'AwaitExpression', 'YieldExpression' {
			[Key.argument]
		}
		'LabeledStatement' { [Key.body, .label] }
		'BreakStatement', 'ContinueStatement' { [Key.label] }
		'IfStatement', 'ConditionalExpression' { [Key.test, .consequent, .alternate] }
		'SwitchStatement' { [Key.discriminant, .cases] }
		'SwitchCase' { [Key.consequent, .test] }
		'TryStatement' { [Key.block, .handler, .finalizer] }
		'CatchClause' { [Key.param, .body] }
		'WhileStatement' { [Key.test, .body] }
		'DoWhileStatement' { [Key.body, .test] }
		'ForStatement' { [Key.init, .test, .update, .body] }
		'ForInStatement', 'ForOfStatement' { [Key.left, .right, .body] }
		'FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression' {
			[Key.id, .params, .body]
		}
		'VariableDeclaration' { [Key.declarations] }
		'VariableDeclarator' { [Key.id, .init] }
		'ClassDeclaration', 'ClassExpression' { [Key.id, .super_class, .body] }
		'MethodDefinition', 'PropertyDefinition', 'Property' { [Key.key, .value] }
		'ArrayExpression', 'ArrayPattern' { [Key.elements] }
		'ObjectExpression', 'ObjectPattern' { [Key.properties] }
		'BinaryExpression', 'LogicalExpression', 'AssignmentExpression', 'AssignmentPattern' {
			[Key.left, .right]
		}
		'CallExpression', 'NewExpression' { [Key.callee, .arguments] }
		'MemberExpression' { [Key.object, .property] }
		'SequenceExpression' { [Key.expressions] }
		'TemplateLiteral' { [Key.expressions, .quasis] }
		'TaggedTemplateExpression' { [Key.tag, .quasi] }
		'ImportExpression' { [Key.source, .options] }
		'MetaProperty' { [Key.meta, .property] }
		'ImportDeclaration' { [Key.specifiers, .source] }
		'ImportSpecifier' { [Key.imported, .local] }
		'ImportDefaultSpecifier', 'ImportNamespaceSpecifier' { [Key.local] }
		'ExportNamedDeclaration' { [Key.declaration, .specifiers, .source] }
		'ExportSpecifier' { [Key.local, .exported] }
		'ExportDefaultDeclaration' { [Key.declaration] }
		'ExportAllDeclaration' { [Key.exported, .source] }
		// template (the Svelte parser's key order)
		'Fragment' { [Key.nodes] }
		'RegularElement', 'Component', 'SlotElement', 'TitleElement', 'SvelteHead', 'SvelteWindow',
		'SvelteDocument', 'SvelteBody', 'SvelteSelf', 'SvelteFragment', 'SvelteBoundary',
		'SvelteOptions' {
			[Key.attributes, .fragment]
		}
		'SvelteElement' { [Key.attributes, .fragment, .tag] }
		'SvelteComponent' { [Key.attributes, .fragment, .expression] }
		'Attribute', 'StyleDirective' { [Key.value] }
		'ExpressionTag', 'HtmlTag', 'RenderTag', 'AttachTag', 'SpreadAttribute', 'BindDirective',
		'OnDirective', 'ClassDirective', 'TransitionDirective', 'AnimateDirective', 'UseDirective',
		'LetDirective' {
			[Key.expression]
		}
		'DebugTag' { [Key.identifiers] }
		'ConstTag', 'DeclarationTag' { [Key.declaration] }
		'IfBlock' { [Key.test, .consequent, .alternate] }
		'EachBlock' { [Key.expression, .body, .context, .key, .fallback] }
		'AwaitBlock' { [Key.expression, .value, .error, .pending, .then, .catch_] }
		'KeyBlock' { [Key.expression, .fragment] }
		'SnippetBlock' { [Key.expression, .parameters, .body] }
		// CSS
		'StyleSheet' { [Key.attributes, .children] }
		'Rule' { [Key.prelude, .block] }
		'Atrule' { [Key.block] }
		'Block', 'SelectorList', 'ComplexSelector' { [Key.children] }
		'RelativeSelector' { [Key.combinator, .selectors] }
		'PseudoClassSelector' { [Key.args] }
		else { []Key{} }
	}
}

// children are the child nodes of `i` in the order zimmerframe visits them.
pub fn (t &Tree) children(i int) []int {
	mut out := []int{}
	for k in child_keys(t.nodes[i].typ) {
		p := t.prop(i, k) or { continue }
		if p.kind == .node && p.idx >= 0 {
			out << p.idx
		} else if p.kind == .list {
			for item in p.list {
				if item >= 0 {
					out << item
				}
			}
		}
	}
	return out
}

// ---------------------------------------------------------------------------------------------
// Comments (acorn.js get_comment_handlers' add_comments): a comment before a node becomes one of
// its leadingComments; one after it, on its line up to `,` or `)`, its trailingComments.

fn (mut b Builder) attach_comments(root int, start int, end int, is_program bool) {
	// The comments acorn has collected when the code is parsed: for a <script>, every comment
	// of the file before its end (the template expressions before it included: they share
	// root.comments); for a template expression, its own and those up to the next token.
	src := b.c.src
	mut comments := []int{}
	if is_program {
		for k, cm in b.c.t.comments {
			if cm.start < end {
				comments << k
			}
		}
	} else {
		mut stop := end
		for k, cm in b.c.t.comments {
			if cm.start >= start && cm.start < stop {
				comments << k
				continue
			}
			if cm.start >= stop {
				// Only white space between: acorn's lookahead reads it.
				mut ws := true
				for j in stop .. cm.start {
					if src[j] !in [` `, `\t`, `\n`, `\r`] {
						ws = false
						break
					}
				}
				if !ws {
					break
				}
				comments << k
				stop = cm.end
			}
		}
	}
	if comments.len == 0 {
		return
	}
	mut path := []int{}
	b.comment_walk(root, mut path, mut comments)
	if comments.len > 0 && (b.c.t.comments[comments[0]].start >= b.c.t.nodes[root].end
		|| is_program) {
		b.c.t.nodes[root].trailing << comments
		comments.clear()
	}
}

fn (mut b Builder) comment_walk(n int, mut path []int, mut comments []int) {
	if b.c.t.nodes[n].start == no_pos {
		// b.empty and other made-up nodes: acorn never saw them.
		return
	}
	// acorn's Program starts at 0: comments before the script go to its first statement.
	for b.c.t.nodes[n].typ != 'Program' && comments.len > 0
		&& b.c.t.comments[comments[0]].start < b.c.t.nodes[n].start {
		b.c.t.nodes[n].leading << comments[0]
		comments.delete(0)
	}
	path << n
	for ch in b.c.t.children(n) {
		b.comment_walk(ch, mut path, mut comments)
	}
	path.pop()
	if comments.len == 0 {
		return
	}
	parent := if path.len > 0 { path.last() } else { -1 }
	node_end := b.c.t.nodes[n].end
	if parent >= 0 && node_end == b.c.t.nodes[parent].end {
		return
	}
	first := b.c.t.comments[comments[0]]
	ptyp := b.c.t.typ(parent)
	mut is_last := false
	if ptyp in ['BlockStatement', 'Program'] {
		body := b.c.t.list(parent, .body)
		is_last = body.len > 0 && body.last() == n
	} else if ptyp == 'ArrayExpression' {
		els := b.c.t.list(parent, .elements)
		is_last = els.len > 0 && els.last() == n
	} else if ptyp == 'ObjectExpression' {
		props := b.c.t.list(parent, .properties)
		is_last = props.len > 0 && props.last() == n
	}
	if is_last {
		for comments.len > 0 {
			cm := b.c.t.comments[comments[0]]
			if parent >= 0 && cm.start >= b.c.t.nodes[parent].end {
				break
			}
			b.c.t.nodes[n].trailing << comments[0]
			comments.delete(0)
		}
	} else if node_end <= first.start {
		src := b.c.src
		mut ok := true
		for j in node_end .. first.start {
			if src[j] !in [`,`, `)`, ` `, `\t`] {
				ok = false
				break
			}
		}
		if ok {
			b.c.t.nodes[n].trailing = [comments[0]]
			comments.delete(0)
		}
	}
}
