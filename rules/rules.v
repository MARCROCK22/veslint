module rules

import json2
import time
import tsgo { Client, CompilerOptions, ParameterResponse, SignatureResponse, SourceFileAst, SymbolResponse, TypeResponse }
import treesitter { Ident, Parser, TokenEnds, children, first_named_child, named_children, node_end, node_field, node_kind, node_start, root_node, token_ends, tree_delete, tree_has_error }
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
	seyfert_group_exists]

// untyped_rules are the ported rules that need no types (`meta.docs.requiresTypeChecking` is false
// in typescript-eslint): with only these, the command line makes no snapshot (Checker.make_snapshot).
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
	triple_slash_reference, unified_signatures]

// needs_types tells whether a rule asks tsgo for the types of the program.
pub fn needs_types(rule string) bool {
	return rule !in untyped_rules
}

// default_options are the default options of each rule (`defaultOptions` of typescript-eslint
// 8.62.0, as JSON). For the rules that do not read options (see check_options), veslint only
// applies these.
pub const default_options = {
	no_floating_promises:                         '[{"allowForKnownSafeCalls":[],"allowForKnownSafePromises":[],"checkThenables":false,"ignoreIIFE":false,"ignoreVoid":true}]'
	await_thenable:                               '[]'
	require_await:                                '[]'
	return_await:                                 '["in-try-catch"]'
	no_misused_promises:                          '[{"checksConditionals":true,"checksSpreads":true,"checksVoidReturn":true}]'
	no_unsafe_call:                               '[]'
	no_unsafe_member_access:                      '[{"allowOptionalChaining":false}]'
	no_unsafe_return:                             '[]'
	no_unsafe_assignment:                         '[]'
	no_unsafe_argument:                           '[]'
	restrict_template_expressions:                '[{"allow":[{"name":["Error","URL","URLSearchParams"],"from":"lib"}],"allowAny":true,"allowBoolean":true,"allowNullish":true,"allowNumber":true,"allowRegExp":true}]'
	switch_exhaustiveness_check:                  '[{"allowDefaultCaseForExhaustiveSwitch":true,"considerDefaultExhaustiveForUnions":false,"requireDefaultForNonUnion":false}]'
	prefer_nullish_coalescing:                    '[{"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"ignoreBooleanCoercion":false,"ignoreConditionalTests":true,"ignoreIfStatements":false,"ignoreMixedLogicalExpressions":false,"ignorePrimitives":{"bigint":false,"boolean":false,"number":false,"string":false},"ignoreTernaryTests":false}]'
	no_unnecessary_condition:                     '[{"allowConstantLoopConditions":"never","allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"checkTypePredicates":false}]'
	no_for_in_array:                              '[]'
	no_array_delete:                              '[]'
	no_unnecessary_boolean_literal_compare:       '[{"allowComparingNullableBooleansToFalse":true,"allowComparingNullableBooleansToTrue":true,"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false}]'
	no_unsafe_unary_minus:                        '[]'
	no_meaningless_void_operator:                 '[{"checkNever":false}]'
	related_getter_setter_pairs:                  '[]'
	non_nullable_type_assertion_style:            '[]'
	prefer_return_this_type:                      '[]'
	no_duplicate_type_constituents:               '[{"ignoreIntersections":false,"ignoreUnions":false}]'
	no_unnecessary_template_expression:           '[]'
	dot_notation:                                 '[{"allowIndexSignaturePropertyAccess":false,"allowKeywords":true,"allowPattern":"","allowPrivateClassPropertyAccess":false,"allowProtectedClassPropertyAccess":false}]'
	restrict_plus_operands:                       '[{"allowAny":true,"allowBoolean":true,"allowNullish":true,"allowNumberAndString":true,"allowRegExp":true,"skipCompoundAssignments":false}]'
	no_confusing_void_expression:                 '[{"ignoreArrowShorthand":false,"ignoreVoidOperator":false,"ignoreVoidReturningFunctions":false}]'
	no_misused_spread:                            '[{"allow":[]}]'
	no_redundant_type_constituents:               '[]'
	no_useless_default_assignment:                '[{"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false}]'
	no_unnecessary_type_arguments:                '[]'
	no_unnecessary_qualifier:                     '[]'
	no_implied_eval:                              '[]'
	no_unnecessary_type_conversion:               '[]'
	no_unnecessary_type_assertion:                '[{}]'
	no_base_to_string:                            '[{"checkUnknown":false,"ignoredTypeNames":["Error","RegExp","URL","URLSearchParams"]}]'
	no_unsafe_enum_comparison:                    '[]'
	no_mixed_enums:                               '[]'
	unbound_method:                               '[{"ignoreStatic":false}]'
	prefer_reduce_type_parameter:                 '[]'
	prefer_find:                                  '[]'
	prefer_regexp_exec:                           '[]'
	prefer_includes:                              '[]'
	prefer_string_starts_ends_with:               '[{"allowSingleElementEquality":"never"}]'
	prefer_optional_chain:                        '[{"allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing":false,"checkAny":true,"checkBigInt":true,"checkBoolean":true,"checkNumber":true,"checkString":true,"checkUnknown":true,"requireNullish":false}]'
	no_deprecated:                                '[{"allow":[]}]'
	prefer_promise_reject_errors:                 '[{"allow":[],"allowEmptyReject":false,"allowThrowingAny":false,"allowThrowingUnknown":false}]'
	use_unknown_in_catch_callback_variable:       '[]'
	only_throw_error:                             '[{"allow":[],"allowRethrowing":true,"allowThrowingAny":true,"allowThrowingUnknown":true}]'
	require_array_sort_compare:                   '[{"ignoreStringArrays":true}]'
	no_unsafe_type_assertion:                     '[]'
	promise_function_async:                       '[{"allowAny":true,"allowedPromiseNames":[],"checkArrowFunctions":true,"checkFunctionDeclarations":true,"checkFunctionExpressions":true,"checkMethodDeclarations":true}]'
	prefer_readonly_parameter_types:              '[{"allow":[],"checkParameterProperties":true,"ignoreInferredTypes":false,"treatMethodsAsReadonly":false}]'
	consistent_type_exports:                      '[{"fixMixedExportsWithInlineTypeSpecifier":false}]'
	strict_void_return:                           '[{"allowReturnAny":false}]'
	consistent_return:                            '[{"treatUndefinedAsUnspecified":false}]'
	prefer_destructuring:                         '[{"AssignmentExpression":{"array":true,"object":true},"VariableDeclarator":{"array":true,"object":true}},{}]'
	prefer_readonly:                              '[{"onlyInlineLambdas":false}]'
	strict_boolean_expressions:                   '[{"allowAny":false,"allowNullableBoolean":false,"allowNullableEnum":false,"allowNullableNumber":false,"allowNullableObject":true,"allowNullableString":false,"allowNumber":true,"allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing":false,"allowString":true}]'
	no_unnecessary_type_parameters:               '[]'
	naming_convention:                            '[{"format":["camelCase"],"leadingUnderscore":"allow","selector":"default","trailingUnderscore":"allow"},{"format":["camelCase","PascalCase"],"selector":"import"},{"format":["camelCase","UPPER_CASE"],"leadingUnderscore":"allow","selector":"variable","trailingUnderscore":"allow"},{"format":["PascalCase"],"selector":"typeLike"}]'
	no_duplicate_enum_values:                     '[]'
	no_extra_non_null_assertion:                  '[]'
	no_non_null_asserted_optional_chain:          '[]'
	no_unsafe_function_type:                      '[]'
	no_wrapper_object_types:                      '[]'
	prefer_enum_initializers:                     '[]'
	no_dynamic_delete:                            '[]'
	no_namespace:                                 '[{"allowDeclarations":false,"allowDefinitionFiles":true}]'
	no_unnecessary_type_constraint:               '[]'
	prefer_as_const:                              '[]'
	no_invalid_void_type:                         '[{"allowAsThisParameter":false,"allowInGenericTypeArguments":true}]'
	no_this_alias:                                '[{"allowDestructuring":true,"allowedNames":[]}]'
	no_misused_new:                               '[]'
	no_useless_empty_export:                      '[]'
	no_extraneous_class:                          '[{"allowConstructorOnly":false,"allowEmpty":false,"allowStaticOnly":false,"allowWithDecorator":false}]'
	adjacent_overload_signatures:                 '[]'
	no_dupe_class_members:                        '[]'
	class_literal_property_style:                 '["fields"]'
	no_empty_function:                            '[{"allow":[]}]'
	no_unused_expressions:                        '[{"allowShortCircuit":false,"allowTaggedTemplates":false,"allowTernary":false}]'
	no_useless_constructor:                       '[]'
	no_array_constructor:                         '[]'
	no_confusing_non_null_assertion:              '[]'
	no_import_type_side_effects:                  '[]'
	no_inferrable_types:                          '[{"ignoreParameters":false,"ignoreProperties":false}]'
	prefer_namespace_keyword:                     '[]'
	triple_slash_reference:                       '[{"lib":"always","path":"never","types":"prefer-import"}]'
	consistent_generic_constructors:              '["constructor"]'
	consistent_type_assertions:                   '[{"arrayLiteralTypeAssertions":"allow","assertionStyle":"as","objectLiteralTypeAssertions":"allow"}]'
	consistent_type_definitions:                  '["interface"]'
	prefer_function_type:                         '[]'
	unified_signatures:                           '[{"ignoreDifferentlyNamedParameters":false,"ignoreOverloadsWithDifferentJSDoc":false}]'
	no_unsafe_declaration_merging:                '[]'
	no_require_imports:                           '[{"allow":[],"allowAsImport":false}]'
	no_non_null_asserted_nullish_coalescing:      '[]'
	prefer_for_of:                                '[]'
	array_type:                                   '[{"default":"array"}]'
	consistent_indexed_object_style:              '["record"]'
	no_unnecessary_parameter_property_assignment: '[]'
	no_unused_private_class_members:              '[]'
	no_use_before_define:                         '[{"allowNamedExports":false,"classes":true,"enums":true,"functions":true,"ignoreTypeReferences":true,"typedefs":true,"variables":true}]'
	no_shadow:                                    '[{"allow":[],"builtinGlobals":false,"hoist":"functions-and-types","ignoreFunctionTypeParameterNameValueShadow":true,"ignoreOnInitialization":false,"ignoreTypeValueShadow":true}]'
	consistent_type_imports:                      '[{"disallowTypeAnnotations":true,"fixStyle":"separate-type-imports","prefer":"type-imports"}]'
	no_unused_vars:                               '[{}]'
	seyfert_prefer_typed_group:                   '[]'
	seyfert_autocomplete_respond:                 '[]'
	seyfert_config_default_export:                '[]'
	seyfert_decorator_target:                     '[]'
	seyfert_decorator_on_command:                 '[]'
	seyfert_i18n_resolve_with_get:                '[]'
	seyfert_no_method_destructure:                '[]'
	seyfert_require_declare:                      '[]'
	seyfert_context_menu_declare:                 '[]'
	seyfert_required_options_order:               '[]'
	seyfert_options_use_builders:                 '[]'
	seyfert_declare_description:                  '[]'
	seyfert_no_deep_imports:                      '[]'
	seyfert_no_hanging_middleware:                '[]'
	seyfert_group_exists:                         '[]'
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
// the rule with `data`, and `fix` what applying it does.
pub struct Suggestion {
pub:
	message_id string
	data       map[string]string
	fix        Fix
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
		else { map[string]string{} }
	}
	return interpolate(messages[finding.message_id] or { finding.message_id }, finding.data)
}

// suggestion_message is the text of a suggestion of `rule` (ESLint's `desc`).
pub fn suggestion_message(rule string, suggestion Suggestion) string {
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
	unmatched     int       // nodes the rules could not analyze (summed per rule): no tsgo counterpart, or nested too deeply
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

pub fn (mut c Checker) lint_file(parser Parser, config LintConfig, src string, abs_path string, mut stats Stats) !FileLint {
	sw := time.new_stopwatch()
	mut tree := parser.parse(src)!
	defer {
		// The index points into the tree.
		c.node_index = treesitter.NodeIndex{}
		tree_delete(tree)
	}
	mut root := root_node(tree)
	c.src = src
	c.tokens = token_ends(root)
	c.node_index = treesitter.new_node_index(root)
	c.ast_path = ''
	c.program_directory = config.program_directory
	c.reset_file_types()
	// Where TypeScript read an `await` as an identifier, the file is parsed again that way
	// (rules/await_identifier.v).
	reread := c.await_identifiers_source(root, abs_path)!
	if reread != '' {
		c.node_index = treesitter.NodeIndex{}
		tree_delete(tree)
		tree = parser.parse(reread)!
		root = root_node(tree)
		c.tokens = token_ends(root)
		c.node_index = treesitter.new_node_index(root)
	}
	unmatched_before := stats.unmatched
	stats.parse_ms += ms(sw.elapsed())
	// The comments that configure ESLint: they may change the rules of this file and they
	// suppress findings.
	inline := c.inline_config(root, config)
	c.scope_setup = c.file_scope_setup(config, inline)
	mut findings := []Finding{}
	for setting in inline.rules {
		if c.lint_stop.stop() {
			return error(lint_stopped)
		}
		if needs_types(setting.name) {
			c.make_snapshot()!
		}
		c.too_deep = 0
		c.options[setting.name] = setting.options
		for f in c.lint_rule(setting.name, root, abs_path, mut stats)! {
			findings << Finding{
				...f
				rule:     setting.name
				severity: setting.severity
			}
		}
		stats.unmatched += c.too_deep
	}
	findings = sort_rule_findings(findings)
	findings = c.apply_disable_directives(findings, inline, config)
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
		else { return error('unknown rule: ${rule}') }
	}
}

// Checker evaluates the rules on the files of a project. Caches are keyed by id, and ids are
// unique within a (snapshot, project).
@[heap]
pub struct Checker {
mut:
	client                                  &Client = unsafe { nil }
	snapshot                                int
	snapshot_tsconfig                       string // made without a snapshot (defer_snapshot): the tsconfig make_snapshot opens
	no_implicit_this                        bool   // isStrictCompilerOptionEnabled(…, 'noImplicitThis') of the project
	strict_null_checks                      bool   // isStrictCompilerOptionEnabled(…, 'strictNullChecks') of the project
	no_unchecked_indexed_access             bool   // isCompilerOptionEnabled(…, 'noUncheckedIndexedAccess') of the project
	no_property_access_from_index_signature bool   // isCompilerOptionEnabled(…, 'noPropertyAccessFromIndexSignature') of the project
	exact_optional_property_types           bool   // isCompilerOptionEnabled(…, 'exactOptionalPropertyTypes') of the project
	decorator_metadata                      bool   // experimentalDecorators and emitDecoratorMetadata of the project (consistent-type-imports)
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
	package_patterns    map[string]RegexpProgram           // the regular expression typescript-eslint makes of the `package` of a type specifier
	project_directory   string // directory of the tsconfig (set_project_directory): what `from: "file"` specifiers are relative to
	program_directory   string // or this one, when the configuration of the file gives it (LintConfig.program_directory)
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
	// asked before each rule of a file whether to give the lint up (set_lint_stop)
	lint_stop LintStop = NoLintStop{}
	// tokens and comments of the file (source_tokens), built on first use (per file)
	file_tokens &SourceTokens = unsafe { nil }
	// no-deprecated: the reason of the first @deprecated tag of each symbol, or ndep_not_deprecated;
	// kept for the whole run, as symbol ids are fixed for a Checker
	jsdoc_deprecation_cache map[int]string
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
