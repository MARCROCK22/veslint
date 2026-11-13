module codepath

import estree

// code-path-state.js: the contexts and the CodePathState of a code path.

@[heap]
struct BreakContext {
	upper     &BreakContext = unsafe { nil }
	breakable bool
	label     string // '' for none
mut:
	broken &ForkContext = unsafe { nil }
}

@[heap]
struct ChainContext {
	upper &ChainContext = unsafe { nil }
mut:
	choice_context_count int
}

@[heap]
struct ChoiceContext {
	upper                &ChoiceContext = unsafe { nil }
	kind                 string // `&&`, `||`, `??`, `test` or `loop`
	is_forking_as_result bool
mut:
	true_fork    &ForkContext = unsafe { nil }
	false_fork   &ForkContext = unsafe { nil }
	nullish_fork &ForkContext = unsafe { nil }
	processed    bool
}

// LoopContext holds the fields of every kind of loop context; `typ` says which.
@[heap]
struct LoopContext {
	upper &LoopContext = unsafe { nil }
	typ   estree.NodeType
	label string
mut:
	broken &ForkContext = unsafe { nil } // the brokenForkContext of its BreakContext
	// `test !== true` is the only use of `test`.
	test_is_true bool
	// DoWhileStatement.
	entry_segments []int
	continue_fork  &ForkContext = unsafe { nil }
	// While, For, ForIn and ForOf statements (null: none).
	continue_dest ?[]int
	// ForStatement.
	end_of_init     ?[]int
	test_segments   ?[]int
	end_of_test     ?[]int
	update_segments ?[]int
	end_of_update   ?[]int
	// ForIn and ForOf statements.
	prev_segments []int
	left_segments []int
	end_of_left   []int
}

@[heap]
struct SwitchContext {
	upper    &SwitchContext = unsafe { nil }
	has_case bool
mut:
	default_segments      []int
	default_body_segments ?[]int
	found_empty_default   bool
	last_is_default       bool
	fork_count            int
}

enum TryPosition {
	try_
	catch_
	finally_
}

@[heap]
struct TryContext {
	upper         &TryContext = unsafe { nil }
	has_finalizer bool
mut:
	position                   TryPosition
	returned_fork              &ForkContext = unsafe { nil }
	thrown_fork                &ForkContext = unsafe { nil }
	last_of_try_is_reachable   bool
	last_of_catch_is_reachable bool
}

// State is the CodePathState of a code path. Its returned, thrown and final segments are kept
// in the CodePath.
@[heap]
struct State {
	cp int
mut:
	fork             &ForkContext   = unsafe { nil }
	choice           &ChoiceContext = unsafe { nil }
	switch_ctx       &SwitchContext = unsafe { nil }
	try_ctx          &TryContext    = unsafe { nil }
	loop             &LoopContext   = unsafe { nil }
	brk              &BreakContext  = unsafe { nil }
	chain            &ChainContext  = unsafe { nil }
	current_segments []int
}

fn (mut a Analyzer) st() &State {
	return a.states[a.cp]
}

// add_to_returned_or_thrown is addToReturnedOrThrown: the `add` of the returned and thrown
// segment lists of the code path.
fn (mut a Analyzer) add_returned_of_code_path(cp int, segs []int) {
	for s in segs {
		a.an.code_paths[cp].returned_segments << s
		if s !in a.an.code_paths[cp].thrown_segments {
			a.an.code_paths[cp].final_segments << s
		}
	}
}

fn (mut a Analyzer) add_thrown_of_code_path(cp int, segs []int) {
	for s in segs {
		a.an.code_paths[cp].thrown_segments << s
		if s !in a.an.code_paths[cp].returned_segments {
			a.an.code_paths[cp].final_segments << s
		}
	}
}

// get_continue_context is getContinueContext.
fn (s &State) get_continue_context(label string) &LoopContext {
	if label == '' {
		return s.loop
	}
	mut c := s.loop
	for !isnil(c) {
		if c.label == label {
			return c
		}
		c = c.upper
	}
	return unsafe { nil }
}

// get_break_context is getBreakContext.
fn (s &State) get_break_context(label string) &BreakContext {
	mut c := s.brk
	for !isnil(c) {
		if (label != '' && c.label == label) || (label == '' && c.breakable) {
			return c
		}
		c = c.upper
	}
	return unsafe { nil }
}

// get_return_context is getReturnContext; nil stands for the state itself.
fn (s &State) get_return_context() &TryContext {
	mut c := s.try_ctx
	for !isnil(c) {
		if c.has_finalizer && c.position != .finally_ {
			return c
		}
		c = c.upper
	}
	return unsafe { nil }
}

// get_throw_context is getThrowContext; nil stands for the state itself.
fn (s &State) get_throw_context() &TryContext {
	mut c := s.try_ctx
	for !isnil(c) {
		if c.position == .try_ || (c.has_finalizer && c.position == .catch_) {
			return c
		}
		c = c.upper
	}
	return unsafe { nil }
}

// add_returned is `getReturnContext(state).returnedForkContext.add(segs)`.
fn (mut a Analyzer) add_returned(segs []int) {
	st := a.st()
	mut c := st.get_return_context()
	if isnil(c) {
		a.add_returned_of_code_path(st.cp, segs)
	} else {
		a.fork_add(mut c.returned_fork, segs)
	}
}

// add_thrown is `getThrowContext(state).thrownForkContext.add(segs)`.
fn (mut a Analyzer) add_thrown(segs []int) {
	st := a.st()
	mut c := st.get_throw_context()
	if isnil(c) {
		a.add_thrown_of_code_path(st.cp, segs)
	} else {
		a.fork_add(mut c.thrown_fork, segs)
	}
}

// remove_from_array is removeFromArray: `splice(indexOf(value), 1)`, which removes the last
// element when the value is missing.
fn remove_from_array(mut elements []int, value int) {
	if elements.len == 0 {
		return
	}
	k := elements.index(value)
	elements.delete(if k < 0 { elements.len - 1 } else { k })
}

// disconnect_segments is disconnectSegments.
fn (mut a Analyzer) disconnect_segments(prev_segments []int, next_segments []int) {
	for i, p in prev_segments {
		n := next_segments[i]
		remove_from_array(mut a.an.segments[p].next_segments, n)
		remove_from_array(mut a.an.segments[p].all_next_segments, n)
		remove_from_array(mut a.an.segments[n].prev_segments, p)
		remove_from_array(mut a.an.segments[n].all_prev_segments, p)
	}
}

// make_looped is makeLooped.
fn (mut a Analyzer) make_looped(unflattened_from []int, unflattened_to []int) {
	from_segments := a.flatten_unused_segments(unflattened_from)
	to_segments := a.flatten_unused_segments(unflattened_to)
	end := if from_segments.len < to_segments.len { from_segments.len } else { to_segments.len }
	for i in 0 .. end {
		from := from_segments[i]
		to := to_segments[i]
		if a.an.segments[to].reachable {
			a.an.segments[from].next_segments << to
		}
		if a.an.segments[from].reachable {
			a.an.segments[to].prev_segments << from
		}
		a.an.segments[from].all_next_segments << to
		a.an.segments[to].all_prev_segments << from
		if a.an.segments[to].all_prev_segments.len >= 2 {
			a.an.segments[to].looped_prev_segments << from
		}
		a.on_looped(from, to)
	}
}

// finalize_test_segments_of_for is finalizeTestSegmentsOfFor.
fn (mut a Analyzer) finalize_test_segments_of_for(mut context LoopContext, mut choice ChoiceContext, head []int) {
	if !choice.processed {
		a.fork_add(mut choice.true_fork, head)
		a.fork_add(mut choice.false_fork, head)
		a.fork_add(mut choice.nullish_fork, head)
	}
	if !context.test_is_true {
		fork_add_all(mut context.broken, choice.false_fork)
	}
	context.end_of_test = a.make_next(choice.true_fork, 0, -1)
}

// new_state is `new CodePathState(idGenerator, onLooped)` for the code path `cp`.
fn (mut a Analyzer) new_state(cp int) &State {
	fork := a.new_root_fork(cp)
	a.an.code_paths[cp].initial_segment = fork.head()[0]
	return &State{
		cp:   cp
		fork: fork
	}
}

fn (mut a Analyzer) push_fork_context(fork_leaving_path bool) {
	mut st := a.st()
	st.fork = new_empty_fork(st.fork, fork_leaving_path)
}

fn (mut a Analyzer) pop_fork_context() {
	mut st := a.st()
	last := st.fork
	st.fork = last.upper
	segs := a.make_next(last, 0, -1)
	a.fork_replace_head(mut st.fork, segs)
}

fn (mut a Analyzer) fork_path() {
	mut st := a.st()
	segs := a.make_next(st.fork.upper, -1, -1)
	a.fork_add(mut st.fork, segs)
}

fn (mut a Analyzer) fork_bypass_path() {
	mut st := a.st()
	a.fork_add(mut st.fork, st.fork.upper.head())
}

fn (mut a Analyzer) push_choice_context(kind string, is_forking_as_result bool) {
	mut st := a.st()
	st.choice = &ChoiceContext{
		upper:                st.choice
		kind:                 kind
		is_forking_as_result: is_forking_as_result
		true_fork:            new_empty_fork(st.fork, false)
		false_fork:           new_empty_fork(st.fork, false)
		nullish_fork:         new_empty_fork(st.fork, false)
	}
}

fn (mut a Analyzer) pop_choice_context() &ChoiceContext {
	mut st := a.st()
	mut popped := st.choice
	mut fork := st.fork
	head := fork.head()
	st.choice = popped.upper
	match popped.kind {
		'&&', '||', '??' {
			if !popped.processed {
				a.fork_add(mut popped.true_fork, head)
				a.fork_add(mut popped.false_fork, head)
				a.fork_add(mut popped.nullish_fork, head)
			}
			if popped.is_forking_as_result {
				mut parent := st.choice
				fork_add_all(mut parent.true_fork, popped.true_fork)
				fork_add_all(mut parent.false_fork, popped.false_fork)
				fork_add_all(mut parent.nullish_fork, popped.nullish_fork)
				parent.processed = true
				return popped
			}
		}
		'test' {
			if !popped.processed {
				fork_clear(mut popped.true_fork)
				a.fork_add(mut popped.true_fork, head)
			} else {
				fork_clear(mut popped.false_fork)
				a.fork_add(mut popped.false_fork, head)
			}
		}
		'loop' {
			return popped
		}
		else {
			panic('unreachable')
		}
	}
	mut combined := popped.true_fork
	fork_add_all(mut combined, popped.false_fork)
	segs := a.make_next(combined, 0, -1)
	a.fork_replace_head(mut fork, segs)
	return popped
}

fn (mut a Analyzer) make_logical_right() {
	mut st := a.st()
	mut choice := st.choice
	mut fork := st.fork
	if choice.processed {
		mut prev := match choice.kind {
			'&&' { choice.true_fork }
			'||' { choice.false_fork }
			'??' { choice.nullish_fork }
			else { panic('unreachable') }
		}
		segs := a.make_next(prev, 0, -1)
		a.fork_replace_head(mut fork, segs)
		fork_clear(mut prev)
		choice.processed = false
	} else {
		match choice.kind {
			'&&' {
				a.fork_add(mut choice.false_fork, fork.head())
				a.fork_add(mut choice.nullish_fork, fork.head())
			}
			'||' {
				a.fork_add(mut choice.true_fork, fork.head())
			}
			'??' {
				a.fork_add(mut choice.true_fork, fork.head())
				a.fork_add(mut choice.false_fork, fork.head())
			}
			else {
				panic('unreachable')
			}
		}
		segs := a.make_next(fork, -1, -1)
		a.fork_replace_head(mut fork, segs)
	}
}

fn (mut a Analyzer) make_if_consequent() {
	mut st := a.st()
	mut context := st.choice
	mut fork := st.fork
	if !context.processed {
		a.fork_add(mut context.true_fork, fork.head())
		a.fork_add(mut context.false_fork, fork.head())
		a.fork_add(mut context.nullish_fork, fork.head())
	}
	context.processed = false
	segs := a.make_next(context.true_fork, 0, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) make_if_alternate() {
	mut st := a.st()
	mut context := st.choice
	mut fork := st.fork
	fork_clear(mut context.true_fork)
	a.fork_add(mut context.true_fork, fork.head())
	context.processed = true
	segs := a.make_next(context.false_fork, 0, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) push_chain_context() {
	mut st := a.st()
	st.chain = &ChainContext{
		upper: st.chain
	}
}

fn (mut a Analyzer) pop_chain_context() {
	mut st := a.st()
	context := st.chain
	st.chain = context.upper
	for i := context.choice_context_count; i > 0; i-- {
		a.pop_choice_context()
	}
}

fn (mut a Analyzer) make_optional_node() {
	mut st := a.st()
	if !isnil(st.chain) {
		st.chain.choice_context_count += 1
		a.push_choice_context('??', false)
	}
}

fn (mut a Analyzer) make_optional_right() {
	st := a.st()
	if !isnil(st.chain) {
		a.make_logical_right()
	}
}

fn (mut a Analyzer) push_switch_context(has_case bool, label string) {
	mut st := a.st()
	st.switch_ctx = &SwitchContext{
		upper:    st.switch_ctx
		has_case: has_case
	}
	a.push_break_context(true, label)
}

fn (mut a Analyzer) pop_switch_context() {
	mut st := a.st()
	context := st.switch_ctx
	st.switch_ctx = context.upper
	mut fork := st.fork
	mut broken := a.pop_break_context().broken
	if context.fork_count == 0 {
		if !broken.empty() {
			segs := a.make_next(fork, -1, -1)
			a.fork_add(mut broken, segs)
			segs2 := a.make_next(broken, 0, -1)
			a.fork_replace_head(mut fork, segs2)
		}
		return
	}
	last_segments := fork.head()
	a.fork_bypass_path()
	last_case_segments := fork.head()
	a.fork_add(mut broken, last_segments)
	if !context.last_is_default {
		if default_body := context.default_body_segments {
			a.disconnect_segments(context.default_segments, default_body)
			a.make_looped(last_case_segments, default_body)
		} else {
			a.fork_add(mut broken, last_case_segments)
		}
	}
	for _ in 0 .. context.fork_count {
		st.fork = st.fork.upper
	}
	segs := a.make_next(broken, 0, -1)
	a.fork_replace_head(mut st.fork, segs)
}

fn (mut a Analyzer) make_switch_case_body(is_case_body_empty bool, is_default_case bool) {
	mut st := a.st()
	mut context := st.switch_ctx
	if !context.has_case {
		return
	}
	parent_fork := st.fork
	a.push_fork_context(false)
	mut fork := st.fork
	segs := a.make_next(parent_fork, 0, -1)
	a.fork_add(mut fork, segs)
	if is_default_case {
		context.default_segments = parent_fork.head()
		if is_case_body_empty {
			context.found_empty_default = true
		} else {
			context.default_body_segments = fork.head()
		}
	} else {
		if !is_case_body_empty && context.found_empty_default {
			context.found_empty_default = false
			context.default_body_segments = fork.head()
		}
	}
	context.last_is_default = is_default_case
	context.fork_count += 1
}

fn (mut a Analyzer) push_try_context(has_finalizer bool) {
	mut st := a.st()
	st.try_ctx = &TryContext{
		upper:         st.try_ctx
		has_finalizer: has_finalizer
		position:      .try_
		returned_fork: if has_finalizer { new_empty_fork(st.fork, false) } else { unsafe { nil } }
		thrown_fork:   new_empty_fork(st.fork, false)
	}
}

fn (mut a Analyzer) pop_try_context() {
	mut st := a.st()
	context := st.try_ctx
	st.try_ctx = context.upper
	if context.position == .catch_ {
		a.pop_fork_context()
		return
	}
	original_returned := context.returned_fork
	original_thrown := context.thrown_fork
	if original_returned.empty() && original_thrown.empty() {
		return
	}
	head_segments := st.fork.head()
	st.fork = st.fork.upper
	half := head_segments.len / 2
	normal_segments := head_segments[..half].clone()
	leaving_segments := head_segments[half..].clone()
	if !original_returned.empty() {
		a.add_returned(leaving_segments)
	}
	if !original_thrown.empty() {
		a.add_thrown(leaving_segments)
	}
	a.fork_replace_head(mut st.fork, normal_segments)
	if !context.last_of_try_is_reachable && !context.last_of_catch_is_reachable {
		a.make_unreachable_without_range(st.fork)
	}
}

fn (mut a Analyzer) make_catch_block() {
	mut st := a.st()
	mut context := st.try_ctx
	fork := st.fork
	mut original_thrown := context.thrown_fork
	context.position = .catch_
	context.thrown_fork = new_empty_fork(fork, false)
	context.last_of_try_is_reachable = a.fork_reachable(fork)
	a.fork_add(mut original_thrown, fork.head())
	thrown_segments := a.make_next(original_thrown, 0, -1)
	a.push_fork_context(false)
	a.fork_bypass_path()
	a.fork_add(mut st.fork, thrown_segments)
}

fn (mut a Analyzer) make_finally_block() {
	mut st := a.st()
	mut context := st.try_ctx
	mut fork := st.fork
	original_returned := context.returned_fork
	original_thrown := context.thrown_fork
	head_of_leaving_segments := fork.head()
	if context.position == .catch_ {
		a.pop_fork_context()
		fork = st.fork
		context.last_of_catch_is_reachable = a.fork_reachable(fork)
	} else {
		context.last_of_try_is_reachable = a.fork_reachable(fork)
	}
	context.position = .finally_
	if original_returned.empty() && original_thrown.empty() {
		return
	}
	mut segments := a.make_next(fork, -1, -1)
	for i in 0 .. fork.count {
		mut prevs := [head_of_leaving_segments[i]]
		for list in original_returned.segments_list {
			prevs << list[i]
		}
		for list in original_thrown.segments_list {
			prevs << list[i]
		}
		segments << a.new_next(st.cp, prevs)
	}
	a.push_fork_context(true)
	a.fork_add(mut st.fork, segments)
}

fn (mut a Analyzer) make_yield() {
	st := a.st()
	mut fork := st.fork
	leaving_segments := fork.head()
	if a.fork_reachable(fork) {
		a.add_returned(leaving_segments)
		a.add_thrown(leaving_segments)
		segs := a.make_next(fork, -1, -1)
		a.fork_replace_head(mut fork, segs)
	}
}

fn (mut a Analyzer) make_first_throwable_path_in_try_or_catch_block() {
	st := a.st()
	mut fork := st.fork
	if !a.fork_reachable(fork) {
		return
	}
	mut context := st.get_throw_context()
	if isnil(context) || !context.thrown_fork.empty() {
		return
	}
	if context.position != .try_ && (context.position != .catch_ || !context.has_finalizer) {
		return
	}
	a.fork_add(mut context.thrown_fork, fork.head())
	segs := a.make_next(fork, -1, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) push_loop_context(typ estree.NodeType, label string) {
	mut st := a.st()
	fork := st.fork
	break_context := a.push_break_context(true, label)
	match typ {
		.while_statement, .for_statement {
			a.push_choice_context('loop', false)
			st.loop = &LoopContext{
				upper:  st.loop
				typ:    typ
				label:  label
				broken: break_context.broken
			}
		}
		.do_while_statement {
			a.push_choice_context('loop', false)
			st.loop = &LoopContext{
				upper:         st.loop
				typ:           typ
				label:         label
				broken:        break_context.broken
				continue_fork: new_empty_fork(fork, false)
			}
		}
		.for_in_statement, .for_of_statement {
			st.loop = &LoopContext{
				upper:  st.loop
				typ:    typ
				label:  label
				broken: break_context.broken
			}
		}
		else {
			panic('unknown type: "${typ.type_name()}"')
		}
	}
}

fn (mut a Analyzer) pop_loop_context() {
	mut st := a.st()
	context := st.loop
	st.loop = context.upper
	mut fork := st.fork
	mut broken := a.pop_break_context().broken
	match context.typ {
		.while_statement, .for_statement {
			a.pop_choice_context()
			a.make_looped(fork.head(), context.continue_dest or { []int{} })
		}
		.do_while_statement {
			mut choice := a.pop_choice_context()
			if !choice.processed {
				a.fork_add(mut choice.true_fork, fork.head())
				a.fork_add(mut choice.false_fork, fork.head())
			}
			if !context.test_is_true {
				fork_add_all(mut broken, choice.false_fork)
			}
			segments_list := choice.true_fork.segments_list.clone()
			for list in segments_list {
				a.make_looped(list, context.entry_segments)
			}
		}
		.for_in_statement, .for_of_statement {
			a.fork_add(mut broken, fork.head())
			a.make_looped(fork.head(), context.left_segments)
		}
		else {
			panic('unreachable')
		}
	}
	if broken.empty() {
		segs := a.make_unreachable(fork, -1, -1)
		a.fork_replace_head(mut fork, segs)
	} else {
		segs := a.make_next(broken, 0, -1)
		a.fork_replace_head(mut fork, segs)
	}
}

fn (mut a Analyzer) make_while_test(test ?bool) {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	test_segments := a.make_next(fork, 0, -1)
	context.test_is_true = test or { false }
	context.continue_dest = test_segments
	a.fork_replace_head(mut fork, test_segments)
}

fn (mut a Analyzer) make_while_body() {
	st := a.st()
	mut context := st.loop
	mut choice := st.choice
	mut fork := st.fork
	if !choice.processed {
		a.fork_add(mut choice.true_fork, fork.head())
		a.fork_add(mut choice.false_fork, fork.head())
	}
	if !context.test_is_true {
		fork_add_all(mut context.broken, choice.false_fork)
	}
	segs := a.make_next(choice.true_fork, 0, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) make_do_while_body() {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	body_segments := a.make_next(fork, -1, -1)
	context.entry_segments = body_segments
	a.fork_replace_head(mut fork, body_segments)
}

fn (mut a Analyzer) make_do_while_test(test ?bool) {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	context.test_is_true = test or { false }
	if !context.continue_fork.empty() {
		a.fork_add(mut context.continue_fork, fork.head())
		test_segments := a.make_next(context.continue_fork, 0, -1)
		a.fork_replace_head(mut fork, test_segments)
	}
}

fn (mut a Analyzer) make_for_test(test ?bool) {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	end_of_init_segments := fork.head()
	test_segments := a.make_next(fork, -1, -1)
	context.test_is_true = test or { false }
	context.end_of_init = end_of_init_segments
	context.continue_dest = test_segments
	context.test_segments = test_segments
	a.fork_replace_head(mut fork, test_segments)
}

fn (mut a Analyzer) make_for_update() {
	st := a.st()
	mut context := st.loop
	mut choice := st.choice
	mut fork := st.fork
	if _ := context.test_segments {
		a.finalize_test_segments_of_for(mut context, mut choice, fork.head())
	} else {
		context.end_of_init = fork.head()
	}
	update_segments := a.make_disconnected(fork, -1, -1)
	context.continue_dest = update_segments
	context.update_segments = update_segments
	a.fork_replace_head(mut fork, update_segments)
}

fn (mut a Analyzer) make_for_body() {
	st := a.st()
	mut context := st.loop
	mut choice := st.choice
	mut fork := st.fork
	if _ := context.update_segments {
		context.end_of_update = fork.head()
		if test_segments := context.test_segments {
			a.make_looped(context.end_of_update or { []int{} }, test_segments)
		}
	} else if _ := context.test_segments {
		a.finalize_test_segments_of_for(mut context, mut choice, fork.head())
	} else {
		context.end_of_init = fork.head()
	}
	body_segments := context.end_of_test or {
		mut prev_fork := new_empty_fork(fork, false)
		a.fork_add(mut prev_fork, context.end_of_init or { []int{} })
		if end_of_update := context.end_of_update {
			a.fork_add(mut prev_fork, end_of_update)
		}
		a.make_next(prev_fork, 0, -1)
	}
	if context.continue_dest == none {
		context.continue_dest = body_segments
	}
	a.fork_replace_head(mut fork, body_segments)
}

fn (mut a Analyzer) make_for_in_of_left() {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	left_segments := a.make_disconnected(fork, -1, -1)
	context.prev_segments = fork.head()
	context.left_segments = left_segments
	context.continue_dest = left_segments
	a.fork_replace_head(mut fork, left_segments)
}

fn (mut a Analyzer) make_for_in_of_right() {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	mut temp := new_empty_fork(fork, false)
	a.fork_add(mut temp, context.prev_segments)
	right_segments := a.make_next(temp, -1, -1)
	context.end_of_left = fork.head()
	a.fork_replace_head(mut fork, right_segments)
}

fn (mut a Analyzer) make_for_in_of_body() {
	st := a.st()
	mut context := st.loop
	mut fork := st.fork
	mut temp := new_empty_fork(fork, false)
	a.fork_add(mut temp, context.end_of_left)
	body_segments := a.make_next(temp, -1, -1)
	a.make_looped(fork.head(), context.left_segments)
	a.fork_add(mut context.broken, fork.head())
	a.fork_replace_head(mut fork, body_segments)
}

fn (mut a Analyzer) push_break_context(breakable bool, label string) &BreakContext {
	mut st := a.st()
	st.brk = &BreakContext{
		upper:     st.brk
		breakable: breakable
		label:     label
		broken:    new_empty_fork(st.fork, false)
	}
	return st.brk
}

fn (mut a Analyzer) pop_break_context() &BreakContext {
	mut st := a.st()
	context := st.brk
	mut fork := st.fork
	st.brk = context.upper
	if !context.breakable {
		mut broken := context.broken
		if !broken.empty() {
			a.fork_add(mut broken, fork.head())
			segs := a.make_next(broken, 0, -1)
			a.fork_replace_head(mut fork, segs)
		}
	}
	return context
}

fn (mut a Analyzer) make_break(label string) {
	st := a.st()
	mut fork := st.fork
	if !a.fork_reachable(fork) {
		return
	}
	mut context := st.get_break_context(label)
	if !isnil(context) {
		a.fork_add(mut context.broken, fork.head())
	}
	segs := a.make_unreachable(fork, -1, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) make_continue(label string) {
	st := a.st()
	mut fork := st.fork
	if !a.fork_reachable(fork) {
		return
	}
	mut context := st.get_continue_context(label)
	if !isnil(context) {
		if dest := context.continue_dest {
			a.make_looped(fork.head(), dest)
			if context.typ in [.for_in_statement, .for_of_statement] {
				a.fork_add(mut context.broken, fork.head())
			}
		} else {
			a.fork_add(mut context.continue_fork, fork.head())
		}
	}
	segs := a.make_unreachable(fork, -1, -1)
	a.fork_replace_head(mut fork, segs)
}

fn (mut a Analyzer) make_return() {
	st := a.st()
	mut fork := st.fork
	if a.fork_reachable(fork) {
		a.add_returned(fork.head())
		segs := a.make_unreachable(fork, -1, -1)
		a.fork_replace_head(mut fork, segs)
	}
}

fn (mut a Analyzer) make_throw() {
	st := a.st()
	mut fork := st.fork
	if a.fork_reachable(fork) {
		a.add_thrown(fork.head())
		segs := a.make_unreachable(fork, -1, -1)
		a.fork_replace_head(mut fork, segs)
	}
}

fn (mut a Analyzer) make_final() {
	st := a.st()
	segments := st.current_segments
	if segments.len > 0 && a.an.segments[segments[0]].reachable {
		a.add_returned_of_code_path(st.cp, segments)
	}
}
