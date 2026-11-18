module rules

import builtin.closure
import codepath
import estree
import json2
import time
import tsgo { Client, CompilerOptions, ParameterResponse, SignatureResponse, SourceFileAst, SymbolResponse, TypeResponse }
import treesitter { Ident, Parser, TokenEnds, children, first_named_child, named_children, node_end, node_field, node_kind, node_start, root_node, token_ends, tree_delete, tree_has_error }
import offsets
import os

// Lint rules ported to V. Each rule lives in its own file of this module and shares what is
// here: the Checker (tsgo client and type caches), the per-node type queries (type_queries.v) and
// the promise helpers (promises.v).

// Names of the ported rules.
pub const no_floating_promises = '@typescript-eslint/no-floating-promises'
pub const await_thenable = '@typescript-eslint/await-thenable'
pub const require_await = '@typescript-eslint/require-await'
pub const return_await = '@typescript-eslint/return-await'
pub const no_misused_promises = '@typescript-eslint/no-misused-promises'
pub const no_unsafe_call = '@typescript-eslint/no-unsafe-call'
pub const no_unsafe_member_access = '@typescript-eslint/no-unsafe-member-access'
pub const no_unsafe_return = '@typescript-eslint/no-unsafe-return'
pub const no_unsafe_assignment = '@typescript-eslint/no-unsafe-assignment'
pub const no_unsafe_argument = '@typescript-eslint/no-unsafe-argument'
pub const restrict_template_expressions = '@typescript-eslint/restrict-template-expressions'
pub const switch_exhaustiveness_check = '@typescript-eslint/switch-exhaustiveness-check'
pub const prefer_nullish_coalescing = '@typescript-eslint/prefer-nullish-coalescing'
pub const no_unnecessary_condition = '@typescript-eslint/no-unnecessary-condition'
pub const no_for_in_array = '@typescript-eslint/no-for-in-array'
pub const no_array_delete = '@typescript-eslint/no-array-delete'
pub const no_unnecessary_boolean_literal_compare = '@typescript-eslint/no-unnecessary-boolean-literal-compare'
pub const no_unsafe_unary_minus = '@typescript-eslint/no-unsafe-unary-minus'
pub const no_meaningless_void_operator = '@typescript-eslint/no-meaningless-void-operator'
pub const related_getter_setter_pairs = '@typescript-eslint/related-getter-setter-pairs'
pub const non_nullable_type_assertion_style = '@typescript-eslint/non-nullable-type-assertion-style'
pub const prefer_return_this_type = '@typescript-eslint/prefer-return-this-type'
pub const no_duplicate_type_constituents = '@typescript-eslint/no-duplicate-type-constituents'
pub const no_unnecessary_template_expression = '@typescript-eslint/no-unnecessary-template-expression'
pub const dot_notation = '@typescript-eslint/dot-notation'
pub const restrict_plus_operands = '@typescript-eslint/restrict-plus-operands'
pub const no_confusing_void_expression = '@typescript-eslint/no-confusing-void-expression'
pub const no_misused_spread = '@typescript-eslint/no-misused-spread'
pub const no_redundant_type_constituents = '@typescript-eslint/no-redundant-type-constituents'
pub const no_useless_default_assignment = '@typescript-eslint/no-useless-default-assignment'
pub const no_unnecessary_type_arguments = '@typescript-eslint/no-unnecessary-type-arguments'
pub const no_unnecessary_qualifier = '@typescript-eslint/no-unnecessary-qualifier'
pub const no_implied_eval = '@typescript-eslint/no-implied-eval'
pub const no_unnecessary_type_conversion = '@typescript-eslint/no-unnecessary-type-conversion'
pub const no_unnecessary_type_assertion = '@typescript-eslint/no-unnecessary-type-assertion'
pub const no_base_to_string = '@typescript-eslint/no-base-to-string'
pub const no_unsafe_enum_comparison = '@typescript-eslint/no-unsafe-enum-comparison'
pub const no_mixed_enums = '@typescript-eslint/no-mixed-enums'
pub const unbound_method = '@typescript-eslint/unbound-method'
pub const prefer_reduce_type_parameter = '@typescript-eslint/prefer-reduce-type-parameter'
pub const prefer_find = '@typescript-eslint/prefer-find'
pub const prefer_regexp_exec = '@typescript-eslint/prefer-regexp-exec'
pub const prefer_includes = '@typescript-eslint/prefer-includes'
pub const prefer_string_starts_ends_with = '@typescript-eslint/prefer-string-starts-ends-with'
pub const prefer_optional_chain = '@typescript-eslint/prefer-optional-chain'
pub const no_deprecated = '@typescript-eslint/no-deprecated'
pub const prefer_promise_reject_errors = '@typescript-eslint/prefer-promise-reject-errors'
pub const use_unknown_in_catch_callback_variable = '@typescript-eslint/use-unknown-in-catch-callback-variable'
pub const only_throw_error = '@typescript-eslint/only-throw-error'
pub const require_array_sort_compare = '@typescript-eslint/require-array-sort-compare'
pub const no_unsafe_type_assertion = '@typescript-eslint/no-unsafe-type-assertion'
pub const promise_function_async = '@typescript-eslint/promise-function-async'
pub const prefer_readonly_parameter_types = '@typescript-eslint/prefer-readonly-parameter-types'
pub const consistent_type_exports = '@typescript-eslint/consistent-type-exports'
pub const strict_void_return = '@typescript-eslint/strict-void-return'
pub const consistent_return = '@typescript-eslint/consistent-return'
pub const prefer_destructuring = '@typescript-eslint/prefer-destructuring'
pub const prefer_readonly = '@typescript-eslint/prefer-readonly'
pub const strict_boolean_expressions = '@typescript-eslint/strict-boolean-expressions'
pub const no_unnecessary_type_parameters = '@typescript-eslint/no-unnecessary-type-parameters'
pub const naming_convention = '@typescript-eslint/naming-convention'
pub const no_duplicate_enum_values = '@typescript-eslint/no-duplicate-enum-values'
pub const no_extra_non_null_assertion = '@typescript-eslint/no-extra-non-null-assertion'
pub const no_non_null_asserted_optional_chain = '@typescript-eslint/no-non-null-asserted-optional-chain'
pub const no_unsafe_function_type = '@typescript-eslint/no-unsafe-function-type'
pub const no_wrapper_object_types = '@typescript-eslint/no-wrapper-object-types'
pub const prefer_enum_initializers = '@typescript-eslint/prefer-enum-initializers'
pub const no_dynamic_delete = '@typescript-eslint/no-dynamic-delete'
pub const no_namespace = '@typescript-eslint/no-namespace'
pub const no_unnecessary_type_constraint = '@typescript-eslint/no-unnecessary-type-constraint'
pub const prefer_as_const = '@typescript-eslint/prefer-as-const'
pub const no_invalid_void_type = '@typescript-eslint/no-invalid-void-type'
pub const no_this_alias = '@typescript-eslint/no-this-alias'
pub const no_misused_new = '@typescript-eslint/no-misused-new'
pub const no_useless_empty_export = '@typescript-eslint/no-useless-empty-export'
pub const no_extraneous_class = '@typescript-eslint/no-extraneous-class'
pub const adjacent_overload_signatures = '@typescript-eslint/adjacent-overload-signatures'
pub const no_dupe_class_members = '@typescript-eslint/no-dupe-class-members'
pub const class_literal_property_style = '@typescript-eslint/class-literal-property-style'
pub const no_empty_function = '@typescript-eslint/no-empty-function'
pub const no_unused_expressions = '@typescript-eslint/no-unused-expressions'
pub const no_useless_constructor = '@typescript-eslint/no-useless-constructor'
pub const no_array_constructor = '@typescript-eslint/no-array-constructor'
pub const no_confusing_non_null_assertion = '@typescript-eslint/no-confusing-non-null-assertion'
pub const no_import_type_side_effects = '@typescript-eslint/no-import-type-side-effects'
pub const no_inferrable_types = '@typescript-eslint/no-inferrable-types'
pub const prefer_namespace_keyword = '@typescript-eslint/prefer-namespace-keyword'
pub const triple_slash_reference = '@typescript-eslint/triple-slash-reference'
pub const consistent_generic_constructors = '@typescript-eslint/consistent-generic-constructors'
pub const consistent_type_assertions = '@typescript-eslint/consistent-type-assertions'
pub const consistent_type_definitions = '@typescript-eslint/consistent-type-definitions'
pub const prefer_function_type = '@typescript-eslint/prefer-function-type'
pub const unified_signatures = '@typescript-eslint/unified-signatures'
pub const no_unsafe_declaration_merging = '@typescript-eslint/no-unsafe-declaration-merging'
pub const no_require_imports = '@typescript-eslint/no-require-imports'
pub const no_non_null_asserted_nullish_coalescing = '@typescript-eslint/no-non-null-asserted-nullish-coalescing'
pub const prefer_for_of = '@typescript-eslint/prefer-for-of'
pub const array_type = '@typescript-eslint/array-type'
pub const consistent_indexed_object_style = '@typescript-eslint/consistent-indexed-object-style'
pub const no_unnecessary_parameter_property_assignment = '@typescript-eslint/no-unnecessary-parameter-property-assignment'
pub const no_unused_private_class_members = '@typescript-eslint/no-unused-private-class-members'
pub const no_use_before_define = '@typescript-eslint/no-use-before-define'
pub const no_shadow = '@typescript-eslint/no-shadow'
pub const consistent_type_imports = '@typescript-eslint/consistent-type-imports'
pub const no_unused_vars = '@typescript-eslint/no-unused-vars'
pub const seyfert_prefer_typed_group = 'seyfert/prefer-typed-group'
pub const seyfert_autocomplete_respond = 'seyfert/autocomplete-respond'
pub const seyfert_config_default_export = 'seyfert/config-default-export'
pub const seyfert_decorator_target = 'seyfert/decorator-target'
pub const seyfert_decorator_on_command = 'seyfert/decorator-on-command'
pub const seyfert_i18n_resolve_with_get = 'seyfert/i18n-resolve-with-get'
pub const seyfert_no_method_destructure = 'seyfert/no-method-destructure'
pub const seyfert_require_declare = 'seyfert/require-declare'
pub const seyfert_context_menu_declare = 'seyfert/context-menu-declare'
pub const seyfert_required_options_order = 'seyfert/required-options-order'
pub const seyfert_options_use_builders = 'seyfert/options-use-builders'
pub const seyfert_declare_description = 'seyfert/declare-description'
pub const seyfert_no_deep_imports = 'seyfert/no-deep-imports'
pub const seyfert_no_hanging_middleware = 'seyfert/no-hanging-middleware'
pub const seyfert_group_exists = 'seyfert/group-exists'
// ESLint core 10.15.0: a rule id without a plugin.
pub const no_compare_neg_zero = 'no-compare-neg-zero'
pub const use_isnan = 'use-isnan'
pub const valid_typeof = 'valid-typeof'
pub const no_dupe_else_if = 'no-dupe-else-if'
pub const no_duplicate_case = 'no-duplicate-case'
pub const no_self_compare = 'no-self-compare'
pub const no_self_assign = 'no-self-assign'
pub const no_unsafe_negation = 'no-unsafe-negation'
pub const no_unsafe_optional_chaining = 'no-unsafe-optional-chaining'
pub const no_cond_assign = 'no-cond-assign'
pub const for_direction = 'for-direction'
pub const no_constant_condition = 'no-constant-condition'
pub const no_constant_binary_expression = 'no-constant-binary-expression'
pub const curly = 'curly'
pub const no_else_return = 'no-else-return'
pub const no_empty = 'no-empty'
pub const no_empty_static_block = 'no-empty-static-block'
pub const default_case_last = 'default-case-last'
pub const no_case_declarations = 'no-case-declarations'
pub const no_labels = 'no-labels'
pub const no_extra_label = 'no-extra-label'
pub const no_unused_labels = 'no-unused-labels'
pub const no_with = 'no-with'
pub const no_debugger = 'no-debugger'
pub const no_unsafe_finally = 'no-unsafe-finally'
pub const no_useless_catch = 'no-useless-catch'
pub const arrow_body_style = 'arrow-body-style'
pub const prefer_arrow_callback = 'prefer-arrow-callback'
pub const func_name_matching = 'func-name-matching'
pub const func_names = 'func-names'
pub const grouped_accessor_pairs = 'grouped-accessor-pairs'
pub const no_setter_return = 'no-setter-return'
pub const no_dupe_args = 'no-dupe-args'
pub const no_dupe_keys = 'no-dupe-keys'
pub const no_empty_pattern = 'no-empty-pattern'
pub const no_useless_rename = 'no-useless-rename'
pub const no_useless_computed_key = 'no-useless-computed-key'
pub const object_shorthand = 'object-shorthand'
pub const require_yield = 'require-yield'
pub const eqeqeq = 'eqeqeq'
pub const yoda = 'yoda'
pub const no_eq_null = 'no-eq-null'
pub const no_extra_boolean_cast = 'no-extra-boolean-cast'
pub const no_implicit_coercion = 'no-implicit-coercion'
pub const logical_assignment_operators = 'logical-assignment-operators'
pub const operator_assignment = 'operator-assignment'
pub const prefer_exponentiation_operator = 'prefer-exponentiation-operator'
pub const no_sequences = 'no-sequences'
pub const no_return_assign = 'no-return-assign'
pub const no_unexpected_multiline = 'no-unexpected-multiline'
pub const no_loss_of_precision = 'no-loss-of-precision'
pub const no_nonoctal_decimal_escape = 'no-nonoctal-decimal-escape'
pub const no_octal = 'no-octal'
pub const no_octal_escape = 'no-octal-escape'
pub const prefer_numeric_literals = 'prefer-numeric-literals'
pub const no_multi_str = 'no-multi-str'
pub const no_template_curly_in_string = 'no-template-curly-in-string'
pub const no_useless_concat = 'no-useless-concat'
pub const prefer_template = 'prefer-template'
pub const no_irregular_whitespace = 'no-irregular-whitespace'
pub const unicode_bom = 'unicode-bom'
pub const no_sparse_arrays = 'no-sparse-arrays'
pub const no_new = 'no-new'
pub const no_new_func = 'no-new-func'
pub const no_new_wrappers = 'no-new-wrappers'
pub const no_new_native_nonconstructor = 'no-new-native-nonconstructor'
pub const no_obj_calls = 'no-obj-calls'
pub const no_object_constructor = 'no-object-constructor'
pub const no_async_promise_executor = 'no-async-promise-executor'
pub const no_extra_bind = 'no-extra-bind'
pub const no_useless_call = 'no-useless-call'
pub const prefer_spread = 'prefer-spread'
pub const prefer_rest_params = 'prefer-rest-params'
pub const symbol_description = 'symbol-description'
pub const radix_rule = 'radix'
pub const no_extend_native = 'no-extend-native'
pub const core_no_implied_eval = 'no-implied-eval'
pub const no_caller = 'no-caller'
pub const no_iterator = 'no-iterator'
pub const no_proto = 'no-proto'
pub const no_script_url = 'no-script-url'
pub const no_prototype_builtins = 'no-prototype-builtins'
pub const prefer_object_has_own = 'prefer-object-has-own'
pub const prefer_object_spread = 'prefer-object-spread'
pub const core_dot_notation = 'dot-notation'
pub const preserve_caught_error = 'preserve-caught-error'
pub const no_class_assign = 'no-class-assign'
pub const no_const_assign = 'no-const-assign'
pub const no_ex_assign = 'no-ex-assign'
pub const no_func_assign = 'no-func-assign'
pub const no_global_assign = 'no-global-assign'
pub const no_import_assign = 'no-import-assign'
pub const no_label_var = 'no-label-var'
pub const no_shadow_restricted_names = 'no-shadow-restricted-names'
pub const no_unassigned_vars = 'no-unassigned-vars'
pub const no_delete_var = 'no-delete-var'
pub const block_scoped_var = 'block-scoped-var'
pub const consistent_this = 'consistent-this'
pub const no_var = 'no-var'
pub const prefer_const = 'prefer-const'
pub const vars_on_top = 'vars-on-top'
pub const sort_vars = 'sort-vars'
pub const strict_rule = 'strict'
pub const no_inner_declarations = 'no-inner-declarations'
pub const no_lone_blocks = 'no-lone-blocks'
pub const no_loop_func = 'no-loop-func'
pub const no_implicit_globals = 'no-implicit-globals'
pub const no_unmodified_loop_condition = 'no-unmodified-loop-condition'
pub const no_control_regex = 'no-control-regex'
pub const no_div_regex = 'no-div-regex'
pub const no_empty_character_class = 'no-empty-character-class'
pub const no_invalid_regexp = 'no-invalid-regexp'
pub const no_misleading_character_class = 'no-misleading-character-class'
pub const no_regex_spaces = 'no-regex-spaces'
pub const no_useless_backreference = 'no-useless-backreference'
pub const no_useless_escape = 'no-useless-escape'
pub const prefer_regex_literals = 'prefer-regex-literals'
pub const no_warning_comments = 'no-warning-comments'
pub const no_restricted_globals = 'no-restricted-globals'
pub const no_restricted_properties = 'no-restricted-properties'
pub const no_restricted_exports = 'no-restricted-exports'
pub const no_restricted_imports = 'no-restricted-imports'
pub const no_constructor_return = 'no-constructor-return'
pub const no_promise_executor_return = 'no-promise-executor-return'
pub const no_invalid_this = 'no-invalid-this'
pub const getter_return = 'getter-return'
pub const no_unreachable_loop = 'no-unreachable-loop'
pub const no_useless_return = 'no-useless-return'
pub const no_unreachable = 'no-unreachable'
pub const no_fallthrough = 'no-fallthrough'
pub const constructor_super = 'constructor-super'
pub const no_this_before_super = 'no-this-before-super'
pub const no_useless_assignment = 'no-useless-assignment'
pub const no_restricted_syntax = 'no-restricted-syntax'
pub const unicorn_no_lonely_if = 'unicorn/no-lonely-if'
pub const unicorn_no_negated_condition = 'unicorn/no-negated-condition'
pub const unicorn_no_negation_in_equality_check = 'unicorn/no-negation-in-equality-check'
pub const unicorn_no_nested_ternary = 'unicorn/no-nested-ternary'
pub const unicorn_no_typeof_undefined = 'unicorn/no-typeof-undefined'
pub const unicorn_prefer_logical_operator_over_ternary = 'unicorn/prefer-logical-operator-over-ternary'
pub const unicorn_prefer_ternary = 'unicorn/prefer-ternary'
pub const unicorn_prefer_switch = 'unicorn/prefer-switch'
pub const unicorn_switch_case_braces = 'unicorn/switch-case-braces'
pub const unicorn_switch_case_break_position = 'unicorn/switch-case-break-position'
pub const unicorn_no_useless_switch_case = 'unicorn/no-useless-switch-case'
pub const unicorn_prefer_simple_condition_first = 'unicorn/prefer-simple-condition-first'
pub const unicorn_prefer_date_now = 'unicorn/prefer-date-now'
pub const unicorn_throw_new_error = 'unicorn/throw-new-error'
pub const unicorn_error_message = 'unicorn/error-message'
pub const unicorn_consistent_date_clone = 'unicorn/consistent-date-clone'
pub const unicorn_consistent_assert = 'unicorn/consistent-assert'
pub const unicorn_no_new_buffer = 'unicorn/no-new-buffer'
pub const unicorn_prefer_type_error = 'unicorn/prefer-type-error'
pub const unicorn_no_useless_error_capture_stack_trace = 'unicorn/no-useless-error-capture-stack-trace'
pub const unicorn_prefer_structured_clone = 'unicorn/prefer-structured-clone'
pub const unicorn_custom_error_definition = 'unicorn/custom-error-definition'
pub const unicorn_no_instanceof_builtins = 'unicorn/no-instanceof-builtins'
pub const unicorn_new_for_builtins = 'unicorn/new-for-builtins'
pub const unicorn_no_hex_escape = 'unicorn/no-hex-escape'
pub const unicorn_escape_case = 'unicorn/escape-case'
pub const unicorn_consistent_template_literal_escape = 'unicorn/consistent-template-literal-escape'
pub const unicorn_prefer_string_trim_start_end = 'unicorn/prefer-string-trim-start-end'
pub const unicorn_no_console_spaces = 'unicorn/no-console-spaces'
pub const unicorn_prefer_code_point = 'unicorn/prefer-code-point'
pub const unicorn_prefer_string_slice = 'unicorn/prefer-string-slice'
pub const unicorn_text_encoding_identifier_case = 'unicorn/text-encoding-identifier-case'
pub const unicorn_no_zero_fractions = 'unicorn/no-zero-fractions'
pub const unicorn_prefer_bigint_literals = 'unicorn/prefer-bigint-literals'
pub const unicorn_prefer_number_properties = 'unicorn/prefer-number-properties'
pub const unicorn_prefer_string_raw = 'unicorn/prefer-string-raw'
pub const unicorn_prefer_string_replace_all = 'unicorn/prefer-string-replace-all'
pub const unicorn_require_number_to_fixed_digits_argument = 'unicorn/require-number-to-fixed-digits-argument'
pub const unicorn_prefer_math_trunc = 'unicorn/prefer-math-trunc'
pub const unicorn_prefer_math_min_max = 'unicorn/prefer-math-min-max'
pub const unicorn_prefer_modern_math_apis = 'unicorn/prefer-modern-math-apis'
pub const unicorn_prefer_native_coercion_functions = 'unicorn/prefer-native-coercion-functions'
pub const unicorn_no_array_callback_reference = 'unicorn/no-array-callback-reference'
pub const unicorn_no_for_each = 'unicorn/no-for-each'
pub const unicorn_no_array_method_this_argument = 'unicorn/no-array-method-this-argument'
pub const unicorn_no_array_reverse = 'unicorn/no-array-reverse'
pub const unicorn_no_array_sort = 'unicorn/no-array-sort'
pub const unicorn_no_new_array = 'unicorn/no-new-array'
pub const unicorn_prefer_array_flat = 'unicorn/prefer-array-flat'
pub const unicorn_prefer_array_flat_map = 'unicorn/prefer-array-flat-map'
pub const unicorn_prefer_array_index_of = 'unicorn/prefer-array-index-of'
pub const unicorn_prefer_array_some = 'unicorn/prefer-array-some'
pub const unicorn_require_array_join_separator = 'unicorn/require-array-join-separator'
pub const unicorn_prefer_negative_index = 'unicorn/prefer-negative-index'
pub const unicorn_consistent_existence_index_check = 'unicorn/consistent-existence-index-check'
pub const unicorn_explicit_length_check = 'unicorn/explicit-length-check'
pub const unicorn_no_unnecessary_array_flat_depth = 'unicorn/no-unnecessary-array-flat-depth'
pub const unicorn_no_unnecessary_array_splice_count = 'unicorn/no-unnecessary-array-splice-count'
pub const unicorn_no_unnecessary_slice_end = 'unicorn/no-unnecessary-slice-end'
pub const unicorn_no_useless_length_check = 'unicorn/no-useless-length-check'
pub const unicorn_no_unreadable_array_destructuring = 'unicorn/no-unreadable-array-destructuring'
pub const unicorn_prefer_set_size = 'unicorn/prefer-set-size'
pub const array_callback_return = 'array-callback-return'
pub const no_lonely_if = 'no-lonely-if'
pub const no_negated_condition = 'no-negated-condition'
pub const no_throw_literal = 'no-throw-literal'
pub const require_atomic_updates = 'require-atomic-updates'
pub const class_methods_use_this = '@typescript-eslint/class-methods-use-this'
pub const no_explicit_any = '@typescript-eslint/no-explicit-any'
pub const unicorn_consistent_empty_array_spread = 'unicorn/consistent-empty-array-spread'
pub const unicorn_no_useless_fallback_in_spread = 'unicorn/no-useless-fallback-in-spread'
pub const unicorn_no_useless_collection_argument = 'unicorn/no-useless-collection-argument'
pub const unicorn_no_useless_iterator_to_array = 'unicorn/no-useless-iterator-to-array'
pub const unicorn_no_useless_spread = 'unicorn/no-useless-spread'
pub const unicorn_prefer_single_call = 'unicorn/prefer-single-call'
pub const unicorn_no_immediate_mutation = 'unicorn/no-immediate-mutation'
pub const unicorn_prefer_blob_reading_methods = 'unicorn/prefer-blob-reading-methods'
pub const unicorn_prefer_response_static_json = 'unicorn/prefer-response-static-json'
pub const unicorn_no_await_expression_member = 'unicorn/no-await-expression-member'
pub const unicorn_prefer_spread = 'unicorn/prefer-spread'
pub const unicorn_no_await_in_promise_methods = 'unicorn/no-await-in-promise-methods'
pub const unicorn_no_invalid_fetch_options = 'unicorn/no-invalid-fetch-options'
pub const unicorn_no_unnecessary_await = 'unicorn/no-unnecessary-await'
pub const unicorn_no_thenable = 'unicorn/no-thenable'
pub const unicorn_no_single_promise_in_promise_methods = 'unicorn/no-single-promise-in-promise-methods'
pub const unicorn_no_useless_promise_resolve_reject = 'unicorn/no-useless-promise-resolve-reject'
pub const unicorn_prefer_node_protocol = 'unicorn/prefer-node-protocol'
pub const unicorn_no_process_exit = 'unicorn/no-process-exit'
pub const unicorn_no_named_default = 'unicorn/no-named-default'
pub const unicorn_require_module_attributes = 'unicorn/require-module-attributes'
pub const unicorn_require_module_specifiers = 'unicorn/require-module-specifiers'
pub const unicorn_prefer_json_parse_buffer = 'unicorn/prefer-json-parse-buffer'
pub const unicorn_no_anonymous_default_export = 'unicorn/no-anonymous-default-export'
pub const unicorn_prefer_import_meta_properties = 'unicorn/prefer-import-meta-properties'
pub const unicorn_prefer_module = 'unicorn/prefer-module'
pub const unicorn_prefer_reflect_apply = 'unicorn/prefer-reflect-apply'
pub const unicorn_prefer_export_from = 'unicorn/prefer-export-from'
pub const unicorn_relative_url_style = 'unicorn/relative-url-style'
pub const unicorn_prefer_prototype_methods = 'unicorn/prefer-prototype-methods'
pub const unicorn_better_regex = 'unicorn/better-regex'
pub const unicorn_no_this_assignment = 'unicorn/no-this-assignment'
pub const unicorn_no_unreadable_iife = 'unicorn/no-unreadable-iife'
pub const unicorn_no_accessor_recursion = 'unicorn/no-accessor-recursion'
pub const unicorn_no_static_only_class = 'unicorn/no-static-only-class'
pub const unicorn_prefer_class_fields = 'unicorn/prefer-class-fields'
pub const unicorn_consistent_function_scoping = 'unicorn/consistent-function-scoping'
pub const unicorn_isolated_functions = 'unicorn/isolated-functions'
pub const unicorn_no_useless_undefined = 'unicorn/no-useless-undefined'
pub const unicorn_no_keyword_prefix = 'unicorn/no-keyword-prefix'
pub const unicorn_prefer_object_from_entries = 'unicorn/prefer-object-from-entries'
pub const unicorn_prefer_default_parameters = 'unicorn/prefer-default-parameters'
pub const unicorn_no_unused_properties = 'unicorn/no-unused-properties'
pub const stylistic_array_bracket_spacing = '@stylistic/array-bracket-spacing'
pub const stylistic_rest_spread_spacing = '@stylistic/rest-spread-spacing'
pub const stylistic_semi_spacing = '@stylistic/semi-spacing'
pub const stylistic_space_in_parens = '@stylistic/space-in-parens'
pub const stylistic_switch_colon_spacing = '@stylistic/switch-colon-spacing'
pub const stylistic_template_curly_spacing = '@stylistic/template-curly-spacing'
pub const stylistic_template_tag_spacing = '@stylistic/template-tag-spacing'
pub const stylistic_no_whitespace_before_property = '@stylistic/no-whitespace-before-property'
pub const stylistic_block_spacing = '@stylistic/block-spacing'
pub const stylistic_comma_spacing = '@stylistic/comma-spacing'
pub const stylistic_computed_property_spacing = '@stylistic/computed-property-spacing'
pub const stylistic_object_curly_spacing = '@stylistic/object-curly-spacing'
pub const stylistic_keyword_spacing = '@stylistic/keyword-spacing'
pub const stylistic_space_before_blocks = '@stylistic/space-before-blocks'
pub const stylistic_arrow_spacing = '@stylistic/arrow-spacing'
pub const stylistic_yield_star_spacing = '@stylistic/yield-star-spacing'
pub const stylistic_type_annotation_spacing = '@stylistic/type-annotation-spacing'
pub const stylistic_type_generic_spacing = '@stylistic/type-generic-spacing'
pub const stylistic_type_named_tuple_spacing = '@stylistic/type-named-tuple-spacing'
pub const stylistic_space_before_function_paren = '@stylistic/space-before-function-paren'
pub const stylistic_key_spacing = '@stylistic/key-spacing'
pub const stylistic_space_infix_ops = '@stylistic/space-infix-ops'
pub const stylistic_space_unary_ops = '@stylistic/space-unary-ops'
pub const stylistic_function_call_spacing = '@stylistic/function-call-spacing'
pub const stylistic_brace_style = '@stylistic/brace-style'
pub const stylistic_comma_style = '@stylistic/comma-style'
pub const stylistic_dot_location = '@stylistic/dot-location'
pub const stylistic_function_call_argument_newline = '@stylistic/function-call-argument-newline'
pub const stylistic_function_paren_newline = '@stylistic/function-paren-newline'
pub const stylistic_implicit_arrow_linebreak = '@stylistic/implicit-arrow-linebreak'
pub const stylistic_multiline_ternary = '@stylistic/multiline-ternary'
pub const stylistic_nonblock_statement_body_position = '@stylistic/nonblock-statement-body-position'
pub const stylistic_one_var_declaration_per_line = '@stylistic/one-var-declaration-per-line'
pub const stylistic_quotes = '@stylistic/quotes'
pub const stylistic_no_multi_spaces = '@stylistic/no-multi-spaces'
pub const stylistic_no_trailing_spaces = '@stylistic/no-trailing-spaces'
pub const stylistic_no_mixed_spaces_and_tabs = '@stylistic/no-mixed-spaces-and-tabs'
pub const stylistic_eol_last = '@stylistic/eol-last'
pub const stylistic_spaced_comment = '@stylistic/spaced-comment'
pub const stylistic_lines_between_class_members = '@stylistic/lines-between-class-members'
pub const stylistic_new_parens = '@stylistic/new-parens'
pub const stylistic_no_floating_decimal = '@stylistic/no-floating-decimal'
pub const stylistic_no_extra_semi = '@stylistic/no-extra-semi'
pub const stylistic_semi_style = '@stylistic/semi-style'
pub const stylistic_semi = '@stylistic/semi'
pub const stylistic_object_curly_newline = '@stylistic/object-curly-newline'
pub const stylistic_object_property_newline = '@stylistic/object-property-newline'
pub const stylistic_list_style = '@stylistic/list-style'
pub const stylistic_exp_jsx_props_style = '@stylistic/exp-jsx-props-style'
pub const stylistic_arrow_parens = '@stylistic/arrow-parens'
pub const stylistic_comma_dangle = '@stylistic/comma-dangle'
pub const stylistic_member_delimiter_style = '@stylistic/member-delimiter-style'
pub const stylistic_quote_props = '@stylistic/quote-props'
pub const stylistic_no_extra_parens = '@stylistic/no-extra-parens'
pub const marcrock_no_newline_if_body_class_empty = 'marcrock/no-newline-if-body-class-empty'
pub const marcrock_numeric_separators = 'marcrock/numeric-separators'
pub const marcrock_uppercase_first_class_letter = 'marcrock/uppercase-first-class-letter'
pub const marcrock_prefer_at = 'marcrock/prefer-at'
pub const perfectionist_sort_array_includes = 'perfectionist/sort-array-includes'
pub const perfectionist_sort_sets = 'perfectionist/sort-sets'
pub const perfectionist_sort_maps = 'perfectionist/sort-maps'
pub const perfectionist_sort_union_types = 'perfectionist/sort-union-types'
pub const perfectionist_sort_intersection_types = 'perfectionist/sort-intersection-types'
pub const ban_ts_comment = '@typescript-eslint/ban-ts-comment'
pub const ban_tslint_comment = '@typescript-eslint/ban-tslint-comment'
pub const default_param_last = '@typescript-eslint/default-param-last'
pub const init_declarations = '@typescript-eslint/init-declarations'
pub const max_params = '@typescript-eslint/max-params'
pub const method_signature_style = '@typescript-eslint/method-signature-style'
pub const no_empty_object_type = '@typescript-eslint/no-empty-object-type'
pub const no_non_null_assertion = '@typescript-eslint/no-non-null-assertion'
pub const ts_no_invalid_this = '@typescript-eslint/no-invalid-this'
pub const no_redeclare = '@typescript-eslint/no-redeclare'
pub const perfectionist_sort_heritage_clauses = 'perfectionist/sort-heritage-clauses'
pub const perfectionist_sort_import_attributes = 'perfectionist/sort-import-attributes'
pub const perfectionist_sort_export_attributes = 'perfectionist/sort-export-attributes'
pub const perfectionist_sort_switch_case = 'perfectionist/sort-switch-case'
pub const perfectionist_sort_named_imports = 'perfectionist/sort-named-imports'
pub const perfectionist_sort_named_exports = 'perfectionist/sort-named-exports'
pub const perfectionist_sort_exports = 'perfectionist/sort-exports'
pub const explicit_function_return_type = '@typescript-eslint/explicit-function-return-type'
pub const explicit_module_boundary_types = '@typescript-eslint/explicit-module-boundary-types'
pub const explicit_member_accessibility = '@typescript-eslint/explicit-member-accessibility'
pub const parameter_properties = '@typescript-eslint/parameter-properties'
pub const prefer_literal_enum_member = '@typescript-eslint/prefer-literal-enum-member'
pub const no_magic_numbers = '@typescript-eslint/no-magic-numbers'
pub const no_restricted_types = '@typescript-eslint/no-restricted-types'
pub const no_generated_empty_object_type = '@typescript-eslint/no-generated-empty-object-type'
pub const no_unsafe_enum_assignment = '@typescript-eslint/no-unsafe-enum-assignment'
pub const member_ordering = '@typescript-eslint/member-ordering'
pub const perfectionist_sort_classes = 'perfectionist/sort-classes'
pub const perfectionist_sort_imports = 'perfectionist/sort-imports'
pub const vue_no_v_html = 'vue/no-v-html'
pub const vue_no_v_text = 'vue/no-v-text'
pub const vue_no_duplicate_attributes = 'vue/no-duplicate-attributes'
pub const vue_comment_directive = 'vue/comment-directive'
pub const vue_no_parsing_error = 'vue/no-parsing-error'
pub const vue_no_deprecated_v_is = 'vue/no-deprecated-v-is'
pub const vue_no_deprecated_scope_attribute = 'vue/no-deprecated-scope-attribute'
pub const vue_no_deprecated_filter = 'vue/no-deprecated-filter'
pub const vue_no_deprecated_inline_template = 'vue/no-deprecated-inline-template'
pub const vue_require_component_is = 'vue/require-component-is'
pub const vue_no_deprecated_v_on_native_modifier = 'vue/no-deprecated-v-on-native-modifier'
pub const vue_no_v_model_argument = 'vue/no-v-model-argument'
pub const vue_no_textarea_mustache = 'vue/no-textarea-mustache'
pub const vue_no_use_v_else_with_v_for = 'vue/no-use-v-else-with-v-for'
pub const vue_no_v_for_template_key = 'vue/no-v-for-template-key'
pub const vue_no_template_key = 'vue/no-template-key'
pub const vue_no_custom_modifiers_on_v_model = 'vue/no-custom-modifiers-on-v-model'
pub const vue_no_deprecated_v_bind_sync = 'vue/no-deprecated-v-bind-sync'
pub const vue_no_spaces_around_equal_signs_in_attribute = 'vue/no-spaces-around-equal-signs-in-attribute'
pub const vue_no_deprecated_v_on_number_modifiers = 'vue/no-deprecated-v-on-number-modifiers'
pub const vue_valid_v_bind = 'vue/valid-v-bind'
pub const vue_valid_v_cloak = 'vue/valid-v-cloak'
pub const vue_valid_v_html = 'vue/valid-v-html'
pub const vue_valid_v_once = 'vue/valid-v-once'
pub const vue_valid_v_pre = 'vue/valid-v-pre'
pub const vue_valid_v_text = 'vue/valid-v-text'
pub const vue_valid_v_show = 'vue/valid-v-show'
pub const vue_valid_v_if = 'vue/valid-v-if'
pub const vue_valid_v_else_if = 'vue/valid-v-else-if'
pub const vue_valid_v_else = 'vue/valid-v-else'
pub const vue_valid_v_is = 'vue/valid-v-is'
pub const vue_valid_v_on = 'vue/valid-v-on'
pub const vue_v_on_style = 'vue/v-on-style'
pub const vue_v_bind_style = 'vue/v-bind-style'
pub const vue_no_multiple_objects_in_class = 'vue/no-multiple-objects-in-class'
pub const vue_require_v_for_key = 'vue/require-v-for-key'
pub const vue_no_deprecated_html_element_is = 'vue/no-deprecated-html-element-is'
pub const vue_no_use_v_if_with_v_for = 'vue/no-use-v-if-with-v-for'
pub const vue_no_v_for_template_key_on_child = 'vue/no-v-for-template-key-on-child'
pub const vue_html_end_tags = 'vue/html-end-tags'
pub const vue_valid_attribute_name = 'vue/valid-attribute-name'
pub const vue_v_for_delimiter_style = 'vue/v-for-delimiter-style'
pub const vue_no_v_text_v_html_on_component = 'vue/no-v-text-v-html-on-component'
pub const vue_no_lone_template = 'vue/no-lone-template'
pub const vue_html_button_has_type = 'vue/html-button-has-type'
pub const vue_no_deprecated_router_link_tag_prop = 'vue/no-deprecated-router-link-tag-prop'
pub const vue_no_restricted_html_elements = 'vue/no-restricted-html-elements'
pub const vue_no_useless_template_attributes = 'vue/no-useless-template-attributes'
pub const vue_mustache_interpolation_spacing = 'vue/mustache-interpolation-spacing'
pub const vue_static_class_names_order = 'vue/static-class-names-order'
pub const vue_restricted_component_names = 'vue/restricted-component-names'
pub const vue_slot_name_casing = 'vue/slot-name-casing'
pub const vue_first_attribute_linebreak = 'vue/first-attribute-linebreak'
pub const vue_html_quotes = 'vue/html-quotes'
pub const vue_no_literals_in_template = 'vue/no-literals-in-template'
pub const vue_require_toggle_inside_transition = 'vue/require-toggle-inside-transition'
pub const vue_no_restricted_static_attribute = 'vue/no-restricted-static-attribute'
pub const vue_html_closing_bracket_spacing = 'vue/html-closing-bracket-spacing'
pub const vue_html_closing_bracket_newline = 'vue/html-closing-bracket-newline'
pub const vue_attribute_hyphenation = 'vue/attribute-hyphenation'
pub const vue_v_on_event_hyphenation = 'vue/v-on-event-hyphenation'
pub const vue_valid_v_memo = 'vue/valid-v-memo'
pub const vue_no_static_inline_styles = 'vue/no-static-inline-styles'
pub const vue_no_child_content = 'vue/no-child-content'
pub const vue_no_template_target_blank = 'vue/no-template-target-blank'
pub const vue_no_restricted_class = 'vue/no-restricted-class'
pub const vue_no_useless_v_bind = 'vue/no-useless-v-bind'
pub const vue_no_restricted_v_bind = 'vue/no-restricted-v-bind'
pub const vue_no_restricted_v_on = 'vue/no-restricted-v-on'
pub const vue_valid_v_bind_sync = 'vue/valid-v-bind-sync'
pub const vue_v_slot_style = 'vue/v-slot-style'
pub const vue_prefer_true_attribute_shorthand = 'vue/prefer-true-attribute-shorthand'
pub const vue_no_dupe_v_else_if = 'vue/no-dupe-v-else-if'
pub const vue_no_deprecated_slot_attribute = 'vue/no-deprecated-slot-attribute'
pub const vue_no_deprecated_slot_scope_attribute = 'vue/no-deprecated-slot-scope-attribute'
pub const vue_this_in_template = 'vue/this-in-template'
pub const vue_no_unused_vars = 'vue/no-unused-vars'
pub const vue_no_define_model_default = 'vue/no-define-model-default'
pub const vue_no_deprecated_functional_template = 'vue/no-deprecated-functional-template'
pub const vue_require_render_return = 'vue/require-render-return'
pub const vue_no_deprecated_vue_config_keycodes = 'vue/no-deprecated-vue-config-keycodes'
pub const vue_no_root_v_if = 'vue/no-root-v-if'
pub const vue_no_arrow_functions_in_watch = 'vue/no-arrow-functions-in-watch'
pub const vue_one_component_per_file = 'vue/one-component-per-file'
pub const vue_valid_model_definition = 'vue/valid-model-definition'
pub const vue_no_deprecated_events_api = 'vue/no-deprecated-events-api'
pub const vue_define_props_declaration = 'vue/define-props-declaration'
pub const vue_valid_template_root = 'vue/valid-template-root'
pub const vue_no_export_in_script_setup = 'vue/no-export-in-script-setup'
pub const vue_require_default_export = 'vue/require-default-export'
pub const vue_jsx_uses_vars = 'vue/jsx-uses-vars'
pub const vue_match_component_import_name = 'vue/match-component-import-name'
pub const vue_no_deprecated_destroyed_lifecycle = 'vue/no-deprecated-destroyed-lifecycle'
pub const vue_max_template_depth = 'vue/max-template-depth'
pub const vue_no_reserved_props = 'vue/no-reserved-props'
pub const vue_no_this_in_before_route_enter = 'vue/no-this-in-before-route-enter'
pub const vue_max_props = 'vue/max-props'
pub const vue_no_content_outside_block = 'vue/no-content-outside-block'
pub const vue_no_shared_component_data = 'vue/no-shared-component-data'
pub const vue_no_deprecated_data_object_declaration = 'vue/no-deprecated-data-object-declaration'
pub const vue_prop_name_casing = 'vue/prop-name-casing'
pub const vue_define_props_destructuring = 'vue/define-props-destructuring'
pub const vue_component_definition_name_casing = 'vue/component-definition-name-casing'
pub const vue_require_emit_validator = 'vue/require-emit-validator'
pub const vue_no_computed_properties_in_data = 'vue/no-computed-properties-in-data'
pub const vue_no_empty_component_block = 'vue/no-empty-component-block'
pub const vue_no_import_compiler_macros = 'vue/no-import-compiler-macros'
pub const vue_prefer_prop_type_boolean_first = 'vue/prefer-prop-type-boolean-first'
pub const vue_require_macro_variable_name = 'vue/require-macro-variable-name'
pub const vue_define_emits_declaration = 'vue/define-emits-declaration'
pub const vue_no_props_shadow = 'vue/no-props-shadow'
pub const vue_require_prop_type_constructor = 'vue/require-prop-type-constructor'
pub const vue_no_restricted_block = 'vue/no-restricted-block'
pub const vue_component_options_name_casing = 'vue/component-options-name-casing'
pub const vue_max_lines_per_block = 'vue/max-lines-per-block'
pub const vue_no_multiple_slot_args = 'vue/no-multiple-slot-args'
pub const vue_no_reserved_keys = 'vue/no-reserved-keys'
pub const vue_no_deprecated_delete_set = 'vue/no-deprecated-delete-set'
pub const vue_require_prop_types = 'vue/require-prop-types'
pub const vue_return_in_computed_property = 'vue/return-in-computed-property'
pub const vue_no_deprecated_props_default_this = 'vue/no-deprecated-props-default-this'
pub const vue_require_slots_as_functions = 'vue/require-slots-as-functions'
pub const vue_require_name_property = 'vue/require-name-property'
pub const vue_arrow_spacing = 'vue/arrow-spacing'
pub const vue_camelcase = 'vue/camelcase'
pub const vue_comma_dangle = 'vue/comma-dangle'
pub const vue_dot_location = 'vue/dot-location'
pub const vue_no_empty_pattern = 'vue/no-empty-pattern'
pub const vue_no_sparse_arrays = 'vue/no-sparse-arrays'
pub const vue_operator_linebreak = 'vue/operator-linebreak'
pub const vue_array_bracket_newline = 'vue/array-bracket-newline'
pub const vue_array_bracket_spacing = 'vue/array-bracket-spacing'
pub const vue_array_element_newline = 'vue/array-element-newline'
pub const vue_block_spacing = 'vue/block-spacing'
pub const vue_brace_style = 'vue/brace-style'
pub const vue_dot_notation = 'vue/dot-notation'
pub const vue_eqeqeq = 'vue/eqeqeq'
pub const vue_key_spacing = 'vue/key-spacing'
pub const vue_keyword_spacing = 'vue/keyword-spacing'
pub const vue_no_restricted_syntax = 'vue/no-restricted-syntax'
pub const vue_no_useless_concat = 'vue/no-useless-concat'
pub const vue_object_curly_newline = 'vue/object-curly-newline'
pub const vue_object_curly_spacing = 'vue/object-curly-spacing'
pub const vue_object_property_newline = 'vue/object-property-newline'
pub const vue_prefer_template = 'vue/prefer-template'
pub const vue_no_implicit_coercion = 'vue/no-implicit-coercion'
pub const vue_no_loss_of_precision = 'vue/no-loss-of-precision'
pub const vue_no_negated_condition = 'vue/no-negated-condition'
pub const vue_object_shorthand = 'vue/object-shorthand'
pub const vue_space_infix_ops = 'vue/space-infix-ops'
pub const vue_space_unary_ops = 'vue/space-unary-ops'
pub const vue_template_curly_spacing = 'vue/template-curly-spacing'
pub const vue_comma_spacing = 'vue/comma-spacing'
pub const vue_multiline_ternary = 'vue/multiline-ternary'
pub const vue_space_in_parens = 'vue/space-in-parens'
pub const vue_func_call_spacing = 'vue/func-call-spacing'
pub const vue_comma_style = 'vue/comma-style'
pub const vue_no_constant_condition = 'vue/no-constant-condition'
pub const vue_no_console = 'vue/no-console'
pub const vue_quote_props = 'vue/quote-props'
pub const vue_no_extra_parens = 'vue/no-extra-parens'
pub const vue_max_attributes_per_line = 'vue/max-attributes-per-line'
pub const vue_no_useless_mustaches = 'vue/no-useless-mustaches'
pub const vue_no_negated_v_if_condition = 'vue/no-negated-v-if-condition'
pub const vue_use_v_on_exact = 'vue/use-v-on-exact'
pub const vue_prefer_v_model = 'vue/prefer-v-model'
pub const vue_singleline_html_element_content_newline = 'vue/singleline-html-element-content-newline'
pub const vue_multiline_html_element_content_newline = 'vue/multiline-html-element-content-newline'
pub const vue_html_self_closing = 'vue/html-self-closing'
pub const vue_padding_line_between_blocks = 'vue/padding-line-between-blocks'
pub const vue_padding_line_between_tags = 'vue/padding-line-between-tags'
pub const vue_block_tag_newline = 'vue/block-tag-newline'
pub const vue_block_lang = 'vue/block-lang'
pub const vue_no_bare_strings_in_template = 'vue/no-bare-strings-in-template'
pub const vue_v_if_else_key = 'vue/v-if-else-key'
pub const vue_no_irregular_whitespace = 'vue/no-irregular-whitespace'
pub const vue_valid_v_for = 'vue/valid-v-for'
pub const vue_valid_v_model = 'vue/valid-v-model'
pub const vue_valid_v_slot = 'vue/valid-v-slot'
pub const vue_no_unsupported_features = 'vue/no-unsupported-features'
pub const vue_prefer_separate_static_class = 'vue/prefer-separate-static-class'
pub const vue_no_duplicate_class_names = 'vue/no-duplicate-class-names'
pub const vue_max_len = 'vue/max-len'
pub const vue_attributes_order = 'vue/attributes-order'
pub const vue_no_deprecated_dollar_listeners_api = 'vue/no-deprecated-dollar-listeners-api'
pub const vue_no_deprecated_dollar_scopedslots_api = 'vue/no-deprecated-dollar-scopedslots-api'
pub const vue_prefer_use_template_ref = 'vue/prefer-use-template-ref'
pub const vue_no_duplicate_attr_inheritance = 'vue/no-duplicate-attr-inheritance'
pub const vue_no_unused_components = 'vue/no-unused-components'
pub const vue_no_template_shadow = 'vue/no-template-shadow'
pub const vue_require_explicit_slots = 'vue/require-explicit-slots'
pub const vue_no_undef_directives = 'vue/no-undef-directives'
pub const vue_component_name_in_template_casing = 'vue/component-name-in-template-casing'
pub const vue_no_unused_refs = 'vue/no-unused-refs'
pub const vue_custom_event_name_casing = 'vue/custom-event-name-casing'
pub const vue_no_restricted_custom_event = 'vue/no-restricted-custom-event'
pub const vue_no_unused_emit_declarations = 'vue/no-unused-emit-declarations'
pub const vue_prefer_single_event_payload = 'vue/prefer-single-event-payload'
pub const vue_no_shadow_native_events = 'vue/no-shadow-native-events'
pub const vue_require_explicit_emits = 'vue/require-explicit-emits'
pub const vue_no_undef_components = 'vue/no-undef-components'
pub const vue_v_on_handler_style = 'vue/v-on-handler-style'
pub const vue_no_mutating_props = 'vue/no-mutating-props'
pub const vue_no_use_computed_property_like_method = 'vue/no-use-computed-property-like-method'
pub const vue_no_unused_properties = 'vue/no-unused-properties'
pub const vue_no_undef_properties = 'vue/no-undef-properties'
pub const vue_prefer_define_options = 'vue/prefer-define-options'
pub const vue_multi_word_component_names = 'vue/multi-word-component-names'
pub const vue_no_multiple_template_root = 'vue/no-multiple-template-root'
pub const vue_no_potential_component_option_typo = 'vue/no-potential-component-option-typo'
pub const vue_no_deprecated_model_definition = 'vue/no-deprecated-model-definition'
pub const vue_match_component_file_name = 'vue/match-component-file-name'
pub const vue_enforce_style_attribute = 'vue/enforce-style-attribute'
pub const vue_require_direct_export = 'vue/require-direct-export'
pub const vue_no_restricted_component_names = 'vue/no-restricted-component-names'
pub const vue_no_restricted_component_options = 'vue/no-restricted-component-options'
pub const vue_prefer_import_from_vue = 'vue/prefer-import-from-vue'
pub const vue_new_line_between_multi_line_property = 'vue/new-line-between-multi-line-property'
pub const vue_component_api_style = 'vue/component-api-style'
pub const vue_no_reserved_component_names = 'vue/no-reserved-component-names'
pub const vue_require_typed_object_prop = 'vue/require-typed-object-prop'
pub const vue_return_in_emits_validator = 'vue/return-in-emits-validator'
pub const vue_valid_define_props = 'vue/valid-define-props'
pub const vue_valid_define_emits = 'vue/valid-define-emits'
pub const vue_valid_define_options = 'vue/valid-define-options'
pub const vue_require_prop_comment = 'vue/require-prop-comment'
pub const vue_define_macros_order = 'vue/define-macros-order'
pub const vue_order_in_components = 'vue/order-in-components'
pub const vue_padding_lines_in_component_definition = 'vue/padding-lines-in-component-definition'
pub const vue_sort_keys = 'vue/sort-keys'
pub const vue_html_comment_content_spacing = 'vue/html-comment-content-spacing'
pub const vue_html_comment_content_newline = 'vue/html-comment-content-newline'
pub const vue_html_comment_indent = 'vue/html-comment-indent'
pub const vue_no_multi_spaces = 'vue/no-multi-spaces'
pub const vue_block_order = 'vue/block-order'
pub const vue_no_lifecycle_after_await = 'vue/no-lifecycle-after-await'
pub const vue_no_watch_after_await = 'vue/no-watch-after-await'
pub const vue_no_expose_after_await = 'vue/no-expose-after-await'
pub const vue_no_restricted_call_after_await = 'vue/no-restricted-call-after-await'
pub const vue_next_tick_style = 'vue/next-tick-style'
pub const vue_valid_next_tick = 'vue/valid-next-tick'
pub const vue_no_boolean_default = 'vue/no-boolean-default'
pub const vue_no_required_prop_with_default = 'vue/no-required-prop-with-default'
pub const vue_require_default_prop = 'vue/require-default-prop'
pub const vue_require_valid_default_prop = 'vue/require-valid-default-prop'
pub const vue_no_restricted_props = 'vue/no-restricted-props'
pub const vue_require_typed_ref = 'vue/require-typed-ref'
pub const vue_no_ref_as_operand = 'vue/no-ref-as-operand'
pub const vue_no_ref_object_reactivity_loss = 'vue/no-ref-object-reactivity-loss'
pub const vue_no_setup_props_reactivity_loss = 'vue/no-setup-props-reactivity-loss'
pub const vue_require_expose = 'vue/require-expose'
pub const vue_no_side_effects_in_computed_properties = 'vue/no-side-effects-in-computed-properties'
pub const vue_no_async_in_computed_properties = 'vue/no-async-in-computed-properties'
pub const vue_no_dupe_keys = 'vue/no-dupe-keys'
pub const svelte_comment_directive = 'svelte/comment-directive'
pub const svelte_system = 'svelte/system'
pub const svelte_no_at_html_tags = 'svelte/no-at-html-tags'
pub const svelte_no_at_debug_tags = 'svelte/no-at-debug-tags'
pub const svelte_button_has_type = 'svelte/button-has-type'
pub const svelte_no_target_blank = 'svelte/no-target-blank'
pub const svelte_require_each_key = 'svelte/require-each-key'
pub const svelte_valid_each_key = 'svelte/valid-each-key'
pub const svelte_no_object_in_text_mustaches = 'svelte/no-object-in-text-mustaches'
pub const svelte_shorthand_attribute = 'svelte/shorthand-attribute'
pub const svelte_no_spaces_around_equal_signs_in_attribute = 'svelte/no-spaces-around-equal-signs-in-attribute'
pub const svelte_spaced_html_comment = 'svelte/spaced-html-comment'
pub const svelte_no_dupe_else_if_blocks = 'svelte/no-dupe-else-if-blocks'
pub const svelte_no_useless_mustaches = 'svelte/no-useless-mustaches'
pub const svelte_first_attribute_linebreak = 'svelte/first-attribute-linebreak'
pub const svelte_shorthand_directive = 'svelte/shorthand-directive'
pub const svelte_html_closing_bracket_spacing = 'svelte/html-closing-bracket-spacing'
pub const svelte_html_closing_bracket_new_line = 'svelte/html-closing-bracket-new-line'
pub const svelte_no_dynamic_slot_name = 'svelte/no-dynamic-slot-name'
pub const svelte_html_quotes = 'svelte/html-quotes'
pub const svelte_mustache_spacing = 'svelte/mustache-spacing'
pub const svelte_no_inline_styles = 'svelte/no-inline-styles'
pub const svelte_no_raw_special_elements = 'svelte/no-raw-special-elements'
pub const svelte_no_nested_style_tag = 'svelte/no-nested-style-tag'
pub const svelte_no_useless_children_snippet = 'svelte/no-useless-children-snippet'
pub const svelte_no_dupe_on_directives = 'svelte/no-dupe-on-directives'
pub const svelte_no_dupe_use_directives = 'svelte/no-dupe-use-directives'
pub const svelte_prefer_attribute_interpolation = 'svelte/prefer-attribute-interpolation'
pub const svelte_max_attributes_per_line = 'svelte/max-attributes-per-line'
pub const svelte_html_self_closing = 'svelte/html-self-closing'
pub const svelte_no_at_const_tags = 'svelte/no-at-const-tags'
pub const svelte_no_not_function_handler = 'svelte/no-not-function-handler'
pub const svelte_block_lang = 'svelte/block-lang'
pub const svelte_prefer_class_directive = 'svelte/prefer-class-directive'
pub const svelte_no_svelte_internal = 'svelte/no-svelte-internal'
pub const svelte_no_inspect = 'svelte/no-inspect'
pub const svelte_no_store_async = 'svelte/no-store-async'
pub const svelte_require_stores_init = 'svelte/require-stores-init'
pub const svelte_no_ignored_unsubscribe = 'svelte/no-ignored-unsubscribe'
pub const svelte_require_store_callbacks_use_set_param = 'svelte/require-store-callbacks-use-set-param'
pub const svelte_derived_has_same_inputs_outputs = 'svelte/derived-has-same-inputs-outputs'
pub const names = [no_floating_promises, await_thenable, require_await, return_await,
	no_misused_promises, no_unsafe_call, no_unsafe_member_access, no_unsafe_return,
	no_unsafe_assignment, no_unsafe_argument, restrict_template_expressions,
	switch_exhaustiveness_check, prefer_nullish_coalescing, no_unnecessary_condition, no_for_in_array,
	no_array_delete, no_unnecessary_boolean_literal_compare, no_unsafe_unary_minus,
	no_meaningless_void_operator, related_getter_setter_pairs, non_nullable_type_assertion_style,
	prefer_return_this_type, no_duplicate_type_constituents, no_unnecessary_template_expression,
	dot_notation, restrict_plus_operands, no_confusing_void_expression, no_misused_spread,
	no_redundant_type_constituents, no_useless_default_assignment, no_unnecessary_type_arguments,
	no_unnecessary_qualifier, no_implied_eval, no_unnecessary_type_conversion,
	no_unnecessary_type_assertion, no_base_to_string, no_unsafe_enum_comparison, no_mixed_enums,
	unbound_method, prefer_reduce_type_parameter, prefer_find, prefer_regexp_exec, prefer_includes,
	prefer_string_starts_ends_with, prefer_optional_chain, no_deprecated, prefer_promise_reject_errors,
	use_unknown_in_catch_callback_variable, only_throw_error, require_array_sort_compare,
	no_unsafe_type_assertion, promise_function_async, prefer_readonly_parameter_types,
	consistent_type_exports, strict_void_return, consistent_return, prefer_destructuring,
	prefer_readonly, strict_boolean_expressions, no_unnecessary_type_parameters, naming_convention,
	no_duplicate_enum_values, no_extra_non_null_assertion, no_non_null_asserted_optional_chain,
	no_unsafe_function_type, no_wrapper_object_types, prefer_enum_initializers, no_dynamic_delete,
	no_namespace, no_unnecessary_type_constraint, prefer_as_const, no_invalid_void_type, no_this_alias,
	no_misused_new, no_useless_empty_export, no_extraneous_class, adjacent_overload_signatures,
	no_dupe_class_members, class_literal_property_style, no_empty_function, no_unused_expressions,
	no_useless_constructor, no_array_constructor, no_confusing_non_null_assertion,
	no_import_type_side_effects, no_inferrable_types, prefer_namespace_keyword, triple_slash_reference,
	consistent_generic_constructors, consistent_type_assertions, consistent_type_definitions,
	prefer_function_type, unified_signatures, no_unsafe_declaration_merging, no_require_imports,
	no_non_null_asserted_nullish_coalescing, prefer_for_of, array_type,
	consistent_indexed_object_style, no_unnecessary_parameter_property_assignment,
	no_unused_private_class_members, no_use_before_define, no_shadow, consistent_type_imports,
	no_unused_vars, seyfert_prefer_typed_group, seyfert_autocomplete_respond,
	seyfert_config_default_export, seyfert_decorator_target, seyfert_decorator_on_command,
	seyfert_i18n_resolve_with_get, seyfert_no_method_destructure, seyfert_require_declare,
	seyfert_context_menu_declare, seyfert_required_options_order, seyfert_options_use_builders,
	seyfert_declare_description, seyfert_no_deep_imports, seyfert_no_hanging_middleware,
	seyfert_group_exists, no_compare_neg_zero, use_isnan, valid_typeof, no_dupe_else_if,
	no_duplicate_case, no_self_compare, no_self_assign, no_unsafe_negation,
	no_unsafe_optional_chaining, no_cond_assign, for_direction, no_constant_condition,
	no_constant_binary_expression, curly, no_else_return, no_empty, no_empty_static_block,
	default_case_last, no_case_declarations, no_labels, no_extra_label, no_unused_labels, no_with,
	no_debugger, no_unsafe_finally, no_useless_catch, arrow_body_style, prefer_arrow_callback,
	func_name_matching, func_names, grouped_accessor_pairs, no_setter_return, no_dupe_args,
	no_dupe_keys, no_empty_pattern, no_useless_rename, no_useless_computed_key, object_shorthand,
	require_yield, eqeqeq, yoda, no_eq_null, no_extra_boolean_cast, no_implicit_coercion,
	logical_assignment_operators, operator_assignment, prefer_exponentiation_operator, no_sequences,
	no_return_assign, no_unexpected_multiline, no_loss_of_precision, no_nonoctal_decimal_escape,
	no_octal, no_octal_escape, prefer_numeric_literals, no_multi_str, no_template_curly_in_string,
	no_useless_concat, prefer_template, no_irregular_whitespace, unicode_bom, no_sparse_arrays,
	no_new, no_new_func, no_new_wrappers, no_new_native_nonconstructor, no_obj_calls,
	no_object_constructor, no_async_promise_executor, no_extra_bind, no_useless_call, prefer_spread,
	prefer_rest_params, symbol_description, radix_rule, no_extend_native, core_no_implied_eval,
	no_caller, no_iterator, no_proto, no_script_url, no_prototype_builtins, prefer_object_has_own,
	prefer_object_spread, core_dot_notation, preserve_caught_error, no_class_assign, no_const_assign,
	no_ex_assign, no_func_assign, no_global_assign, no_import_assign, no_label_var,
	no_shadow_restricted_names, no_unassigned_vars, no_delete_var, block_scoped_var, consistent_this,
	no_var, prefer_const, vars_on_top, sort_vars, strict_rule, no_inner_declarations, no_lone_blocks,
	no_loop_func, no_implicit_globals, no_unmodified_loop_condition, no_control_regex, no_div_regex,
	no_empty_character_class, no_invalid_regexp, no_misleading_character_class, no_regex_spaces,
	no_useless_backreference, no_useless_escape, prefer_regex_literals, no_warning_comments,
	no_restricted_globals, no_restricted_properties, no_restricted_exports, no_restricted_imports,
	no_constructor_return, no_promise_executor_return, no_invalid_this, getter_return,
	no_unreachable_loop, no_useless_return, no_unreachable, no_fallthrough, constructor_super,
	no_this_before_super, no_useless_assignment, no_restricted_syntax, unicorn_no_lonely_if,
	unicorn_no_negated_condition, unicorn_no_negation_in_equality_check, unicorn_no_nested_ternary,
	unicorn_no_typeof_undefined, unicorn_prefer_logical_operator_over_ternary, unicorn_prefer_ternary,
	unicorn_prefer_switch, unicorn_switch_case_braces, unicorn_switch_case_break_position,
	unicorn_no_useless_switch_case, unicorn_prefer_simple_condition_first, unicorn_prefer_date_now,
	unicorn_throw_new_error, unicorn_error_message, unicorn_consistent_date_clone,
	unicorn_consistent_assert, unicorn_no_new_buffer, unicorn_prefer_type_error,
	unicorn_no_useless_error_capture_stack_trace, unicorn_prefer_structured_clone,
	unicorn_custom_error_definition, unicorn_no_instanceof_builtins, unicorn_new_for_builtins,
	unicorn_no_hex_escape, unicorn_escape_case, unicorn_consistent_template_literal_escape,
	unicorn_prefer_string_trim_start_end, unicorn_no_console_spaces, unicorn_prefer_code_point,
	unicorn_prefer_string_slice, unicorn_text_encoding_identifier_case, unicorn_no_zero_fractions,
	unicorn_prefer_bigint_literals, unicorn_prefer_number_properties, unicorn_prefer_string_raw,
	unicorn_prefer_string_replace_all, unicorn_require_number_to_fixed_digits_argument,
	unicorn_prefer_math_trunc, unicorn_prefer_math_min_max, unicorn_prefer_modern_math_apis,
	unicorn_prefer_native_coercion_functions, unicorn_no_array_callback_reference, unicorn_no_for_each,
	unicorn_no_array_method_this_argument, unicorn_no_array_reverse, unicorn_no_array_sort,
	unicorn_no_new_array, unicorn_prefer_array_flat, unicorn_prefer_array_flat_map,
	unicorn_prefer_array_index_of, unicorn_prefer_array_some, unicorn_require_array_join_separator,
	unicorn_prefer_negative_index, unicorn_consistent_existence_index_check,
	unicorn_explicit_length_check, unicorn_no_unnecessary_array_flat_depth,
	unicorn_no_unnecessary_array_splice_count, unicorn_no_unnecessary_slice_end,
	unicorn_no_useless_length_check, unicorn_no_unreadable_array_destructuring,
	unicorn_prefer_set_size, array_callback_return, no_lonely_if, no_negated_condition,
	no_throw_literal, require_atomic_updates, class_methods_use_this, no_explicit_any,
	unicorn_consistent_empty_array_spread, unicorn_no_useless_fallback_in_spread,
	unicorn_no_useless_collection_argument, unicorn_no_useless_iterator_to_array,
	unicorn_no_useless_spread, unicorn_prefer_single_call, unicorn_no_immediate_mutation,
	unicorn_prefer_blob_reading_methods, unicorn_prefer_response_static_json,
	unicorn_no_await_expression_member, unicorn_prefer_spread, unicorn_no_await_in_promise_methods,
	unicorn_no_invalid_fetch_options, unicorn_no_unnecessary_await, unicorn_no_thenable,
	unicorn_no_single_promise_in_promise_methods, unicorn_no_useless_promise_resolve_reject,
	unicorn_prefer_node_protocol, unicorn_no_process_exit, unicorn_no_named_default,
	unicorn_require_module_attributes, unicorn_require_module_specifiers,
	unicorn_prefer_json_parse_buffer, unicorn_no_anonymous_default_export,
	unicorn_prefer_import_meta_properties, unicorn_prefer_module, unicorn_prefer_reflect_apply,
	unicorn_prefer_export_from, unicorn_relative_url_style, unicorn_prefer_prototype_methods,
	unicorn_better_regex, unicorn_no_this_assignment, unicorn_no_unreadable_iife,
	unicorn_no_accessor_recursion, unicorn_no_static_only_class, unicorn_prefer_class_fields,
	unicorn_consistent_function_scoping, unicorn_isolated_functions, unicorn_no_useless_undefined,
	unicorn_no_keyword_prefix, unicorn_prefer_object_from_entries, unicorn_prefer_default_parameters,
	unicorn_no_unused_properties, stylistic_array_bracket_spacing, stylistic_rest_spread_spacing,
	stylistic_semi_spacing, stylistic_space_in_parens, stylistic_switch_colon_spacing,
	stylistic_template_curly_spacing, stylistic_template_tag_spacing,
	stylistic_no_whitespace_before_property, stylistic_block_spacing, stylistic_comma_spacing,
	stylistic_computed_property_spacing, stylistic_object_curly_spacing, stylistic_keyword_spacing,
	stylistic_space_before_blocks, stylistic_arrow_spacing, stylistic_yield_star_spacing,
	stylistic_type_annotation_spacing, stylistic_type_generic_spacing,
	stylistic_type_named_tuple_spacing, stylistic_space_before_function_paren, stylistic_key_spacing,
	stylistic_space_infix_ops, stylistic_space_unary_ops, stylistic_function_call_spacing,
	stylistic_brace_style, stylistic_comma_style, stylistic_dot_location,
	stylistic_function_call_argument_newline, stylistic_function_paren_newline,
	stylistic_implicit_arrow_linebreak, stylistic_multiline_ternary,
	stylistic_nonblock_statement_body_position, stylistic_one_var_declaration_per_line,
	stylistic_quotes, stylistic_no_multi_spaces, stylistic_no_trailing_spaces,
	stylistic_no_mixed_spaces_and_tabs, stylistic_eol_last, stylistic_spaced_comment,
	stylistic_lines_between_class_members, stylistic_new_parens, stylistic_no_floating_decimal,
	stylistic_no_extra_semi, stylistic_semi_style, stylistic_semi, stylistic_object_curly_newline,
	stylistic_object_property_newline, stylistic_list_style, stylistic_exp_jsx_props_style,
	stylistic_arrow_parens, stylistic_comma_dangle, stylistic_member_delimiter_style,
	stylistic_quote_props, stylistic_no_extra_parens, marcrock_no_newline_if_body_class_empty,
	marcrock_numeric_separators, marcrock_uppercase_first_class_letter, marcrock_prefer_at,
	perfectionist_sort_array_includes, perfectionist_sort_sets, perfectionist_sort_maps,
	perfectionist_sort_union_types, perfectionist_sort_intersection_types, ban_ts_comment,
	ban_tslint_comment, default_param_last, init_declarations, max_params, method_signature_style,
	no_empty_object_type, no_non_null_assertion, ts_no_invalid_this, no_redeclare,
	perfectionist_sort_heritage_clauses, perfectionist_sort_import_attributes,
	perfectionist_sort_export_attributes, perfectionist_sort_switch_case,
	perfectionist_sort_named_imports, perfectionist_sort_named_exports, perfectionist_sort_exports,
	explicit_function_return_type, explicit_module_boundary_types, explicit_member_accessibility,
	parameter_properties, prefer_literal_enum_member, no_magic_numbers, no_restricted_types,
	no_generated_empty_object_type, no_unsafe_enum_assignment, member_ordering,
	perfectionist_sort_classes, perfectionist_sort_imports, vue_comment_directive,
	vue_no_parsing_error, vue_no_v_html, vue_no_v_text, vue_no_duplicate_attributes,
	vue_no_deprecated_v_is, vue_no_deprecated_scope_attribute, vue_no_deprecated_filter,
	vue_no_deprecated_inline_template, vue_require_component_is,
	vue_no_deprecated_v_on_native_modifier, vue_no_v_model_argument, vue_no_textarea_mustache,
	vue_no_use_v_else_with_v_for, vue_no_v_for_template_key, vue_no_template_key,
	vue_no_custom_modifiers_on_v_model, vue_no_deprecated_v_bind_sync,
	vue_no_spaces_around_equal_signs_in_attribute, vue_no_deprecated_v_on_number_modifiers,
	vue_valid_v_bind, vue_valid_v_cloak, vue_valid_v_html, vue_valid_v_once, vue_valid_v_pre,
	vue_valid_v_text, vue_valid_v_show, vue_valid_v_if, vue_valid_v_else_if, vue_valid_v_else,
	vue_valid_v_is, vue_valid_v_on, vue_v_on_style, vue_v_bind_style, vue_no_multiple_objects_in_class,
	vue_require_v_for_key, vue_no_deprecated_html_element_is, vue_no_use_v_if_with_v_for,
	vue_no_v_for_template_key_on_child, vue_html_end_tags, vue_valid_attribute_name,
	vue_v_for_delimiter_style, vue_no_v_text_v_html_on_component, vue_no_lone_template,
	vue_html_button_has_type, vue_no_deprecated_router_link_tag_prop, vue_no_restricted_html_elements,
	vue_no_useless_template_attributes, vue_mustache_interpolation_spacing,
	vue_static_class_names_order, vue_restricted_component_names, vue_slot_name_casing,
	vue_first_attribute_linebreak, vue_html_quotes, vue_no_literals_in_template,
	vue_require_toggle_inside_transition, vue_no_restricted_static_attribute,
	vue_html_closing_bracket_spacing, vue_html_closing_bracket_newline, vue_attribute_hyphenation,
	vue_v_on_event_hyphenation, vue_valid_v_memo, vue_no_static_inline_styles, vue_no_child_content,
	vue_no_template_target_blank, vue_no_restricted_class, vue_no_useless_v_bind,
	vue_no_restricted_v_bind, vue_no_restricted_v_on, vue_valid_v_bind_sync, vue_v_slot_style,
	vue_prefer_true_attribute_shorthand, vue_no_dupe_v_else_if, vue_no_deprecated_slot_attribute,
	vue_no_deprecated_slot_scope_attribute, vue_this_in_template, vue_no_unused_vars,
	vue_no_define_model_default, vue_no_deprecated_functional_template, vue_require_render_return,
	vue_no_deprecated_vue_config_keycodes, vue_no_root_v_if, vue_no_arrow_functions_in_watch,
	vue_one_component_per_file, vue_valid_model_definition, vue_no_deprecated_events_api,
	vue_define_props_declaration, vue_valid_template_root, vue_no_export_in_script_setup,
	vue_require_default_export, vue_jsx_uses_vars, vue_match_component_import_name,
	vue_no_deprecated_destroyed_lifecycle, vue_max_template_depth, vue_no_reserved_props,
	vue_no_this_in_before_route_enter, vue_max_props, vue_no_content_outside_block,
	vue_no_shared_component_data, vue_no_deprecated_data_object_declaration, vue_prop_name_casing,
	vue_define_props_destructuring, vue_component_definition_name_casing, vue_require_emit_validator,
	vue_no_computed_properties_in_data, vue_no_empty_component_block, vue_no_import_compiler_macros,
	vue_prefer_prop_type_boolean_first, vue_require_macro_variable_name, vue_define_emits_declaration,
	vue_no_props_shadow, vue_require_prop_type_constructor, vue_no_restricted_block,
	vue_component_options_name_casing, vue_max_lines_per_block, vue_no_multiple_slot_args,
	vue_no_reserved_keys, vue_no_deprecated_delete_set, vue_require_prop_types,
	vue_return_in_computed_property, vue_no_deprecated_props_default_this,
	vue_require_slots_as_functions, vue_require_name_property, vue_arrow_spacing, vue_camelcase,
	vue_comma_dangle, vue_dot_location, vue_no_empty_pattern, vue_no_sparse_arrays,
	vue_operator_linebreak, vue_array_bracket_newline, vue_array_bracket_spacing,
	vue_array_element_newline, vue_block_spacing, vue_brace_style, vue_dot_notation, vue_eqeqeq,
	vue_key_spacing, vue_keyword_spacing, vue_no_restricted_syntax, vue_no_useless_concat,
	vue_object_curly_newline, vue_object_curly_spacing, vue_object_property_newline,
	vue_prefer_template, vue_no_implicit_coercion, vue_no_loss_of_precision, vue_no_negated_condition,
	vue_object_shorthand, vue_space_infix_ops, vue_space_unary_ops, vue_template_curly_spacing,
	vue_comma_spacing, vue_multiline_ternary, vue_space_in_parens, vue_func_call_spacing,
	vue_comma_style, vue_no_constant_condition, vue_no_console, vue_quote_props, vue_no_extra_parens,
	vue_max_attributes_per_line, vue_no_useless_mustaches, vue_no_negated_v_if_condition,
	vue_use_v_on_exact, vue_prefer_v_model, vue_singleline_html_element_content_newline,
	vue_multiline_html_element_content_newline, vue_html_self_closing, vue_padding_line_between_blocks,
	vue_padding_line_between_tags, vue_block_tag_newline, vue_block_lang,
	vue_no_bare_strings_in_template, vue_v_if_else_key, vue_no_irregular_whitespace, vue_valid_v_for,
	vue_valid_v_model, vue_valid_v_slot, vue_no_unsupported_features, vue_prefer_separate_static_class,
	vue_no_duplicate_class_names, vue_max_len, vue_attributes_order,
	vue_no_deprecated_dollar_listeners_api, vue_no_deprecated_dollar_scopedslots_api,
	vue_prefer_use_template_ref, vue_no_duplicate_attr_inheritance, vue_no_unused_components,
	vue_no_template_shadow, vue_require_explicit_slots, vue_no_undef_directives,
	vue_component_name_in_template_casing, vue_no_unused_refs, vue_custom_event_name_casing,
	vue_no_restricted_custom_event, vue_no_unused_emit_declarations, vue_prefer_single_event_payload,
	vue_no_shadow_native_events, vue_require_explicit_emits, vue_no_undef_components,
	vue_v_on_handler_style, vue_no_mutating_props, vue_no_use_computed_property_like_method,
	vue_no_unused_properties, vue_no_undef_properties, vue_prefer_define_options,
	vue_multi_word_component_names, vue_no_multiple_template_root,
	vue_no_potential_component_option_typo, vue_no_deprecated_model_definition,
	vue_match_component_file_name, vue_enforce_style_attribute, vue_require_direct_export,
	vue_no_restricted_component_names, vue_no_restricted_component_options, vue_prefer_import_from_vue,
	vue_new_line_between_multi_line_property, vue_component_api_style, vue_no_reserved_component_names,
	vue_require_typed_object_prop, vue_return_in_emits_validator, vue_valid_define_props,
	vue_valid_define_emits, vue_valid_define_options, vue_require_prop_comment,
	vue_define_macros_order, vue_order_in_components, vue_padding_lines_in_component_definition,
	vue_sort_keys, vue_html_comment_content_spacing, vue_html_comment_content_newline,
	vue_html_comment_indent, vue_no_multi_spaces, vue_block_order, vue_no_lifecycle_after_await,
	vue_no_watch_after_await, vue_no_expose_after_await, vue_no_restricted_call_after_await,
	vue_next_tick_style, vue_valid_next_tick, vue_no_boolean_default,
	vue_no_required_prop_with_default, vue_require_default_prop, vue_require_valid_default_prop,
	vue_no_restricted_props, vue_require_typed_ref, vue_no_ref_as_operand,
	vue_no_ref_object_reactivity_loss, vue_no_setup_props_reactivity_loss, vue_require_expose,
	vue_no_side_effects_in_computed_properties, vue_no_async_in_computed_properties, vue_no_dupe_keys,
	svelte_comment_directive, svelte_system, svelte_no_at_html_tags, svelte_no_at_debug_tags,
	svelte_button_has_type, svelte_no_target_blank, svelte_require_each_key, svelte_valid_each_key,
	svelte_no_object_in_text_mustaches, svelte_shorthand_attribute,
	svelte_no_spaces_around_equal_signs_in_attribute, svelte_spaced_html_comment,
	svelte_no_dupe_else_if_blocks, svelte_no_useless_mustaches, svelte_first_attribute_linebreak,
	svelte_shorthand_directive, svelte_html_closing_bracket_spacing,
	svelte_html_closing_bracket_new_line, svelte_no_dynamic_slot_name, svelte_html_quotes,
	svelte_mustache_spacing, svelte_no_inline_styles, svelte_no_raw_special_elements,
	svelte_no_nested_style_tag, svelte_no_useless_children_snippet, svelte_no_dupe_on_directives,
	svelte_no_dupe_use_directives, svelte_prefer_attribute_interpolation,
	svelte_max_attributes_per_line, svelte_html_self_closing, svelte_no_at_const_tags,
	svelte_no_not_function_handler, svelte_block_lang, svelte_prefer_class_directive,
	svelte_no_svelte_internal, svelte_no_inspect, svelte_no_store_async, svelte_require_stores_init,
	svelte_no_ignored_unsubscribe, svelte_require_store_callbacks_use_set_param,
	svelte_derived_has_same_inputs_outputs]

// untyped_rules are the ported rules that need no types (`meta.docs.requiresTypeChecking` is false
// in typescript-eslint; the eslint-plugin-unicorn rules that read the types when the parser has a
// program, through withTypeInformation, are not here): with only these, the command line makes no
// snapshot (Checker.make_snapshot).
pub const untyped_rules = [adjacent_overload_signatures, array_type, class_literal_property_style,
	consistent_generic_constructors, consistent_indexed_object_style, consistent_type_assertions,
	consistent_type_definitions, consistent_type_imports, no_array_constructor,
	no_confusing_non_null_assertion, no_dupe_class_members, no_duplicate_enum_values,
	no_dynamic_delete, no_empty_function, no_extra_non_null_assertion, no_extraneous_class,
	no_import_type_side_effects, no_inferrable_types, no_invalid_void_type, no_misused_new,
	no_namespace, no_non_null_asserted_nullish_coalescing, no_non_null_asserted_optional_chain,
	no_require_imports, no_shadow, no_this_alias, no_unnecessary_parameter_property_assignment,
	no_unnecessary_type_constraint, no_unsafe_declaration_merging, no_unsafe_function_type,
	no_unused_expressions, no_unused_private_class_members, no_unused_vars, no_use_before_define,
	no_useless_constructor, no_useless_empty_export, no_wrapper_object_types, prefer_as_const,
	prefer_enum_initializers, prefer_for_of, prefer_function_type, prefer_namespace_keyword,
	triple_slash_reference, unified_signatures, no_compare_neg_zero, use_isnan, valid_typeof,
	no_dupe_else_if, no_duplicate_case, no_self_compare, no_self_assign, no_unsafe_negation,
	no_unsafe_optional_chaining, no_cond_assign, for_direction, no_constant_condition,
	no_constant_binary_expression, curly, no_else_return, no_empty, no_empty_static_block,
	default_case_last, no_case_declarations, no_labels, no_extra_label, no_unused_labels, no_with,
	no_debugger, no_unsafe_finally, no_useless_catch, arrow_body_style, prefer_arrow_callback,
	func_name_matching, func_names, grouped_accessor_pairs, no_setter_return, no_dupe_args,
	no_dupe_keys, no_empty_pattern, no_useless_rename, no_useless_computed_key, object_shorthand,
	require_yield, eqeqeq, yoda, no_eq_null, no_extra_boolean_cast, no_implicit_coercion,
	logical_assignment_operators, operator_assignment, prefer_exponentiation_operator, no_sequences,
	no_return_assign, no_unexpected_multiline, no_loss_of_precision, no_nonoctal_decimal_escape,
	no_octal, no_octal_escape, prefer_numeric_literals, no_multi_str, no_template_curly_in_string,
	no_useless_concat, prefer_template, no_irregular_whitespace, unicode_bom, no_sparse_arrays,
	no_new, no_new_func, no_new_wrappers, no_new_native_nonconstructor, no_obj_calls,
	no_object_constructor, no_async_promise_executor, no_extra_bind, no_useless_call, prefer_spread,
	prefer_rest_params, symbol_description, radix_rule, no_extend_native, core_no_implied_eval,
	no_caller, no_iterator, no_proto, no_script_url, no_prototype_builtins, prefer_object_has_own,
	prefer_object_spread, core_dot_notation, preserve_caught_error, no_class_assign, no_const_assign,
	no_ex_assign, no_func_assign, no_global_assign, no_import_assign, no_label_var,
	no_shadow_restricted_names, no_unassigned_vars, no_delete_var, block_scoped_var, consistent_this,
	no_var, prefer_const, vars_on_top, sort_vars, strict_rule, no_inner_declarations, no_lone_blocks,
	no_loop_func, no_implicit_globals, no_unmodified_loop_condition, no_control_regex, no_div_regex,
	no_empty_character_class, no_invalid_regexp, no_misleading_character_class, no_regex_spaces,
	no_useless_backreference, no_useless_escape, prefer_regex_literals, no_warning_comments,
	no_restricted_globals, no_restricted_properties, no_restricted_exports, no_restricted_imports,
	no_constructor_return, no_promise_executor_return, no_invalid_this, getter_return,
	no_unreachable_loop, no_useless_return, no_unreachable, no_fallthrough, constructor_super,
	no_this_before_super, no_useless_assignment, no_restricted_syntax, unicorn_no_lonely_if,
	unicorn_no_negated_condition, unicorn_no_negation_in_equality_check, unicorn_no_nested_ternary,
	unicorn_no_typeof_undefined, unicorn_prefer_switch, unicorn_switch_case_braces,
	unicorn_switch_case_break_position, unicorn_no_useless_switch_case,
	unicorn_prefer_simple_condition_first, unicorn_prefer_date_now, unicorn_error_message,
	unicorn_consistent_date_clone, unicorn_consistent_assert, unicorn_prefer_type_error,
	unicorn_no_useless_error_capture_stack_trace, unicorn_prefer_structured_clone,
	unicorn_custom_error_definition, unicorn_no_instanceof_builtins, unicorn_new_for_builtins,
	unicorn_no_hex_escape, unicorn_escape_case, unicorn_consistent_template_literal_escape,
	unicorn_no_console_spaces, unicorn_prefer_code_point, unicorn_text_encoding_identifier_case,
	unicorn_no_zero_fractions, unicorn_prefer_bigint_literals,
	unicorn_require_number_to_fixed_digits_argument, unicorn_prefer_math_trunc,
	unicorn_prefer_modern_math_apis, unicorn_prefer_native_coercion_functions, unicorn_no_new_array,
	unicorn_prefer_negative_index, unicorn_consistent_existence_index_check,
	unicorn_explicit_length_check, unicorn_no_unnecessary_slice_end, array_callback_return,
	no_lonely_if, no_negated_condition, no_throw_literal, require_atomic_updates,
	class_methods_use_this, no_explicit_any, unicorn_consistent_empty_array_spread,
	unicorn_no_useless_fallback_in_spread, unicorn_no_useless_collection_argument,
	unicorn_no_useless_iterator_to_array, unicorn_no_immediate_mutation,
	unicorn_prefer_blob_reading_methods, unicorn_prefer_response_static_json,
	unicorn_no_await_expression_member, unicorn_no_await_in_promise_methods,
	unicorn_no_invalid_fetch_options, unicorn_no_unnecessary_await, unicorn_no_thenable,
	unicorn_no_single_promise_in_promise_methods, unicorn_no_useless_promise_resolve_reject,
	unicorn_prefer_node_protocol, unicorn_no_process_exit, unicorn_no_named_default,
	unicorn_require_module_attributes, unicorn_require_module_specifiers,
	unicorn_prefer_json_parse_buffer, unicorn_no_anonymous_default_export,
	unicorn_prefer_import_meta_properties, unicorn_prefer_module, unicorn_prefer_reflect_apply,
	unicorn_prefer_export_from, unicorn_relative_url_style, unicorn_prefer_prototype_methods,
	unicorn_better_regex, unicorn_no_this_assignment, unicorn_no_unreadable_iife,
	unicorn_no_accessor_recursion, unicorn_no_static_only_class, unicorn_prefer_class_fields,
	unicorn_consistent_function_scoping, unicorn_isolated_functions, unicorn_no_useless_undefined,
	unicorn_no_keyword_prefix, unicorn_no_unused_properties, stylistic_array_bracket_spacing,
	stylistic_rest_spread_spacing, stylistic_semi_spacing, stylistic_space_in_parens,
	stylistic_switch_colon_spacing, stylistic_template_curly_spacing, stylistic_template_tag_spacing,
	stylistic_no_whitespace_before_property, stylistic_block_spacing, stylistic_comma_spacing,
	stylistic_computed_property_spacing, stylistic_object_curly_spacing, stylistic_keyword_spacing,
	stylistic_space_before_blocks, stylistic_arrow_spacing, stylistic_yield_star_spacing,
	stylistic_type_annotation_spacing, stylistic_type_generic_spacing,
	stylistic_type_named_tuple_spacing, stylistic_space_before_function_paren, stylistic_key_spacing,
	stylistic_space_infix_ops, stylistic_space_unary_ops, stylistic_function_call_spacing,
	stylistic_brace_style, stylistic_comma_style, stylistic_dot_location,
	stylistic_function_call_argument_newline, stylistic_function_paren_newline,
	stylistic_implicit_arrow_linebreak, stylistic_multiline_ternary,
	stylistic_nonblock_statement_body_position, stylistic_one_var_declaration_per_line,
	stylistic_quotes, stylistic_no_multi_spaces, stylistic_no_trailing_spaces,
	stylistic_no_mixed_spaces_and_tabs, stylistic_eol_last, stylistic_spaced_comment,
	stylistic_lines_between_class_members, stylistic_new_parens, stylistic_no_floating_decimal,
	stylistic_no_extra_semi, stylistic_semi_style, stylistic_semi, stylistic_object_curly_newline,
	stylistic_object_property_newline, stylistic_list_style, stylistic_exp_jsx_props_style,
	stylistic_arrow_parens, stylistic_comma_dangle, stylistic_member_delimiter_style,
	stylistic_quote_props, stylistic_no_extra_parens, marcrock_no_newline_if_body_class_empty,
	marcrock_numeric_separators, marcrock_uppercase_first_class_letter,
	perfectionist_sort_array_includes, perfectionist_sort_sets, perfectionist_sort_maps,
	perfectionist_sort_union_types, perfectionist_sort_intersection_types, ban_ts_comment,
	ban_tslint_comment, default_param_last, init_declarations, max_params, method_signature_style,
	no_empty_object_type, no_non_null_assertion, ts_no_invalid_this, no_redeclare,
	perfectionist_sort_heritage_clauses, perfectionist_sort_import_attributes,
	perfectionist_sort_export_attributes, perfectionist_sort_switch_case,
	perfectionist_sort_named_imports, perfectionist_sort_named_exports, perfectionist_sort_exports,
	explicit_function_return_type, explicit_module_boundary_types, explicit_member_accessibility,
	parameter_properties, prefer_literal_enum_member, no_magic_numbers, no_restricted_types,
	member_ordering, perfectionist_sort_classes, perfectionist_sort_imports, vue_no_v_html,
	vue_no_v_text, vue_no_duplicate_attributes, vue_comment_directive, vue_no_parsing_error,
	vue_no_deprecated_v_is, vue_no_deprecated_scope_attribute, vue_no_deprecated_filter,
	vue_no_deprecated_inline_template, vue_require_component_is,
	vue_no_deprecated_v_on_native_modifier, vue_no_v_model_argument, vue_no_textarea_mustache,
	vue_no_use_v_else_with_v_for, vue_no_v_for_template_key, vue_no_template_key,
	vue_no_custom_modifiers_on_v_model, vue_no_deprecated_v_bind_sync,
	vue_no_spaces_around_equal_signs_in_attribute, vue_no_deprecated_v_on_number_modifiers,
	vue_valid_v_bind, vue_valid_v_cloak, vue_valid_v_html, vue_valid_v_once, vue_valid_v_pre,
	vue_valid_v_text, vue_valid_v_show, vue_valid_v_if, vue_valid_v_else_if, vue_valid_v_else,
	vue_valid_v_is, vue_valid_v_on, vue_v_on_style, vue_v_bind_style, vue_no_multiple_objects_in_class,
	vue_require_v_for_key, vue_no_deprecated_html_element_is, vue_no_use_v_if_with_v_for,
	vue_no_v_for_template_key_on_child, vue_html_end_tags, vue_valid_attribute_name,
	vue_v_for_delimiter_style, vue_no_v_text_v_html_on_component, vue_no_lone_template,
	vue_html_button_has_type, vue_no_deprecated_router_link_tag_prop, vue_no_restricted_html_elements,
	vue_no_useless_template_attributes, vue_mustache_interpolation_spacing,
	vue_static_class_names_order, vue_restricted_component_names, vue_slot_name_casing,
	vue_first_attribute_linebreak, vue_html_quotes, vue_no_literals_in_template,
	vue_require_toggle_inside_transition, vue_no_restricted_static_attribute,
	vue_html_closing_bracket_spacing, vue_html_closing_bracket_newline, vue_attribute_hyphenation,
	vue_v_on_event_hyphenation, vue_valid_v_memo, vue_no_static_inline_styles, vue_no_child_content,
	vue_no_template_target_blank, vue_no_restricted_class, vue_no_useless_v_bind,
	vue_no_restricted_v_bind, vue_no_restricted_v_on, vue_valid_v_bind_sync, vue_v_slot_style,
	vue_prefer_true_attribute_shorthand, vue_no_dupe_v_else_if, vue_no_deprecated_slot_attribute,
	vue_no_deprecated_slot_scope_attribute, vue_this_in_template, vue_no_unused_vars,
	vue_no_define_model_default, vue_no_deprecated_functional_template,
	vue_no_deprecated_vue_config_keycodes, vue_no_root_v_if, vue_no_arrow_functions_in_watch,
	vue_one_component_per_file, vue_valid_model_definition, vue_no_deprecated_events_api,
	vue_define_props_declaration, vue_valid_template_root, vue_no_export_in_script_setup,
	vue_require_default_export, vue_jsx_uses_vars, vue_match_component_import_name,
	vue_no_deprecated_destroyed_lifecycle, vue_max_template_depth, vue_no_this_in_before_route_enter,
	vue_no_content_outside_block, vue_no_shared_component_data,
	vue_no_deprecated_data_object_declaration, vue_component_definition_name_casing,
	vue_require_emit_validator, vue_no_computed_properties_in_data, vue_no_empty_component_block,
	vue_no_import_compiler_macros, vue_prefer_prop_type_boolean_first, vue_require_macro_variable_name,
	vue_define_emits_declaration, vue_require_prop_type_constructor, vue_no_restricted_block,
	vue_component_options_name_casing, vue_max_lines_per_block, vue_no_multiple_slot_args,
	vue_no_deprecated_delete_set, vue_require_prop_types, vue_no_deprecated_props_default_this,
	vue_require_slots_as_functions, vue_require_name_property, vue_arrow_spacing, vue_camelcase,
	vue_comma_dangle, vue_dot_location, vue_no_empty_pattern, vue_no_sparse_arrays,
	vue_operator_linebreak, vue_array_bracket_newline, vue_array_bracket_spacing,
	vue_array_element_newline, vue_block_spacing, vue_brace_style, vue_dot_notation, vue_eqeqeq,
	vue_key_spacing, vue_keyword_spacing, vue_no_restricted_syntax, vue_no_useless_concat,
	vue_object_curly_newline, vue_object_curly_spacing, vue_object_property_newline,
	vue_prefer_template, vue_no_implicit_coercion, vue_no_loss_of_precision, vue_no_negated_condition,
	vue_object_shorthand, vue_space_infix_ops, vue_space_unary_ops, vue_template_curly_spacing,
	vue_comma_spacing, vue_multiline_ternary, vue_space_in_parens, vue_func_call_spacing,
	vue_comma_style, vue_no_constant_condition, vue_no_console, vue_quote_props, vue_no_extra_parens,
	vue_max_attributes_per_line, vue_no_useless_mustaches, vue_no_negated_v_if_condition,
	vue_use_v_on_exact, vue_prefer_v_model, vue_singleline_html_element_content_newline,
	vue_multiline_html_element_content_newline, vue_html_self_closing, vue_padding_line_between_blocks,
	vue_padding_line_between_tags, vue_block_tag_newline, vue_block_lang,
	vue_no_bare_strings_in_template, vue_v_if_else_key, vue_no_irregular_whitespace, vue_valid_v_for,
	vue_valid_v_model, vue_valid_v_slot, vue_no_unsupported_features, vue_prefer_separate_static_class,
	vue_no_duplicate_class_names, vue_max_len, vue_attributes_order,
	vue_no_deprecated_dollar_listeners_api, vue_no_deprecated_dollar_scopedslots_api,
	vue_prefer_use_template_ref, vue_no_duplicate_attr_inheritance, vue_no_unused_components,
	vue_no_undef_directives, vue_component_name_in_template_casing, vue_no_unused_refs,
	vue_custom_event_name_casing, vue_no_restricted_custom_event, vue_no_undef_components,
	vue_v_on_handler_style, vue_no_use_computed_property_like_method, vue_prefer_define_options,
	vue_multi_word_component_names, vue_no_multiple_template_root,
	vue_no_potential_component_option_typo, vue_no_deprecated_model_definition,
	vue_match_component_file_name, vue_enforce_style_attribute, vue_require_direct_export,
	vue_no_restricted_component_names, vue_no_restricted_component_options, vue_prefer_import_from_vue,
	vue_new_line_between_multi_line_property, vue_component_api_style, vue_no_reserved_component_names,
	vue_require_typed_object_prop, vue_return_in_emits_validator, vue_valid_define_props,
	vue_valid_define_emits, vue_valid_define_options, vue_require_prop_comment,
	vue_define_macros_order, vue_order_in_components, vue_padding_lines_in_component_definition,
	vue_sort_keys, vue_html_comment_content_spacing, vue_html_comment_content_newline,
	vue_html_comment_indent, vue_no_multi_spaces, vue_block_order, vue_no_lifecycle_after_await,
	vue_no_watch_after_await, vue_no_expose_after_await, vue_no_restricted_call_after_await,
	vue_next_tick_style, vue_valid_next_tick, vue_require_typed_ref, vue_no_ref_object_reactivity_loss,
	vue_no_setup_props_reactivity_loss, vue_require_expose, vue_no_side_effects_in_computed_properties,
	vue_no_async_in_computed_properties, svelte_comment_directive, svelte_system,
	svelte_no_at_html_tags, svelte_no_at_debug_tags, svelte_button_has_type, svelte_no_target_blank,
	svelte_require_each_key, svelte_valid_each_key, svelte_no_object_in_text_mustaches,
	svelte_shorthand_attribute, svelte_no_spaces_around_equal_signs_in_attribute,
	svelte_spaced_html_comment, svelte_no_dupe_else_if_blocks, svelte_no_useless_mustaches,
	svelte_first_attribute_linebreak, svelte_shorthand_directive, svelte_html_closing_bracket_spacing,
	svelte_html_closing_bracket_new_line, svelte_no_dynamic_slot_name, svelte_html_quotes,
	svelte_mustache_spacing, svelte_no_inline_styles, svelte_no_raw_special_elements,
	svelte_no_nested_style_tag, svelte_no_useless_children_snippet, svelte_no_dupe_on_directives,
	svelte_no_dupe_use_directives, svelte_prefer_attribute_interpolation,
	svelte_max_attributes_per_line, svelte_html_self_closing, svelte_no_at_const_tags,
	svelte_no_not_function_handler, svelte_block_lang, svelte_prefer_class_directive,
	svelte_no_svelte_internal, svelte_no_inspect, svelte_no_store_async, svelte_require_stores_init,
	svelte_no_ignored_unsubscribe, svelte_require_store_callbacks_use_set_param,
	svelte_derived_has_same_inputs_outputs]

// needs_types tells whether a rule asks tsgo for the types of the program.
pub fn needs_types(rule string) bool {
	return rule !in untyped_rules
}

// default_options are the default options of each rule (`defaultOptions` of typescript-eslint
// 8.72.2, as JSON). For the rules that do not read options (see check_options), veslint only
// applies these.
pub const default_options = {
	no_floating_promises:                             '[{"allowForKnownSafeCalls":[],"allowForKnownSafePromises":[],"checkThenables":false,"ignoreIIFE":false,"ignoreVoid":true}]'
	await_thenable:                                   '[{"allowMixedPromiseArrays":false}]'
	require_await:                                    '[]'
	return_await:                                     '["in-try-catch"]'
	no_misused_promises:                              '[{"checksConditionals":true,"checksSpreads":true,"checksVoidReturn":true}]'
	no_unsafe_call:                                   '[]'
	no_unsafe_member_access:                          '[{"allowOptionalChaining":false}]'
	no_unsafe_return:                                 '[]'
	no_unsafe_assignment:                             '[]'
	no_unsafe_argument:                               '[]'
	restrict_template_expressions:                    '[{"allow":[{"name":["Error","URL","URLSearchParams"],"from":"lib"}],"allowAny":true,"allowBoolean":true,"allowNullish":true,"allowNumber":true,"allowRegExp":true}]'
	switch_exhaustiveness_check:                      '[{"allowDefaultCaseForExhaustiveSwitch":true,"considerDefaultExhaustiveForUnions":false,"requireDefaultForNonUnion":false}]'
	prefer_nullish_coalescing:                        '[{"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"ignoreBooleanCoercion":false,"ignoreConditionalTests":true,"ignoreIfStatements":false,"ignoreMixedLogicalExpressions":false,"ignorePrimitives":{"bigint":false,"boolean":false,"number":false,"string":false},"ignoreTernaryTests":false}]'
	no_unnecessary_condition:                         '[{"allowConstantLoopConditions":"never","allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"checkTypePredicates":false}]'
	no_for_in_array:                                  '[]'
	no_array_delete:                                  '[]'
	no_unnecessary_boolean_literal_compare:           '[{"allowComparingNullableBooleansToFalse":true,"allowComparingNullableBooleansToTrue":true,"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false}]'
	no_unsafe_unary_minus:                            '[]'
	no_meaningless_void_operator:                     '[{"checkNever":false}]'
	related_getter_setter_pairs:                      '[]'
	non_nullable_type_assertion_style:                '[]'
	prefer_return_this_type:                          '[]'
	no_duplicate_type_constituents:                   '[{"ignoreIntersections":false,"ignoreUnions":false}]'
	no_unnecessary_template_expression:               '[]'
	dot_notation:                                     '[{"allowIndexSignaturePropertyAccess":false,"allowKeywords":true,"allowPattern":"","allowPrivateClassPropertyAccess":false,"allowProtectedClassPropertyAccess":false}]'
	restrict_plus_operands:                           '[{"allowAny":true,"allowBoolean":true,"allowNullish":true,"allowNumberAndString":true,"allowRegExp":true,"skipCompoundAssignments":false}]'
	no_confusing_void_expression:                     '[{"ignoreArrowShorthand":false,"ignoreVoidOperator":false,"ignoreVoidReturningFunctions":false}]'
	no_misused_spread:                                '[{"allow":[]}]'
	no_redundant_type_constituents:                   '[]'
	no_useless_default_assignment:                    '[{"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false}]'
	no_unnecessary_type_arguments:                    '[]'
	no_unnecessary_qualifier:                         '[]'
	no_implied_eval:                                  '[]'
	no_unnecessary_type_conversion:                   '[]'
	no_unnecessary_type_assertion:                    '[{}]'
	no_base_to_string:                                '[{"checkUnknown":false,"ignoredTypeNames":["Error","RegExp","URL","URLSearchParams"]}]'
	no_unsafe_enum_comparison:                        '[]'
	no_mixed_enums:                                   '[]'
	unbound_method:                                   '[{"ignoreStatic":false}]'
	prefer_reduce_type_parameter:                     '[]'
	prefer_find:                                      '[]'
	prefer_regexp_exec:                               '[]'
	prefer_includes:                                  '[]'
	prefer_string_starts_ends_with:                   '[{"allowSingleElementEquality":"never"}]'
	prefer_optional_chain:                            '[{"allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing":false,"checkAny":true,"checkBigInt":true,"checkBoolean":true,"checkNumber":true,"checkString":true,"checkUnknown":true,"requireNullish":false}]'
	no_deprecated:                                    '[{"allow":[]}]'
	prefer_promise_reject_errors:                     '[{"allow":[],"allowEmptyReject":false,"allowThrowingAny":false,"allowThrowingUnknown":false}]'
	use_unknown_in_catch_callback_variable:           '[]'
	only_throw_error:                                 '[{"allow":[],"allowRethrowing":true,"allowThrowingAny":true,"allowThrowingUnknown":true}]'
	require_array_sort_compare:                       '[{"ignoreStringArrays":true}]'
	no_unsafe_type_assertion:                         '[]'
	promise_function_async:                           '[{"allowAny":true,"allowedPromiseNames":[],"checkArrowFunctions":true,"checkFunctionDeclarations":true,"checkFunctionExpressions":true,"checkMethodDeclarations":true}]'
	prefer_readonly_parameter_types:                  '[{"allow":[],"checkParameterProperties":true,"ignoreInferredTypes":false,"treatMethodsAsReadonly":false}]'
	consistent_type_exports:                          '[{"fixMixedExportsWithInlineTypeSpecifier":false}]'
	strict_void_return:                               '[{"allowReturnAny":false}]'
	consistent_return:                                '[{"treatUndefinedAsUnspecified":false}]'
	prefer_destructuring:                             '[{"AssignmentExpression":{"array":true,"object":true},"VariableDeclarator":{"array":true,"object":true}},{}]'
	prefer_readonly:                                  '[{"onlyInlineLambdas":false}]'
	strict_boolean_expressions:                       '[{"allowAny":false,"allowNullableBoolean":false,"allowNullableEnum":false,"allowNullableNumber":false,"allowNullableObject":true,"allowNullableString":false,"allowNumber":true,"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"allowString":true}]'
	no_unnecessary_type_parameters:                   '[]'
	naming_convention:                                '[{"format":["camelCase"],"leadingUnderscore":"allow","selector":"default","trailingUnderscore":"allow"},{"format":["camelCase","PascalCase"],"selector":"import"},{"format":["camelCase","UPPER_CASE"],"leadingUnderscore":"allow","selector":"variable","trailingUnderscore":"allow"},{"format":["PascalCase"],"selector":"typeLike"}]'
	no_duplicate_enum_values:                         '[]'
	no_extra_non_null_assertion:                      '[]'
	no_non_null_asserted_optional_chain:              '[]'
	no_unsafe_function_type:                          '[]'
	no_wrapper_object_types:                          '[]'
	prefer_enum_initializers:                         '[]'
	no_dynamic_delete:                                '[]'
	no_namespace:                                     '[{"allowDeclarations":false,"allowDefinitionFiles":true}]'
	no_unnecessary_type_constraint:                   '[]'
	prefer_as_const:                                  '[]'
	no_invalid_void_type:                             '[{"allowAsThisParameter":false,"allowInGenericTypeArguments":true}]'
	no_this_alias:                                    '[{"allowDestructuring":true,"allowedNames":[]}]'
	no_misused_new:                                   '[]'
	no_useless_empty_export:                          '[]'
	no_extraneous_class:                              '[{"allowConstructorOnly":false,"allowEmpty":false,"allowStaticOnly":false,"allowWithDecorator":false}]'
	adjacent_overload_signatures:                     '[]'
	no_dupe_class_members:                            '[]'
	class_literal_property_style:                     '["fields"]'
	no_empty_function:                                '[{"allow":[]}]'
	no_unused_expressions:                            '[{"allowShortCircuit":false,"allowTaggedTemplates":false,"allowTernary":false}]'
	no_useless_constructor:                           '[]'
	no_array_constructor:                             '[]'
	no_confusing_non_null_assertion:                  '[]'
	no_import_type_side_effects:                      '[]'
	no_inferrable_types:                              '[{"ignoreParameters":false,"ignoreProperties":false}]'
	prefer_namespace_keyword:                         '[]'
	triple_slash_reference:                           '[{"lib":"always","path":"never","types":"prefer-import"}]'
	consistent_generic_constructors:                  '["constructor"]'
	consistent_type_assertions:                       '[{"arrayLiteralTypeAssertions":"allow","assertionStyle":"as","objectLiteralTypeAssertions":"allow"}]'
	consistent_type_definitions:                      '["interface"]'
	prefer_function_type:                             '[]'
	unified_signatures:                               '[{"ignoreDifferentlyNamedParameters":false,"ignoreOverloadsWithDifferentJSDoc":false}]'
	no_unsafe_declaration_merging:                    '[]'
	no_require_imports:                               '[{"allow":[],"allowAsImport":false}]'
	no_non_null_asserted_nullish_coalescing:          '[]'
	prefer_for_of:                                    '[]'
	array_type:                                       '[{"default":"array"}]'
	consistent_indexed_object_style:                  '["record"]'
	no_unnecessary_parameter_property_assignment:     '[]'
	no_unused_private_class_members:                  '[]'
	no_use_before_define:                             '[{"allowNamedExports":false,"classes":true,"enums":true,"functions":true,"ignoreTypeReferences":true,"typedefs":true,"variables":true}]'
	no_shadow:                                        '[{"allow":[],"builtinGlobals":false,"hoist":"functions-and-types","ignoreFunctionTypeParameterNameValueShadow":true,"ignoreOnInitialization":false,"ignoreTypeValueShadow":true}]'
	consistent_type_imports:                          '[{"disallowTypeAnnotations":true,"fixStyle":"separate-type-imports","prefer":"type-imports"}]'
	no_unused_vars:                                   '[{}]'
	seyfert_prefer_typed_group:                       '[]'
	seyfert_autocomplete_respond:                     '[]'
	seyfert_config_default_export:                    '[]'
	seyfert_decorator_target:                         '[]'
	seyfert_decorator_on_command:                     '[]'
	seyfert_i18n_resolve_with_get:                    '[]'
	seyfert_no_method_destructure:                    '[]'
	seyfert_require_declare:                          '[]'
	seyfert_context_menu_declare:                     '[]'
	seyfert_required_options_order:                   '[]'
	seyfert_options_use_builders:                     '[]'
	seyfert_declare_description:                      '[]'
	seyfert_no_deep_imports:                          '[]'
	seyfert_no_hanging_middleware:                    '[]'
	seyfert_group_exists:                             '[]'
	no_compare_neg_zero:                              '[]'
	use_isnan:                                        '[{"enforceForIndexOf":false,"enforceForSwitchCase":true}]'
	valid_typeof:                                     '[{"requireStringLiterals":false}]'
	no_dupe_else_if:                                  '[]'
	no_duplicate_case:                                '[]'
	no_self_compare:                                  '[]'
	no_self_assign:                                   '[{"props":true}]'
	no_unsafe_negation:                               '[{"enforceForOrderingRelations":false}]'
	no_unsafe_optional_chaining:                      '[{"disallowArithmeticOperators":false}]'
	no_cond_assign:                                   '["except-parens"]'
	for_direction:                                    '[]'
	no_constant_condition:                            '[{"checkLoops":"allExceptWhileTrue"}]'
	no_constant_binary_expression:                    '[{"checkRelationalComparisons":false}]'
	curly:                                            '["all"]'
	no_else_return:                                   '[{"allowElseIf":true}]'
	no_empty:                                         '[{"allowEmptyCatch":false}]'
	no_empty_static_block:                            '[]'
	default_case_last:                                '[]'
	no_case_declarations:                             '[]'
	no_labels:                                        '[{"allowLoop":false,"allowSwitch":false}]'
	no_extra_label:                                   '[]'
	no_unused_labels:                                 '[]'
	no_with:                                          '[]'
	no_debugger:                                      '[]'
	no_unsafe_finally:                                '[]'
	no_useless_catch:                                 '[]'
	arrow_body_style:                                 '["as-needed"]'
	prefer_arrow_callback:                            '[{"allowNamedFunctions":false,"allowUnboundThis":true}]'
	func_name_matching:                               '["always"]'
	func_names:                                       '["always",{}]'
	grouped_accessor_pairs:                           '["anyOrder",{"enforceForTSTypes":false}]'
	no_setter_return:                                 '[]'
	no_dupe_args:                                     '[]'
	no_dupe_keys:                                     '[]'
	no_empty_pattern:                                 '[{"allowObjectPatternsAsParameters":false}]'
	no_useless_rename:                                '[{"ignoreDestructuring":false,"ignoreImport":false,"ignoreExport":false}]'
	no_useless_computed_key:                          '[{"enforceForClassMembers":true}]'
	object_shorthand:                                 '["always"]'
	require_yield:                                    '[]'
	eqeqeq:                                           '["always"]'
	yoda:                                             '["never",{"exceptRange":false,"onlyEquality":false}]'
	no_eq_null:                                       '[]'
	no_extra_boolean_cast:                            '[{}]'
	no_implicit_coercion:                             '[{"allow":[],"boolean":true,"disallowTemplateShorthand":false,"number":true,"string":true}]'
	logical_assignment_operators:                     '["always"]'
	operator_assignment:                              '["always"]'
	prefer_exponentiation_operator:                   '[]'
	no_sequences:                                     '[{"allowInParentheses":true}]'
	no_return_assign:                                 '["except-parens"]'
	no_unexpected_multiline:                          '[]'
	no_loss_of_precision:                             '[]'
	no_nonoctal_decimal_escape:                       '[]'
	no_octal:                                         '[]'
	no_octal_escape:                                  '[]'
	prefer_numeric_literals:                          '[]'
	no_multi_str:                                     '[]'
	no_template_curly_in_string:                      '[]'
	no_useless_concat:                                '[]'
	prefer_template:                                  '[]'
	no_irregular_whitespace:                          '[{"skipComments":false,"skipJSXText":false,"skipRegExps":false,"skipStrings":true,"skipTemplates":false}]'
	unicode_bom:                                      '["never"]'
	no_sparse_arrays:                                 '[]'
	no_new:                                           '[]'
	no_new_func:                                      '[]'
	no_new_wrappers:                                  '[]'
	no_new_native_nonconstructor:                     '[]'
	no_obj_calls:                                     '[]'
	no_object_constructor:                            '[]'
	no_async_promise_executor:                        '[]'
	no_extra_bind:                                    '[]'
	no_useless_call:                                  '[]'
	prefer_spread:                                    '[]'
	prefer_rest_params:                               '[]'
	symbol_description:                               '[]'
	radix_rule:                                       '["always"]'
	no_extend_native:                                 '[{"exceptions":[]}]'
	core_no_implied_eval:                             '[]'
	no_caller:                                        '[]'
	no_iterator:                                      '[]'
	no_proto:                                         '[]'
	no_script_url:                                    '[]'
	no_prototype_builtins:                            '[]'
	prefer_object_has_own:                            '[]'
	prefer_object_spread:                             '[]'
	core_dot_notation:                                '[{"allowKeywords":true,"allowPattern":""}]'
	preserve_caught_error:                            '[{"requireCatchParameter":false,"errorClassNames":[]}]'
	no_class_assign:                                  '[]'
	no_const_assign:                                  '[]'
	no_ex_assign:                                     '[]'
	no_func_assign:                                   '[]'
	no_global_assign:                                 '[{"exceptions":[]}]'
	no_import_assign:                                 '[]'
	no_label_var:                                     '[]'
	no_shadow_restricted_names:                       '[{"reportGlobalThis":true}]'
	no_unassigned_vars:                               '[]'
	no_delete_var:                                    '[]'
	block_scoped_var:                                 '[]'
	consistent_this:                                  '["that"]'
	no_var:                                           '[]'
	prefer_const:                                     '[{"destructuring":"any","ignoreReadBeforeAssign":false}]'
	vars_on_top:                                      '[]'
	sort_vars:                                        '[{"ignoreCase":false}]'
	strict_rule:                                      '["safe"]'
	no_inner_declarations:                            '["functions",{"blockScopedFunctions":"allow"}]'
	no_lone_blocks:                                   '[]'
	no_loop_func:                                     '[]'
	no_implicit_globals:                              '[{"lexicalBindings":false}]'
	no_unmodified_loop_condition:                     '[{"checkConditionalExpressions":false}]'
	no_control_regex:                                 '[]'
	no_div_regex:                                     '[]'
	no_empty_character_class:                         '[]'
	no_invalid_regexp:                                '[{}]'
	no_misleading_character_class:                    '[{"allowEscape":false}]'
	no_regex_spaces:                                  '[]'
	no_useless_backreference:                         '[]'
	no_useless_escape:                                '[{"allowRegexCharacters":[]}]'
	prefer_regex_literals:                            '[{"disallowRedundantWrapping":false}]'
	no_warning_comments:                              '[{"location":"start","terms":["todo","fixme","xxx"]}]'
	no_restricted_globals:                            '[]'
	no_restricted_properties:                         '[]'
	no_restricted_exports:                            '[{}]'
	no_restricted_imports:                            '[]'
	no_constructor_return:                            '[]'
	no_promise_executor_return:                       '[{"allowVoid":false}]'
	no_invalid_this:                                  '[{"capIsConstructor":true}]'
	getter_return:                                    '[{"allowImplicit":false}]'
	no_unreachable_loop:                              '[{"ignore":[]}]'
	no_useless_return:                                '[]'
	no_unreachable:                                   '[]'
	no_fallthrough:                                   '[{"allowEmptyCase":false,"reportUnusedFallthroughComment":false}]'
	constructor_super:                                '[]'
	no_this_before_super:                             '[]'
	no_useless_assignment:                            '[]'
	no_restricted_syntax:                             '[]'
	unicorn_no_lonely_if:                             '[]'
	unicorn_no_negated_condition:                     '[]'
	unicorn_no_negation_in_equality_check:            '[]'
	unicorn_no_nested_ternary:                        '[]'
	unicorn_no_typeof_undefined:                      '[{"checkGlobalVariables":false}]'
	unicorn_prefer_logical_operator_over_ternary:     '[]'
	unicorn_prefer_ternary:                           '["always",{"checkVaryingBase":false,"checkComputedMemberAccess":false}]'
	unicorn_prefer_switch:                            '[{"minimumCases":3,"emptyDefaultCase":"no-default-comment"}]'
	unicorn_switch_case_braces:                       '["always"]'
	unicorn_switch_case_break_position:               '[]'
	unicorn_no_useless_switch_case:                   '[]'
	unicorn_prefer_simple_condition_first:            '[]'
	unicorn_prefer_date_now:                          '[]'
	unicorn_throw_new_error:                          '[]'
	unicorn_error_message:                            '[]'
	unicorn_consistent_date_clone:                    '[]'
	unicorn_consistent_assert:                        '[]'
	unicorn_no_new_buffer:                            '[]'
	unicorn_prefer_type_error:                        '[]'
	unicorn_no_useless_error_capture_stack_trace:     '[]'
	unicorn_prefer_structured_clone:                  '[{"functions":[]}]'
	unicorn_custom_error_definition:                  '[]'
	unicorn_no_instanceof_builtins:                   '[{"useErrorIsError":false,"strategy":"loose","include":[],"exclude":[]}]'
	unicorn_new_for_builtins:                         '[]'
	unicorn_no_hex_escape:                            '[]'
	unicorn_escape_case:                              '["uppercase"]'
	unicorn_consistent_template_literal_escape:       '[]'
	unicorn_prefer_string_trim_start_end:             '[]'
	unicorn_no_console_spaces:                        '[]'
	unicorn_prefer_code_point:                        '[]'
	unicorn_prefer_string_slice:                      '[]'
	unicorn_text_encoding_identifier_case:            '[{"withDash":false}]'
	unicorn_no_zero_fractions:                        '[]'
	unicorn_prefer_bigint_literals:                   '[]'
	unicorn_prefer_number_properties:                 '[{"checkInfinity":false,"checkNaN":false}]'
	unicorn_prefer_string_raw:                        '[]'
	unicorn_prefer_string_replace_all:                '[]'
	unicorn_require_number_to_fixed_digits_argument:  '[]'
	unicorn_prefer_math_trunc:                        '[]'
	unicorn_prefer_math_min_max:                      '[]'
	unicorn_prefer_modern_math_apis:                  '[]'
	unicorn_prefer_native_coercion_functions:         '[]'
	unicorn_no_array_callback_reference:              '[{"ignore":[]}]'
	unicorn_no_for_each:                              '[]'
	unicorn_no_array_method_this_argument:            '[]'
	unicorn_no_array_reverse:                         '[{"allowExpressionStatement":true}]'
	unicorn_no_array_sort:                            '[{"allowExpressionStatement":true}]'
	unicorn_no_new_array:                             '[]'
	unicorn_prefer_array_flat:                        '[{"functions":[]}]'
	unicorn_prefer_array_flat_map:                    '[]'
	unicorn_prefer_array_index_of:                    '[]'
	unicorn_prefer_array_some:                        '[]'
	unicorn_require_array_join_separator:             '[]'
	unicorn_prefer_negative_index:                    '[]'
	unicorn_consistent_existence_index_check:         '[]'
	unicorn_explicit_length_check:                    '[{"non-zero":"greater-than"}]'
	unicorn_no_unnecessary_array_flat_depth:          '[]'
	unicorn_no_unnecessary_array_splice_count:        '[]'
	unicorn_no_unnecessary_slice_end:                 '[]'
	unicorn_no_useless_length_check:                  '[]'
	unicorn_no_unreadable_array_destructuring:        '[{"maximumIgnoredElements":1}]'
	unicorn_prefer_set_size:                          '[]'
	array_callback_return:                            '[{"allowImplicit":false,"checkForEach":false,"allowVoid":false}]'
	no_lonely_if:                                     '[]'
	no_negated_condition:                             '[]'
	no_throw_literal:                                 '[]'
	require_atomic_updates:                           '[{"allowProperties":false}]'
	class_methods_use_this:                           '[{"enforceForClassFields":true,"exceptMethods":[],"ignoreClassesThatImplementAnInterface":false,"ignoreOverrideMethods":false}]'
	no_explicit_any:                                  '[{"fixToUnknown":false,"ignoreRestArgs":false}]'
	unicorn_consistent_empty_array_spread:            '[]'
	unicorn_no_useless_fallback_in_spread:            '[]'
	unicorn_no_useless_collection_argument:           '[]'
	unicorn_no_useless_iterator_to_array:             '[]'
	unicorn_no_useless_spread:                        '[]'
	unicorn_prefer_single_call:                       '[{"ignore":[]}]'
	unicorn_no_immediate_mutation:                    '[{"checkConditionals":false}]'
	unicorn_prefer_blob_reading_methods:              '[]'
	unicorn_prefer_response_static_json:              '[]'
	unicorn_no_await_expression_member:               '[]'
	unicorn_prefer_spread:                            '[]'
	unicorn_no_await_in_promise_methods:              '[]'
	unicorn_no_invalid_fetch_options:                 '[]'
	unicorn_no_unnecessary_await:                     '[]'
	unicorn_no_thenable:                              '[]'
	unicorn_no_single_promise_in_promise_methods:     '[]'
	unicorn_no_useless_promise_resolve_reject:        '[]'
	unicorn_prefer_node_protocol:                     '[]'
	unicorn_no_process_exit:                          '[]'
	unicorn_no_named_default:                         '[]'
	unicorn_require_module_attributes:                '[]'
	unicorn_require_module_specifiers:                '[]'
	unicorn_prefer_json_parse_buffer:                 '[]'
	unicorn_no_anonymous_default_export:              '[]'
	unicorn_prefer_import_meta_properties:            '[]'
	unicorn_prefer_module:                            '[]'
	unicorn_prefer_reflect_apply:                     '[]'
	unicorn_prefer_export_from:                       '[{"checkUsedVariables":true}]'
	unicorn_relative_url_style:                       '["never"]'
	unicorn_prefer_prototype_methods:                 '[]'
	unicorn_better_regex:                             '[]'
	unicorn_no_this_assignment:                       '[]'
	unicorn_no_unreadable_iife:                       '[]'
	unicorn_no_accessor_recursion:                    '[]'
	unicorn_no_static_only_class:                     '[]'
	unicorn_prefer_class_fields:                      '[]'
	unicorn_consistent_function_scoping:              '[{"checkArrowFunctions":true}]'
	unicorn_isolated_functions:                       '[{"functions":["makeSynchronous","workerize"],"selectors":[],"comments":["@isolated"],"overrideGlobals":{}}]'
	unicorn_no_useless_undefined:                     '[{"checkArguments":true,"checkArrowFunctionBody":true}]'
	unicorn_no_keyword_prefix:                        '[{}]'
	unicorn_prefer_object_from_entries:               '[{"functions":[]}]'
	unicorn_prefer_default_parameters:                '[{"checkFallbackExpressions":true}]'
	unicorn_no_unused_properties:                     '[]'
	stylistic_array_bracket_spacing:                  '["never"]'
	stylistic_rest_spread_spacing:                    '["never"]'
	stylistic_semi_spacing:                           '[{"before":false,"after":true}]'
	stylistic_space_in_parens:                        '["never"]'
	stylistic_switch_colon_spacing:                   '[{"before":false,"after":true}]'
	stylistic_template_curly_spacing:                 '["never"]'
	stylistic_template_tag_spacing:                   '["never"]'
	stylistic_no_whitespace_before_property:          '[]'
	stylistic_block_spacing:                          '["always"]'
	stylistic_comma_spacing:                          '[{"before":false,"after":true}]'
	stylistic_computed_property_spacing:              '["never",{"enforceForClassMembers":true}]'
	stylistic_object_curly_spacing:                   '["never"]'
	stylistic_keyword_spacing:                        '[{"before":true,"after":true,"overrides":{}}]'
	stylistic_space_before_blocks:                    '["always"]'
	stylistic_arrow_spacing:                          '[{"before":true,"after":true}]'
	stylistic_yield_star_spacing:                     '["after"]'
	stylistic_type_annotation_spacing:                '[{}]'
	stylistic_type_generic_spacing:                   '[{"before":false,"after":false}]'
	stylistic_type_named_tuple_spacing:               '[]'
	stylistic_space_before_function_paren:            '["always"]'
	stylistic_key_spacing:                            '[{}]'
	stylistic_space_infix_ops:                        '[{"int32Hint":false,"ignoreOperators":[],"ignoreTypes":false}]'
	stylistic_space_unary_ops:                        '[{"words":true,"nonwords":false}]'
	stylistic_function_call_spacing:                  '["never"]'
	stylistic_brace_style:                            '["1tbs",{"allowSingleLine":false}]'
	stylistic_comma_style:                            '["last"]'
	stylistic_dot_location:                           '["property"]'
	stylistic_function_call_argument_newline:         '["always"]'
	stylistic_function_paren_newline:                 '["multiline"]'
	stylistic_implicit_arrow_linebreak:               '["beside"]'
	stylistic_multiline_ternary:                      '["always"]'
	stylistic_nonblock_statement_body_position:       '["beside"]'
	stylistic_one_var_declaration_per_line:           '["initializations"]'
	stylistic_quotes:                                 '["double",{"allowTemplateLiterals":"never","avoidEscape":false,"ignoreStringLiterals":false}]'
	stylistic_no_multi_spaces:                        '[{"ignoreEOLComments":false,"includeTabs":true}]'
	stylistic_no_trailing_spaces:                     '[{"skipBlankLines":false,"ignoreComments":false}]'
	stylistic_no_mixed_spaces_and_tabs:               '[]'
	stylistic_eol_last:                               '["always"]'
	stylistic_spaced_comment:                         '["always"]'
	stylistic_lines_between_class_members:            '["always",{"exceptAfterOverload":true,"exceptAfterSingleLine":false}]'
	stylistic_new_parens:                             '["always"]'
	stylistic_no_floating_decimal:                    '[]'
	stylistic_no_extra_semi:                          '[]'
	stylistic_semi_style:                             '["last"]'
	stylistic_semi:                                   '["always"]'
	stylistic_object_curly_newline:                   '[]'
	stylistic_object_property_newline:                '[{"allowAllPropertiesOnSameLine":false}]'
	stylistic_list_style:                             '[{"empty":"ignore","singleLine":{"spacing":"never","maxItems":1.7976931348623157e+308},"multiLine":{"minItems":0},"overrides":{"{}":{"singleLine":{"spacing":"always"}}}}]'
	stylistic_exp_jsx_props_style:                    '[{"singleLine":{"maxItems":1.7976931348623157e+308},"multiLine":{"minItems":0,"maxItemsPerLine":1}}]'
	stylistic_arrow_parens:                           '["always"]'
	stylistic_comma_dangle:                           '["never"]'
	stylistic_member_delimiter_style:                 '[{"multiline":{"delimiter":"semi","requireLast":true},"singleline":{"delimiter":"semi","requireLast":false},"multilineDetection":"brackets"}]'
	stylistic_quote_props:                            '["always"]'
	stylistic_no_extra_parens:                        '["all"]'
	marcrock_no_newline_if_body_class_empty:          '[]'
	marcrock_numeric_separators:                      '[]'
	marcrock_uppercase_first_class_letter:            '[]'
	marcrock_prefer_at:                               '[{}]'
	perfectionist_sort_array_includes:                '[]'
	perfectionist_sort_sets:                          '[]'
	perfectionist_sort_maps:                          '[]'
	perfectionist_sort_union_types:                   '[]'
	perfectionist_sort_intersection_types:            '[]'
	ban_ts_comment:                                   '[{"minimumDescriptionLength":3,"ts-check":false,"ts-expect-error":"allow-with-description","ts-ignore":true,"ts-nocheck":true}]'
	ban_tslint_comment:                               '[]'
	default_param_last:                               '[]'
	init_declarations:                                '["always"]'
	max_params:                                       '[{"countVoidThis":false,"max":3}]'
	method_signature_style:                           '["property"]'
	no_empty_object_type:                             '[{"allowInterfaces":"never","allowObjectTypes":"never"}]'
	no_non_null_assertion:                            '[]'
	ts_no_invalid_this:                               '[{"capIsConstructor":true}]'
	no_redeclare:                                     '[{"builtinGlobals":true,"ignoreDeclarationMerge":true}]'
	perfectionist_sort_heritage_clauses:              '[]'
	perfectionist_sort_import_attributes:             '[]'
	perfectionist_sort_export_attributes:             '[]'
	perfectionist_sort_switch_case:                   '[]'
	perfectionist_sort_named_imports:                 '[]'
	perfectionist_sort_named_exports:                 '[]'
	perfectionist_sort_exports:                       '[]'
	explicit_function_return_type:                    '[{"allowConciseArrowFunctionExpressionsStartingWithVoid":false,"allowDirectConstAssertionInArrowFunctions":true,"allowedNames":[],"allowExpressions":false,"allowFunctionsWithoutTypeParameters":false,"allowHigherOrderFunctions":true,"allowIIFEs":false,"allowTypedFunctionExpressions":true}]'
	explicit_module_boundary_types:                   '[{"allowArgumentsExplicitlyTypedAsAny":false,"allowDirectConstAssertionInArrowFunctions":true,"allowedNames":[],"allowHigherOrderFunctions":true,"allowOverloadFunctions":false,"allowTypedFunctionExpressions":true}]'
	explicit_member_accessibility:                    '[{"accessibility":"explicit"}]'
	parameter_properties:                             '[{"allow":[],"prefer":"class-property"}]'
	prefer_literal_enum_member:                       '[{"allowBitwiseExpressions":false}]'
	no_magic_numbers:                                 '[{"detectObjects":false,"enforceConst":false,"ignore":[],"ignoreArrayIndexes":false,"ignoreEnums":false,"ignoreNumericLiteralTypes":false,"ignoreReadonlyClassProperties":false,"ignoreTypeIndexes":false}]'
	no_restricted_types:                              '[{}]'
	no_generated_empty_object_type:                   '[]'
	no_unsafe_enum_assignment:                        '[]'
	member_ordering:                                  '[{"default":{"memberTypes":["signature","call-signature","public-static-field","protected-static-field","private-static-field","#private-static-field","public-decorated-field","protected-decorated-field","private-decorated-field","public-instance-field","protected-instance-field","private-instance-field","#private-instance-field","public-abstract-field","protected-abstract-field","public-field","protected-field","private-field","#private-field","static-field","instance-field","abstract-field","decorated-field","field","static-initialization","public-constructor","protected-constructor","private-constructor","constructor","public-static-accessor","protected-static-accessor","private-static-accessor","#private-static-accessor","public-decorated-accessor","protected-decorated-accessor","private-decorated-accessor","public-instance-accessor","protected-instance-accessor","private-instance-accessor","#private-instance-accessor","public-abstract-accessor","protected-abstract-accessor","public-accessor","protected-accessor","private-accessor","#private-accessor","static-accessor","instance-accessor","abstract-accessor","decorated-accessor","accessor","public-static-get","protected-static-get","private-static-get","#private-static-get","public-decorated-get","protected-decorated-get","private-decorated-get","public-instance-get","protected-instance-get","private-instance-get","#private-instance-get","public-abstract-get","protected-abstract-get","public-get","protected-get","private-get","#private-get","static-get","instance-get","abstract-get","decorated-get","get","public-static-set","protected-static-set","private-static-set","#private-static-set","public-decorated-set","protected-decorated-set","private-decorated-set","public-instance-set","protected-instance-set","private-instance-set","#private-instance-set","public-abstract-set","protected-abstract-set","public-set","protected-set","private-set","#private-set","static-set","instance-set","abstract-set","decorated-set","set","public-static-method","protected-static-method","private-static-method","#private-static-method","public-decorated-method","protected-decorated-method","private-decorated-method","public-instance-method","protected-instance-method","private-instance-method","#private-instance-method","public-abstract-method","protected-abstract-method","public-method","protected-method","private-method","#private-method","static-method","instance-method","abstract-method","decorated-method","method"]}}]'
	perfectionist_sort_classes:                       '[]'
	perfectionist_sort_imports:                       '[]'
	vue_no_v_html:                                    '[]'
	vue_no_v_text:                                    '[]'
	vue_no_duplicate_attributes:                      '[]'
	vue_comment_directive:                            '[]'
	vue_no_parsing_error:                             '[]'
	vue_no_deprecated_v_is:                           '[]'
	vue_no_deprecated_scope_attribute:                '[]'
	vue_no_deprecated_filter:                         '[]'
	vue_no_deprecated_inline_template:                '[]'
	vue_require_component_is:                         '[]'
	vue_no_deprecated_v_on_native_modifier:           '[]'
	vue_no_v_model_argument:                          '[]'
	vue_no_textarea_mustache:                         '[]'
	vue_no_use_v_else_with_v_for:                     '[]'
	vue_no_v_for_template_key:                        '[]'
	vue_no_template_key:                              '[]'
	vue_no_custom_modifiers_on_v_model:               '[]'
	vue_no_deprecated_v_bind_sync:                    '[]'
	vue_no_spaces_around_equal_signs_in_attribute:    '[]'
	vue_no_deprecated_v_on_number_modifiers:          '[]'
	vue_valid_v_bind:                                 '[]'
	vue_valid_v_cloak:                                '[]'
	vue_valid_v_html:                                 '[]'
	vue_valid_v_once:                                 '[]'
	vue_valid_v_pre:                                  '[]'
	vue_valid_v_text:                                 '[]'
	vue_valid_v_show:                                 '[]'
	vue_valid_v_if:                                   '[]'
	vue_valid_v_else_if:                              '[]'
	vue_valid_v_else:                                 '[]'
	vue_valid_v_is:                                   '[]'
	vue_valid_v_on:                                   '[]'
	vue_v_on_style:                                   '[]'
	vue_v_bind_style:                                 '[]'
	vue_no_multiple_objects_in_class:                 '[]'
	vue_require_v_for_key:                            '[]'
	vue_no_deprecated_html_element_is:                '[]'
	vue_no_use_v_if_with_v_for:                       '[]'
	vue_no_v_for_template_key_on_child:               '[]'
	vue_html_end_tags:                                '[]'
	vue_valid_attribute_name:                         '[]'
	vue_v_for_delimiter_style:                        '[]'
	vue_no_v_text_v_html_on_component:                '[]'
	vue_no_lone_template:                             '[]'
	vue_html_button_has_type:                         '[]'
	vue_no_deprecated_router_link_tag_prop:           '[]'
	vue_no_restricted_html_elements:                  '[]'
	vue_no_useless_template_attributes:               '[]'
	vue_mustache_interpolation_spacing:               '[]'
	vue_static_class_names_order:                     '[]'
	vue_restricted_component_names:                   '[]'
	vue_slot_name_casing:                             '[]'
	vue_first_attribute_linebreak:                    '[]'
	vue_html_quotes:                                  '[]'
	vue_no_literals_in_template:                      '[]'
	vue_require_toggle_inside_transition:             '[]'
	vue_no_restricted_static_attribute:               '[]'
	vue_html_closing_bracket_spacing:                 '[]'
	vue_html_closing_bracket_newline:                 '[]'
	vue_attribute_hyphenation:                        '[]'
	vue_v_on_event_hyphenation:                       '[]'
	vue_valid_v_memo:                                 '[]'
	vue_no_static_inline_styles:                      '[]'
	vue_no_child_content:                             '[]'
	vue_no_template_target_blank:                     '[]'
	vue_no_restricted_class:                          '[]'
	vue_no_useless_v_bind:                            '[]'
	vue_no_restricted_v_bind:                         '[]'
	vue_no_restricted_v_on:                           '[]'
	vue_valid_v_bind_sync:                            '[]'
	vue_v_slot_style:                                 '[]'
	vue_prefer_true_attribute_shorthand:              '[]'
	vue_no_dupe_v_else_if:                            '[]'
	vue_no_deprecated_slot_attribute:                 '[]'
	vue_no_deprecated_slot_scope_attribute:           '[]'
	vue_this_in_template:                             '[]'
	vue_no_unused_vars:                               '[]'
	vue_no_define_model_default:                      '[]'
	vue_no_deprecated_functional_template:            '[]'
	vue_require_render_return:                        '[]'
	vue_no_deprecated_vue_config_keycodes:            '[]'
	vue_no_root_v_if:                                 '[]'
	vue_no_arrow_functions_in_watch:                  '[]'
	vue_one_component_per_file:                       '[]'
	vue_valid_model_definition:                       '[]'
	vue_no_deprecated_events_api:                     '[]'
	vue_define_props_declaration:                     '[]'
	vue_valid_template_root:                          '[]'
	vue_no_export_in_script_setup:                    '[]'
	vue_require_default_export:                       '[]'
	vue_jsx_uses_vars:                                '[]'
	vue_match_component_import_name:                  '[]'
	vue_no_deprecated_destroyed_lifecycle:            '[]'
	vue_max_template_depth:                           '[]'
	vue_no_reserved_props:                            '[]'
	vue_no_this_in_before_route_enter:                '[]'
	vue_max_props:                                    '[]'
	vue_no_content_outside_block:                     '[]'
	vue_no_shared_component_data:                     '[]'
	vue_no_deprecated_data_object_declaration:        '[]'
	vue_prop_name_casing:                             '[]'
	vue_define_props_destructuring:                   '[]'
	vue_component_definition_name_casing:             '[]'
	vue_require_emit_validator:                       '[]'
	vue_no_computed_properties_in_data:               '[]'
	vue_no_empty_component_block:                     '[]'
	vue_no_import_compiler_macros:                    '[]'
	vue_prefer_prop_type_boolean_first:               '[]'
	vue_require_macro_variable_name:                  '[]'
	vue_define_emits_declaration:                     '[]'
	vue_no_props_shadow:                              '[]'
	vue_require_prop_type_constructor:                '[]'
	vue_no_restricted_block:                          '[]'
	vue_component_options_name_casing:                '[]'
	vue_max_lines_per_block:                          '[]'
	vue_no_multiple_slot_args:                        '[]'
	vue_no_reserved_keys:                             '[]'
	vue_no_deprecated_delete_set:                     '[]'
	vue_require_prop_types:                           '[]'
	vue_return_in_computed_property:                  '[]'
	vue_no_deprecated_props_default_this:             '[]'
	vue_require_slots_as_functions:                   '[]'
	vue_require_name_property:                        '[]'
	vue_arrow_spacing:                                '[{"before":true,"after":true}]'
	vue_camelcase:                                    '[]'
	vue_comma_dangle:                                 '["never"]'
	vue_dot_location:                                 '[]'
	vue_no_empty_pattern:                             '[{"allowObjectPatternsAsParameters":false}]'
	vue_no_sparse_arrays:                             '[]'
	vue_operator_linebreak:                           '[]'
	vue_array_bracket_newline:                        '[]'
	vue_array_bracket_spacing:                        '["never"]'
	vue_array_element_newline:                        '[]'
	vue_block_spacing:                                '["always"]'
	vue_brace_style:                                  '["1tbs",{"allowSingleLine":false}]'
	vue_dot_notation:                                 '[{"allowKeywords":true,"allowPattern":""}]'
	vue_eqeqeq:                                       '["always"]'
	vue_key_spacing:                                  '[{}]'
	vue_keyword_spacing:                              '[{"before":true,"after":true,"overrides":{}}]'
	vue_no_restricted_syntax:                         '[]'
	vue_no_useless_concat:                            '[]'
	vue_object_curly_newline:                         '[]'
	vue_object_curly_spacing:                         '["never"]'
	vue_object_property_newline:                      '[{"allowAllPropertiesOnSameLine":false}]'
	vue_prefer_template:                              '[]'
	vue_no_implicit_coercion:                         '[{"allow":[],"boolean":true,"disallowTemplateShorthand":false,"number":true,"string":true}]'
	vue_no_loss_of_precision:                         '[]'
	vue_no_negated_condition:                         '[]'
	vue_object_shorthand:                             '["always"]'
	vue_space_infix_ops:                              '[{"int32Hint":false,"ignoreOperators":[],"ignoreTypes":false}]'
	vue_space_unary_ops:                              '[{"words":true,"nonwords":false}]'
	vue_template_curly_spacing:                       '["never"]'
	vue_comma_spacing:                                '[{"before":false,"after":true}]'
	vue_multiline_ternary:                            '["always"]'
	vue_space_in_parens:                              '["never"]'
	vue_func_call_spacing:                            '["never"]'
	vue_comma_style:                                  '["last"]'
	vue_no_constant_condition:                        '[{"checkLoops":"allExceptWhileTrue"}]'
	vue_no_console:                                   '[]'
	vue_quote_props:                                  '["always"]'
	vue_no_extra_parens:                              '["all"]'
	vue_max_attributes_per_line:                      '[]'
	vue_no_useless_mustaches:                         '[]'
	vue_no_negated_v_if_condition:                    '[]'
	vue_use_v_on_exact:                               '[]'
	vue_prefer_v_model:                               '[]'
	vue_singleline_html_element_content_newline:      '[]'
	vue_multiline_html_element_content_newline:       '[]'
	vue_html_self_closing:                            '[]'
	vue_padding_line_between_blocks:                  '[]'
	vue_padding_line_between_tags:                    '[]'
	vue_block_tag_newline:                            '[]'
	vue_block_lang:                                   '[]'
	vue_no_bare_strings_in_template:                  '[]'
	vue_v_if_else_key:                                '[]'
	vue_no_irregular_whitespace:                      '[]'
	vue_valid_v_for:                                  '[]'
	vue_valid_v_model:                                '[]'
	vue_valid_v_slot:                                 '[]'
	vue_no_unsupported_features:                      '[]'
	vue_prefer_separate_static_class:                 '[]'
	vue_no_duplicate_class_names:                     '[]'
	vue_max_len:                                      '[]'
	vue_attributes_order:                             '[]'
	vue_no_deprecated_dollar_listeners_api:           '[]'
	vue_no_deprecated_dollar_scopedslots_api:         '[]'
	vue_prefer_use_template_ref:                      '[]'
	vue_no_duplicate_attr_inheritance:                '[]'
	vue_no_unused_components:                         '[]'
	vue_no_template_shadow:                           '[]'
	vue_require_explicit_slots:                       '[]'
	vue_no_undef_directives:                          '[]'
	vue_component_name_in_template_casing:            '[]'
	vue_no_unused_refs:                               '[]'
	vue_custom_event_name_casing:                     '[]'
	vue_no_restricted_custom_event:                   '[]'
	vue_no_unused_emit_declarations:                  '[]'
	vue_prefer_single_event_payload:                  '[]'
	vue_no_shadow_native_events:                      '[]'
	vue_require_explicit_emits:                       '[]'
	vue_no_undef_components:                          '[]'
	vue_v_on_handler_style:                           '[]'
	vue_no_mutating_props:                            '[]'
	vue_no_use_computed_property_like_method:         '[]'
	vue_no_unused_properties:                         '[]'
	vue_no_undef_properties:                          '[]'
	vue_prefer_define_options:                        '[]'
	vue_multi_word_component_names:                   '[]'
	vue_no_multiple_template_root:                    '[]'
	vue_no_potential_component_option_typo:           '[]'
	vue_no_deprecated_model_definition:               '[]'
	vue_match_component_file_name:                    '[]'
	vue_enforce_style_attribute:                      '[]'
	vue_require_direct_export:                        '[]'
	vue_no_restricted_component_names:                '[]'
	vue_no_restricted_component_options:              '[]'
	vue_prefer_import_from_vue:                       '[]'
	vue_new_line_between_multi_line_property:         '[]'
	vue_component_api_style:                          '[]'
	vue_no_reserved_component_names:                  '[]'
	vue_require_typed_object_prop:                    '[]'
	vue_return_in_emits_validator:                    '[]'
	vue_valid_define_props:                           '[]'
	vue_valid_define_emits:                           '[]'
	vue_valid_define_options:                         '[]'
	vue_require_prop_comment:                         '[]'
	vue_define_macros_order:                          '[]'
	vue_order_in_components:                          '[]'
	vue_padding_lines_in_component_definition:        '[]'
	vue_sort_keys:                                    '[]'
	vue_html_comment_content_spacing:                 '[]'
	vue_html_comment_content_newline:                 '[]'
	vue_html_comment_indent:                          '[]'
	vue_no_multi_spaces:                              '[]'
	vue_block_order:                                  '[]'
	vue_no_lifecycle_after_await:                     '[]'
	vue_no_watch_after_await:                         '[]'
	vue_no_expose_after_await:                        '[]'
	vue_no_restricted_call_after_await:               '[]'
	vue_next_tick_style:                              '[]'
	vue_valid_next_tick:                              '[]'
	vue_no_boolean_default:                           '[]'
	vue_no_required_prop_with_default:                '[]'
	vue_require_default_prop:                         '[]'
	vue_require_valid_default_prop:                   '[]'
	vue_no_restricted_props:                          '[]'
	vue_require_typed_ref:                            '[]'
	vue_no_ref_as_operand:                            '[]'
	vue_no_ref_object_reactivity_loss:                '[]'
	vue_no_setup_props_reactivity_loss:               '[]'
	vue_require_expose:                               '[]'
	vue_no_side_effects_in_computed_properties:       '[]'
	vue_no_async_in_computed_properties:              '[]'
	vue_no_dupe_keys:                                 '[]'
	svelte_comment_directive:                         '[]'
	svelte_system:                                    '[]'
	svelte_no_at_html_tags:                           '[]'
	svelte_no_at_debug_tags:                          '[]'
	svelte_button_has_type:                           '[]'
	svelte_no_target_blank:                           '[]'
	svelte_require_each_key:                          '[]'
	svelte_valid_each_key:                            '[]'
	svelte_no_object_in_text_mustaches:               '[]'
	svelte_shorthand_attribute:                       '[]'
	svelte_no_spaces_around_equal_signs_in_attribute: '[]'
	svelte_spaced_html_comment:                       '[]'
	svelte_no_dupe_else_if_blocks:                    '[]'
	svelte_no_useless_mustaches:                      '[]'
	svelte_first_attribute_linebreak:                 '[]'
	svelte_shorthand_directive:                       '[]'
	svelte_html_closing_bracket_spacing:              '[]'
	svelte_html_closing_bracket_new_line:             '[]'
	svelte_no_dynamic_slot_name:                      '[]'
	svelte_html_quotes:                               '[]'
	svelte_mustache_spacing:                          '[]'
	svelte_no_inline_styles:                          '[]'
	svelte_no_raw_special_elements:                   '[]'
	svelte_no_nested_style_tag:                       '[]'
	svelte_no_useless_children_snippet:               '[]'
	svelte_no_dupe_on_directives:                     '[]'
	svelte_no_dupe_use_directives:                    '[]'
	svelte_prefer_attribute_interpolation:            '[]'
	svelte_max_attributes_per_line:                   '[]'
	svelte_html_self_closing:                         '[]'
	svelte_no_at_const_tags:                          '[]'
	svelte_no_not_function_handler:                   '[]'
	svelte_block_lang:                                '[]'
	svelte_prefer_class_directive:                    '[]'
	svelte_no_svelte_internal:                        '[]'
	svelte_no_inspect:                                '[]'
	svelte_no_store_async:                            '[]'
	svelte_require_stores_init:                       '[]'
	svelte_no_ignored_unsubscribe:                    '[]'
	svelte_require_store_callbacks_use_set_param:     '[]'
	svelte_derived_has_same_inputs_outputs:           '[]'
}

// Finding is a problem a rule found at a node.
pub struct Finding {
pub:
	stmt        Ident // position of the reported node
	message_id  string
	data        map[string]string // values of the {{placeholders}} of the message
	rule        string            // the rule that reports it (set by lint_file)
	has_fix     bool
	fix         Fix          // the fix of the report, if has_fix (see fixes.v)
	suggestions []Suggestion // the suggestions of the report, in ESLint's order
	severity    int = 2 // 1 for a warning, 2 for an error (set by lint_file from the configuration)
	// A problem that is not a rule's finding (a directive comment without use, an invalid inline
	// configuration…) carries its message in `text`; its `rule` is `problem_rule`, or the id of a
	// rule that does not exist, and its message_id is `fatal`, `error` or `warning`.
	text string
	// ESLint's column of a parsing error is TypeScript's character, which counts from 0, where any
	// other column counts from 1.
	column_from_zero bool
	// The rule builds its `loc` from offsets of the text (sourceCode.getLocFromIndex, or the
	// lines of sourceCode.lines) and not from a node or a token: ESLint's lines end at CRLF, LF,
	// CR, U+2028 and U+2029 there, where the locations of vue-eslint-parser's nodes and tokens
	// end only at LF (the two only differ in a .vue file).
	text_loc bool
	// Only the start (text_loc_start) or only the end (text_loc_end) of the `loc` comes from the
	// text, the other side from a node or a token (vue/block-tag-newline's).
	text_loc_start bool
	text_loc_end   bool
	// A report of a .vue file whose `loc` is a line and a column given as such
	// (vue/no-parsing-error's, from the errors of the document, which may be past the end of the
	// file): when fixed_line is not 0, ESLint's line and column are fixed_line and fixed_column
	// (from 1), and the report has no end.
	fixed_line   int
	fixed_column int
	// A report of any file whose `loc` is a start and an end given as lines and columns (from 1)
	// that need not be places of the text (vue/max-len's: the column of the limit and the length
	// of the line, tabs counted as tabWidth): fixed_line and fixed_column, fixed_end_line and
	// fixed_end_column. `stmt` is a place on that line, for what needs a byte offset.
	line_loc         bool
	fixed_end_line   int
	fixed_end_column int
	// The report's `loc` is a line and a column without an end (`{ line: 0, column: 0 }`, a
	// selector error of vue/block-order): the line has no end with --fixes.
	no_end bool
}

// problem_rule is the `rule` of the problems ESLint reports without a rule (`ruleId: null`).
pub const problem_rule = 'eslint'

// typescript_eslint_prefix is the prefix of the ids of the ported rules in an ESLint configuration.
pub const typescript_eslint_prefix = '@typescript-eslint/'

// RuleSetting is a ported rule a configuration turns on.
pub struct RuleSetting {
pub:
	name     string      // without the prefix
	severity int         // 1 = warn, 2 = error
	options  []json2.Any // effective: the configured ones merged with the defaults
}

// LintConfig is the configuration a file is linted with.
pub struct LintConfig {
pub:
	rules []RuleSetting // in the order of `names`
	// base_options are the effective options of every ported rule the configuration mentions,
	// also when it turns the rule off: an inline `/* eslint rule: "error" */` takes them.
	base_options map[string][]json2.Any
	// off_problems has, for each ported rule the configuration turns off with options that do not
	// fit it (ESLint does not validate those), what ESLint says of them when a comment turns the
	// rule on.
	off_problems map[string]string
	// other_active are the ESLint ids of the active rules veslint does not have: whether a
	// directive comment that names one of them is unused cannot be known.
	other_active []string
	// only_rule is the rule of `--rule`, the only one that runs: a directive comment for any other
	// rule (or for every rule) may be used by a rule that does not run, so it is never unused.
	only_rule string
	// plugin_rules are the rule ids of the plugins of the configuration other than
	// typescript-eslint, when the configuration was resolved by ESLint itself (strict_plugins);
	// without that, a rule of another plugin is assumed to exist.
	plugin_rules   []string
	strict_plugins bool
	// plugins are the namespaces of the plugins of a configuration that lists them without their
	// rules (the output of `eslint --print-config`): a rule of another plugin does not exist.
	plugins []string
	// reportUnusedDisableDirectives: 0 = off, 1 = warn (ESLint's default), 2 = error.
	report_unused int = 1
	// reportUnusedInlineConfigs: 0 = off (ESLint's default), 1 = warn, 2 = error. A configuration
	// comment is compared with all_rules, the `rules` section as ESLint normalizes it (every
	// rule, also the ones veslint does not have: `[severity, options…]`), with the
	// meta.defaultOptions of the rule under the options of the comment: rule_defaults has the
	// ones ESLint gave when it resolved the configuration (strict_plugins).
	report_unused_inline int
	all_rules            map[string]json2.Any
	rule_defaults        map[string]json2.Any
	no_inline_config     bool
	// languageOptions: what decides the globals and the scopes of a file (see LanguageOptions).
	language LanguageOptions
	// settings are the shared settings of the configuration (ESLint's `settings`, which rules read
	// as context.settings).
	settings map[string]json2.Any
	// project_programs: typescript-eslint gets the types from the programs of
	// `parserOptions.project`, not from the project service (a .vue file is a SourceFile of
	// ScriptKind TS in such a program, and of the extension's own kind for the project service).
	project_programs bool
pub mut:
	// program_directory is the current directory of ESLint's program, which `from: "file"` type
	// specifiers are relative to, when it is not the directory of the tsconfig (see specifiers.v).
	program_directory string
}

// rule_exists: ESLint has a rule with that id (`config.getRuleDefinition(ruleId)`).
pub fn (cfg &LintConfig) rule_exists(id string) bool {
	if id.starts_with(typescript_eslint_prefix) {
		return id[typescript_eslint_prefix.len..] in typescript_eslint_rule_names
	}
	if !id.contains('/') {
		return id in eslint_core_rule_names
	}
	if cfg.strict_plugins {
		return id in cfg.plugin_rules
	}
	// parseRuleId of ESLint's config.js: the plugin of `@scope/name/rule` is `@scope/name`.
	plugin := if id.starts_with('@') { id.all_before_last('/') } else { id.all_before('/') }
	return cfg.plugins.len == 0 || plugin in cfg.plugins
}

// eslint_id is the ESLint `ruleId` of a finding: '' for a problem without a rule.
pub fn (f &Finding) eslint_id() string {
	if f.text != '' {
		return if f.rule == problem_rule { '' } else { f.rule }
	}
	return f.rule
}

// Fix is ESLint's fix of a report: the bytes [start, end) of the source become `text`. A rule that
// makes several edits merges them into one with merge_fixes, like ESLint does.
pub struct Fix {
pub:
	start int
	end   int
	text  string
}

// Suggestion is one of the suggestions of a report: its message is the template `message_id` of
// the rule with `data`, and `fix` what applying it does. A suggestion with a text of its own and
// no messageId (ESLint's `desc` alone) has that text in `desc` and an empty message_id.
pub struct Suggestion {
pub:
	message_id string
	data       map[string]string
	fix        Fix
	desc       string
}

// Stats are the --rule mode timings and counters that `--bench` reports.
pub struct Stats {
pub mut:
	parse_ms  f64
	nodes     int // nodes whose type was requested from tsgo
	types_ms  f64 // collecting those nodes and requesting their types
	eval_ms   f64
	checked   int // statements or nodes evaluated by the rule
	unmatched int // nodes without a tsgo node with the same range (left without a type)
	findings  int
	rule_ms   map[string]f64 // the time of each rule, for --bench
}

// message returns the text of a finding of a rule.
pub fn message(rule string, finding Finding) string {
	if finding.text != '' {
		return finding.text
	}
	messages := match rule {
		no_floating_promises { nfp_messages }
		await_thenable { at_messages }
		require_await { ra_messages }
		return_await { rw_messages }
		no_misused_promises { nmp_messages }
		no_unsafe_call { nuc_messages }
		no_unsafe_member_access { numa_messages }
		no_unsafe_return { nur_messages }
		no_unsafe_assignment { nua_messages }
		no_unsafe_argument { nuarg_messages }
		restrict_template_expressions { rte_messages }
		switch_exhaustiveness_check { sec_messages }
		prefer_nullish_coalescing { pnc_messages }
		no_unnecessary_condition { nuco_messages }
		no_for_in_array { nfia_messages }
		no_array_delete { nad_messages }
		no_unnecessary_boolean_literal_compare { nublc_messages }
		no_unsafe_unary_minus { nuum_messages }
		no_meaningless_void_operator { nmvo_messages }
		related_getter_setter_pairs { rgsp_messages }
		non_nullable_type_assertion_style { nntas_messages }
		prefer_return_this_type { prtt_messages }
		no_duplicate_type_constituents { ndtc_messages }
		no_unnecessary_template_expression { nute_messages }
		dot_notation { dotn_messages }
		restrict_plus_operands { rpo_messages }
		no_confusing_void_expression { ncve_messages }
		no_misused_spread { nms_messages }
		no_redundant_type_constituents { nrtc_messages }
		no_useless_default_assignment { nuda_messages }
		no_unnecessary_type_arguments { nutarg_messages }
		no_unnecessary_qualifier { nuq_messages }
		no_implied_eval { nie_messages }
		no_base_to_string { nbts_messages }
		no_unsafe_enum_comparison { nuec_messages }
		no_mixed_enums { nme_messages }
		no_unnecessary_type_conversion { nutc_messages }
		no_unnecessary_type_assertion { nuta_messages }
		unbound_method { ubm_messages }
		prefer_reduce_type_parameter { prtp_messages }
		prefer_find { pfind_messages }
		prefer_regexp_exec { prx_messages }
		prefer_includes { pinc_messages }
		prefer_string_starts_ends_with { pssew_messages }
		prefer_optional_chain { poc_messages }
		no_deprecated { ndep_messages }
		prefer_promise_reject_errors { ppre_messages }
		use_unknown_in_catch_callback_variable { uuiccv_messages }
		only_throw_error { ote_messages }
		require_array_sort_compare { rasc_messages }
		no_unsafe_type_assertion { nusta_messages }
		promise_function_async { pfa_messages }
		prefer_readonly_parameter_types { prpt_messages }
		consistent_type_exports { cte_messages }
		strict_void_return { svr_messages }
		consistent_return { cr_messages }
		prefer_destructuring { pd_messages }
		prefer_readonly { prd_messages }
		strict_boolean_expressions { sbe_messages }
		no_unnecessary_type_parameters { nutp_messages }
		naming_convention { nc_messages }
		no_duplicate_enum_values { ndev_messages }
		no_extra_non_null_assertion { nenna_messages }
		no_non_null_asserted_optional_chain { nnnaoc_messages }
		no_unsafe_function_type { nuft_messages }
		no_wrapper_object_types { nwot_messages }
		prefer_enum_initializers { pei_messages }
		no_dynamic_delete { ndd_messages }
		no_namespace { nn_messages }
		no_unnecessary_type_constraint { nutcon_messages }
		prefer_as_const { pac_messages }
		no_invalid_void_type { nivt_messages }
		no_this_alias { nta_messages }
		no_misused_new { nmn_messages }
		no_useless_empty_export { nuee_messages }
		no_extraneous_class { nec_messages }
		adjacent_overload_signatures { aos_messages }
		no_dupe_class_members { ndcm_messages }
		class_literal_property_style { clps_messages }
		no_empty_function { nef_messages }
		no_unused_expressions { nuex_messages }
		no_useless_constructor { nuctor_messages }
		no_array_constructor { nac_messages }
		no_confusing_non_null_assertion { ncnna_messages }
		no_import_type_side_effects { nitse_messages }
		no_inferrable_types { nit_messages }
		prefer_namespace_keyword { pnk_messages }
		triple_slash_reference { tsr_messages }
		consistent_generic_constructors { cgc_messages }
		consistent_type_assertions { cta_messages }
		consistent_type_definitions { ctd_messages }
		prefer_function_type { pft_messages }
		unified_signatures { us_messages }
		no_unsafe_declaration_merging { nudm_messages }
		no_require_imports { nri_messages }
		no_non_null_asserted_nullish_coalescing { nnanc_messages }
		prefer_for_of { pfo_messages }
		array_type { arty_messages }
		consistent_indexed_object_style { cios_messages }
		no_unnecessary_parameter_property_assignment { nuppa_messages }
		no_unused_private_class_members { nupcm_messages }
		no_use_before_define { nubd_messages }
		no_shadow { nsh_messages }
		consistent_type_imports { cti_messages }
		no_unused_vars { nuv_messages }
		seyfert_prefer_typed_group { sy_ptg_messages }
		seyfert_autocomplete_respond { sy_ar_messages }
		seyfert_config_default_export { sy_cde_messages }
		seyfert_decorator_target { sy_dt_messages }
		seyfert_decorator_on_command { sy_doc_messages }
		seyfert_i18n_resolve_with_get { sy_irwg_messages }
		seyfert_no_method_destructure { sy_nmd_messages }
		seyfert_require_declare { sy_rd_messages }
		seyfert_context_menu_declare { sy_cmd_messages }
		seyfert_required_options_order { sy_roo_messages }
		seyfert_options_use_builders { sy_oub_messages }
		seyfert_declare_description { sy_dd_messages }
		seyfert_no_deep_imports { sy_ndi_messages }
		seyfert_no_hanging_middleware { sy_nhm_messages }
		seyfert_group_exists { sy_ge_messages }
		no_compare_neg_zero { ncnz_messages }
		use_isnan { uin_messages }
		valid_typeof { vt_messages }
		no_dupe_else_if { ndei_messages }
		no_duplicate_case { ndc_messages }
		no_self_compare { nsc_messages }
		no_self_assign { nsa_messages }
		no_unsafe_negation { nun_messages }
		no_unsafe_optional_chaining { nuoc_messages }
		no_cond_assign { nca_messages }
		for_direction { fd_messages }
		no_constant_condition { ncc_messages }
		no_constant_binary_expression { ncbe_messages }
		curly { cu_messages }
		no_else_return { ner_messages }
		no_empty { ne_messages }
		no_empty_static_block { nesb_messages }
		default_case_last { dcl_messages }
		no_case_declarations { ncd_messages }
		no_labels { nl_messages }
		no_extra_label { nel_messages }
		no_unused_labels { nul_messages }
		no_with { nw_messages }
		no_debugger { nd_messages }
		no_unsafe_finally { nuf_messages }
		no_useless_catch { nuca_messages }
		arrow_body_style { abs_messages }
		prefer_arrow_callback { parc_messages }
		func_name_matching { fnm_messages }
		func_names { fn_messages }
		grouped_accessor_pairs { gap_messages }
		no_setter_return { nsr_messages }
		no_dupe_args { nda_messages }
		no_dupe_keys { ndk_messages }
		no_empty_pattern { nep_messages }
		no_useless_rename { nurn_messages }
		no_useless_computed_key { nuck_messages }
		object_shorthand { os_messages }
		require_yield { ry_messages }
		eqeqeq { eqe_messages }
		yoda { yoda_messages }
		no_eq_null { neqn_messages }
		no_extra_boolean_cast { nebc_messages }
		no_implicit_coercion { nic_messages }
		logical_assignment_operators { lao_messages }
		operator_assignment { oa_messages }
		prefer_exponentiation_operator { peo_messages }
		no_sequences { nseq_messages }
		no_return_assign { nra_messages }
		no_unexpected_multiline { num_messages }
		no_loss_of_precision { nlop_messages }
		no_nonoctal_decimal_escape { nnde_messages }
		no_octal { noc_messages }
		no_octal_escape { noe_messages }
		prefer_numeric_literals { pnl_messages }
		no_multi_str { nmstr_messages }
		no_template_curly_in_string { ntcis_messages }
		no_useless_concat { nuconcat_messages }
		prefer_template { ptpl_messages }
		no_irregular_whitespace { niw_messages }
		unicode_bom { ubom_messages }
		no_sparse_arrays { nsa2_messages }
		no_new { nnew_messages }
		no_new_func { nnf_messages }
		no_new_wrappers { nnwr_messages }
		no_new_native_nonconstructor { nnnn_messages }
		no_obj_calls { noc2_messages }
		no_object_constructor { nobc_messages }
		no_async_promise_executor { nape_messages }
		no_extra_bind { neb_messages }
		no_useless_call { nuca2_messages }
		prefer_spread { psp_messages }
		prefer_rest_params { prp_messages }
		symbol_description { sd_messages }
		radix_rule { radix_messages }
		no_extend_native { nen_messages }
		core_no_implied_eval { niec_messages }
		no_caller { ncal_messages }
		no_iterator { nitr_messages }
		no_proto { nprt_messages }
		no_script_url { nsu_messages }
		no_prototype_builtins { npb_messages }
		prefer_object_has_own { poho_messages }
		prefer_object_spread { pos_messages }
		core_dot_notation { dotn_messages }
		preserve_caught_error { pce_messages }
		no_class_assign { nclsa_messages }
		no_const_assign { ncona_messages }
		no_ex_assign { nexa_messages }
		no_func_assign { nfa_messages }
		no_global_assign { nga_messages }
		no_import_assign { nia_messages }
		no_label_var { nlv_messages }
		no_shadow_restricted_names { nsrn_messages }
		no_unassigned_vars { nuv2_messages }
		no_delete_var { ndv_messages }
		block_scoped_var { bsv_messages }
		consistent_this { cth_messages }
		no_var { nvar_messages }
		prefer_const { pconst_messages }
		vars_on_top { vot_messages }
		sort_vars { svars_messages }
		strict_rule { strict_messages }
		no_inner_declarations { nid_messages }
		no_lone_blocks { nlb_messages }
		no_loop_func { nlf_messages }
		no_implicit_globals { nig_messages }
		no_unmodified_loop_condition { nulc_messages }
		no_control_regex { ncrx_messages }
		no_div_regex { ndr_messages }
		no_empty_character_class { necc_messages }
		no_invalid_regexp { nir_messages }
		no_misleading_character_class { nmcc_messages }
		no_regex_spaces { nrs_messages }
		no_useless_backreference { nub_messages }
		no_useless_escape { nue_messages }
		prefer_regex_literals { prl_messages }
		no_warning_comments { nwc_messages }
		no_restricted_globals { nrg_messages }
		no_restricted_properties { nrp_messages }
		no_restricted_exports { nre_messages }
		no_restricted_imports { nrim_messages }
		no_constructor_return { ncr_messages }
		no_promise_executor_return { npe_messages }
		no_invalid_this { nith_messages }
		getter_return { gr_messages }
		no_unreachable_loop { nurl_messages }
		no_useless_return { nuret_messages }
		no_unreachable { nunr_messages }
		no_fallthrough { nft_messages }
		constructor_super { csup_messages }
		no_this_before_super { ntbs_messages }
		no_useless_assignment { nuas_messages }
		no_restricted_syntax { nrsx_messages }
		unicorn_no_lonely_if { unli_messages }
		unicorn_no_negated_condition { unnc_messages }
		unicorn_no_negation_in_equality_check { unnec_messages }
		unicorn_no_nested_ternary { unnt_messages }
		unicorn_no_typeof_undefined { unty_messages }
		unicorn_prefer_logical_operator_over_ternary { uploot_messages }
		unicorn_prefer_ternary { upt_messages }
		unicorn_prefer_switch { ups_messages }
		unicorn_switch_case_braces { uscb_messages }
		unicorn_switch_case_break_position { uscbp_messages }
		unicorn_no_useless_switch_case { unusc_messages }
		unicorn_prefer_simple_condition_first { upscf_messages }
		unicorn_prefer_date_now { updn_messages }
		unicorn_throw_new_error { utne_messages }
		unicorn_error_message { uem_messages }
		unicorn_consistent_date_clone { ucdc_messages }
		unicorn_consistent_assert { uca_messages }
		unicorn_no_new_buffer { unnb_messages }
		unicorn_prefer_type_error { upte_messages }
		unicorn_no_useless_error_capture_stack_trace { unuecst_messages }
		unicorn_prefer_structured_clone { upsc_messages }
		unicorn_custom_error_definition { ucedf_messages }
		unicorn_no_instanceof_builtins { unib_messages }
		unicorn_new_for_builtins { unfb_messages }
		unicorn_no_hex_escape { unhe_messages }
		unicorn_escape_case { uec_messages }
		unicorn_consistent_template_literal_escape { uctle_messages }
		unicorn_prefer_string_trim_start_end { upstse_messages }
		unicorn_no_console_spaces { uncs_messages }
		unicorn_prefer_code_point { upcp_messages }
		unicorn_prefer_string_slice { upssl_messages }
		unicorn_text_encoding_identifier_case { uteic_messages }
		unicorn_no_zero_fractions { unzf_messages }
		unicorn_prefer_bigint_literals { upbl_messages }
		unicorn_prefer_number_properties { upnp_messages }
		unicorn_prefer_string_raw { upsr_messages }
		unicorn_prefer_string_replace_all { upsra_messages }
		unicorn_require_number_to_fixed_digits_argument { urntfda_messages }
		unicorn_prefer_math_trunc { upmt_messages }
		unicorn_prefer_math_min_max { upmmm_messages }
		unicorn_prefer_modern_math_apis { upmma_messages }
		unicorn_prefer_native_coercion_functions { upncf_messages }
		unicorn_no_array_callback_reference { unacr_messages }
		unicorn_no_for_each { unafe_messages }
		unicorn_no_array_method_this_argument { unamta_messages }
		unicorn_no_array_reverse { unar_messages }
		unicorn_no_array_sort { unas_messages }
		unicorn_no_new_array { unna_messages }
		unicorn_prefer_array_flat { upaf_messages }
		unicorn_prefer_array_flat_map { upafm_messages }
		unicorn_prefer_array_index_of { upaio_messages }
		unicorn_prefer_array_some { upas_messages }
		unicorn_require_array_join_separator { urajs_messages }
		unicorn_prefer_negative_index { upni_messages }
		unicorn_consistent_existence_index_check { uceic_messages }
		unicorn_explicit_length_check { uelc_messages }
		unicorn_no_unnecessary_array_flat_depth { unuafd_messages }
		unicorn_no_unnecessary_array_splice_count { unuasc_messages }
		unicorn_no_unnecessary_slice_end { unuse_messages }
		unicorn_no_useless_length_check { unulc_messages }
		unicorn_no_unreadable_array_destructuring { unuad_messages }
		unicorn_prefer_set_size { upss_messages }
		array_callback_return { acr_messages }
		no_lonely_if { nli_messages }
		no_negated_condition { nnc_messages }
		no_throw_literal { ntl_messages }
		require_atomic_updates { rau_messages }
		class_methods_use_this { cmut_messages }
		no_explicit_any { nea_messages }
		unicorn_consistent_empty_array_spread { uceas_messages }
		unicorn_no_useless_fallback_in_spread { unufis_messages }
		unicorn_no_useless_collection_argument { unuca_messages }
		unicorn_no_useless_iterator_to_array { unuita_messages }
		unicorn_no_useless_spread { unus_messages }
		unicorn_prefer_single_call { upsg_messages }
		unicorn_no_immediate_mutation { unim_messages }
		unicorn_prefer_blob_reading_methods { upbrm_messages }
		unicorn_prefer_response_static_json { uprsj_messages }
		unicorn_no_await_expression_member { unaem_messages }
		unicorn_prefer_spread { upsp_messages }
		unicorn_no_await_in_promise_methods { unaipm_messages }
		unicorn_no_invalid_fetch_options { unifo_messages }
		unicorn_no_unnecessary_await { unua_messages }
		unicorn_no_thenable { unt_messages }
		unicorn_no_single_promise_in_promise_methods { unspipm_messages }
		unicorn_no_useless_promise_resolve_reject { unuprr_messages }
		unicorn_prefer_node_protocol { upnpr_messages }
		unicorn_no_process_exit { unpe_messages }
		unicorn_no_named_default { unnd_messages }
		unicorn_require_module_attributes { urma_messages }
		unicorn_require_module_specifiers { urms_messages }
		unicorn_prefer_json_parse_buffer { upjpb_messages }
		unicorn_no_anonymous_default_export { unade_messages }
		unicorn_prefer_import_meta_properties { upimp_messages }
		unicorn_prefer_module { upm_messages }
		unicorn_prefer_reflect_apply { upra_messages }
		unicorn_prefer_export_from { upef_messages }
		unicorn_relative_url_style { rus_messages }
		unicorn_prefer_prototype_methods { uppm_messages }
		unicorn_better_regex { ubr_messages }
		unicorn_no_this_assignment { unta_messages }
		unicorn_no_unreadable_iife { unui_messages }
		unicorn_no_accessor_recursion { unaccr_messages }
		unicorn_no_static_only_class { unsoc_messages }
		unicorn_prefer_class_fields { upcfl_messages }
		unicorn_consistent_function_scoping { ucfs_messages }
		unicorn_isolated_functions { uisf_messages }
		unicorn_no_useless_undefined { unuu_messages }
		unicorn_no_keyword_prefix { unkp_messages }
		unicorn_prefer_object_from_entries { upofe_messages }
		unicorn_prefer_default_parameters { updp_messages }
		unicorn_no_unused_properties { unup_messages }
		stylistic_array_bracket_spacing { sabs_messages }
		stylistic_rest_spread_spacing { srsp_messages }
		stylistic_semi_spacing { ssmi_messages }
		stylistic_space_in_parens { sinp_messages }
		stylistic_switch_colon_spacing { sscs_messages }
		stylistic_template_curly_spacing { stcs_messages }
		stylistic_template_tag_spacing { stts_messages }
		stylistic_no_whitespace_before_property { snwbp_messages }
		stylistic_block_spacing { sbls_messages }
		stylistic_comma_spacing { scmsp_messages }
		stylistic_computed_property_spacing { scpsp_messages }
		stylistic_object_curly_spacing { socsp_messages }
		stylistic_keyword_spacing { skwsp_messages }
		stylistic_space_before_blocks { ssbb_messages }
		stylistic_arrow_spacing { sarws_messages }
		stylistic_yield_star_spacing { sysp_messages }
		stylistic_type_annotation_spacing { stas_messages }
		stylistic_type_generic_spacing { stgs_messages }
		stylistic_type_named_tuple_spacing { stnts_messages }
		stylistic_space_before_function_paren { ssbfp_messages }
		stylistic_key_spacing { sks_messages }
		stylistic_space_infix_ops { ssio_messages }
		stylistic_space_unary_ops { ssuo_messages }
		stylistic_function_call_spacing { sfcs_messages }
		stylistic_brace_style { sbs_messages }
		stylistic_comma_style { scst_messages }
		stylistic_dot_location { sdl_messages }
		stylistic_function_call_argument_newline { sfcan_messages }
		stylistic_function_paren_newline { sfpn_messages }
		stylistic_implicit_arrow_linebreak { sial_messages }
		stylistic_multiline_ternary { smtn_messages }
		stylistic_nonblock_statement_body_position { snsbp_messages }
		stylistic_one_var_declaration_per_line { sovdpl_messages }
		stylistic_quotes { squo_messages }
		stylistic_no_multi_spaces { snms_messages }
		stylistic_no_trailing_spaces { sntr_messages }
		stylistic_no_mixed_spaces_and_tabs { snmst_messages }
		stylistic_eol_last { seol_messages }
		stylistic_spaced_comment { sspc_messages }
		stylistic_lines_between_class_members { slbcm_messages }
		stylistic_new_parens { snwp_messages }
		stylistic_no_floating_decimal { snfd_messages }
		stylistic_no_extra_semi { snes_messages }
		stylistic_semi_style { ssms_messages }
		stylistic_semi { ssemi_messages }
		stylistic_object_curly_newline { socn_messages }
		stylistic_object_property_newline { sopn_messages }
		stylistic_list_style { sls_messages }
		stylistic_exp_jsx_props_style { sjps_messages }
		stylistic_arrow_parens { sap_messages }
		stylistic_comma_dangle { scd_messages }
		stylistic_member_delimiter_style { smds_messages }
		stylistic_quote_props { sqp_messages }
		stylistic_no_extra_parens { snep_messages }
		marcrock_no_newline_if_body_class_empty { mnl_messages }
		marcrock_numeric_separators { mns_messages }
		marcrock_uppercase_first_class_letter { mufc_messages }
		marcrock_prefer_at { mpa_messages }
		perfectionist_sort_array_includes { pfai_messages }
		perfectionist_sort_sets { pfss_messages }
		perfectionist_sort_maps { pfsm_messages }
		perfectionist_sort_union_types { pfsut_messages }
		perfectionist_sort_intersection_types { pfsit_messages }
		ban_ts_comment { btsc_messages }
		ban_tslint_comment { btslc_messages }
		default_param_last { dpl_messages }
		init_declarations { tsid_messages }
		max_params { tsmp_messages }
		method_signature_style { mss_messages }
		no_empty_object_type { neot_messages }
		no_non_null_assertion { nnna_messages }
		ts_no_invalid_this { tsnit_messages }
		no_redeclare { tsnr_messages }
		perfectionist_sort_heritage_clauses { pfhc_messages }
		perfectionist_sort_import_attributes { pfsia_messages }
		perfectionist_sort_export_attributes { pfsea_messages }
		perfectionist_sort_switch_case { pfsw_messages }
		perfectionist_sort_named_imports { pfsni_messages }
		perfectionist_sort_named_exports { pfsne_messages }
		perfectionist_sort_exports { pfsx_messages }
		explicit_function_return_type { efrt_messages }
		explicit_module_boundary_types { embt_messages }
		explicit_member_accessibility { ema_messages }
		parameter_properties { ppr_messages }
		prefer_literal_enum_member { plem_messages }
		no_magic_numbers { nmag_messages }
		no_restricted_types { nrty_messages }
		no_generated_empty_object_type { ngeo_messages }
		no_unsafe_enum_assignment { nuea_messages }
		member_ordering { mord_messages }
		perfectionist_sort_classes { pfsc_messages }
		perfectionist_sort_imports { pfsi_messages }
		vue_no_v_html { vnvh_messages }
		vue_no_v_text { vnvt_messages }
		vue_no_duplicate_attributes { vnda_messages }
		vue_comment_directive { vcd_messages }
		vue_no_parsing_error { vnpe_messages }
		vue_no_deprecated_v_is { vndvi_messages }
		vue_no_deprecated_scope_attribute { vndsa_messages }
		vue_no_deprecated_filter { vndf_messages }
		vue_no_deprecated_inline_template { vndit_messages }
		vue_require_component_is { vrci_messages }
		vue_no_deprecated_v_on_native_modifier { vndvonm_messages }
		vue_no_v_model_argument { vnvma_messages }
		vue_no_textarea_mustache { vntm_messages }
		vue_no_use_v_else_with_v_for { vnuvewvf_messages }
		vue_no_v_for_template_key { vnvftk_messages }
		vue_no_template_key { vntk_messages }
		vue_no_custom_modifiers_on_v_model { vncmovm_messages }
		vue_no_deprecated_v_bind_sync { vndvbs_messages }
		vue_no_spaces_around_equal_signs_in_attribute { vnsaesia_messages }
		vue_no_deprecated_v_on_number_modifiers { vndvonum_messages }
		vue_valid_v_bind { vvbind_messages }
		vue_valid_v_cloak { vvcloak_messages }
		vue_valid_v_html { vvhtml_messages }
		vue_valid_v_once { vvonce_messages }
		vue_valid_v_pre { vvpre_messages }
		vue_valid_v_text { vvtext_messages }
		vue_valid_v_show { vvshow_messages }
		vue_valid_v_if { vvif_messages }
		vue_valid_v_else_if { vvelseif_messages }
		vue_valid_v_else { vvelse_messages }
		vue_valid_v_is { vvis_messages }
		vue_valid_v_on { vvon_messages }
		vue_v_on_style { vvos_messages }
		vue_v_bind_style { vvbs_messages }
		vue_no_multiple_objects_in_class { vnmoic_messages }
		vue_require_v_for_key { vrvfk_messages }
		vue_no_deprecated_html_element_is { vndhei_messages }
		vue_no_use_v_if_with_v_for { vnuviwvf_messages }
		vue_no_v_for_template_key_on_child { vnvftkoc_messages }
		vue_html_end_tags { vhet_messages }
		vue_valid_attribute_name { vvan_messages }
		vue_v_for_delimiter_style { vvfds_messages }
		vue_no_v_text_v_html_on_component { vnvtvhoc_messages }
		vue_no_lone_template { vnlt_messages }
		vue_html_button_has_type { vhbht_messages }
		vue_no_deprecated_router_link_tag_prop { vndrltp_messages }
		vue_no_restricted_html_elements { vnrhe_messages }
		vue_no_useless_template_attributes { vnuta_messages }
		vue_mustache_interpolation_spacing { vmis_messages }
		vue_static_class_names_order { vscno_messages }
		vue_restricted_component_names { vrcn_messages }
		vue_slot_name_casing { vsnc_messages }
		vue_first_attribute_linebreak { vfal_messages }
		vue_html_quotes { vhq_messages }
		vue_no_literals_in_template { vnlit_messages }
		vue_require_toggle_inside_transition { vrtit_messages }
		vue_no_restricted_static_attribute { vnrsa_messages }
		vue_html_closing_bracket_spacing { vhcbs_messages }
		vue_html_closing_bracket_newline { vhcbn_messages }
		vue_attribute_hyphenation { vah_messages }
		vue_v_on_event_hyphenation { voeh_messages }
		vue_valid_v_memo { vvm_messages }
		vue_no_static_inline_styles { vnsis_messages }
		vue_no_child_content { vncc_messages }
		vue_no_template_target_blank { vnttb_messages }
		vue_no_restricted_class { vnrc_messages }
		vue_no_useless_v_bind { vnuvb_messages }
		vue_no_restricted_v_bind { vnrvb_messages }
		vue_no_restricted_v_on { vnrvo_messages }
		vue_valid_v_bind_sync { vvbsync_messages }
		vue_v_slot_style { vvss_messages }
		vue_prefer_true_attribute_shorthand { vptas_messages }
		vue_no_dupe_v_else_if { vndvei_messages }
		vue_no_deprecated_slot_attribute { vndslota_messages }
		vue_no_deprecated_slot_scope_attribute { vndslotsa_messages }
		vue_this_in_template { vtit_messages }
		vue_no_unused_vars { vnuv_messages }
		vue_no_define_model_default { vue_no_define_model_default_messages }
		vue_no_deprecated_functional_template { vue_no_deprecated_functional_template_messages }
		vue_require_render_return { vue_require_render_return_messages }
		vue_no_deprecated_vue_config_keycodes { vue_no_deprecated_vue_config_keycodes_messages }
		vue_no_root_v_if { vue_no_root_v_if_messages }
		vue_no_arrow_functions_in_watch { vue_no_arrow_functions_in_watch_messages }
		vue_one_component_per_file { vue_one_component_per_file_messages }
		vue_valid_model_definition { vue_valid_model_definition_messages }
		vue_no_deprecated_events_api { vue_no_deprecated_events_api_messages }
		vue_define_props_declaration { vue_define_props_declaration_messages }
		vue_valid_template_root { vue_valid_template_root_messages }
		vue_no_export_in_script_setup { vue_no_export_in_script_setup_messages }
		vue_require_default_export { vue_require_default_export_messages }
		vue_jsx_uses_vars { vue_jsx_uses_vars_messages }
		vue_match_component_import_name { vue_match_component_import_name_messages }
		vue_no_deprecated_destroyed_lifecycle { vue_no_deprecated_destroyed_lifecycle_messages }
		vue_max_template_depth { vue_max_template_depth_messages }
		vue_no_reserved_props { vue_no_reserved_props_messages }
		vue_no_this_in_before_route_enter { vue_no_this_in_before_route_enter_messages }
		vue_max_props { vue_max_props_messages }
		vue_no_content_outside_block { vue_no_content_outside_block_messages }
		vue_no_shared_component_data { vue_no_shared_component_data_messages }
		vue_no_deprecated_data_object_declaration {
			vue_no_deprecated_data_object_declaration_messages
		}
		vue_prop_name_casing { vue_prop_name_casing_messages }
		vue_define_props_destructuring { vue_define_props_destructuring_messages }
		vue_component_definition_name_casing { vue_component_definition_name_casing_messages }
		vue_require_emit_validator { vue_require_emit_validator_messages }
		vue_no_computed_properties_in_data { vue_no_computed_properties_in_data_messages }
		vue_no_empty_component_block { vue_no_empty_component_block_messages }
		vue_no_import_compiler_macros { vue_no_import_compiler_macros_messages }
		vue_prefer_prop_type_boolean_first { vue_prefer_prop_type_boolean_first_messages }
		vue_require_macro_variable_name { vue_require_macro_variable_name_messages }
		vue_define_emits_declaration { vue_define_emits_declaration_messages }
		vue_no_props_shadow { vue_no_props_shadow_messages }
		vue_require_prop_type_constructor { vue_require_prop_type_constructor_messages }
		vue_no_restricted_block { vue_no_restricted_block_messages }
		vue_component_options_name_casing { vue_component_options_name_casing_messages }
		vue_max_lines_per_block { vue_max_lines_per_block_messages }
		vue_no_multiple_slot_args { vue_no_multiple_slot_args_messages }
		vue_no_reserved_keys { vue_no_reserved_keys_messages }
		vue_no_deprecated_delete_set { vue_no_deprecated_delete_set_messages }
		vue_require_prop_types { vue_require_prop_types_messages }
		vue_return_in_computed_property { vue_return_in_computed_property_messages }
		vue_no_deprecated_props_default_this { vue_no_deprecated_props_default_this_messages }
		vue_require_slots_as_functions { vue_require_slots_as_functions_messages }
		vue_require_name_property { vue_require_name_property_messages }
		vue_arrow_spacing { sarws_messages }
		vue_camelcase { ccase_messages }
		vue_comma_dangle { scd_messages }
		vue_dot_location { sdl_messages }
		vue_no_empty_pattern { nep_messages }
		vue_no_sparse_arrays { nsa2_messages }
		vue_operator_linebreak { solb_messages }
		vue_array_bracket_newline { sabn_messages }
		vue_array_bracket_spacing { sabs_messages }
		vue_array_element_newline { saen_messages }
		vue_block_spacing { sbls_messages }
		vue_brace_style { sbs_messages }
		vue_dot_notation { dotn_messages }
		vue_eqeqeq { eqe_messages }
		vue_key_spacing { sks_messages }
		vue_keyword_spacing { skwsp_messages }
		vue_no_restricted_syntax { nrsx_messages }
		vue_no_useless_concat { nuconcat_messages }
		vue_object_curly_newline { socn_messages }
		vue_object_curly_spacing { socsp_messages }
		vue_object_property_newline { sopn_messages }
		vue_prefer_template { ptpl_messages }
		vue_no_implicit_coercion { nic_messages }
		vue_no_loss_of_precision { nlop_messages }
		vue_no_negated_condition { nnc_messages }
		vue_object_shorthand { os_messages }
		vue_space_infix_ops { ssio_messages }
		vue_space_unary_ops { vssuo_messages }
		vue_template_curly_spacing { stcs_messages }
		vue_comma_spacing { scmsp_messages }
		vue_multiline_ternary { smtn_messages }
		vue_space_in_parens { sinp_messages }
		vue_func_call_spacing { sfcs_messages }
		vue_comma_style { scst_messages }
		vue_no_constant_condition { ncc_messages }
		vue_no_console { vncon_messages }
		vue_quote_props { sqp_messages }
		vue_no_extra_parens { snep_messages }
		vue_max_attributes_per_line { vmapl_messages }
		vue_no_useless_mustaches { vnum_messages }
		vue_no_negated_v_if_condition { vnvic_messages }
		vue_use_v_on_exact { vuvoe_messages }
		vue_prefer_v_model { vpvm_messages }
		vue_singleline_html_element_content_newline { vhecn_single_messages }
		vue_multiline_html_element_content_newline { vhecn_multi_messages }
		vue_html_self_closing { vhsc_messages }
		vue_padding_line_between_blocks { vplbb_messages }
		vue_padding_line_between_tags { vplbt_messages }
		vue_block_tag_newline { vbtn_messages }
		vue_block_lang { vblang_messages }
		vue_no_bare_strings_in_template { vnbs_messages }
		vue_v_if_else_key { vviek_messages }
		vue_no_irregular_whitespace { vnirw_messages }
		vue_valid_v_for { vvfor_messages }
		vue_valid_v_model { vvmod_messages }
		vue_valid_v_slot { vvslot_messages }
		vue_no_unsupported_features { vnuf_messages }
		vue_prefer_separate_static_class { vpssc_messages }
		vue_no_duplicate_class_names { vndcn_messages }
		vue_max_len { vmaxlen_messages }
		vue_attributes_order { vattro_messages }
		vue_no_deprecated_dollar_listeners_api { vue_no_deprecated_dollar_listeners_api_messages }
		vue_no_deprecated_dollar_scopedslots_api {
			vue_no_deprecated_dollar_scopedslots_api_messages
		}
		vue_prefer_use_template_ref { vue_prefer_use_template_ref_messages }
		vue_no_duplicate_attr_inheritance { vue_no_duplicate_attr_inheritance_messages }
		vue_no_unused_components { vue_no_unused_components_messages }
		vue_no_template_shadow { vue_no_template_shadow_messages }
		vue_require_explicit_slots { vue_require_explicit_slots_messages }
		vue_no_undef_directives { vue_no_undef_directives_messages }
		vue_component_name_in_template_casing { vue_component_name_in_template_casing_messages }
		vue_no_unused_refs { vue_no_unused_refs_messages }
		vue_custom_event_name_casing { vue_custom_event_name_casing_messages }
		vue_no_restricted_custom_event { vue_no_restricted_custom_event_messages }
		vue_no_unused_emit_declarations { vue_no_unused_emit_declarations_messages }
		vue_prefer_single_event_payload { vue_prefer_single_event_payload_messages }
		vue_no_shadow_native_events { vue_no_shadow_native_events_messages }
		vue_require_explicit_emits { vue_require_explicit_emits_messages }
		vue_no_undef_components { vue_no_undef_components_messages }
		vue_v_on_handler_style { vue_v_on_handler_style_messages }
		vue_no_mutating_props { vue_no_mutating_props_messages }
		vue_no_use_computed_property_like_method {
			vue_no_use_computed_property_like_method_messages
		}
		vue_no_unused_properties { vue_no_unused_properties_messages }
		vue_no_undef_properties { vue_no_undef_properties_messages }
		vue_prefer_define_options { vue_prefer_define_options_messages }
		vue_multi_word_component_names { vue_multi_word_component_names_messages }
		vue_no_multiple_template_root { vue_no_multiple_template_root_messages }
		vue_no_potential_component_option_typo { vue_no_potential_component_option_typo_messages }
		vue_no_deprecated_model_definition { vue_no_deprecated_model_definition_messages }
		vue_match_component_file_name { vue_match_component_file_name_messages }
		vue_enforce_style_attribute { vue_enforce_style_attribute_messages }
		vue_require_direct_export { vue_require_direct_export_messages }
		vue_no_restricted_component_names { vue_no_restricted_component_names_messages }
		vue_no_restricted_component_options { vue_no_restricted_component_options_messages }
		vue_prefer_import_from_vue { vue_prefer_import_from_vue_messages }
		vue_new_line_between_multi_line_property {
			vue_new_line_between_multi_line_property_messages
		}
		vue_component_api_style { vue_component_api_style_messages }
		vue_no_reserved_component_names { vue_no_reserved_component_names_messages }
		vue_require_typed_object_prop { vue_require_typed_object_prop_messages }
		vue_return_in_emits_validator { vue_return_in_emits_validator_messages }
		vue_valid_define_props { vue_valid_define_props_messages }
		vue_valid_define_emits { vue_valid_define_emits_messages }
		vue_valid_define_options { vue_valid_define_options_messages }
		vue_require_prop_comment { vue_require_prop_comment_messages }
		vue_define_macros_order { vue_define_macros_order_messages }
		vue_order_in_components { vue_order_in_components_messages }
		vue_padding_lines_in_component_definition {
			vue_padding_lines_in_component_definition_messages
		}
		vue_sort_keys { vue_sort_keys_messages }
		vue_html_comment_content_spacing { vue_html_comment_content_spacing_messages }
		vue_html_comment_content_newline { vue_html_comment_content_newline_messages }
		vue_html_comment_indent { vue_html_comment_indent_messages }
		vue_no_multi_spaces { vue_no_multi_spaces_messages }
		vue_block_order { vue_block_order_messages }
		vue_no_lifecycle_after_await { vue_no_lifecycle_after_await_messages }
		vue_no_watch_after_await { vue_no_watch_after_await_messages }
		vue_no_expose_after_await { vue_no_expose_after_await_messages }
		vue_no_restricted_call_after_await { vue_no_restricted_call_after_await_messages }
		vue_next_tick_style { vue_next_tick_style_messages }
		vue_valid_next_tick { vue_valid_next_tick_messages }
		vue_no_boolean_default { vue_no_boolean_default_messages }
		vue_no_required_prop_with_default { vue_no_required_prop_with_default_messages }
		vue_require_default_prop { vue_require_default_prop_messages }
		vue_require_valid_default_prop { vue_require_valid_default_prop_messages }
		vue_no_restricted_props { vue_no_restricted_props_messages }
		vue_require_typed_ref { vue_require_typed_ref_messages }
		vue_no_ref_as_operand { vue_no_ref_as_operand_messages }
		vue_no_ref_object_reactivity_loss { vue_no_ref_object_reactivity_loss_messages }
		vue_no_setup_props_reactivity_loss { vue_no_setup_props_reactivity_loss_messages }
		vue_require_expose { vue_require_expose_messages }
		vue_no_side_effects_in_computed_properties {
			vue_no_side_effects_in_computed_properties_messages
		}
		vue_no_async_in_computed_properties { vue_no_async_in_computed_properties_messages }
		vue_no_dupe_keys { vue_no_dupe_keys_messages }
		svelte_comment_directive { svcd_messages }
		svelte_system { map[string]string{} }
		svelte_no_at_html_tags { svnaht_messages }
		svelte_no_at_debug_tags { svnadt_messages }
		svelte_button_has_type { sbht_messages }
		svelte_no_target_blank { sntb_messages }
		svelte_require_each_key { svrek_messages }
		svelte_valid_each_key { svvek_messages }
		svelte_no_object_in_text_mustaches { snoitm_messages }
		svelte_shorthand_attribute { svsha_messages }
		svelte_no_spaces_around_equal_signs_in_attribute { snsaes_messages }
		svelte_spaced_html_comment { sshc_messages }
		svelte_no_dupe_else_if_blocks { sndeib_messages }
		svelte_no_useless_mustaches { snum_messages }
		svelte_first_attribute_linebreak { sfal_messages }
		svelte_shorthand_directive { svshd_messages }
		svelte_html_closing_bracket_spacing { shcbs_messages }
		svelte_html_closing_bracket_new_line { shcbnl_messages }
		svelte_no_dynamic_slot_name { sndsn_messages }
		svelte_html_quotes { shq_messages }
		svelte_mustache_spacing { smsp_messages }
		svelte_no_inline_styles { snis_messages }
		svelte_no_raw_special_elements { snrse_messages }
		svelte_no_nested_style_tag { snnst_messages }
		svelte_no_useless_children_snippet { snucs_messages }
		svelte_no_dupe_on_directives { snddo_messages }
		svelte_no_dupe_use_directives { snddu_messages }
		svelte_prefer_attribute_interpolation { spai_messages }
		svelte_max_attributes_per_line { smapl_messages }
		svelte_html_self_closing { shsc_messages }
		svelte_no_at_const_tags { snact_messages }
		svelte_no_not_function_handler { snnfh_messages }
		svelte_block_lang { sbl_messages }
		svelte_prefer_class_directive { spcd_messages }
		svelte_no_svelte_internal { svnsi_messages }
		svelte_no_inspect { svnin_messages }
		svelte_no_store_async { svnsa_messages }
		svelte_require_stores_init { svrsi_messages }
		svelte_no_ignored_unsubscribe { svniu_messages }
		svelte_require_store_callbacks_use_set_param { svrscusp_messages }
		svelte_derived_has_same_inputs_outputs { svdhsio_messages }
		else { map[string]string{} }
	}
	return interpolate(messages[finding.message_id] or { finding.message_id }, finding.data)
}

// suggestion_message is the text of a suggestion of `rule` (ESLint's `desc`).
pub fn suggestion_message(rule string, suggestion Suggestion) string {
	if suggestion.desc != '' {
		return suggestion.desc
	}
	return message(rule, Finding{
		message_id: suggestion.message_id
		data:       suggestion.data
	})
}

// interpolate ports ESLint's interpolate: every `{{ key }}` (whitespace allowed around the key)
// whose key is in `data` becomes its value; any other placeholder stays as it is.
fn interpolate(template string, data map[string]string) string {
	mut out := []u8{cap: template.len}
	mut i := 0
	for i < template.len {
		if i + 1 < template.len && template[i] == `{` && template[i + 1] == `{` {
			mut j := i + 2
			for j < template.len && template[j] != `{` && template[j] != `}` {
				j++
			}
			if j > i + 2 && j + 1 < template.len && template[j] == `}` && template[j + 1] == `}` {
				key := template[i + 2..j].trim_space()
				if value := data[key] {
					out << value.bytes()
				} else {
					out << template[i..j + 2].bytes()
				}
				i = j + 2
				continue
			}
		}
		out << template[i]
		i++
	}
	return out.bytestr()
}

fn ms(d time.Duration) f64 {
	return f64(d) / f64(time.millisecond)
}

// FileLint is the result of applying the rules to a file.
pub struct FileLint {
pub:
	findings      []Finding // in order
	syntax_errors bool      // tree-sitter found syntax errors (ERROR or MISSING nodes)
	// TypeScript's parser found an error: `findings` is it alone, as ESLint reports a file it cannot
	// parse (a fix may have given code tree-sitter reads and TypeScript does not).
	parsing_error bool
	unmatched     int // nodes the rules could not analyze (summed per rule): no tsgo counterpart, or nested too deeply
}

// lint_file applies the `selected` rules to a file (BOM already stripped), with a single parse and
// a single tsgo AST; types a rule already requested are not requested again for the next ones.
// Findings come out by position and, at the same position, in the order of `names`.
// lint_stopped is the error of lint_file when its LintStop told it to give the lint up.
pub const lint_stopped = 'the lint was given up: a newer request for the same files arrived'

// LintStop is asked before each rule of a file whether to give the lint up: `veslint --server`
// gives up a lint that a newer request for the same files made useless (server.v).
pub interface LintStop {
mut:
	stop() bool
}

// NoLintStop never gives a lint up (the command line).
struct NoLintStop {}

fn (mut n NoLintStop) stop() bool {
	return false
}

// set_lint_stop makes lint_file ask `stop` before each rule whether to give the lint up.
pub fn (mut c Checker) set_lint_stop(stop LintStop) {
	c.lint_stop = stop
}

// set_has_bom tells the Checker whether the next file it lints had a BOM (unicode-bom): its text
// comes without it, as ESLint's does.
pub fn (mut c Checker) set_has_bom(has_bom bool) {
	c.has_bom = has_bom
}

// ScopedLint carries what lint_file_in_lifetime runs into the closure of its frame and out of it.
@[heap]
struct ScopedLint {
mut:
	checker  &Checker = unsafe { nil }
	parser   Parser
	config   LintConfig
	src      string
	abs_path string
	stats    Stats
	result   FileLint
	failure  string
	failed   bool
}

// lint_file lints a file inside a closure lifetime and releases, when it returns, the closures the
// rules made. V keeps every closure that is not released, and with it what it captured (often the
// Checker, with its caches, or a tree), alive for the whole run: --fix makes a Checker per pass
// and none of them was freed (gigabytes over a large project).
pub fn (mut c Checker) lint_file(parser Parser, config LintConfig, src string, abs_path string, mut stats Stats) !FileLint {
	mut scoped := &ScopedLint{
		checker:  c
		parser:   parser
		config:   config
		src:      src
		abs_path: abs_path
		stats:    stats
	}
	mut lifetime := closure.new_lifetime()
	lifetime.frame(fn [mut scoped] () {
		mut checker := scoped.checker
		scoped.result = checker.lint_file_in_lifetime(scoped.parser, scoped.config, scoped.src,
			scoped.abs_path, mut scoped.stats) or {
			scoped.failure = err.msg()
			scoped.failed = true
			FileLint{}
		}
	})!
	lifetime.dispose()!
	stats = scoped.stats
	result := scoped.result
	failed, failure := scoped.failed, scoped.failure
	// The closure of the frame is not released with the lifetime: it keeps `scoped`, which keeps
	// nothing large from here on.
	unsafe {
		scoped.checker = nil
	}
	scoped.result = FileLint{}
	scoped.config = LintConfig{}
	scoped.src = ''
	scoped.stats = Stats{}
	if failed {
		return error(failure)
	}
	return result
}

fn (mut c Checker) lint_file_in_lifetime(parser Parser, config LintConfig, src string, abs_path string, mut stats Stats) !FileLint {
	sw := time.new_stopwatch()
	// A .vue file comes parsed: its tree is the one of its masked script (vue_file.v), which the
	// document owns; tsgo knows it by its twin. A .svelte file's tree is the one of its lint code
	// (svelte_file.v).
	vue_file := c.is_vue()
	svelte_file := c.is_svelte()
	ts_path := if vue_file {
		c.vue.ts_path
	} else if svelte_file {
		c.svelte.ts_path
	} else {
		abs_path
	}
	if svelte_file && c.svelte.doc.error != none {
		fatal := c.svelte_parsing_error()
		c.svelte = SvelteView{}
		stats.findings++
		return FileLint{
			findings:      fatal
			parsing_error: true
		}
	}
	mut owned := !vue_file || c.vue.doc.script.tree == unsafe { nil }
	mut tree := if svelte_file {
		parser.parse(c.svelte.doc.lint_code)!
	} else if !vue_file {
		parser.parse(src)!
	} else if owned {
		parser.parse(c.vue.doc.script.masked)!
	} else {
		c.vue.doc.script.tree
	}
	defer {
		// The index points into the tree.
		c.node_index = treesitter.NodeIndex{}
		if owned {
			tree_delete(tree)
		}
		c.vue = VueView{}
		c.svelte = SvelteView{}
		c.svelte_module = SvelteModuleView{}
	}
	mut root := root_node(tree)
	// The text of a .svelte file's nodes: the file, then the template part of the lint code.
	c.src = if svelte_file { c.svelte.doc.lint_text() } else { src }
	c.tokens = c.file_token_ends(root)
	c.node_index = treesitter.new_node_index(root)
	c.ast_path = ''
	c.program_directory = config.program_directory
	c.ecma_version = config.language.ecma_version
	c.language = config.language
	c.settings = config.settings
	c.project_programs = config.project_programs
	c.reset_file_types()
	fatal := c.parsing_error(ts_path)
	if fatal.len > 0 {
		stats.parse_ms += ms(sw.elapsed())
		stats.findings++
		return FileLint{
			findings:      if svelte_file { c.svelte_move_findings(fatal) } else { fatal }
			parsing_error: true
		}
	}
	// Where TypeScript read an `await` as an identifier, the file is parsed again that way
	// (rules/await_identifier.v).
	reread := c.await_identifiers_source(root, ts_path)!
	if reread != '' {
		c.node_index = treesitter.NodeIndex{}
		if owned {
			tree_delete(tree)
		}
		tree = parser.parse(reread)!
		owned = true
		root = root_node(tree)
		c.tokens = c.file_token_ends(root)
		c.node_index = treesitter.new_node_index(root)
	}
	unmatched_before := stats.unmatched
	stats.parse_ms += ms(sw.elapsed())
	// The comments that configure ESLint: they may change the rules of this file and they
	// suppress findings.
	inline := c.inline_config(root, config)
	c.scope_setup = c.file_scope_setup(config, inline)
	mut findings := []Finding{}
	c.file_rules = inline.rules.map(it.name)
	c.vue_template_owner = c.vue_template_owner_of(config, inline)
	for setting in inline.rules {
		if c.lint_stop.stop() {
			return error(lint_stopped)
		}
		if needs_types(setting.name) {
			c.make_snapshot()!
		}
		c.too_deep = 0
		c.options[setting.name] = setting.options
		rule_sw := time.new_stopwatch()
		rule_findings := c.lint_rule(setting.name, root, ts_path, mut stats)!
		stats.rule_ms[setting.name] += ms(rule_sw.elapsed())
		for f in rule_findings {
			findings << Finding{
				...f
				stmt:       c.trimmed_end(f.stmt)
				rule:       setting.name
				severity:   setting.severity
				// A report with a message of its own and no messageId: ESLint's line has the
				// severity in its place.
				message_id: if f.message_id == '' && f.text != '' {
					if setting.severity == 1 { 'warning' } else { 'error' }
				} else {
					f.message_id
				}
			}
		}
		stats.unmatched += c.too_deep
	}
	if svelte_file {
		findings = c.svelte_move_findings(c.svelte_drop_wrapper_function_findings(root, findings))
	}
	findings = sort_rule_findings(findings)
	findings = c.apply_disable_directives(findings, inline, config)
	// The template's directive comments of a .vue file: the postprocess of eslint-plugin-vue's
	// processor, with its rule on (vue_comment_directive.v).
	if c.is_vue() {
		for setting in inline.rules {
			if setting.name == vue_comment_directive {
				findings = c.vue_comment_directive_postprocess(findings, setting)!
			}
		}
	}
	// The template's directive comments of a .svelte file and settings.svelte.ignoreWarnings: the
	// postprocess of eslint-plugin-svelte's processor, with svelte/comment-directive or
	// svelte/system on (svelte_comment_directive.v).
	if svelte_file && inline.rules.any(it.name in [svelte_comment_directive, svelte_system]) {
		findings = c.svelte_comment_directive_postprocess(findings, inline.rules)!
	}
	stats.findings += findings.len
	return FileLint{
		findings:      findings
		syntax_errors: tree_has_error(tree)
		unmatched:     stats.unmatched - unmatched_before
	}
}

// sort_rule_findings orders the findings of several rules: by position, by the order of `names`
// and, within a rule, in the order the rule gave them, as ESLint keeps the order of the reports at
// one position (switch-exhaustiveness-check reports a missing case before a missing default).
fn sort_rule_findings(findings []Finding) []Finding {
	mut order := []int{len: findings.len, init: index}
	order.sort_with_compare(fn [findings] (a &int, b &int) int {
		fa := findings[*a]
		fb := findings[*b]
		if fa.stmt.start_byte != fb.stmt.start_byte {
			return if fa.stmt.start_byte < fb.stmt.start_byte { -1 } else { 1 }
		}
		if fa.rule != fb.rule {
			return if names.index(fa.rule) < names.index(fb.rule) { -1 } else { 1 }
		}
		return *a - *b
	})
	return order.map(findings[it])
}

// lint_rule applies a rule to the tree of the file prepared by lint_file.
fn (mut c Checker) lint_rule(rule string, root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	match rule {
		no_floating_promises { return c.lint_no_floating_promises(root, abs_path, mut stats)! }
		await_thenable { return c.lint_await_thenable(root, abs_path, mut stats)! }
		require_await { return c.lint_require_await(root, abs_path, mut stats)! }
		return_await { return c.lint_return_await(root, abs_path, mut stats)! }
		no_misused_promises { return c.lint_no_misused_promises(root, abs_path, mut stats)! }
		no_unsafe_call { return c.lint_no_unsafe_call(root, abs_path, mut stats)! }
		no_unsafe_member_access {
			return c.lint_no_unsafe_member_access(root, abs_path, mut stats)!
		}
		no_unsafe_return { return c.lint_no_unsafe_return(root, abs_path, mut stats)! }
		no_unsafe_assignment { return c.lint_no_unsafe_assignment(root, abs_path, mut stats)! }
		no_unsafe_argument { return c.lint_no_unsafe_argument(root, abs_path, mut stats)! }
		restrict_template_expressions {
			return c.lint_restrict_template_expressions(root, abs_path, mut stats)!
		}
		switch_exhaustiveness_check {
			return c.lint_switch_exhaustiveness_check(root, abs_path, mut stats)!
		}
		prefer_nullish_coalescing {
			return c.lint_prefer_nullish_coalescing(root, abs_path, mut stats)!
		}
		no_unnecessary_condition {
			return c.lint_no_unnecessary_condition(root, abs_path, mut stats)!
		}
		no_for_in_array {
			return c.lint_no_for_in_array(root, abs_path, mut stats)!
		}
		no_array_delete {
			return c.lint_no_array_delete(root, abs_path, mut stats)!
		}
		no_unnecessary_boolean_literal_compare {
			return c.lint_no_unnecessary_boolean_literal_compare(root, abs_path, mut stats)!
		}
		no_unsafe_unary_minus {
			return c.lint_no_unsafe_unary_minus(root, abs_path, mut stats)!
		}
		no_meaningless_void_operator {
			return c.lint_no_meaningless_void_operator(root, abs_path, mut stats)!
		}
		related_getter_setter_pairs {
			return c.lint_related_getter_setter_pairs(root, abs_path, mut stats)!
		}
		non_nullable_type_assertion_style {
			return c.lint_non_nullable_type_assertion_style(root, abs_path, mut stats)!
		}
		prefer_return_this_type {
			return c.lint_prefer_return_this_type(root, abs_path, mut stats)!
		}
		no_duplicate_type_constituents {
			return c.lint_no_duplicate_type_constituents(root, abs_path, mut stats)!
		}
		no_unnecessary_template_expression {
			return c.lint_no_unnecessary_template_expression(root, abs_path, mut stats)!
		}
		dot_notation {
			return c.lint_dot_notation(root, abs_path, mut stats)!
		}
		restrict_plus_operands {
			return c.lint_restrict_plus_operands(root, abs_path, mut stats)!
		}
		no_confusing_void_expression {
			return c.lint_no_confusing_void_expression(root, abs_path, mut stats)!
		}
		no_misused_spread {
			return c.lint_no_misused_spread(root, abs_path, mut stats)!
		}
		no_redundant_type_constituents {
			return c.lint_no_redundant_type_constituents(root, abs_path, mut stats)!
		}
		no_useless_default_assignment {
			return c.lint_no_useless_default_assignment(root, abs_path, mut stats)!
		}
		no_unnecessary_type_arguments {
			return c.lint_no_unnecessary_type_arguments(root, abs_path, mut stats)!
		}
		no_unnecessary_qualifier {
			return c.lint_no_unnecessary_qualifier(root, abs_path, mut stats)!
		}
		no_implied_eval {
			return c.lint_no_implied_eval(root, abs_path, mut stats)!
		}
		no_base_to_string {
			return c.lint_no_base_to_string(root, abs_path, mut stats)!
		}
		no_unsafe_enum_comparison {
			return c.lint_no_unsafe_enum_comparison(root, abs_path, mut stats)!
		}
		no_mixed_enums { return c.lint_no_mixed_enums(root, abs_path, mut stats)! }
		no_unnecessary_type_conversion {
			return c.lint_no_unnecessary_type_conversion(root, abs_path, mut stats)!
		}
		no_unnecessary_type_assertion {
			return c.lint_no_unnecessary_type_assertion(root, abs_path, mut stats)!
		}
		unbound_method { return c.lint_unbound_method(root, abs_path, mut stats)! }
		prefer_reduce_type_parameter {
			return c.lint_prefer_reduce_type_parameter(root, abs_path, mut stats)!
		}
		prefer_find {
			return c.lint_prefer_find(root, abs_path, mut stats)!
		}
		prefer_regexp_exec {
			return c.lint_prefer_regexp_exec(root, abs_path, mut stats)!
		}
		prefer_includes {
			return c.lint_prefer_includes(root, abs_path, mut stats)!
		}
		prefer_string_starts_ends_with {
			return c.lint_prefer_string_starts_ends_with(root, abs_path, mut stats)!
		}
		prefer_optional_chain {
			return c.lint_prefer_optional_chain(root, abs_path, mut stats)!
		}
		no_deprecated {
			return c.lint_no_deprecated(root, abs_path, mut stats)!
		}
		prefer_promise_reject_errors {
			return c.lint_prefer_promise_reject_errors(root, abs_path, mut stats)!
		}
		use_unknown_in_catch_callback_variable {
			return c.lint_use_unknown_in_catch_callback_variable(root, abs_path, mut stats)!
		}
		only_throw_error {
			return c.lint_only_throw_error(root, abs_path, mut stats)!
		}
		require_array_sort_compare {
			return c.lint_require_array_sort_compare(root, abs_path, mut stats)!
		}
		no_unsafe_type_assertion {
			return c.lint_no_unsafe_type_assertion(root, abs_path, mut stats)!
		}
		promise_function_async {
			return c.lint_promise_function_async(root, abs_path, mut stats)!
		}
		prefer_readonly_parameter_types {
			return c.lint_prefer_readonly_parameter_types(root, abs_path, mut stats)!
		}
		consistent_type_exports {
			return c.lint_consistent_type_exports(root, abs_path, mut stats)!
		}
		strict_void_return {
			return c.lint_strict_void_return(root, abs_path, mut stats)!
		}
		consistent_return {
			return c.lint_consistent_return(root, abs_path, mut stats)!
		}
		prefer_destructuring {
			return c.lint_prefer_destructuring(root, abs_path, mut stats)!
		}
		prefer_readonly {
			return c.lint_prefer_readonly(root, abs_path, mut stats)!
		}
		strict_boolean_expressions {
			return c.lint_strict_boolean_expressions(root, abs_path, mut stats)!
		}
		no_unnecessary_type_parameters {
			return c.lint_no_unnecessary_type_parameters(root, abs_path, mut stats)!
		}
		naming_convention {
			return c.lint_naming_convention(root, abs_path, mut stats)!
		}
		no_duplicate_enum_values {
			return c.lint_no_duplicate_enum_values(root, abs_path, mut stats)!
		}
		no_extra_non_null_assertion {
			return c.lint_no_extra_non_null_assertion(root, abs_path, mut stats)!
		}
		no_non_null_asserted_optional_chain {
			return c.lint_no_non_null_asserted_optional_chain(root, abs_path, mut stats)!
		}
		no_unsafe_function_type {
			return c.lint_no_unsafe_function_type(root, abs_path, mut stats)!
		}
		no_wrapper_object_types {
			return c.lint_no_wrapper_object_types(root, abs_path, mut stats)!
		}
		prefer_enum_initializers {
			return c.lint_prefer_enum_initializers(root, abs_path, mut stats)!
		}
		no_dynamic_delete {
			return c.lint_no_dynamic_delete(root, abs_path, mut stats)!
		}
		no_namespace {
			return c.lint_no_namespace(root, abs_path, mut stats)!
		}
		no_unnecessary_type_constraint {
			return c.lint_no_unnecessary_type_constraint(root, abs_path, mut stats)!
		}
		prefer_as_const {
			return c.lint_prefer_as_const(root, abs_path, mut stats)!
		}
		no_invalid_void_type {
			return c.lint_no_invalid_void_type(root, abs_path, mut stats)!
		}
		no_this_alias {
			return c.lint_no_this_alias(root, abs_path, mut stats)!
		}
		no_misused_new {
			return c.lint_no_misused_new(root, abs_path, mut stats)!
		}
		no_useless_empty_export {
			return c.lint_no_useless_empty_export(root, abs_path, mut stats)!
		}
		no_extraneous_class {
			return c.lint_no_extraneous_class(root, abs_path, mut stats)!
		}
		adjacent_overload_signatures {
			return c.lint_adjacent_overload_signatures(root, abs_path, mut stats)!
		}
		no_dupe_class_members {
			return c.lint_no_dupe_class_members(root, abs_path, mut stats)!
		}
		class_literal_property_style {
			return c.lint_class_literal_property_style(root, abs_path, mut stats)!
		}
		no_empty_function {
			return c.lint_no_empty_function(root, abs_path, mut stats)!
		}
		no_unused_expressions {
			return c.lint_no_unused_expressions(root, abs_path, mut stats)!
		}
		no_useless_constructor {
			return c.lint_no_useless_constructor(root, abs_path, mut stats)!
		}
		no_array_constructor {
			return c.lint_no_array_constructor(root, abs_path, mut stats)!
		}
		no_confusing_non_null_assertion {
			return c.lint_no_confusing_non_null_assertion(root, abs_path, mut stats)!
		}
		no_import_type_side_effects {
			return c.lint_no_import_type_side_effects(root, abs_path, mut stats)!
		}
		no_inferrable_types {
			return c.lint_no_inferrable_types(root, abs_path, mut stats)!
		}
		prefer_namespace_keyword {
			return c.lint_prefer_namespace_keyword(root, abs_path, mut stats)!
		}
		triple_slash_reference {
			return c.lint_triple_slash_reference(root, abs_path, mut stats)!
		}
		consistent_generic_constructors {
			return c.lint_consistent_generic_constructors(root, abs_path, mut stats)!
		}
		consistent_type_assertions {
			return c.lint_consistent_type_assertions(root, abs_path, mut stats)!
		}
		consistent_type_definitions {
			return c.lint_consistent_type_definitions(root, abs_path, mut stats)!
		}
		prefer_function_type {
			return c.lint_prefer_function_type(root, abs_path, mut stats)!
		}
		unified_signatures {
			return c.lint_unified_signatures(root, abs_path, mut stats)!
		}
		no_unsafe_declaration_merging {
			return c.lint_no_unsafe_declaration_merging(root, abs_path, mut stats)!
		}
		no_require_imports {
			return c.lint_no_require_imports(root, abs_path, mut stats)!
		}
		no_non_null_asserted_nullish_coalescing {
			return c.lint_no_non_null_asserted_nullish_coalescing(root, abs_path, mut stats)!
		}
		prefer_for_of {
			return c.lint_prefer_for_of(root, abs_path, mut stats)!
		}
		array_type {
			return c.lint_array_type(root, abs_path, mut stats)!
		}
		consistent_indexed_object_style {
			return c.lint_consistent_indexed_object_style(root, abs_path, mut stats)!
		}
		no_unnecessary_parameter_property_assignment {
			return c.lint_no_unnecessary_parameter_property_assignment(root, abs_path, mut stats)!
		}
		no_unused_private_class_members {
			return c.lint_no_unused_private_class_members(root, abs_path, mut stats)!
		}
		no_use_before_define {
			return c.lint_no_use_before_define(root, abs_path, mut stats)!
		}
		no_shadow {
			return c.lint_no_shadow(root, abs_path, mut stats)!
		}
		consistent_type_imports {
			return c.lint_consistent_type_imports(root, abs_path, mut stats)!
		}
		no_unused_vars {
			return c.lint_no_unused_vars(root, abs_path, mut stats)!
		}
		seyfert_prefer_typed_group {
			return c.lint_seyfert_prefer_typed_group(root, abs_path, mut stats)!
		}
		seyfert_autocomplete_respond {
			return c.lint_seyfert_autocomplete_respond(root, abs_path, mut stats)!
		}
		seyfert_config_default_export {
			return c.lint_seyfert_config_default_export(root, abs_path, mut stats)!
		}
		seyfert_decorator_target {
			return c.lint_seyfert_decorator_target(root, abs_path, mut stats)!
		}
		seyfert_decorator_on_command {
			return c.lint_seyfert_decorator_on_command(root, abs_path, mut stats)!
		}
		seyfert_i18n_resolve_with_get {
			return c.lint_seyfert_i18n_resolve_with_get(root, abs_path, mut stats)!
		}
		seyfert_no_method_destructure {
			return c.lint_seyfert_no_method_destructure(root, abs_path, mut stats)!
		}
		seyfert_require_declare {
			return c.lint_seyfert_require_declare(root, abs_path, mut stats)!
		}
		seyfert_context_menu_declare {
			return c.lint_seyfert_context_menu_declare(root, abs_path, mut stats)!
		}
		seyfert_required_options_order {
			return c.lint_seyfert_required_options_order(root, abs_path, mut stats)!
		}
		seyfert_options_use_builders {
			return c.lint_seyfert_options_use_builders(root, abs_path, mut stats)!
		}
		seyfert_declare_description {
			return c.lint_seyfert_declare_description(root, abs_path, mut stats)!
		}
		seyfert_no_deep_imports {
			return c.lint_seyfert_no_deep_imports(root, abs_path, mut stats)!
		}
		seyfert_no_hanging_middleware {
			return c.lint_seyfert_no_hanging_middleware(root, abs_path, mut stats)!
		}
		seyfert_group_exists {
			return c.lint_seyfert_group_exists(root, abs_path, mut stats)!
		}
		no_compare_neg_zero {
			return c.lint_no_compare_neg_zero(root, abs_path, mut stats)!
		}
		use_isnan {
			return c.lint_use_isnan(root, abs_path, mut stats)!
		}
		valid_typeof {
			return c.lint_valid_typeof(root, abs_path, mut stats)!
		}
		no_dupe_else_if {
			return c.lint_no_dupe_else_if(root, abs_path, mut stats)!
		}
		no_duplicate_case {
			return c.lint_no_duplicate_case(root, abs_path, mut stats)!
		}
		no_self_compare {
			return c.lint_no_self_compare(root, abs_path, mut stats)!
		}
		no_self_assign {
			return c.lint_no_self_assign(root, abs_path, mut stats)!
		}
		no_unsafe_negation {
			return c.lint_no_unsafe_negation(root, abs_path, mut stats)!
		}
		no_unsafe_optional_chaining {
			return c.lint_no_unsafe_optional_chaining(root, abs_path, mut stats)!
		}
		no_cond_assign {
			return c.lint_no_cond_assign(root, abs_path, mut stats)!
		}
		for_direction {
			return c.lint_for_direction(root, abs_path, mut stats)!
		}
		no_constant_condition {
			return c.lint_no_constant_condition(root, abs_path, mut stats)!
		}
		no_constant_binary_expression {
			return c.lint_no_constant_binary_expression(root, abs_path, mut stats)!
		}
		curly {
			return c.lint_curly(root, abs_path, mut stats)!
		}
		no_else_return {
			return c.lint_no_else_return(root, abs_path, mut stats)!
		}
		no_empty {
			return c.lint_no_empty(root, abs_path, mut stats)!
		}
		no_empty_static_block {
			return c.lint_no_empty_static_block(root, abs_path, mut stats)!
		}
		default_case_last {
			return c.lint_default_case_last(root, abs_path, mut stats)!
		}
		no_case_declarations {
			return c.lint_no_case_declarations(root, abs_path, mut stats)!
		}
		no_labels {
			return c.lint_no_labels(root, abs_path, mut stats)!
		}
		no_extra_label {
			return c.lint_no_extra_label(root, abs_path, mut stats)!
		}
		no_unused_labels {
			return c.lint_no_unused_labels(root, abs_path, mut stats)!
		}
		no_with {
			return c.lint_no_with(root, abs_path, mut stats)!
		}
		no_debugger {
			return c.lint_no_debugger(root, abs_path, mut stats)!
		}
		no_unsafe_finally {
			return c.lint_no_unsafe_finally(root, abs_path, mut stats)!
		}
		no_useless_catch {
			return c.lint_no_useless_catch(root, abs_path, mut stats)!
		}
		arrow_body_style {
			return c.lint_arrow_body_style(root, abs_path, mut stats)!
		}
		prefer_arrow_callback {
			return c.lint_prefer_arrow_callback(root, abs_path, mut stats)!
		}
		func_name_matching {
			return c.lint_func_name_matching(root, abs_path, mut stats)!
		}
		func_names {
			return c.lint_func_names(root, abs_path, mut stats)!
		}
		grouped_accessor_pairs {
			return c.lint_grouped_accessor_pairs(root, abs_path, mut stats)!
		}
		no_setter_return {
			return c.lint_no_setter_return(root, abs_path, mut stats)!
		}
		no_dupe_args {
			return c.lint_no_dupe_args(root, abs_path, mut stats)!
		}
		no_dupe_keys {
			return c.lint_no_dupe_keys(root, abs_path, mut stats)!
		}
		no_empty_pattern {
			return c.lint_no_empty_pattern(root, abs_path, mut stats)!
		}
		no_useless_rename {
			return c.lint_no_useless_rename(root, abs_path, mut stats)!
		}
		no_useless_computed_key {
			return c.lint_no_useless_computed_key(root, abs_path, mut stats)!
		}
		object_shorthand {
			return c.lint_object_shorthand(root, abs_path, mut stats)!
		}
		require_yield {
			return c.lint_require_yield(root, abs_path, mut stats)!
		}
		eqeqeq {
			return c.lint_eqeqeq(root, abs_path, mut stats)!
		}
		yoda {
			return c.lint_yoda(root, abs_path, mut stats)!
		}
		no_eq_null {
			return c.lint_no_eq_null(root, abs_path, mut stats)!
		}
		no_extra_boolean_cast {
			return c.lint_no_extra_boolean_cast(root, abs_path, mut stats)!
		}
		no_implicit_coercion {
			return c.lint_no_implicit_coercion(root, abs_path, mut stats)!
		}
		logical_assignment_operators {
			return c.lint_logical_assignment_operators(root, abs_path, mut stats)!
		}
		operator_assignment {
			return c.lint_operator_assignment(root, abs_path, mut stats)!
		}
		prefer_exponentiation_operator {
			return c.lint_prefer_exponentiation_operator(root, abs_path, mut stats)!
		}
		no_sequences {
			return c.lint_no_sequences(root, abs_path, mut stats)!
		}
		no_return_assign {
			return c.lint_no_return_assign(root, abs_path, mut stats)!
		}
		no_unexpected_multiline {
			return c.lint_no_unexpected_multiline(root, abs_path, mut stats)!
		}
		no_loss_of_precision {
			return c.lint_no_loss_of_precision(root, abs_path, mut stats)!
		}
		no_nonoctal_decimal_escape {
			return c.lint_no_nonoctal_decimal_escape(root, abs_path, mut stats)!
		}
		no_octal {
			return c.lint_no_octal(root, abs_path, mut stats)!
		}
		no_octal_escape {
			return c.lint_no_octal_escape(root, abs_path, mut stats)!
		}
		prefer_numeric_literals {
			return c.lint_prefer_numeric_literals(root, abs_path, mut stats)!
		}
		no_multi_str {
			return c.lint_no_multi_str(root, abs_path, mut stats)!
		}
		no_template_curly_in_string {
			return c.lint_no_template_curly_in_string(root, abs_path, mut stats)!
		}
		no_useless_concat {
			return c.lint_no_useless_concat(root, abs_path, mut stats)!
		}
		prefer_template {
			return c.lint_prefer_template(root, abs_path, mut stats)!
		}
		no_irregular_whitespace {
			return c.lint_no_irregular_whitespace(root, abs_path, mut stats)!
		}
		unicode_bom {
			return c.lint_unicode_bom(root, abs_path, mut stats)!
		}
		no_sparse_arrays {
			return c.lint_no_sparse_arrays(root, abs_path, mut stats)!
		}
		no_new {
			return c.lint_no_new(root, abs_path, mut stats)!
		}
		no_new_func {
			return c.lint_no_new_func(root, abs_path, mut stats)!
		}
		no_new_wrappers {
			return c.lint_no_new_wrappers(root, abs_path, mut stats)!
		}
		no_new_native_nonconstructor {
			return c.lint_no_new_native_nonconstructor(root, abs_path, mut stats)!
		}
		no_obj_calls {
			return c.lint_no_obj_calls(root, abs_path, mut stats)!
		}
		no_object_constructor {
			return c.lint_no_object_constructor(root, abs_path, mut stats)!
		}
		no_async_promise_executor {
			return c.lint_no_async_promise_executor(root, abs_path, mut stats)!
		}
		no_extra_bind {
			return c.lint_no_extra_bind(root, abs_path, mut stats)!
		}
		no_useless_call {
			return c.lint_no_useless_call(root, abs_path, mut stats)!
		}
		prefer_spread {
			return c.lint_prefer_spread(root, abs_path, mut stats)!
		}
		prefer_rest_params {
			return c.lint_prefer_rest_params(root, abs_path, mut stats)!
		}
		symbol_description {
			return c.lint_symbol_description(root, abs_path, mut stats)!
		}
		radix_rule {
			return c.lint_radix(root, abs_path, mut stats)!
		}
		no_extend_native {
			return c.lint_no_extend_native(root, abs_path, mut stats)!
		}
		core_no_implied_eval {
			return c.lint_core_no_implied_eval(root, abs_path, mut stats)!
		}
		no_caller {
			return c.lint_no_caller(root, abs_path, mut stats)!
		}
		no_iterator {
			return c.lint_no_iterator(root, abs_path, mut stats)!
		}
		no_proto {
			return c.lint_no_proto(root, abs_path, mut stats)!
		}
		no_script_url {
			return c.lint_no_script_url(root, abs_path, mut stats)!
		}
		no_prototype_builtins {
			return c.lint_no_prototype_builtins(root, abs_path, mut stats)!
		}
		prefer_object_has_own {
			return c.lint_prefer_object_has_own(root, abs_path, mut stats)!
		}
		prefer_object_spread {
			return c.lint_prefer_object_spread(root, abs_path, mut stats)!
		}
		core_dot_notation {
			return c.lint_core_dot_notation(root, abs_path, mut stats)!
		}
		preserve_caught_error {
			return c.lint_preserve_caught_error(root, abs_path, mut stats)!
		}
		no_class_assign {
			return c.lint_no_class_assign(root, abs_path, mut stats)!
		}
		no_const_assign {
			return c.lint_no_const_assign(root, abs_path, mut stats)!
		}
		no_ex_assign {
			return c.lint_no_ex_assign(root, abs_path, mut stats)!
		}
		no_func_assign {
			return c.lint_no_func_assign(root, abs_path, mut stats)!
		}
		no_global_assign {
			return c.lint_no_global_assign(root, abs_path, mut stats)!
		}
		no_import_assign {
			return c.lint_no_import_assign(root, abs_path, mut stats)!
		}
		no_label_var {
			return c.lint_no_label_var(root, abs_path, mut stats)!
		}
		no_shadow_restricted_names {
			return c.lint_no_shadow_restricted_names(root, abs_path, mut stats)!
		}
		no_unassigned_vars {
			return c.lint_no_unassigned_vars(root, abs_path, mut stats)!
		}
		no_delete_var {
			return c.lint_no_delete_var(root, abs_path, mut stats)!
		}
		block_scoped_var {
			return c.lint_block_scoped_var(root, abs_path, mut stats)!
		}
		consistent_this {
			return c.lint_consistent_this(root, abs_path, mut stats)!
		}
		no_var {
			return c.lint_no_var(root, abs_path, mut stats)!
		}
		prefer_const {
			return c.lint_prefer_const(root, abs_path, mut stats)!
		}
		vars_on_top {
			return c.lint_vars_on_top(root, abs_path, mut stats)!
		}
		sort_vars {
			return c.lint_sort_vars(root, abs_path, mut stats)!
		}
		strict_rule {
			return c.lint_strict(root, abs_path, mut stats)!
		}
		no_inner_declarations {
			return c.lint_no_inner_declarations(root, abs_path, mut stats)!
		}
		no_lone_blocks {
			return c.lint_no_lone_blocks(root, abs_path, mut stats)!
		}
		no_loop_func {
			return c.lint_no_loop_func(root, abs_path, mut stats)!
		}
		no_implicit_globals {
			return c.lint_no_implicit_globals(root, abs_path, mut stats)!
		}
		no_unmodified_loop_condition {
			return c.lint_no_unmodified_loop_condition(root, abs_path, mut stats)!
		}
		no_control_regex {
			return c.lint_no_control_regex(root, abs_path, mut stats)!
		}
		no_div_regex {
			return c.lint_no_div_regex(root, abs_path, mut stats)!
		}
		no_empty_character_class {
			return c.lint_no_empty_character_class(root, abs_path, mut stats)!
		}
		no_invalid_regexp {
			return c.lint_no_invalid_regexp(root, abs_path, mut stats)!
		}
		no_misleading_character_class {
			return c.lint_no_misleading_character_class(root, abs_path, mut stats)!
		}
		no_regex_spaces {
			return c.lint_no_regex_spaces(root, abs_path, mut stats)!
		}
		no_useless_backreference {
			return c.lint_no_useless_backreference(root, abs_path, mut stats)!
		}
		no_useless_escape {
			return c.lint_no_useless_escape(root, abs_path, mut stats)!
		}
		prefer_regex_literals {
			return c.lint_prefer_regex_literals(root, abs_path, mut stats)!
		}
		no_warning_comments {
			return c.lint_no_warning_comments(root, abs_path, mut stats)!
		}
		no_restricted_globals {
			return c.lint_no_restricted_globals(root, abs_path, mut stats)!
		}
		no_restricted_properties {
			return c.lint_no_restricted_properties(root, abs_path, mut stats)!
		}
		no_restricted_exports {
			return c.lint_no_restricted_exports(root, abs_path, mut stats)!
		}
		no_restricted_imports {
			return c.lint_no_restricted_imports(root, abs_path, mut stats)!
		}
		no_constructor_return {
			return c.lint_no_constructor_return(root, abs_path, mut stats)!
		}
		no_promise_executor_return {
			return c.lint_no_promise_executor_return(root, abs_path, mut stats)!
		}
		no_invalid_this {
			return c.lint_no_invalid_this(root, abs_path, mut stats)!
		}
		getter_return {
			return c.lint_getter_return(root, abs_path, mut stats)!
		}
		no_unreachable_loop {
			return c.lint_no_unreachable_loop(root, abs_path, mut stats)!
		}
		no_useless_return {
			return c.lint_no_useless_return(root, abs_path, mut stats)!
		}
		no_unreachable {
			return c.lint_no_unreachable(root, abs_path, mut stats)!
		}
		no_fallthrough {
			return c.lint_no_fallthrough(root, abs_path, mut stats)!
		}
		constructor_super {
			return c.lint_constructor_super(root, abs_path, mut stats)!
		}
		no_this_before_super {
			return c.lint_no_this_before_super(root, abs_path, mut stats)!
		}
		no_useless_assignment {
			return c.lint_no_useless_assignment(root, abs_path, mut stats)!
		}
		no_restricted_syntax {
			return c.lint_no_restricted_syntax(root, abs_path, mut stats)!
		}
		unicorn_no_lonely_if {
			return c.lint_unicorn_no_lonely_if(root, abs_path, mut stats)!
		}
		unicorn_no_negated_condition {
			return c.lint_unicorn_no_negated_condition(root, abs_path, mut stats)!
		}
		unicorn_no_negation_in_equality_check {
			return c.lint_unicorn_no_negation_in_equality_check(root, abs_path, mut stats)!
		}
		unicorn_no_nested_ternary {
			return c.lint_unicorn_no_nested_ternary(root, abs_path, mut stats)!
		}
		unicorn_no_typeof_undefined {
			return c.lint_unicorn_no_typeof_undefined(root, abs_path, mut stats)!
		}
		unicorn_prefer_logical_operator_over_ternary {
			return c.lint_unicorn_prefer_logical_operator_over_ternary(root, abs_path, mut stats)!
		}
		unicorn_prefer_ternary {
			return c.lint_unicorn_prefer_ternary(root, abs_path, mut stats)!
		}
		unicorn_prefer_switch {
			return c.lint_unicorn_prefer_switch(root, abs_path, mut stats)!
		}
		unicorn_switch_case_braces {
			return c.lint_unicorn_switch_case_braces(root, abs_path, mut stats)!
		}
		unicorn_switch_case_break_position {
			return c.lint_unicorn_switch_case_break_position(root, abs_path, mut stats)!
		}
		unicorn_no_useless_switch_case {
			return c.lint_unicorn_no_useless_switch_case(root, abs_path, mut stats)!
		}
		unicorn_prefer_simple_condition_first {
			return c.lint_unicorn_prefer_simple_condition_first(root, abs_path, mut stats)!
		}
		unicorn_prefer_date_now {
			return c.lint_unicorn_prefer_date_now(root, abs_path, mut stats)!
		}
		unicorn_throw_new_error {
			return c.lint_unicorn_throw_new_error(root, abs_path, mut stats)!
		}
		unicorn_error_message {
			return c.lint_unicorn_error_message(root, abs_path, mut stats)!
		}
		unicorn_consistent_date_clone {
			return c.lint_unicorn_consistent_date_clone(root, abs_path, mut stats)!
		}
		unicorn_consistent_assert {
			return c.lint_unicorn_consistent_assert(root, abs_path, mut stats)!
		}
		unicorn_no_new_buffer {
			return c.lint_unicorn_no_new_buffer(root, abs_path, mut stats)!
		}
		unicorn_prefer_type_error {
			return c.lint_unicorn_prefer_type_error(root, abs_path, mut stats)!
		}
		unicorn_no_useless_error_capture_stack_trace {
			return c.lint_unicorn_no_useless_error_capture_stack_trace(root, abs_path, mut stats)!
		}
		unicorn_prefer_structured_clone {
			return c.lint_unicorn_prefer_structured_clone(root, abs_path, mut stats)!
		}
		unicorn_custom_error_definition {
			return c.lint_unicorn_custom_error_definition(root, abs_path, mut stats)!
		}
		unicorn_no_instanceof_builtins {
			return c.lint_unicorn_no_instanceof_builtins(root, abs_path, mut stats)!
		}
		unicorn_new_for_builtins {
			return c.lint_unicorn_new_for_builtins(root, abs_path, mut stats)!
		}
		unicorn_no_hex_escape {
			return c.lint_unicorn_no_hex_escape(root, abs_path, mut stats)!
		}
		unicorn_escape_case {
			return c.lint_unicorn_escape_case(root, abs_path, mut stats)!
		}
		unicorn_consistent_template_literal_escape {
			return c.lint_unicorn_consistent_template_literal_escape(root, abs_path, mut stats)!
		}
		unicorn_prefer_string_trim_start_end {
			return c.lint_unicorn_prefer_string_trim_start_end(root, abs_path, mut stats)!
		}
		unicorn_no_console_spaces {
			return c.lint_unicorn_no_console_spaces(root, abs_path, mut stats)!
		}
		unicorn_prefer_code_point {
			return c.lint_unicorn_prefer_code_point(root, abs_path, mut stats)!
		}
		unicorn_prefer_string_slice {
			return c.lint_unicorn_prefer_string_slice(root, abs_path, mut stats)!
		}
		unicorn_text_encoding_identifier_case {
			return c.lint_unicorn_text_encoding_identifier_case(root, abs_path, mut stats)!
		}
		unicorn_no_zero_fractions {
			return c.lint_unicorn_no_zero_fractions(root, abs_path, mut stats)!
		}
		unicorn_prefer_bigint_literals {
			return c.lint_unicorn_prefer_bigint_literals(root, abs_path, mut stats)!
		}
		unicorn_prefer_number_properties {
			return c.lint_unicorn_prefer_number_properties(root, abs_path, mut stats)!
		}
		unicorn_prefer_string_raw {
			return c.lint_unicorn_prefer_string_raw(root, abs_path, mut stats)!
		}
		unicorn_prefer_string_replace_all {
			return c.lint_unicorn_prefer_string_replace_all(root, abs_path, mut stats)!
		}
		unicorn_require_number_to_fixed_digits_argument {
			return c.lint_unicorn_require_number_to_fixed_digits_argument(root, abs_path, mut stats)!
		}
		unicorn_prefer_math_trunc {
			return c.lint_unicorn_prefer_math_trunc(root, abs_path, mut stats)!
		}
		unicorn_prefer_math_min_max {
			return c.lint_unicorn_prefer_math_min_max(root, abs_path, mut stats)!
		}
		unicorn_prefer_modern_math_apis {
			return c.lint_unicorn_prefer_modern_math_apis(root, abs_path, mut stats)!
		}
		unicorn_prefer_native_coercion_functions {
			return c.lint_unicorn_prefer_native_coercion_functions(root, abs_path, mut stats)!
		}
		unicorn_no_array_callback_reference {
			return c.lint_unicorn_no_array_callback_reference(root, abs_path, mut stats)!
		}
		unicorn_no_for_each {
			return c.lint_unicorn_no_for_each(root, abs_path, mut stats)!
		}
		unicorn_no_array_method_this_argument {
			return c.lint_unicorn_no_array_method_this_argument(root, abs_path, mut stats)!
		}
		unicorn_no_array_reverse {
			return c.lint_unicorn_no_array_reverse(root, abs_path, mut stats)!
		}
		unicorn_no_array_sort {
			return c.lint_unicorn_no_array_sort(root, abs_path, mut stats)!
		}
		unicorn_no_new_array {
			return c.lint_unicorn_no_new_array(root, abs_path, mut stats)!
		}
		unicorn_prefer_array_flat {
			return c.lint_unicorn_prefer_array_flat(root, abs_path, mut stats)!
		}
		unicorn_prefer_array_flat_map {
			return c.lint_unicorn_prefer_array_flat_map(root, abs_path, mut stats)!
		}
		unicorn_prefer_array_index_of {
			return c.lint_unicorn_prefer_array_index_of(root, abs_path, mut stats)!
		}
		unicorn_prefer_array_some {
			return c.lint_unicorn_prefer_array_some(root, abs_path, mut stats)!
		}
		unicorn_require_array_join_separator {
			return c.lint_unicorn_require_array_join_separator(root, abs_path, mut stats)!
		}
		unicorn_prefer_negative_index {
			return c.lint_unicorn_prefer_negative_index(root, abs_path, mut stats)!
		}
		unicorn_consistent_existence_index_check {
			return c.lint_unicorn_consistent_existence_index_check(root, abs_path, mut stats)!
		}
		unicorn_explicit_length_check {
			return c.lint_unicorn_explicit_length_check(root, abs_path, mut stats)!
		}
		unicorn_no_unnecessary_array_flat_depth {
			return c.lint_unicorn_no_unnecessary_array_flat_depth(root, abs_path, mut stats)!
		}
		unicorn_no_unnecessary_array_splice_count {
			return c.lint_unicorn_no_unnecessary_array_splice_count(root, abs_path, mut stats)!
		}
		unicorn_no_unnecessary_slice_end {
			return c.lint_unicorn_no_unnecessary_slice_end(root, abs_path, mut stats)!
		}
		unicorn_no_useless_length_check {
			return c.lint_unicorn_no_useless_length_check(root, abs_path, mut stats)!
		}
		unicorn_no_unreadable_array_destructuring {
			return c.lint_unicorn_no_unreadable_array_destructuring(root, abs_path, mut stats)!
		}
		unicorn_prefer_set_size {
			return c.lint_unicorn_prefer_set_size(root, abs_path, mut stats)!
		}
		array_callback_return {
			return c.lint_array_callback_return(root, abs_path, mut stats)!
		}
		no_lonely_if {
			return c.lint_no_lonely_if(root, abs_path, mut stats)!
		}
		no_negated_condition {
			return c.lint_no_negated_condition(root, abs_path, mut stats)!
		}
		no_throw_literal {
			return c.lint_no_throw_literal(root, abs_path, mut stats)!
		}
		require_atomic_updates {
			return c.lint_require_atomic_updates(root, abs_path, mut stats)!
		}
		class_methods_use_this {
			return c.lint_class_methods_use_this(root, abs_path, mut stats)!
		}
		no_explicit_any {
			return c.lint_no_explicit_any(root, abs_path, mut stats)!
		}
		unicorn_consistent_empty_array_spread {
			return c.lint_unicorn_consistent_empty_array_spread(root, abs_path, mut stats)!
		}
		unicorn_no_useless_fallback_in_spread {
			return c.lint_unicorn_no_useless_fallback_in_spread(root, abs_path, mut stats)!
		}
		unicorn_no_useless_collection_argument {
			return c.lint_unicorn_no_useless_collection_argument(root, abs_path, mut stats)!
		}
		unicorn_no_useless_iterator_to_array {
			return c.lint_unicorn_no_useless_iterator_to_array(root, abs_path, mut stats)!
		}
		unicorn_no_useless_spread {
			return c.lint_unicorn_no_useless_spread(root, abs_path, mut stats)!
		}
		unicorn_prefer_single_call {
			return c.lint_unicorn_prefer_single_call(root, abs_path, mut stats)!
		}
		unicorn_no_immediate_mutation {
			return c.lint_unicorn_no_immediate_mutation(root, abs_path, mut stats)!
		}
		unicorn_prefer_blob_reading_methods {
			return c.lint_unicorn_prefer_blob_reading_methods(root, abs_path, mut stats)!
		}
		unicorn_prefer_response_static_json {
			return c.lint_unicorn_prefer_response_static_json(root, abs_path, mut stats)!
		}
		unicorn_no_await_expression_member {
			return c.lint_unicorn_no_await_expression_member(root, abs_path, mut stats)!
		}
		unicorn_prefer_spread {
			return c.lint_unicorn_prefer_spread(root, abs_path, mut stats)!
		}
		unicorn_no_await_in_promise_methods {
			return c.lint_unicorn_no_await_in_promise_methods(root, abs_path, mut stats)!
		}
		unicorn_no_invalid_fetch_options {
			return c.lint_unicorn_no_invalid_fetch_options(root, abs_path, mut stats)!
		}
		unicorn_no_unnecessary_await {
			return c.lint_unicorn_no_unnecessary_await(root, abs_path, mut stats)!
		}
		unicorn_no_thenable {
			return c.lint_unicorn_no_thenable(root, abs_path, mut stats)!
		}
		unicorn_no_single_promise_in_promise_methods {
			return c.lint_unicorn_no_single_promise_in_promise_methods(root, abs_path, mut stats)!
		}
		unicorn_no_useless_promise_resolve_reject {
			return c.lint_unicorn_no_useless_promise_resolve_reject(root, abs_path, mut stats)!
		}
		unicorn_prefer_node_protocol {
			return c.lint_unicorn_prefer_node_protocol(root, abs_path, mut stats)!
		}
		unicorn_no_process_exit {
			return c.lint_unicorn_no_process_exit(root, abs_path, mut stats)!
		}
		unicorn_no_named_default {
			return c.lint_unicorn_no_named_default(root, abs_path, mut stats)!
		}
		unicorn_require_module_attributes {
			return c.lint_unicorn_require_module_attributes(root, abs_path, mut stats)!
		}
		unicorn_require_module_specifiers {
			return c.lint_unicorn_require_module_specifiers(root, abs_path, mut stats)!
		}
		unicorn_prefer_json_parse_buffer {
			return c.lint_unicorn_prefer_json_parse_buffer(root, abs_path, mut stats)!
		}
		unicorn_no_anonymous_default_export {
			return c.lint_unicorn_no_anonymous_default_export(root, abs_path, mut stats)!
		}
		unicorn_prefer_import_meta_properties {
			return c.lint_unicorn_prefer_import_meta_properties(root, abs_path, mut stats)!
		}
		unicorn_prefer_module {
			return c.lint_unicorn_prefer_module(root, abs_path, mut stats)!
		}
		unicorn_prefer_reflect_apply {
			return c.lint_unicorn_prefer_reflect_apply(root, abs_path, mut stats)!
		}
		unicorn_prefer_export_from {
			return c.lint_unicorn_prefer_export_from(root, abs_path, mut stats)!
		}
		unicorn_relative_url_style {
			return c.lint_unicorn_relative_url_style(root, abs_path, mut stats)!
		}
		unicorn_prefer_prototype_methods {
			return c.lint_unicorn_prefer_prototype_methods(root, abs_path, mut stats)!
		}
		unicorn_better_regex {
			return c.lint_unicorn_better_regex(root, abs_path, mut stats)!
		}
		unicorn_no_this_assignment {
			return c.lint_unicorn_no_this_assignment(root, abs_path, mut stats)!
		}
		unicorn_no_unreadable_iife {
			return c.lint_unicorn_no_unreadable_iife(root, abs_path, mut stats)!
		}
		unicorn_no_accessor_recursion {
			return c.lint_unicorn_no_accessor_recursion(root, abs_path, mut stats)!
		}
		unicorn_no_static_only_class {
			return c.lint_unicorn_no_static_only_class(root, abs_path, mut stats)!
		}
		unicorn_prefer_class_fields {
			return c.lint_unicorn_prefer_class_fields(root, abs_path, mut stats)!
		}
		unicorn_consistent_function_scoping {
			return c.lint_unicorn_consistent_function_scoping(root, abs_path, mut stats)!
		}
		unicorn_isolated_functions {
			return c.lint_unicorn_isolated_functions(root, abs_path, mut stats)!
		}
		unicorn_no_useless_undefined {
			return c.lint_unicorn_no_useless_undefined(root, abs_path, mut stats)!
		}
		unicorn_no_keyword_prefix {
			return c.lint_unicorn_no_keyword_prefix(root, abs_path, mut stats)!
		}
		unicorn_prefer_object_from_entries {
			return c.lint_unicorn_prefer_object_from_entries(root, abs_path, mut stats)!
		}
		unicorn_prefer_default_parameters {
			return c.lint_unicorn_prefer_default_parameters(root, abs_path, mut stats)!
		}
		unicorn_no_unused_properties {
			return c.lint_unicorn_no_unused_properties(root, abs_path, mut stats)!
		}
		stylistic_array_bracket_spacing {
			return c.lint_stylistic_array_bracket_spacing(root, abs_path, mut stats)!
		}
		stylistic_rest_spread_spacing {
			return c.lint_stylistic_rest_spread_spacing(root, abs_path, mut stats)!
		}
		stylistic_semi_spacing {
			return c.lint_stylistic_semi_spacing(root, abs_path, mut stats)!
		}
		stylistic_space_in_parens {
			return c.lint_stylistic_space_in_parens(root, abs_path, mut stats)!
		}
		stylistic_switch_colon_spacing {
			return c.lint_stylistic_switch_colon_spacing(root, abs_path, mut stats)!
		}
		stylistic_template_curly_spacing {
			return c.lint_stylistic_template_curly_spacing(root, abs_path, mut stats)!
		}
		stylistic_template_tag_spacing {
			return c.lint_stylistic_template_tag_spacing(root, abs_path, mut stats)!
		}
		stylistic_no_whitespace_before_property {
			return c.lint_stylistic_no_whitespace_before_property(root, abs_path, mut stats)!
		}
		stylistic_block_spacing {
			return c.lint_stylistic_block_spacing(root, abs_path, mut stats)!
		}
		stylistic_comma_spacing {
			return c.lint_stylistic_comma_spacing(root, abs_path, mut stats)!
		}
		stylistic_computed_property_spacing {
			return c.lint_stylistic_computed_property_spacing(root, abs_path, mut stats)!
		}
		stylistic_object_curly_spacing {
			return c.lint_stylistic_object_curly_spacing(root, abs_path, mut stats)!
		}
		stylistic_keyword_spacing {
			return c.lint_stylistic_keyword_spacing(root, abs_path, mut stats)!
		}
		stylistic_space_before_blocks {
			return c.lint_stylistic_space_before_blocks(root, abs_path, mut stats)!
		}
		stylistic_arrow_spacing {
			return c.lint_stylistic_arrow_spacing(root, abs_path, mut stats)!
		}
		stylistic_yield_star_spacing {
			return c.lint_stylistic_yield_star_spacing(root, abs_path, mut stats)!
		}
		stylistic_type_annotation_spacing {
			return c.lint_stylistic_type_annotation_spacing(root, abs_path, mut stats)!
		}
		stylistic_type_generic_spacing {
			return c.lint_stylistic_type_generic_spacing(root, abs_path, mut stats)!
		}
		stylistic_type_named_tuple_spacing {
			return c.lint_stylistic_type_named_tuple_spacing(root, abs_path, mut stats)!
		}
		stylistic_space_before_function_paren {
			return c.lint_stylistic_space_before_function_paren(root, abs_path, mut stats)!
		}
		stylistic_key_spacing {
			return c.lint_stylistic_key_spacing(root, abs_path, mut stats)!
		}
		stylistic_space_infix_ops {
			return c.lint_stylistic_space_infix_ops(root, abs_path, mut stats)!
		}
		stylistic_space_unary_ops {
			return c.lint_stylistic_space_unary_ops(root, abs_path, mut stats)!
		}
		stylistic_function_call_spacing {
			return c.lint_stylistic_function_call_spacing(root, abs_path, mut stats)!
		}
		stylistic_brace_style {
			return c.lint_stylistic_brace_style(root, abs_path, mut stats)!
		}
		stylistic_comma_style {
			return c.lint_stylistic_comma_style(root, abs_path, mut stats)!
		}
		stylistic_dot_location {
			return c.lint_stylistic_dot_location(root, abs_path, mut stats)!
		}
		stylistic_function_call_argument_newline {
			return c.lint_stylistic_function_call_argument_newline(root, abs_path, mut stats)!
		}
		stylistic_function_paren_newline {
			return c.lint_stylistic_function_paren_newline(root, abs_path, mut stats)!
		}
		stylistic_implicit_arrow_linebreak {
			return c.lint_stylistic_implicit_arrow_linebreak(root, abs_path, mut stats)!
		}
		stylistic_multiline_ternary {
			return c.lint_stylistic_multiline_ternary(root, abs_path, mut stats)!
		}
		stylistic_nonblock_statement_body_position {
			return c.lint_stylistic_nonblock_statement_body_position(root, abs_path, mut stats)!
		}
		stylistic_one_var_declaration_per_line {
			return c.lint_stylistic_one_var_declaration_per_line(root, abs_path, mut stats)!
		}
		stylistic_quotes {
			return c.lint_stylistic_quotes(root, abs_path, mut stats)!
		}
		stylistic_no_multi_spaces {
			return c.lint_stylistic_no_multi_spaces(root, abs_path, mut stats)!
		}
		stylistic_no_trailing_spaces {
			return c.lint_stylistic_no_trailing_spaces(root, abs_path, mut stats)!
		}
		stylistic_no_mixed_spaces_and_tabs {
			return c.lint_stylistic_no_mixed_spaces_and_tabs(root, abs_path, mut stats)!
		}
		stylistic_eol_last {
			return c.lint_stylistic_eol_last(root, abs_path, mut stats)!
		}
		stylistic_spaced_comment {
			return c.lint_stylistic_spaced_comment(root, abs_path, mut stats)!
		}
		stylistic_lines_between_class_members {
			return c.lint_stylistic_lines_between_class_members(root, abs_path, mut stats)!
		}
		stylistic_new_parens {
			return c.lint_stylistic_new_parens(root, abs_path, mut stats)!
		}
		stylistic_no_floating_decimal {
			return c.lint_stylistic_no_floating_decimal(root, abs_path, mut stats)!
		}
		stylistic_no_extra_semi {
			return c.lint_stylistic_no_extra_semi(root, abs_path, mut stats)!
		}
		stylistic_semi_style {
			return c.lint_stylistic_semi_style(root, abs_path, mut stats)!
		}
		stylistic_semi {
			return c.lint_stylistic_semi(root, abs_path, mut stats)!
		}
		stylistic_object_curly_newline {
			return c.lint_stylistic_object_curly_newline(root, abs_path, mut stats)!
		}
		stylistic_object_property_newline {
			return c.lint_stylistic_object_property_newline(root, abs_path, mut stats)!
		}
		stylistic_list_style {
			return c.lint_stylistic_list_style(root, abs_path, mut stats)!
		}
		stylistic_exp_jsx_props_style {
			return c.lint_stylistic_exp_jsx_props_style(root, abs_path, mut stats)!
		}
		stylistic_arrow_parens {
			return c.lint_stylistic_arrow_parens(root, abs_path, mut stats)!
		}
		stylistic_comma_dangle {
			return c.lint_stylistic_comma_dangle(root, abs_path, mut stats)!
		}
		stylistic_member_delimiter_style {
			return c.lint_stylistic_member_delimiter_style(root, abs_path, mut stats)!
		}
		stylistic_quote_props {
			return c.lint_stylistic_quote_props(root, abs_path, mut stats)!
		}
		stylistic_no_extra_parens {
			return c.lint_stylistic_no_extra_parens(root, abs_path, mut stats)!
		}
		marcrock_no_newline_if_body_class_empty {
			return c.lint_marcrock_no_newline_if_body_class_empty(root, abs_path, mut stats)!
		}
		marcrock_numeric_separators {
			return c.lint_marcrock_numeric_separators(root, abs_path, mut stats)!
		}
		marcrock_uppercase_first_class_letter {
			return c.lint_marcrock_uppercase_first_class_letter(root, abs_path, mut stats)!
		}
		marcrock_prefer_at {
			return c.lint_marcrock_prefer_at(root, abs_path, mut stats)!
		}
		perfectionist_sort_array_includes {
			return c.lint_perfectionist_sort_array_includes(root, abs_path, mut stats)!
		}
		perfectionist_sort_sets {
			return c.lint_perfectionist_sort_sets(root, abs_path, mut stats)!
		}
		perfectionist_sort_maps {
			return c.lint_perfectionist_sort_maps(root, abs_path, mut stats)!
		}
		perfectionist_sort_union_types {
			return c.lint_perfectionist_sort_union_types(root, abs_path, mut stats)!
		}
		perfectionist_sort_intersection_types {
			return c.lint_perfectionist_sort_intersection_types(root, abs_path, mut stats)!
		}
		ban_ts_comment {
			return c.lint_ban_ts_comment(root, abs_path, mut stats)!
		}
		ban_tslint_comment {
			return c.lint_ban_tslint_comment(root, abs_path, mut stats)!
		}
		default_param_last {
			return c.lint_default_param_last(root, abs_path, mut stats)!
		}
		init_declarations {
			return c.lint_init_declarations(root, abs_path, mut stats)!
		}
		max_params {
			return c.lint_max_params(root, abs_path, mut stats)!
		}
		method_signature_style {
			return c.lint_method_signature_style(root, abs_path, mut stats)!
		}
		no_empty_object_type {
			return c.lint_no_empty_object_type(root, abs_path, mut stats)!
		}
		no_non_null_assertion {
			return c.lint_no_non_null_assertion(root, abs_path, mut stats)!
		}
		ts_no_invalid_this {
			return c.lint_ts_no_invalid_this(root, abs_path, mut stats)!
		}
		no_redeclare {
			return c.lint_no_redeclare(root, abs_path, mut stats)!
		}
		perfectionist_sort_heritage_clauses {
			return c.lint_perfectionist_sort_heritage_clauses(root, abs_path, mut stats)!
		}
		perfectionist_sort_import_attributes {
			return c.lint_perfectionist_sort_import_attributes(root, abs_path, mut stats)!
		}
		perfectionist_sort_export_attributes {
			return c.lint_perfectionist_sort_export_attributes(root, abs_path, mut stats)!
		}
		perfectionist_sort_switch_case {
			return c.lint_perfectionist_sort_switch_case(root, abs_path, mut stats)!
		}
		perfectionist_sort_named_imports {
			return c.lint_perfectionist_sort_named_imports(root, abs_path, mut stats)!
		}
		perfectionist_sort_named_exports {
			return c.lint_perfectionist_sort_named_exports(root, abs_path, mut stats)!
		}
		perfectionist_sort_exports {
			return c.lint_perfectionist_sort_exports(root, abs_path, mut stats)!
		}
		explicit_function_return_type {
			return c.lint_explicit_function_return_type(root, abs_path, mut stats)!
		}
		explicit_module_boundary_types {
			return c.lint_explicit_module_boundary_types(root, abs_path, mut stats)!
		}
		explicit_member_accessibility {
			return c.lint_explicit_member_accessibility(root, abs_path, mut stats)!
		}
		parameter_properties {
			return c.lint_parameter_properties(root, abs_path, mut stats)!
		}
		prefer_literal_enum_member {
			return c.lint_prefer_literal_enum_member(root, abs_path, mut stats)!
		}
		no_magic_numbers {
			return c.lint_no_magic_numbers(root, abs_path, mut stats)!
		}
		no_restricted_types {
			return c.lint_no_restricted_types(root, abs_path, mut stats)!
		}
		no_generated_empty_object_type {
			return c.lint_no_generated_empty_object_type(root, abs_path, mut stats)!
		}
		no_unsafe_enum_assignment {
			return c.lint_no_unsafe_enum_assignment(root, abs_path, mut stats)!
		}
		member_ordering {
			return c.lint_member_ordering(root, abs_path, mut stats)!
		}
		perfectionist_sort_classes {
			return c.lint_perfectionist_sort_classes(root, abs_path, mut stats)!
		}
		perfectionist_sort_imports {
			return c.lint_perfectionist_sort_imports(root, abs_path, mut stats)!
		}
		vue_no_v_html {
			return c.lint_vue_no_v_html(root, abs_path, mut stats)!
		}
		vue_no_v_text {
			return c.lint_vue_no_v_text(root, abs_path, mut stats)!
		}
		vue_no_duplicate_attributes {
			return c.lint_vue_no_duplicate_attributes(root, abs_path, mut stats)!
		}
		vue_comment_directive {
			return c.lint_vue_comment_directive(root, abs_path, mut stats)!
		}
		vue_no_parsing_error {
			return c.lint_vue_no_parsing_error(root, abs_path, mut stats)!
		}
		vue_no_deprecated_v_is {
			return c.lint_vue_no_deprecated_v_is(root, abs_path, mut stats)!
		}
		vue_no_deprecated_scope_attribute {
			return c.lint_vue_no_deprecated_scope_attribute(root, abs_path, mut stats)!
		}
		vue_no_deprecated_filter {
			return c.lint_vue_no_deprecated_filter(root, abs_path, mut stats)!
		}
		vue_no_deprecated_inline_template {
			return c.lint_vue_no_deprecated_inline_template(root, abs_path, mut stats)!
		}
		vue_require_component_is {
			return c.lint_vue_require_component_is(root, abs_path, mut stats)!
		}
		vue_no_deprecated_v_on_native_modifier {
			return c.lint_vue_no_deprecated_v_on_native_modifier(root, abs_path, mut stats)!
		}
		vue_no_v_model_argument {
			return c.lint_vue_no_v_model_argument(root, abs_path, mut stats)!
		}
		vue_no_textarea_mustache {
			return c.lint_vue_no_textarea_mustache(root, abs_path, mut stats)!
		}
		vue_no_use_v_else_with_v_for {
			return c.lint_vue_no_use_v_else_with_v_for(root, abs_path, mut stats)!
		}
		vue_no_v_for_template_key {
			return c.lint_vue_no_v_for_template_key(root, abs_path, mut stats)!
		}
		vue_no_template_key {
			return c.lint_vue_no_template_key(root, abs_path, mut stats)!
		}
		vue_no_custom_modifiers_on_v_model {
			return c.lint_vue_no_custom_modifiers_on_v_model(root, abs_path, mut stats)!
		}
		vue_no_deprecated_v_bind_sync {
			return c.lint_vue_no_deprecated_v_bind_sync(root, abs_path, mut stats)!
		}
		vue_no_spaces_around_equal_signs_in_attribute {
			return c.lint_vue_no_spaces_around_equal_signs_in_attribute(root, abs_path, mut stats)!
		}
		vue_no_deprecated_v_on_number_modifiers {
			return c.lint_vue_no_deprecated_v_on_number_modifiers(root, abs_path, mut stats)!
		}
		vue_valid_v_bind {
			return c.lint_vue_valid_v_bind(root, abs_path, mut stats)!
		}
		vue_valid_v_cloak {
			return c.lint_vue_valid_v_cloak(root, abs_path, mut stats)!
		}
		vue_valid_v_html {
			return c.lint_vue_valid_v_html(root, abs_path, mut stats)!
		}
		vue_valid_v_once {
			return c.lint_vue_valid_v_once(root, abs_path, mut stats)!
		}
		vue_valid_v_pre {
			return c.lint_vue_valid_v_pre(root, abs_path, mut stats)!
		}
		vue_valid_v_text {
			return c.lint_vue_valid_v_text(root, abs_path, mut stats)!
		}
		vue_valid_v_show {
			return c.lint_vue_valid_v_show(root, abs_path, mut stats)!
		}
		vue_valid_v_if {
			return c.lint_vue_valid_v_if(root, abs_path, mut stats)!
		}
		vue_valid_v_else_if {
			return c.lint_vue_valid_v_else_if(root, abs_path, mut stats)!
		}
		vue_valid_v_else {
			return c.lint_vue_valid_v_else(root, abs_path, mut stats)!
		}
		vue_valid_v_is {
			return c.lint_vue_valid_v_is(root, abs_path, mut stats)!
		}
		vue_valid_v_on {
			return c.lint_vue_valid_v_on(root, abs_path, mut stats)!
		}
		vue_v_on_style {
			return c.lint_vue_v_on_style(root, abs_path, mut stats)!
		}
		vue_v_bind_style {
			return c.lint_vue_v_bind_style(root, abs_path, mut stats)!
		}
		vue_no_multiple_objects_in_class {
			return c.lint_vue_no_multiple_objects_in_class(root, abs_path, mut stats)!
		}
		vue_require_v_for_key {
			return c.lint_vue_require_v_for_key(root, abs_path, mut stats)!
		}
		vue_no_deprecated_html_element_is {
			return c.lint_vue_no_deprecated_html_element_is(root, abs_path, mut stats)!
		}
		vue_no_use_v_if_with_v_for {
			return c.lint_vue_no_use_v_if_with_v_for(root, abs_path, mut stats)!
		}
		vue_no_v_for_template_key_on_child {
			return c.lint_vue_no_v_for_template_key_on_child(root, abs_path, mut stats)!
		}
		vue_html_end_tags {
			return c.lint_vue_html_end_tags(root, abs_path, mut stats)!
		}
		vue_valid_attribute_name {
			return c.lint_vue_valid_attribute_name(root, abs_path, mut stats)!
		}
		vue_v_for_delimiter_style {
			return c.lint_vue_v_for_delimiter_style(root, abs_path, mut stats)!
		}
		vue_no_v_text_v_html_on_component {
			return c.lint_vue_no_v_text_v_html_on_component(root, abs_path, mut stats)!
		}
		vue_no_lone_template {
			return c.lint_vue_no_lone_template(root, abs_path, mut stats)!
		}
		vue_html_button_has_type {
			return c.lint_vue_html_button_has_type(root, abs_path, mut stats)!
		}
		vue_no_deprecated_router_link_tag_prop {
			return c.lint_vue_no_deprecated_router_link_tag_prop(root, abs_path, mut stats)!
		}
		vue_no_restricted_html_elements {
			return c.lint_vue_no_restricted_html_elements(root, abs_path, mut stats)!
		}
		vue_no_useless_template_attributes {
			return c.lint_vue_no_useless_template_attributes(root, abs_path, mut stats)!
		}
		vue_mustache_interpolation_spacing {
			return c.lint_vue_mustache_interpolation_spacing(root, abs_path, mut stats)!
		}
		vue_static_class_names_order {
			return c.lint_vue_static_class_names_order(root, abs_path, mut stats)!
		}
		vue_restricted_component_names {
			return c.lint_vue_restricted_component_names(root, abs_path, mut stats)!
		}
		vue_slot_name_casing {
			return c.lint_vue_slot_name_casing(root, abs_path, mut stats)!
		}
		vue_first_attribute_linebreak {
			return c.lint_vue_first_attribute_linebreak(root, abs_path, mut stats)!
		}
		vue_html_quotes {
			return c.lint_vue_html_quotes(root, abs_path, mut stats)!
		}
		vue_no_literals_in_template {
			return c.lint_vue_no_literals_in_template(root, abs_path, mut stats)!
		}
		vue_require_toggle_inside_transition {
			return c.lint_vue_require_toggle_inside_transition(root, abs_path, mut stats)!
		}
		vue_no_restricted_static_attribute {
			return c.lint_vue_no_restricted_static_attribute(root, abs_path, mut stats)!
		}
		vue_html_closing_bracket_spacing {
			return c.lint_vue_html_closing_bracket_spacing(root, abs_path, mut stats)!
		}
		vue_html_closing_bracket_newline {
			return c.lint_vue_html_closing_bracket_newline(root, abs_path, mut stats)!
		}
		vue_attribute_hyphenation {
			return c.lint_vue_attribute_hyphenation(root, abs_path, mut stats)!
		}
		vue_v_on_event_hyphenation {
			return c.lint_vue_v_on_event_hyphenation(root, abs_path, mut stats)!
		}
		vue_valid_v_memo {
			return c.lint_vue_valid_v_memo(root, abs_path, mut stats)!
		}
		vue_no_static_inline_styles {
			return c.lint_vue_no_static_inline_styles(root, abs_path, mut stats)!
		}
		vue_no_child_content {
			return c.lint_vue_no_child_content(root, abs_path, mut stats)!
		}
		vue_no_template_target_blank {
			return c.lint_vue_no_template_target_blank(root, abs_path, mut stats)!
		}
		vue_no_restricted_class {
			return c.lint_vue_no_restricted_class(root, abs_path, mut stats)!
		}
		vue_no_useless_v_bind {
			return c.lint_vue_no_useless_v_bind(root, abs_path, mut stats)!
		}
		vue_no_restricted_v_bind {
			return c.lint_vue_no_restricted_v_bind(root, abs_path, mut stats)!
		}
		vue_no_restricted_v_on {
			return c.lint_vue_no_restricted_v_on(root, abs_path, mut stats)!
		}
		vue_valid_v_bind_sync {
			return c.lint_vue_valid_v_bind_sync(root, abs_path, mut stats)!
		}
		vue_v_slot_style {
			return c.lint_vue_v_slot_style(root, abs_path, mut stats)!
		}
		vue_prefer_true_attribute_shorthand {
			return c.lint_vue_prefer_true_attribute_shorthand(root, abs_path, mut stats)!
		}
		vue_no_dupe_v_else_if {
			return c.lint_vue_no_dupe_v_else_if(root, abs_path, mut stats)!
		}
		vue_no_deprecated_slot_attribute {
			return c.lint_vue_no_deprecated_slot_attribute(root, abs_path, mut stats)!
		}
		vue_no_deprecated_slot_scope_attribute {
			return c.lint_vue_no_deprecated_slot_scope_attribute(root, abs_path, mut stats)!
		}
		vue_this_in_template {
			return c.lint_vue_this_in_template(root, abs_path, mut stats)!
		}
		vue_no_unused_vars {
			return c.lint_vue_no_unused_vars(root, abs_path, mut stats)!
		}
		vue_no_define_model_default {
			return c.lint_vue_no_define_model_default(root, abs_path, mut stats)!
		}
		vue_no_deprecated_functional_template {
			return c.lint_vue_no_deprecated_functional_template(root, abs_path, mut stats)!
		}
		vue_require_render_return {
			return c.lint_vue_require_render_return(root, abs_path, mut stats)!
		}
		vue_no_deprecated_vue_config_keycodes {
			return c.lint_vue_no_deprecated_vue_config_keycodes(root, abs_path, mut stats)!
		}
		vue_no_root_v_if {
			return c.lint_vue_no_root_v_if(root, abs_path, mut stats)!
		}
		vue_no_arrow_functions_in_watch {
			return c.lint_vue_no_arrow_functions_in_watch(root, abs_path, mut stats)!
		}
		vue_one_component_per_file {
			return c.lint_vue_one_component_per_file(root, abs_path, mut stats)!
		}
		vue_valid_model_definition {
			return c.lint_vue_valid_model_definition(root, abs_path, mut stats)!
		}
		vue_no_deprecated_events_api {
			return c.lint_vue_no_deprecated_events_api(root, abs_path, mut stats)!
		}
		vue_define_props_declaration {
			return c.lint_vue_define_props_declaration(root, abs_path, mut stats)!
		}
		vue_valid_template_root {
			return c.lint_vue_valid_template_root(root, abs_path, mut stats)!
		}
		vue_no_export_in_script_setup {
			return c.lint_vue_no_export_in_script_setup(root, abs_path, mut stats)!
		}
		vue_require_default_export {
			return c.lint_vue_require_default_export(root, abs_path, mut stats)!
		}
		vue_jsx_uses_vars {
			return c.lint_vue_jsx_uses_vars(root, abs_path, mut stats)!
		}
		vue_match_component_import_name {
			return c.lint_vue_match_component_import_name(root, abs_path, mut stats)!
		}
		vue_no_deprecated_destroyed_lifecycle {
			return c.lint_vue_no_deprecated_destroyed_lifecycle(root, abs_path, mut stats)!
		}
		vue_max_template_depth {
			return c.lint_vue_max_template_depth(root, abs_path, mut stats)!
		}
		vue_no_reserved_props {
			return c.lint_vue_no_reserved_props(root, abs_path, mut stats)!
		}
		vue_no_this_in_before_route_enter {
			return c.lint_vue_no_this_in_before_route_enter(root, abs_path, mut stats)!
		}
		vue_max_props {
			return c.lint_vue_max_props(root, abs_path, mut stats)!
		}
		vue_no_content_outside_block {
			return c.lint_vue_no_content_outside_block(root, abs_path, mut stats)!
		}
		vue_no_shared_component_data {
			return c.lint_vue_no_shared_component_data(root, abs_path, mut stats)!
		}
		vue_no_deprecated_data_object_declaration {
			return c.lint_vue_no_deprecated_data_object_declaration(root, abs_path, mut stats)!
		}
		vue_prop_name_casing {
			return c.lint_vue_prop_name_casing(root, abs_path, mut stats)!
		}
		vue_define_props_destructuring {
			return c.lint_vue_define_props_destructuring(root, abs_path, mut stats)!
		}
		vue_component_definition_name_casing {
			return c.lint_vue_component_definition_name_casing(root, abs_path, mut stats)!
		}
		vue_require_emit_validator {
			return c.lint_vue_require_emit_validator(root, abs_path, mut stats)!
		}
		vue_no_computed_properties_in_data {
			return c.lint_vue_no_computed_properties_in_data(root, abs_path, mut stats)!
		}
		vue_no_empty_component_block {
			return c.lint_vue_no_empty_component_block(root, abs_path, mut stats)!
		}
		vue_no_import_compiler_macros {
			return c.lint_vue_no_import_compiler_macros(root, abs_path, mut stats)!
		}
		vue_prefer_prop_type_boolean_first {
			return c.lint_vue_prefer_prop_type_boolean_first(root, abs_path, mut stats)!
		}
		vue_require_macro_variable_name {
			return c.lint_vue_require_macro_variable_name(root, abs_path, mut stats)!
		}
		vue_define_emits_declaration {
			return c.lint_vue_define_emits_declaration(root, abs_path, mut stats)!
		}
		vue_no_props_shadow {
			return c.lint_vue_no_props_shadow(root, abs_path, mut stats)!
		}
		vue_require_prop_type_constructor {
			return c.lint_vue_require_prop_type_constructor(root, abs_path, mut stats)!
		}
		vue_no_restricted_block {
			return c.lint_vue_no_restricted_block(root, abs_path, mut stats)!
		}
		vue_component_options_name_casing {
			return c.lint_vue_component_options_name_casing(root, abs_path, mut stats)!
		}
		vue_max_lines_per_block {
			return c.lint_vue_max_lines_per_block(root, abs_path, mut stats)!
		}
		vue_no_multiple_slot_args {
			return c.lint_vue_no_multiple_slot_args(root, abs_path, mut stats)!
		}
		vue_no_reserved_keys {
			return c.lint_vue_no_reserved_keys(root, abs_path, mut stats)!
		}
		vue_no_deprecated_delete_set {
			return c.lint_vue_no_deprecated_delete_set(root, abs_path, mut stats)!
		}
		vue_require_prop_types {
			return c.lint_vue_require_prop_types(root, abs_path, mut stats)!
		}
		vue_return_in_computed_property {
			return c.lint_vue_return_in_computed_property(root, abs_path, mut stats)!
		}
		vue_no_deprecated_props_default_this {
			return c.lint_vue_no_deprecated_props_default_this(root, abs_path, mut stats)!
		}
		vue_require_slots_as_functions {
			return c.lint_vue_require_slots_as_functions(root, abs_path, mut stats)!
		}
		vue_require_name_property {
			return c.lint_vue_require_name_property(root, abs_path, mut stats)!
		}
		vue_arrow_spacing, vue_camelcase, vue_comma_dangle, vue_dot_location, vue_no_empty_pattern,
		vue_no_sparse_arrays, vue_operator_linebreak, vue_array_bracket_newline,
		vue_array_bracket_spacing, vue_array_element_newline, vue_block_spacing, vue_brace_style,
		vue_dot_notation, vue_eqeqeq, vue_key_spacing, vue_keyword_spacing,
		vue_no_restricted_syntax, vue_no_useless_concat, vue_object_curly_newline,
		vue_object_curly_spacing, vue_object_property_newline, vue_prefer_template,
		vue_no_implicit_coercion, vue_no_loss_of_precision, vue_no_negated_condition,
		vue_object_shorthand, vue_space_infix_ops, vue_space_unary_ops, vue_template_curly_spacing,
		vue_comma_spacing, vue_multiline_ternary, vue_space_in_parens, vue_func_call_spacing,
		vue_comma_style, vue_no_constant_condition, vue_no_console, vue_quote_props,
		vue_no_extra_parens {
			return c.lint_vue_wrap(rule, root, abs_path, mut stats)!
		}
		vue_max_attributes_per_line {
			return c.lint_vue_max_attributes_per_line(root, abs_path, mut stats)!
		}
		vue_no_useless_mustaches {
			return c.lint_vue_no_useless_mustaches(root, abs_path, mut stats)!
		}
		vue_no_negated_v_if_condition {
			return c.lint_vue_no_negated_v_if_condition(root, abs_path, mut stats)!
		}
		vue_use_v_on_exact {
			return c.lint_vue_use_v_on_exact(root, abs_path, mut stats)!
		}
		vue_prefer_v_model {
			return c.lint_vue_prefer_v_model(root, abs_path, mut stats)!
		}
		vue_singleline_html_element_content_newline {
			return c.lint_vue_singleline_html_element_content_newline(root, abs_path, mut stats)!
		}
		vue_multiline_html_element_content_newline {
			return c.lint_vue_multiline_html_element_content_newline(root, abs_path, mut stats)!
		}
		vue_html_self_closing {
			return c.lint_vue_html_self_closing(root, abs_path, mut stats)!
		}
		vue_padding_line_between_blocks {
			return c.lint_vue_padding_line_between_blocks(root, abs_path, mut stats)!
		}
		vue_padding_line_between_tags {
			return c.lint_vue_padding_line_between_tags(root, abs_path, mut stats)!
		}
		vue_block_tag_newline {
			return c.lint_vue_block_tag_newline(root, abs_path, mut stats)!
		}
		vue_block_lang {
			return c.lint_vue_block_lang(root, abs_path, mut stats)!
		}
		vue_no_bare_strings_in_template {
			return c.lint_vue_no_bare_strings_in_template(root, abs_path, mut stats)!
		}
		vue_v_if_else_key {
			return c.lint_vue_v_if_else_key(root, abs_path, mut stats)!
		}
		vue_no_irregular_whitespace {
			return c.lint_vue_no_irregular_whitespace(root, abs_path, mut stats)!
		}
		vue_valid_v_for {
			return c.lint_vue_valid_v_for(root, abs_path, mut stats)!
		}
		vue_valid_v_model {
			return c.lint_vue_valid_v_model(root, abs_path, mut stats)!
		}
		vue_valid_v_slot {
			return c.lint_vue_valid_v_slot(root, abs_path, mut stats)!
		}
		vue_no_unsupported_features {
			return c.lint_vue_no_unsupported_features(root, abs_path, mut stats)!
		}
		vue_prefer_separate_static_class {
			return c.lint_vue_prefer_separate_static_class(root, abs_path, mut stats)!
		}
		vue_no_duplicate_class_names {
			return c.lint_vue_no_duplicate_class_names(root, abs_path, mut stats)!
		}
		vue_max_len {
			return c.lint_vue_max_len(root, abs_path, mut stats)!
		}
		vue_attributes_order {
			return c.lint_vue_attributes_order(root, abs_path, mut stats)!
		}
		vue_no_deprecated_dollar_listeners_api {
			return c.lint_vue_no_deprecated_dollar_listeners_api(root, abs_path, mut stats)!
		}
		vue_no_deprecated_dollar_scopedslots_api {
			return c.lint_vue_no_deprecated_dollar_scopedslots_api(root, abs_path, mut stats)!
		}
		vue_prefer_use_template_ref {
			return c.lint_vue_prefer_use_template_ref(root, abs_path, mut stats)!
		}
		vue_no_duplicate_attr_inheritance {
			return c.lint_vue_no_duplicate_attr_inheritance(root, abs_path, mut stats)!
		}
		vue_no_unused_components {
			return c.lint_vue_no_unused_components(root, abs_path, mut stats)!
		}
		vue_no_template_shadow {
			return c.lint_vue_no_template_shadow(root, abs_path, mut stats)!
		}
		vue_require_explicit_slots {
			return c.lint_vue_require_explicit_slots(root, abs_path, mut stats)!
		}
		vue_no_undef_directives {
			return c.lint_vue_no_undef_directives(root, abs_path, mut stats)!
		}
		vue_component_name_in_template_casing {
			return c.lint_vue_component_name_in_template_casing(root, abs_path, mut stats)!
		}
		vue_no_unused_refs {
			return c.lint_vue_no_unused_refs(root, abs_path, mut stats)!
		}
		vue_custom_event_name_casing {
			return c.lint_vue_custom_event_name_casing(root, abs_path, mut stats)!
		}
		vue_no_restricted_custom_event {
			return c.lint_vue_no_restricted_custom_event(root, abs_path, mut stats)!
		}
		vue_no_unused_emit_declarations {
			return c.lint_vue_no_unused_emit_declarations(root, abs_path, mut stats)!
		}
		vue_prefer_single_event_payload {
			return c.lint_vue_prefer_single_event_payload(root, abs_path, mut stats)!
		}
		vue_no_shadow_native_events {
			return c.lint_vue_no_shadow_native_events(root, abs_path, mut stats)!
		}
		vue_require_explicit_emits {
			return c.lint_vue_require_explicit_emits(root, abs_path, mut stats)!
		}
		vue_no_undef_components {
			return c.lint_vue_no_undef_components(root, abs_path, mut stats)!
		}
		vue_v_on_handler_style {
			return c.lint_vue_v_on_handler_style(root, abs_path, mut stats)!
		}
		vue_no_mutating_props {
			return c.lint_vue_no_mutating_props(root, abs_path, mut stats)!
		}
		vue_no_use_computed_property_like_method {
			return c.lint_vue_no_use_computed_property_like_method(root, abs_path, mut stats)!
		}
		vue_no_unused_properties {
			return c.lint_vue_no_unused_properties(root, abs_path, mut stats)!
		}
		vue_no_undef_properties {
			return c.lint_vue_no_undef_properties(root, abs_path, mut stats)!
		}
		vue_prefer_define_options {
			return c.lint_vue_prefer_define_options(root, abs_path, mut stats)!
		}
		vue_multi_word_component_names {
			return c.lint_vue_multi_word_component_names(root, abs_path, mut stats)!
		}
		vue_no_multiple_template_root {
			return c.lint_vue_no_multiple_template_root(root, abs_path, mut stats)!
		}
		vue_no_potential_component_option_typo {
			return c.lint_vue_no_potential_component_option_typo(root, abs_path, mut stats)!
		}
		vue_no_deprecated_model_definition {
			return c.lint_vue_no_deprecated_model_definition(root, abs_path, mut stats)!
		}
		vue_match_component_file_name {
			return c.lint_vue_match_component_file_name(root, abs_path, mut stats)!
		}
		vue_enforce_style_attribute {
			return c.lint_vue_enforce_style_attribute(root, abs_path, mut stats)!
		}
		vue_require_direct_export {
			return c.lint_vue_require_direct_export(root, abs_path, mut stats)!
		}
		vue_no_restricted_component_names {
			return c.lint_vue_no_restricted_component_names(root, abs_path, mut stats)!
		}
		vue_no_restricted_component_options {
			return c.lint_vue_no_restricted_component_options(root, abs_path, mut stats)!
		}
		vue_prefer_import_from_vue {
			return c.lint_vue_prefer_import_from_vue(root, abs_path, mut stats)!
		}
		vue_new_line_between_multi_line_property {
			return c.lint_vue_new_line_between_multi_line_property(root, abs_path, mut stats)!
		}
		vue_component_api_style {
			return c.lint_vue_component_api_style(root, abs_path, mut stats)!
		}
		vue_no_reserved_component_names {
			return c.lint_vue_no_reserved_component_names(root, abs_path, mut stats)!
		}
		vue_require_typed_object_prop {
			return c.lint_vue_require_typed_object_prop(root, abs_path, mut stats)!
		}
		vue_return_in_emits_validator {
			return c.lint_vue_return_in_emits_validator(root, abs_path, mut stats)!
		}
		vue_valid_define_props {
			return c.lint_vue_valid_define_props(root, abs_path, mut stats)!
		}
		vue_valid_define_emits {
			return c.lint_vue_valid_define_emits(root, abs_path, mut stats)!
		}
		vue_valid_define_options {
			return c.lint_vue_valid_define_options(root, abs_path, mut stats)!
		}
		vue_require_prop_comment {
			return c.lint_vue_require_prop_comment(root, abs_path, mut stats)!
		}
		vue_define_macros_order {
			return c.lint_vue_define_macros_order(root, abs_path, mut stats)!
		}
		vue_order_in_components {
			return c.lint_vue_order_in_components(root, abs_path, mut stats)!
		}
		vue_padding_lines_in_component_definition {
			return c.lint_vue_padding_lines_in_component_definition(root, abs_path, mut stats)!
		}
		vue_sort_keys {
			return c.lint_vue_sort_keys(root, abs_path, mut stats)!
		}
		vue_html_comment_content_spacing {
			return c.lint_vue_html_comment_content_spacing(root, abs_path, mut stats)!
		}
		vue_html_comment_content_newline {
			return c.lint_vue_html_comment_content_newline(root, abs_path, mut stats)!
		}
		vue_html_comment_indent {
			return c.lint_vue_html_comment_indent(root, abs_path, mut stats)!
		}
		vue_no_multi_spaces {
			return c.lint_vue_no_multi_spaces(root, abs_path, mut stats)!
		}
		vue_block_order {
			return c.lint_vue_block_order(root, abs_path, mut stats)!
		}
		vue_no_lifecycle_after_await {
			return c.lint_vue_no_lifecycle_after_await(root, abs_path, mut stats)!
		}
		vue_no_watch_after_await {
			return c.lint_vue_no_watch_after_await(root, abs_path, mut stats)!
		}
		vue_no_expose_after_await {
			return c.lint_vue_no_expose_after_await(root, abs_path, mut stats)!
		}
		vue_no_restricted_call_after_await {
			return c.lint_vue_no_restricted_call_after_await(root, abs_path, mut stats)!
		}
		vue_next_tick_style {
			return c.lint_vue_next_tick_style(root, abs_path, mut stats)!
		}
		vue_valid_next_tick {
			return c.lint_vue_valid_next_tick(root, abs_path, mut stats)!
		}
		vue_no_boolean_default {
			return c.lint_vue_no_boolean_default(root, abs_path, mut stats)!
		}
		vue_no_required_prop_with_default {
			return c.lint_vue_no_required_prop_with_default(root, abs_path, mut stats)!
		}
		vue_require_default_prop {
			return c.lint_vue_require_default_prop(root, abs_path, mut stats)!
		}
		vue_require_valid_default_prop {
			return c.lint_vue_require_valid_default_prop(root, abs_path, mut stats)!
		}
		vue_no_restricted_props {
			return c.lint_vue_no_restricted_props(root, abs_path, mut stats)!
		}
		vue_require_typed_ref {
			return c.lint_vue_require_typed_ref(root, abs_path, mut stats)!
		}
		vue_no_ref_as_operand {
			return c.lint_vue_no_ref_as_operand(root, abs_path, mut stats)!
		}
		vue_no_ref_object_reactivity_loss {
			return c.lint_vue_no_ref_object_reactivity_loss(root, abs_path, mut stats)!
		}
		vue_no_setup_props_reactivity_loss {
			return c.lint_vue_no_setup_props_reactivity_loss(root, abs_path, mut stats)!
		}
		vue_require_expose {
			return c.lint_vue_require_expose(root, abs_path, mut stats)!
		}
		vue_no_side_effects_in_computed_properties {
			return c.lint_vue_no_side_effects_in_computed_properties(root, abs_path, mut stats)!
		}
		vue_no_async_in_computed_properties {
			return c.lint_vue_no_async_in_computed_properties(root, abs_path, mut stats)!
		}
		vue_no_dupe_keys {
			return c.lint_vue_no_dupe_keys(root, abs_path, mut stats)!
		}
		svelte_comment_directive {
			return c.lint_svelte_comment_directive(root, abs_path, mut stats)!
		}
		svelte_system {
			return c.lint_svelte_system(root, abs_path, mut stats)!
		}
		svelte_no_at_html_tags {
			return c.lint_svelte_no_at_html_tags(root, abs_path, mut stats)!
		}
		svelte_no_at_debug_tags {
			return c.lint_svelte_no_at_debug_tags(root, abs_path, mut stats)!
		}
		svelte_button_has_type {
			return c.lint_svelte_button_has_type(root, abs_path, mut stats)!
		}
		svelte_no_target_blank {
			return c.lint_svelte_no_target_blank(root, abs_path, mut stats)!
		}
		svelte_require_each_key {
			return c.lint_svelte_require_each_key(root, abs_path, mut stats)!
		}
		svelte_valid_each_key {
			return c.lint_svelte_valid_each_key(root, abs_path, mut stats)!
		}
		svelte_no_object_in_text_mustaches {
			return c.lint_svelte_no_object_in_text_mustaches(root, abs_path, mut stats)!
		}
		svelte_shorthand_attribute {
			return c.lint_svelte_shorthand_attribute(root, abs_path, mut stats)!
		}
		svelte_no_spaces_around_equal_signs_in_attribute {
			return c.lint_svelte_no_spaces_around_equal_signs_in_attribute(root, abs_path, mut stats)!
		}
		svelte_spaced_html_comment {
			return c.lint_svelte_spaced_html_comment(root, abs_path, mut stats)!
		}
		svelte_no_dupe_else_if_blocks {
			return c.lint_svelte_no_dupe_else_if_blocks(root, abs_path, mut stats)!
		}
		svelte_no_useless_mustaches {
			return c.lint_svelte_no_useless_mustaches(root, abs_path, mut stats)!
		}
		svelte_first_attribute_linebreak {
			return c.lint_svelte_first_attribute_linebreak(root, abs_path, mut stats)!
		}
		svelte_shorthand_directive {
			return c.lint_svelte_shorthand_directive(root, abs_path, mut stats)!
		}
		svelte_html_closing_bracket_spacing {
			return c.lint_svelte_html_closing_bracket_spacing(root, abs_path, mut stats)!
		}
		svelte_html_closing_bracket_new_line {
			return c.lint_svelte_html_closing_bracket_new_line(root, abs_path, mut stats)!
		}
		svelte_no_dynamic_slot_name {
			return c.lint_svelte_no_dynamic_slot_name(root, abs_path, mut stats)!
		}
		svelte_html_quotes {
			return c.lint_svelte_html_quotes(root, abs_path, mut stats)!
		}
		svelte_mustache_spacing {
			return c.lint_svelte_mustache_spacing(root, abs_path, mut stats)!
		}
		svelte_no_inline_styles {
			return c.lint_svelte_no_inline_styles(root, abs_path, mut stats)!
		}
		svelte_no_raw_special_elements {
			return c.lint_svelte_no_raw_special_elements(root, abs_path, mut stats)!
		}
		svelte_no_nested_style_tag {
			return c.lint_svelte_no_nested_style_tag(root, abs_path, mut stats)!
		}
		svelte_no_useless_children_snippet {
			return c.lint_svelte_no_useless_children_snippet(root, abs_path, mut stats)!
		}
		svelte_no_dupe_on_directives {
			return c.lint_svelte_no_dupe_on_directives(root, abs_path, mut stats)!
		}
		svelte_no_dupe_use_directives {
			return c.lint_svelte_no_dupe_use_directives(root, abs_path, mut stats)!
		}
		svelte_prefer_attribute_interpolation {
			return c.lint_svelte_prefer_attribute_interpolation(root, abs_path, mut stats)!
		}
		svelte_max_attributes_per_line {
			return c.lint_svelte_max_attributes_per_line(root, abs_path, mut stats)!
		}
		svelte_html_self_closing {
			return c.lint_svelte_html_self_closing(root, abs_path, mut stats)!
		}
		svelte_no_at_const_tags {
			return c.lint_svelte_no_at_const_tags(root, abs_path, mut stats)!
		}
		svelte_no_not_function_handler {
			return c.lint_svelte_no_not_function_handler(root, abs_path, mut stats)!
		}
		svelte_block_lang {
			return c.lint_svelte_block_lang(root, abs_path, mut stats)!
		}
		svelte_prefer_class_directive {
			return c.lint_svelte_prefer_class_directive(root, abs_path, mut stats)!
		}
		svelte_no_svelte_internal {
			return c.lint_svelte_no_svelte_internal(root, abs_path, mut stats)!
		}
		svelte_no_inspect {
			return c.lint_svelte_no_inspect(root, abs_path, mut stats)!
		}
		svelte_no_store_async {
			return c.lint_svelte_no_store_async(root, abs_path, mut stats)!
		}
		svelte_require_stores_init {
			return c.lint_svelte_require_stores_init(root, abs_path, mut stats)!
		}
		svelte_no_ignored_unsubscribe {
			return c.lint_svelte_no_ignored_unsubscribe(root, abs_path, mut stats)!
		}
		svelte_require_store_callbacks_use_set_param {
			return c.lint_svelte_require_store_callbacks_use_set_param(root, abs_path, mut stats)!
		}
		svelte_derived_has_same_inputs_outputs {
			return c.lint_svelte_derived_has_same_inputs_outputs(root, abs_path, mut stats)!
		}
		else { return error('unknown rule: ${rule}') }
	}
}

// Checker evaluates the rules on the files of a project. Caches are keyed by id, and ids are
// unique within a (snapshot, project).
@[heap]
pub struct Checker {
mut:
	client            &Client = unsafe { nil }
	snapshot          int
	snapshot_tsconfig string // made without a snapshot (defer_snapshot): the tsconfig make_snapshot opens
	// syntax_baseline is how many errors TypeScript's parser found in the file before --fix changed
	// it: lint_file reports a parsing error when the fixes added one (-1: it does not check).
	syntax_baseline                         int = -1
	no_implicit_this                        bool // isStrictCompilerOptionEnabled(…, 'noImplicitThis') of the project
	strict_null_checks                      bool // isStrictCompilerOptionEnabled(…, 'strictNullChecks') of the project
	no_unchecked_indexed_access             bool // isCompilerOptionEnabled(…, 'noUncheckedIndexedAccess') of the project
	no_property_access_from_index_signature bool // isCompilerOptionEnabled(…, 'noPropertyAccessFromIndexSignature') of the project
	exact_optional_property_types           bool // isCompilerOptionEnabled(…, 'exactOptionalPropertyTypes') of the project
	decorator_metadata                      bool // experimentalDecorators and emitDecoratorMetadata of the project (consistent-type-imports)
	project                                 string
	src                                     string
	tokens                                  TokenEnds                          // token ends of the file (per file)
	node_index                              treesitter.NodeIndex               // nodes of the file by kind (per file)
	ast_path                                string                             // file `ast` belongs to ('' when it must be requested)
	ast                                     SourceFileAst                      // tsgo AST of the file, shared by the rules
	attempted                               map[u64]bool                       // keys already looked up in tsgo (per file)
	too_deep                                int                                // expressions not analyzed because they are nested too deeply, or because TypeScript reads another kind of node there (per rule)
	node_types                              map[u64]TypeResponse               // type of each requested node, by byte range (per file)
	node_kinds                              map[u64]u32                        // tsgo SyntaxKind of each requested node (per file)
	node_handles                            map[u64]string                     // tsgo handle of each requested node (per file)
	contextual_cache                        map[u64]TypeResponse               // contextual type of each queried node (per file)
	resolved_cache                          map[u64]SignatureResponse          // resolved signature of each queried call (per file)
	predicate_cache                         map[int]tsgo.TypePredicateResponse // type predicate of each queried signature
	apparent_kind_cache                     map[int]TypeResponse               // apparent type of the primitives of each kind (apparent_primitive_kinds)
	type_node_cache                         map[string]TypeResponse            // type of each queried type node of a declaration, by its handle
	name_symbol_cache                       map[string]SymbolResponse          // symbol of each queried name of a declaration, by its handle (type_sources.v)
	mapped_parts_cache                      map[int]MappedParts                // what the declaration of each queried mapped type tells of it (mapped_parts.v)
	sig_cache                               map[string][]SignatureResponse
	return_cache                            map[int]TypeResponse
	member_cache                            map[int][]TypeResponse
	symbol_cache                            map[int]SymbolResponse
	apparent_cache                          map[int]TypeResponse
	constraint_cache                        map[int]TypeResponse
	base_cache                              map[int][]TypeResponse
	promise_cache                           map[int]bool
	builtin_cache                           map[string]bool
	array_cache                             map[int]bool
	// await-thenable
	base_constraint_cache map[int]TypeResponse
	property_cache        map[string]SymbolResponse
	properties_cache      map[int][]SymbolResponse
	symbol_type_cache     map[int]TypeResponse
	parameters_cache      map[int][]ParameterResponse
	number_index_cache    map[int]TypeResponse
	thenable_cache        map[int]bool
	calls                 CheckerCalls        // caches of rules/checker_calls.v
	awaited               map[int]AwaitedType // checker.getAwaitedType of each type asked
	// no-unsafe-*
	array_type_cache map[int]bool
	type_args_cache  map[int][]TypeResponse
	unsafe_cache     map[int]bool // no-unsafe-argument: types that may produce findings
	well_known_names map[string]string
	// options and type specifiers
	options             map[string][]json2.Any // effective options of each rule (set_options)
	type_string_cache   map[int]string
	alias_symbol_cache  map[int]SymbolResponse
	aliased_cache       map[int]SymbolResponse             // getAliasedSymbol of each queried symbol
	index_infos_cache   map[int][]tsgo.IndexInfoResponse   // getIndexInfosOfType of each queried type
	assignable_cache    map[u64]bool                       // isTypeAssignableTo of each queried pair of types
	targets_unsigned    map[u64]bool                       // generic types an instance of which has no signatures, by kind of signature
	file_metadata_cache map[string]tsgo.SourceFileMetadata // by tsgo path (file_metadata)
	package_name_cache  map[string]string                  // package.json name of each package directory; '' if it gives no package id
	package_root_cache  map[string]string                  // package.json name of each directory (resolvePackageIdName); '' if it has none
	project_directory   string               // directory of the tsconfig (set_project_directory): what `from: "file"` specifiers are relative to
	program_directory   string               // or this one, when the configuration of the file gives it (LintConfig.program_directory)
	ecma_version        int                  // the normalized languageOptions.ecmaVersion of the file being linted
	language            LanguageOptions      // the languageOptions of the file being linted
	settings            map[string]json2.Any // the shared settings of the file's configuration (context.settings)
	has_bom             bool                 // the file being linted had a BOM, which its text does not have (set_has_bom)
	base_types_cache    map[int][]TypeResponse
	target_cache        map[int]TypeResponse
	// The `seyfert/*` rules (seyfert.v): getSymbolAtLocation and getTypeAtLocation of each queried
	// tsgo node, by its handle, and getDeclaredTypeOfSymbol of each queried symbol.
	sy_symbols  map[string]SymbolResponse
	sy_types    map[string]TypeResponse
	sy_declared map[int]TypeResponse
	// AstTree of the files whose declarations the rules look at (declaration_ast), by tsgo path; kept
	// for the whole run, or in shared_asts when the Checker shares them (share_declaration_asts)
	declaration_asts map[string]tsgo.AstTree
	shared_asts      &DeclarationAsts = unsafe { nil }
	// lexical scopes of the file (scope_tree), built on first use (per file)
	file_scopes &ScopeTree = unsafe { nil }
	// scope_project is what the compiler options of the project decide about the scopes of its
	// files, scope_setup the setup of the file being linted (file_scope_setup) and
	// scope_libs_cache the implicit variables of each list of libs (scope_libs).
	scope_project    ScopeProject
	scope_setup      ScopeSetup
	scope_libs_cache map[string]&ScopeLibs
	nc_unused        map[int]bool // naming-convention: the unused variables of the file
	// file_rules are the rules that run on the file being linted (what one rule may see of
	// another: ESLint runs them on the same scope manager)
	file_rules []string
	// vue_template_owner is the rule in whose Program:exit vue-eslint-parser walks the template of
	// the .vue file being linted ('' for none; vue_template.v)
	vue_template_owner string
	// asked before each rule of a file whether to give the lint up (set_lint_stop)
	lint_stop LintStop = NoLintStop{}
	// tokens and comments of the file (source_tokens), built on first use (per file)
	file_tokens &SourceTokens = unsafe { nil }
	// the ESTree of the file and its code path analysis (estree_bridge.v), built on first use (per
	// file)
	file_es_state EsFileState
	file_es       estree.EsTree
	// file_es_by_ts is the ESTree node of each tree-sitter node of the file (see es_index_of).
	file_es_by_ts         map[u64]int
	file_code_paths       codepath.Analysis
	file_code_paths_built bool
	// no-deprecated: the reason of the first @deprecated tag of each symbol, or ndep_not_deprecated;
	// kept for the whole run, as symbol ids are fixed for a Checker
	jsdoc_deprecation_cache map[int]string
	// the .vue file being linted (vue_file.v), set before lint_file by set_vue
	vue VueView
	// the .svelte file being linted (svelte_file.v), set before lint_file by set_svelte
	svelte SvelteView
	// the `.svelte.ts` module being linted (svelte_file.v), set before lint_file by
	// set_svelte_module
	svelte_module SvelteModuleView
	// what the vue/* script rules share about the file being linted (vue_component.v), built on
	// first use (per file)
	vue_script_info VueScript
	// LintConfig.project_programs of the file being linted
	project_programs bool
	// vue_wrap_core: a rule of ESLint Stylistic runs as the rule of ESLint core a wrapper rule of
	// eslint-plugin-vue takes without @stylistic/eslint-plugin (vue_wrap.v); vue_stylistic is
	// the major version of the one that resolves (0: not looked up yet, -1: none).
	vue_wrap_core bool
	vue_stylistic int
	// vue_wrap_roots are the tree-sitter nodes of the expressions the template's traversal enters
	// from its V* nodes, while a wrapper rule runs on a snippet: their parent is none of the
	// snippet's.
	vue_wrap_roots map[u64]bool
}

// DeclarationAsts keeps the AstTree of the files whose declarations the rules look at, by tsgo
// path, beyond one Checker: veslint --server gives the same one to the Checker of each snapshot of
// a project, and drops the files tsgo reads again. A file's AstTree is its syntax only, so it holds
// in every snapshot where the file did not change.
@[heap]
pub struct DeclarationAsts {
pub mut:
	trees map[string]tsgo.AstTree
}

// forget drops the AstTree of a file that changed: `path` is an absolute path, and tsgo may know
// the file by its real path, or in lower case where file names are not case-sensitive.
pub fn (mut a DeclarationAsts) forget(path string) {
	real := os.real_path(path)
	lower := path.to_lower()
	// On Windows tsgo also writes `\` as `/`.
	keys := [tsgo.path_key(path), tsgo.path_key(real)]
	for key in a.trees.keys() {
		if key == path || key == real || key.to_lower() == lower || tsgo.path_key(key) in keys {
			a.trees.delete(key)
		}
	}
}

// share_declaration_asts makes the Checker keep the AstTrees it requests in `asts` and use those
// already there.
pub fn (mut c Checker) share_declaration_asts(asts &DeclarationAsts) {
	c.shared_asts = asts
}

pub fn new_checker(client &Client, snapshot int, project string, options CompilerOptions) !&Checker {
	mut checker := &Checker{
		client:                                  client
		snapshot:                                snapshot
		project:                                 project
		no_implicit_this:                        options.no_implicit_this_enabled()
		strict_null_checks:                      options.strict_null_checks_enabled()
		no_unchecked_indexed_access:             options.no_unchecked_indexed_access_enabled()
		no_property_access_from_index_signature: options.no_property_access_from_index_signature_enabled()
		exact_optional_property_types:           options.exact_optional_property_types_enabled()
		decorator_metadata:                      (options.experimental_decorators or { false })
			&& (options.emit_decorator_metadata or { false })
		scope_project:                           new_scope_project(options)
	}
	return checker
}

// defer_snapshot marks a checker made from the parsed tsconfig alone, before any snapshot: it
// makes one the first time something needs the program (make_snapshot).
pub fn (mut c Checker) defer_snapshot(tsconfig string) {
	c.snapshot_tsconfig = tsconfig
}

// syntax_error_count is how many errors TypeScript's parser finds in the file as tsgo has it now,
// or -1 if tsgo does not have it.
pub fn (mut c Checker) syntax_error_count(abs_path string) int {
	diagnostics := c.client.syntactic_diagnostics(c.snapshot, c.project, abs_path) or { return -1 }
	return diagnostics.len
}

// check_syntax makes lint_file report a parsing error when TypeScript's parser finds more errors in
// the file than `baseline`, the ones it found before --fix changed it (syntax_error_count).
pub fn (mut c Checker) check_syntax(baseline int) {
	c.syntax_baseline = baseline
}

// parsing_error is the first error TypeScript's parser found in the file, as ESLint reports it
// (typescript-estree throws the first of the parse diagnostics), when a fix gave code TypeScript
// does not parse: tree-sitter reads some of it (`type satisfies never;`, `<T>(x: T) => x` in a
// .tsx file). Only then: the parser of tsgo 7.1 rejects some code that the one of TypeScript 6.0.3,
// which typescript-estree uses, takes (`x < 0 as any ** 2`), so an error that was already there
// is not reported.
fn (mut c Checker) parsing_error(abs_path string) []Finding {
	if c.syntax_baseline < 0 {
		return []
	}
	// A file tsgo does not have is reported by the first rule that asks for its types.
	diagnostics := c.client.syntactic_diagnostics(c.snapshot, c.project, abs_path) or { return [] }
	if diagnostics.len <= c.syntax_baseline {
		return []
	}
	// tsgo orders them by position, and typescript-estree takes the first one the parser reported:
	// that a JSX element (17008) or fragment (17014) has no closing tag, or that JSX expressions
	// must have one parent element (2657), is reported once what follows is parsed.
	mut first := diagnostics[0]
	for diagnostic in diagnostics {
		if diagnostic.code !in [17008, 17014, 2657] {
			first = diagnostic
			break
		}
	}
	return [Finding{
		stmt:             c.position_at(c.file_offset_of_ts_unit(first.pos))
		rule:             problem_rule
		message_id:       'fatal'
		text:             'Parsing error: ${first.text}'
		column_from_zero: true
	}]
}

// make_snapshot gives a checker made without a snapshot one with its tsconfig open: a comment
// turned on a rule that needs types, or TypeScript may read an `await` as a name.
fn (mut c Checker) make_snapshot() ! {
	if c.snapshot_tsconfig == '' {
		return
	}
	snap := c.client.create_snapshot([c.snapshot_tsconfig])!
	key := tsgo.path_key(c.snapshot_tsconfig)
	for p in snap.projects {
		if tsgo.path_key(p.id) == key || tsgo.path_key(p.config_file_name) == key {
			c.snapshot = snap.snapshot
			c.project = p.id
			c.snapshot_tsconfig = ''
			return
		}
	}
	return error('tsconfig ${c.snapshot_tsconfig} is not in the tsgo snapshot (projects: ${snap.projects.map(it.id)})')
}

// max_expression_depth bounds the recursion over nested expressions (conditionals, logical
// operators, commas): beyond it, the expression is not analyzed and counts in `unmatched`.
const max_expression_depth = 1000

// using_kind is ESTree's `kind` of a VariableDeclaration that declares resources: 'using' or
// 'await using' for a lexical_declaration, or for a for-in/of whose header declares one
// (`for (using x of y)`; the `await` of `for await (…)` is not part of it). '' for any other node.
fn using_kind(n C.TSNode) string {
	mut words := []string{}
	mut started := node_kind(n) != 'for_in_statement'
	for child in children(n) {
		kind := node_kind(child)
		// A comment may sit between the keywords: `await /* c */ using x = …`.
		if kind == 'comment' {
			continue
		}
		if !started {
			started = kind == '('
			continue
		}
		if kind !in ['await', 'using'] {
			break
		}
		words << kind
	}
	return if words.len > 0 && words.last() == 'using' { words.join(' ') } else { '' }
}

// jsx_expression_value is the expression of a JSX `{…}` (ESTree's JSXExpressionContainer), without
// parentheses; none for `{}` and `{/* comment */}`, whose expression is a JSXEmptyExpression, and
// for a spread.
fn jsx_expression_value(container C.TSNode) ?C.TSNode {
	for child in named_children(container) {
		if node_kind(child) in ['comment', 'spread_element'] {
			continue
		}
		return unwrap_parens(child)
	}
	return none
}

// unwrap_parens removes parentheses, which are not nodes in ESTree.
fn unwrap_parens(n C.TSNode) C.TSNode {
	mut node := n
	for node_kind(node) == 'parenthesized_expression' {
		node = first_named_child(node) or { return node }
	}
	return node
}

fn operator_of(node C.TSNode) string {
	op := node_field(node, 'operator') or { return '' }
	return node_kind(op)
}

// nodes_of_kind and nodes_of_kinds give the nodes of the file treesitter's functions of the same
// name give, from the index of the file when `root` is its root: every rule asks for the nodes of
// some kinds, and walking the tree once for each was most of the time of veslint itself.
fn (c &Checker) nodes_of_kind(root C.TSNode, kind &char) []C.TSNode {
	return c.node_index.of_kind(root, unsafe { tos2(&u8(kind)) })
}

fn (c &Checker) nodes_of_kinds(root C.TSNode, kinds []string, skip []string) []C.TSNode {
	return c.node_index.of_kinds(root, kinds, skip)
}

fn (c &Checker) text(n C.TSNode) string {
	return c.src[node_start(n)..node_end(n)]
}

// position_at is the position of a byte offset of the file, like position_of for a node. The
// offset is all a position needs: the printed line and column come from it, with ESLint's line
// breaks (offsets.utf16_positions), and not from tree-sitter's rows.
fn (c &Checker) position_at(offset int) Ident {
	return Ident{
		start_byte: offset
	}
}

// trimmed_end ends the report on a tree-sitter node at its last token, as an ESTree node ends:
// tree-sitter may put the comments and spaces that follow a node inside it.
fn (c &Checker) trimmed_end(place Ident) Ident {
	if !place.node_end || place.end_byte <= place.start_byte {
		return place
	}
	last := c.tokens.last_end(place.end_byte)
	if last <= place.start_byte || last >= place.end_byte
		|| !only_trivia(c.src[last..place.end_byte]) {
		return place
	}
	return Ident{
		...place
		end_byte: last
	}
}

// only_trivia: the text is only white space, line breaks and comments.
fn only_trivia(text string) bool {
	mut i := 0
	for i < text.len {
		ch := text[i]
		if ch in [` `, `\t`, `\n`, `\r`, `\v`, `\f`] {
			i++
		} else if text[i..].starts_with('//') {
			end := text.index_after('\n', i) or { text.len }
			i = end
		} else if text[i..].starts_with('/*') {
			end := text.index_after('*/', i + 2) or { return false }
			i = end + 2
		} else if ch >= 0x80 {
			// Other white space (U+00A0, U+FEFF, U+2028…).
			r := text[i..].runes()[0]
			if !is_js_space(r) {
				return false
			}
			i += r.length_in_bytes()
		} else {
			return false
		}
	}
	return true
}

// position_range is the place of a report from byte `start` to byte `end` (ESLint's `loc`).
fn (c &Checker) position_range(start int, end int) Ident {
	return Ident{
		start_byte: start
		end_byte:   end
	}
}
