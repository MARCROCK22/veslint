module rules

import json2

// Rule options. main gives each active rule its effective options: the typescript-eslint
// defaults (default_options) merged with the configured ones, like applyDefault. Which options a
// rule takes is ESLint's answer: they are validated first against the schema of the rule
// (rule_options_problems of json_schema.v), by the configuration and by the comments of a file.
// The rules then read them with check_options, which can only reject what a schema does not tell:
// a pattern that is not a regular expression.

// check_options checks that veslint applies the effective `options` of `rule`. Returns false if
// the rule reads no options: then only the defaults are valid.
pub fn check_options(rule string, options []json2.Any) !bool {
	match rule {
		no_floating_promises { nfp_options(options)! }
		return_await { rw_options(options)! }
		no_unsafe_member_access { numa_options(options)! }
		no_misused_promises { nmp_options(options)! }
		restrict_template_expressions { rte_options(options)! }
		switch_exhaustiveness_check { sec_options(options)! }
		prefer_nullish_coalescing { pnc_options(options)! }
		no_unnecessary_condition { nuco_options(options)! }
		no_unnecessary_boolean_literal_compare { nublc_options(options)! }
		no_meaningless_void_operator { nmvo_options(options)! }
		no_duplicate_type_constituents { ndtc_options(options)! }
		dot_notation { dotn_options(options, false)! }
		restrict_plus_operands { rpo_options(options)! }
		no_confusing_void_expression { ncve_options(options)! }
		no_misused_spread { nms_options(options)! }
		no_base_to_string { nbts_options(options)! }
		no_useless_default_assignment { nuda_options(options)! }
		no_unnecessary_type_assertion { nuta_options(options)! }
		unbound_method { ubm_options(options)! }
		prefer_string_starts_ends_with { pssew_options(options)! }
		prefer_optional_chain { poc_options(options)! }
		no_deprecated { ndep_options(options)! }
		prefer_promise_reject_errors { ppre_options(options)! }
		only_throw_error { ote_options(options)! }
		require_array_sort_compare { rasc_options(options)! }
		promise_function_async { pfa_options(options)! }
		prefer_readonly_parameter_types { prpt_options(options)! }
		consistent_type_exports { cte_options(options)! }
		strict_void_return { svr_options(options)! }
		no_namespace { nn_options(options)! }
		no_invalid_void_type { nivt_options(options)! }
		consistent_return { cr_options(options)! }
		prefer_destructuring { pd_options(options)! }
		prefer_readonly { prd_options(options)! }
		strict_boolean_expressions { sbe_options(options)! }
		naming_convention { nc_options(options)! }
		no_use_before_define { nubd_options(options)! }
		no_shadow { nsh_options(options)! }
		consistent_type_imports { cti_options(options)! }
		no_unused_vars { nuv_options(options)! }
		no_this_alias { nta_options(options)! }
		no_extraneous_class { nec_options(options)! }
		class_literal_property_style { clps_options(options)! }
		no_empty_function { nef_options(options)! }
		no_unused_expressions { nuex_options(options)! }
		no_inferrable_types { nit_options(options)! }
		triple_slash_reference { tsr_options(options)! }
		consistent_generic_constructors { cgc_option(options)! }
		consistent_type_assertions { cta_options(options)! }
		consistent_type_definitions { ctd_option(options)! }
		unified_signatures { us_options(options)! }
		no_require_imports { nri_options(options)! }
		array_type { arty_options(options)! }
		consistent_indexed_object_style { cios_options(options)! }
		use_isnan { uin_options(options)! }
		valid_typeof { vt_options(options)! }
		no_self_assign { nsa_options(options)! }
		no_unsafe_negation { nun_options(options)! }
		no_unsafe_optional_chaining { nuoc_options(options)! }
		no_cond_assign { nca_always(options)! }
		no_constant_condition { ncc_check_loops(options)! }
		no_constant_binary_expression { ncbe_options(options)! }
		curly { cu_options(options)! }
		no_else_return { ner_allow_else_if(options)! }
		no_empty { ne_allow_empty_catch(options)! }
		no_labels { nl_options(options)! }
		arrow_body_style { abs_options(options)! }
		prefer_arrow_callback { pac_options(options)! }
		func_name_matching { fnm_options(options)! }
		func_names { fn_options(options)! }
		grouped_accessor_pairs { gap_options(options)! }
		no_empty_pattern { nep_allow_parameters(options)! }
		no_useless_rename { nur_options(options)! }
		no_useless_computed_key { nuck_class_members(options)! }
		object_shorthand { os_options(options)! }
		eqeqeq { eqe_options(options)! }
		yoda { yoda_options(options)! }
		no_extra_boolean_cast { nebc_options(options)! }
		no_implicit_coercion { nic_options(options)! }
		logical_assignment_operators { lao_options(options)! }
		operator_assignment { oa_never(options)! }
		no_sequences { nseq_allow_parentheses(options)! }
		no_return_assign { nra_always(options)! }
		no_irregular_whitespace { niw_options(options)! }
		unicode_bom { ubom_always(options)! }
		radix_rule { radix_options(options)! }
		no_extend_native { nen_exceptions(options)! }
		core_dot_notation { dotn_core_options(options)! }
		preserve_caught_error { pce_require_parameter(options)! }
		no_global_assign { nga_exceptions(options)! }
		no_shadow_restricted_names { nsrn_report_global_this(options)! }
		consistent_this { cth_aliases(options)! }
		prefer_const { pconst_options(options)! }
		sort_vars { svars_options(options)! }
		strict_rule { strict_options(options)! }
		no_inner_declarations { nid_options(options)! }
		no_implicit_globals { nig_options(options)! }
		no_invalid_regexp { nir_options(options)! }
		no_misleading_character_class { nmcc_options(options)! }
		no_useless_escape { nue_options(options)! }
		prefer_regex_literals { prl_options(options)! }
		no_warning_comments { nwc_options(options)! }
		no_restricted_globals { nrg_options(options)! }
		no_restricted_properties { nrp_options(options)! }
		no_restricted_exports { nre_options(options)! }
		no_restricted_imports { nrim_options(options)! }
		no_promise_executor_return { npe_options(options)! }
		no_invalid_this { nith_options(options)! }
		getter_return { gr_options(options)! }
		no_unreachable_loop { nurl_options(options)! }
		no_fallthrough { nft_options(options)! }
		no_restricted_syntax { nrsx_options(options)! }
		else { return false }
	}
	return true
}

// set_options sets the effective options of a rule (already checked with check_options).
pub fn (mut c Checker) set_options(rule string, options []json2.Any) {
	c.options[rule] = options
}

// rule_options are the effective options of a rule: the ones set, or the defaults.
fn (c &Checker) rule_options(rule string) []json2.Any {
	return c.options[rule] or { decoded_default_options(rule) }
}

// decoded_default_options are the default options of a rule.
pub fn decoded_default_options(rule string) []json2.Any {
	text := default_options[rule] or { '[]' }
	return (json2.decode[json2.Any](text) or { json2.Any([]json2.Any{}) }).as_array()
}

// effective_options merges the options of a rule with its defaults, like typescript-eslint
// (applyDefault), and returns the effective ones. If the rule reads options, check_options rejects
// the ones veslint does not apply; otherwise only options equivalent to the defaults pass.
pub fn effective_options(name string, options []json2.Any) ![]json2.Any {
	defaults := decoded_default_options(name)
	// The options of naming-convention replace its defaults: they are a list of any length.
	if name == naming_convention {
		written := if options.len > 0 { options } else { defaults }
		nc_options(written) or { return error('`${name}`: ${err.msg()}') }
		return written
	}
	mut merged := apply_default(defaults, options)
	// ESLint merges the options of its core rules with deepMergeArrays, which keeps the options
	// past the defaults (`curly`'s "consistent").
	if !name.contains('/') && options.len > merged.len {
		// One by one: `<<` of an array would add it as one value (json2.Any has arrays). The
		// slice is taken before the loop: V evaluates `options[merged.len..]` again on every
		// iteration (tests/v-bugs/13-for-in-slice-start-reevaluated).
		extra := options[merged.len..].clone()
		for option in extra {
			merged << option
		}
	}
	reads := check_options(name, merged) or { return error('`${name}`: ${err.msg()}') }
	if reads {
		// A rule takes as many options as it has defaults for, and at least one; the schema of a
		// rule of ESLint core limits its options (`curly` has a second one without a default).
		limit := if defaults.len > 1 { defaults.len } else { 1 }
		if name.contains('/') && options.len > limit {
			return error('`${name}` takes ${if limit == 1 {
				'a single option'
			} else {
				'${limit} options'
			}}, got ${options.len}')
		}
		// The core rule that prefer-destructuring extends reads the options as written.
		if name == prefer_destructuring {
			mut with_written := merged.clone()
			with_written << json2.Any(options.clone())
			pd_options(with_written) or { return error('`${name}`: ${err.msg()}') }
			return with_written
		}
	} else if options.len > defaults.len
		|| canonical_json(json2.Any(merged)) != canonical_json(json2.Any(defaults)) {
		defaults_json := default_options[name] or { '[]' }
		return error('`${name}`: veslint only applies the default options (${defaults_json}), got ${canonical_json(json2.Any(options))}')
	}
	return merged
}

// apply_default ports applyDefault from typescript-eslint: each user option replaces the default
// one, except two objects, which are merged.
fn apply_default(defaults []json2.Any, user []json2.Any) []json2.Any {
	mut out := defaults.clone()
	for i, d in defaults {
		if i >= user.len {
			break
		}
		u := user[i]
		if u is map[string]json2.Any && d is map[string]json2.Any {
			out[i] = json2.Any(deep_merge(d, u))
		} else {
			out[i] = u
		}
	}
	return out
}

// deep_merge ports deepMerge from typescript-eslint.
fn deep_merge(first map[string]json2.Any, second map[string]json2.Any) map[string]json2.Any {
	mut out := first.clone()
	for key, value in second {
		previous := first[key] or {
			out[key] = value
			continue
		}
		if previous is map[string]json2.Any && value is map[string]json2.Any {
			out[key] = json2.Any(deep_merge(previous, value))
		} else {
			out[key] = value
		}
	}
	return out
}

// canonical_json is the JSON of a value with object keys sorted, for comparisons.
fn canonical_json(value json2.Any) string {
	if value is map[string]json2.Any {
		mut keys := value.keys()
		keys.sort()
		return '{' + keys.map('${json2.encode(it)}:${canonical_json(value[it] or { json2.Any(json2.null) })}').join(',') + '}'
	}
	if value is []json2.Any {
		return '[' + value.map(canonical_json(it)).join(',') + ']'
	}
	return value.json_str()
}

// OptionObject is the options object of a rule (its first option).
struct OptionObject {
	rule   string
	values map[string]json2.Any
}

fn option_object(rule string, options []json2.Any, known []string) !OptionObject {
	if options.len == 0 {
		return OptionObject{
			rule: rule
		}
	}
	first := options[0]
	if first !is map[string]json2.Any {
		return error('the options of `${rule}` must be an object')
	}
	values := first.as_map()
	// Like additionalProperties: false in the typescript-eslint schemas.
	for key, _ in values {
		if key !in known {
			return error('`${rule}` has no option `${key}`')
		}
	}
	return OptionObject{
		rule:   rule
		values: values
	}
}

// bool_value reads a boolean option; when missing it is false, like `undefined` in JavaScript.
fn (o OptionObject) bool_value(key string) !bool {
	value := o.values[key] or { return false }
	if value !is bool {
		return error('option `${key}` of `${o.rule}` must be true or false')
	}
	return value as bool
}

// string_value reads a text option from `allowed`; when missing it is ''.
fn (o OptionObject) string_value(key string, allowed []string) !string {
	value := o.values[key] or { return '' }
	if value is string && value in allowed {
		return value
	}
	return error('option `${key}` of `${o.rule}` must be one of: ${allowed.join(', ')}')
}

// string_list reads a list of texts; when missing, empty.
fn (o OptionObject) string_list(key string) ![]string {
	value := o.values[key] or { return []string{} }
	if value !is []json2.Any {
		return error('option `${key}` of `${o.rule}` must be a list of texts')
	}
	mut out := []string{}
	for item in value.as_array() {
		if item !is string {
			return error('option `${key}` of `${o.rule}` must be a list of texts')
		}
		out << item as string
	}
	return out
}

// specifiers reads a list of type specifiers (TypeOrValueSpecifier); when missing, empty.
fn (o OptionObject) specifiers(key string) ![]TypeSpecifier {
	value := o.values[key] or { return []TypeSpecifier{} }
	if value !is []json2.Any {
		return error('option `${key}` of `${o.rule}` must be a list')
	}
	mut out := []TypeSpecifier{}
	for item in value.as_array() {
		out << type_specifier(item) or { return error('`${key}` of `${o.rule}`: ${err.msg()}') }
	}
	return out
}
