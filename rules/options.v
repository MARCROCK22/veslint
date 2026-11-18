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
		await_thenable { at_options(options)! }
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
		unicorn_no_typeof_undefined { unty_options(options)! }
		unicorn_prefer_ternary { upt_options(options)! }
		unicorn_prefer_switch { ups_options(options)! }
		unicorn_switch_case_braces { uscb_options(options)! }
		unicorn_prefer_structured_clone { upsc_options(options)! }
		unicorn_no_unreadable_array_destructuring { unuad_options(options)! }
		unicorn_no_array_callback_reference { unacr_options(options)! }
		unicorn_no_instanceof_builtins { unib_options(options)! }
		unicorn_escape_case { uec_options(options)! }
		unicorn_text_encoding_identifier_case { uteic_options(options)! }
		unicorn_prefer_number_properties { upnp_options(options)! }
		unicorn_no_array_reverse { unar_options(options)! }
		unicorn_no_array_sort { unas_options(options)! }
		unicorn_prefer_array_flat { upaf_options(options)! }
		unicorn_explicit_length_check { uelc_options(options)! }
		no_unmodified_loop_condition { nulc_options(options)! }
		array_callback_return { acr_options(options)! }
		require_atomic_updates { rau_options(options)! }
		class_methods_use_this { cmut_options(options)! }
		no_explicit_any { nea_options(options)! }
		unicorn_prefer_single_call { upsg_options(options)! }
		unicorn_no_immediate_mutation { unim_options(options)! }
		unicorn_prefer_export_from { upef_options(options)! }
		unicorn_relative_url_style { rus_options(options)! }
		stylistic_array_bracket_spacing { sabs_options(options)! }
		unicorn_consistent_function_scoping { ucfs_options(options)! }
		unicorn_isolated_functions { uisf_options(options)! }
		unicorn_no_useless_undefined { unuu_options(options)! }
		unicorn_no_keyword_prefix { unkp_options(options)! }
		unicorn_prefer_object_from_entries { upofe_options(options)! }
		unicorn_prefer_default_parameters { updp_options(options)! }
		stylistic_rest_spread_spacing { srsp_options(options)! }
		stylistic_semi_spacing { ssmi_options(options)! }
		stylistic_space_in_parens { sinp_options(options)! }
		stylistic_switch_colon_spacing { sscs_options(options)! }
		stylistic_template_curly_spacing { stcs_options(options)! }
		stylistic_template_tag_spacing { stts_options(options)! }
		stylistic_block_spacing { sbls_options(options)! }
		stylistic_comma_spacing { scmsp_options(options)! }
		stylistic_computed_property_spacing { scpsp_options(options)! }
		stylistic_object_curly_spacing { socsp_options(options)! }
		stylistic_keyword_spacing { skwsp_options(options)! }
		stylistic_space_before_blocks { ssbb_options(options)! }
		stylistic_arrow_spacing { sarws_options(options)! }
		stylistic_yield_star_spacing { sysp_options(options)! }
		stylistic_type_annotation_spacing { stas_options(options)! }
		stylistic_type_generic_spacing { stgs_options(options)! }
		stylistic_space_before_function_paren { ssbfp_options(options)! }
		stylistic_key_spacing { sks_options(options)! }
		stylistic_space_infix_ops { ssio_options(options)! }
		stylistic_space_unary_ops { ssuo_options(options)! }
		stylistic_function_call_spacing { sfcs_options(options)! }
		stylistic_brace_style { sbs_options(options)! }
		stylistic_comma_style { scst_options(options, false)! }
		stylistic_dot_location { sdl_options(options)! }
		stylistic_function_call_argument_newline { sfcan_options(options)! }
		stylistic_function_paren_newline { sfpn_options(options)! }
		stylistic_implicit_arrow_linebreak { sial_options(options)! }
		stylistic_multiline_ternary { smtn_options(options)! }
		stylistic_nonblock_statement_body_position { snsbp_options(options)! }
		stylistic_one_var_declaration_per_line { sovdpl_options(options)! }
		stylistic_quotes { squo_options(options)! }
		stylistic_no_multi_spaces { snms_options(options)! }
		stylistic_no_trailing_spaces { sntr_options(options)! }
		stylistic_no_mixed_spaces_and_tabs { snmst_options(options)! }
		stylistic_eol_last { seol_options(options)! }
		stylistic_spaced_comment { sspc_options(options)! }
		stylistic_lines_between_class_members { slbcm_options(options)! }
		stylistic_new_parens { snwp_options(options)! }
		stylistic_semi_style { ssms_options(options)! }
		stylistic_semi { ssemi_options(options)! }
		stylistic_object_curly_newline { socn_options(options)! }
		stylistic_object_property_newline { sopn_options(options)! }
		stylistic_list_style { sls_options(options)! }
		stylistic_exp_jsx_props_style { sjps_options(options)! }
		stylistic_arrow_parens { sap_options(options)! }
		stylistic_comma_dangle { scd_options(options)! }
		stylistic_member_delimiter_style { smds_options(options)! }
		stylistic_quote_props { sqp_options(options)! }
		stylistic_no_extra_parens { snep_options(options)! }
		marcrock_prefer_at { mpa_options(options)! }
		perfectionist_sort_array_includes { pf_options(options)! }
		perfectionist_sort_sets { pf_options(options)! }
		perfectionist_sort_maps { pf_options(options)! }
		perfectionist_sort_union_types { pf_options(options)! }
		perfectionist_sort_intersection_types { pf_options(options)! }
		ban_ts_comment { btsc_options(options)! }
		init_declarations { tsid_options(options)! }
		max_params { tsmp_options(options)! }
		method_signature_style { mss_options(options)! }
		no_empty_object_type { neot_options(options)! }
		ts_no_invalid_this { tsnit_options(options)! }
		no_redeclare { tsnr_options(options)! }
		perfectionist_sort_heritage_clauses { pf_options(options)! }
		perfectionist_sort_import_attributes { pf_options(options)! }
		perfectionist_sort_export_attributes { pf_options(options)! }
		perfectionist_sort_switch_case { pf_options(options)! }
		perfectionist_sort_named_imports { pf_options(options)! }
		perfectionist_sort_named_exports { pf_options(options)! }
		perfectionist_sort_exports { pf_options(options)! }
		explicit_function_return_type { efrt_options(options)! }
		explicit_module_boundary_types { embt_options(options)! }
		explicit_member_accessibility { ema_options(options)! }
		parameter_properties { ppr_options(options)! }
		prefer_literal_enum_member { plem_options(options)! }
		no_magic_numbers { nmag_options(options)! }
		no_restricted_types { nrty_options(options)! }
		member_ordering { mord_options(options)! }
		perfectionist_sort_classes { pf_options(options)! }
		perfectionist_sort_imports { pf_options(options)! }
		vue_no_v_html { vnvh_options(options)! }
		vue_no_duplicate_attributes { vnda_options(options)! }
		vue_comment_directive { vcd_options(options)! }
		vue_no_parsing_error { vnpe_options(options)! }
		vue_valid_v_on { vvon_options(options)! }
		vue_v_on_style { vvos_options(options)! }
		vue_v_bind_style { vvbs_options(options)! }
		vue_no_use_v_if_with_v_for { vnuviwvf_options(options)! }
		vue_v_for_delimiter_style { vvfds_options(options)! }
		vue_no_v_text_v_html_on_component { vnvtvhoc_options(options)! }
		vue_no_lone_template { vnlt_options(options)! }
		vue_html_button_has_type { vhbht_options(options)! }
		vue_no_deprecated_router_link_tag_prop { vndrltp_options(options)! }
		vue_no_restricted_html_elements { vnrhe_options(options)! }
		vue_mustache_interpolation_spacing { vmis_options(options)! }
		vue_restricted_component_names { vrcn_options(options)! }
		vue_slot_name_casing { vsnc_options(options)! }
		vue_first_attribute_linebreak { vfal_options(options)! }
		vue_html_quotes { vhq_options(options)! }
		vue_no_literals_in_template { vnlit_options(options)! }
		vue_require_toggle_inside_transition { vrtit_options(options)! }
		vue_no_restricted_static_attribute { vnrsa_options(options)! }
		vue_html_closing_bracket_spacing { vhcbs_options(options)! }
		vue_html_closing_bracket_newline { vhcbn_options(options)! }
		vue_attribute_hyphenation { vah_options(options)! }
		vue_v_on_event_hyphenation { voeh_options(options)! }
		vue_no_static_inline_styles { vnsis_options(options)! }
		vue_no_child_content { vncc_options(options)! }
		vue_no_template_target_blank { vnttb_options(options)! }
		vue_no_restricted_class { vnrc_options(options)! }
		vue_no_useless_v_bind { vnuvb_options(options)! }
		vue_no_restricted_v_bind { vnrvb_options(options)! }
		vue_no_restricted_v_on { vnrvo_options(options)! }
		vue_v_slot_style { vvss_options(options)! }
		vue_prefer_true_attribute_shorthand { vptas_options(options)! }
		vue_no_deprecated_slot_attribute { vndslota_options(options)! }
		vue_this_in_template { vtit_options(options)! }
		vue_no_unused_vars { vnuv_options(options)! }
		vue_define_props_declaration { vue_define_props_declaration_options(options)! }
		vue_max_template_depth { vue_max_template_depth_options(options)! }
		vue_no_reserved_props { vue_no_reserved_props_options(options)! }
		vue_max_props { vue_max_props_options(options)! }
		vue_prop_name_casing { vue_prop_name_casing_options(options)! }
		vue_define_props_destructuring { vue_define_props_destructuring_options(options)! }
		vue_component_definition_name_casing {
			vue_component_definition_name_casing_options(options)!
		}
		vue_require_macro_variable_name { vue_require_macro_variable_name_options(options)! }
		vue_define_emits_declaration { vue_define_emits_declaration_options(options)! }
		vue_no_restricted_block { vue_no_restricted_block_options(options)! }
		vue_component_options_name_casing { vue_component_options_name_casing_options(options)! }
		vue_max_lines_per_block { vue_max_lines_per_block_options(options)! }
		vue_no_reserved_keys { vue_no_reserved_keys_options(options)! }
		vue_return_in_computed_property { vue_return_in_computed_property_options(options)! }
		vue_max_attributes_per_line { vmapl_options(options)! }
		vue_no_useless_mustaches { vnum_options(options)! }
		vue_singleline_html_element_content_newline { vhecn_single_options(options)! }
		vue_multiline_html_element_content_newline { vhecn_multi_options(options)! }
		vue_html_self_closing { vhsc_options(options)! }
		vue_padding_line_between_blocks { vplbb_options(options)! }
		vue_padding_line_between_tags { vplbt_options(options)! }
		vue_block_tag_newline { vbtn_options(options)! }
		vue_block_lang { vblang_options(options)! }
		vue_no_bare_strings_in_template { vnbs_options(options)! }
		vue_no_irregular_whitespace { vnirw_options(options)! }
		vue_valid_v_for { vvfor_options(options)! }
		vue_valid_v_slot { vvslot_options(options)! }
		vue_no_unsupported_features { vnuf_options(options)! }
		vue_max_len { vmaxlen_options(options)! }
		vue_attributes_order { vattro_options(options)! }
		vue_no_duplicate_attr_inheritance { vndai_options(options)! }
		vue_no_unused_components { vnuc_options(options)! }
		vue_no_template_shadow { vnts_options(options)! }
		vue_no_undef_directives { vnud_options(options)! }
		vue_component_name_in_template_casing { vcnitc_options(options)! }
		vue_custom_event_name_casing { vcenc_options(options)! }
		vue_no_restricted_custom_event { vnrce_options(options)! }
		vue_require_explicit_emits { vree_options(options)! }
		vue_no_undef_components { vnuco_options(options)! }
		vue_v_on_handler_style { vohs_options(options)! }
		vue_no_mutating_props { vnmp_options(options)! }
		vue_no_unused_properties { vnup_options(options)! }
		vue_no_undef_properties { vnudp_options(options)! }
		vue_multi_word_component_names { vue_multi_word_component_names_options(options)! }
		vue_no_multiple_template_root { vue_no_multiple_template_root_options(options)! }
		vue_no_potential_component_option_typo {
			vue_no_potential_component_option_typo_options(options)!
		}
		vue_no_deprecated_model_definition { vue_no_deprecated_model_definition_options(options)! }
		vue_match_component_file_name { vue_match_component_file_name_options(options)! }
		vue_enforce_style_attribute { vue_enforce_style_attribute_options(options)! }
		vue_require_direct_export { vue_require_direct_export_options(options)! }
		vue_no_restricted_component_names { vue_no_restricted_component_names_options(options)! }
		vue_no_restricted_component_options {
			vue_no_restricted_component_options_options(options)!
		}
		vue_new_line_between_multi_line_property {
			vue_new_line_between_multi_line_property_options(options)!
		}
		vue_component_api_style { vue_component_api_style_options(options)! }
		vue_no_reserved_component_names { vue_no_reserved_component_names_options(options)! }
		vue_require_prop_comment { vue_require_prop_comment_options(options)! }
		vue_define_macros_order { vue_define_macros_order_options(options)! }
		vue_order_in_components { vue_order_in_components_options(options)! }
		vue_padding_lines_in_component_definition {
			vue_padding_lines_in_component_definition_options(options)!
		}
		vue_sort_keys { vue_sort_keys_options(options)! }
		vue_html_comment_content_spacing { vue_html_comment_content_spacing_options(options)! }
		vue_html_comment_content_newline { vue_html_comment_content_newline_options(options)! }
		vue_html_comment_indent { vue_html_comment_indent_options(options)! }
		vue_no_multi_spaces { vue_no_multi_spaces_options(options)! }
		vue_block_order { vue_block_order_options(options)! }
		vue_no_restricted_call_after_await { vue_no_restricted_call_after_await_options(options)! }
		vue_next_tick_style { vue_next_tick_style_options(options)! }
		vue_no_boolean_default { vue_no_boolean_default_options(options)! }
		vue_no_required_prop_with_default { vue_no_required_prop_with_default_options(options)! }
		vue_no_restricted_props { vue_no_restricted_props_options(options)! }
		vue_no_async_in_computed_properties {
			vue_no_async_in_computed_properties_options(options)!
		}
		vue_no_dupe_keys { vue_no_dupe_keys_options(options)! }
		svelte_comment_directive { svcd_options(options)! }
		svelte_button_has_type { sbht_options(options)! }
		svelte_no_target_blank { sntb_options(options)! }
		svelte_shorthand_attribute { svsha_options(options)! }
		svelte_spaced_html_comment { sshc_options(options)! }
		svelte_no_useless_mustaches { snum_options(options)! }
		svelte_first_attribute_linebreak { sfal_options(options)! }
		svelte_shorthand_directive { svshd_options(options)! }
		svelte_html_closing_bracket_spacing { shcbs_options(options)! }
		svelte_html_closing_bracket_new_line { shcbnl_options(options)! }
		svelte_html_quotes { shq_options(options)! }
		svelte_mustache_spacing { smsp_options(options)! }
		svelte_no_inline_styles { snis_options(options)! }
		svelte_max_attributes_per_line { smapl_options(options)! }
		svelte_html_self_closing { shsc_options(options)! }
		svelte_block_lang { sbl_options(options)! }
		svelte_prefer_class_directive { spcd_options(options)! }
		svelte_prefer_const { svpc_options(options)! }
		svelte_no_inner_declarations { svnid_options(options)! }
		svelte_no_trailing_spaces { svnts_options(options)! }
		svelte_no_unnecessary_state_wrap { svnusw_options(options)! }
		svelte_no_reactive_reassign { svnrr_options(options)! }
		svelte_no_navigation_without_base { svnnwb_options(options)! }
		svelte_no_navigation_without_resolve { svnnwr_options(options)! }
		svelte_no_unused_props { svnup_options(options)! }
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
	// The rules of eslint-plugin-perfectionist read their options as written (context.options: a
	// list of option objects, one of which useConfigurationIf picks), over their own defaults.
	// The rules of eslint-plugin-vue have no meta.defaultOptions either: they read their options as
	// written, with their defaults in their code.
	// A wrapper rule of eslint-plugin-vue has the meta of the rule it wraps (its defaultOptions
	// too): its options are that rule's (rules/vue_wrap.v).
	if base := vue_wrap_base_rule(name) {
		return effective_options(base, options) or {
			return error(err.msg().replace_once('`${base}`', '`${name}`'))
		}
	}
	// So have those of eslint-plugin-svelte.
	if name.starts_with('perfectionist/') || name.starts_with('vue/') || name.starts_with('svelte/') {
		check_options(name, options) or { return error('`${name}`: ${err.msg()}') }
		return options
	}
	mut merged := apply_default(defaults, options)
	// ESLint merges the options of its core rules with deepMergeArrays, which keeps the options
	// past the defaults (`curly`'s "consistent"); createRule of @stylistic keeps them too.
	stylistic := name.starts_with('@stylistic/')
	if (!name.contains('/') || stylistic) && options.len > merged.len {
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
		// The core rule that init-declarations extends takes a second option.
		limit := if name == init_declarations {
			2
		} else if defaults.len > 1 {
			defaults.len
		} else {
			1
		}
		// The schema of a rule of @stylistic limits its options.
		if name.contains('/') && !stylistic && options.len > limit {
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
		// So do the ones init-declarations and max-params extend (their wrappers have no
		// meta.defaultOptions): the written options follow the merged ones, as a list.
		if name in [init_declarations, max_params] {
			mut with_written := merged.clone()
			with_written << json2.Any(options.clone())
			check_options(name, with_written) or { return error('`${name}`: ${err.msg()}') }
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
