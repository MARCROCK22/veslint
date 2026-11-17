module rules

// The case converters and checkers of vue_casing.v against eslint-plugin-vue 10.12.1's casing.ts:
// each row is an input and what kebabCase, isKebabCase, snakeCase, isSnakeCase, camelCase,
// isCamelCase, pascalCase, isPascalCase and capitalize give for it (Node 26).
struct VcaseRow {
	input       string
	kebab       string
	is_kebab    bool
	snake       string
	is_snake    bool
	camel       string
	is_camel    bool
	pascal      string
	is_pascal   bool
	capitalized string
}

const vcase_rows = [
	VcaseRow{'fooBar', 'foo-bar', false, 'foo_bar', false, 'fooBar', true, 'FooBar', false, 'FooBar'},
	VcaseRow{'FooBar', 'foo-bar', false, 'foo_bar', false, 'fooBar', false, 'FooBar', true, 'FooBar'},
	VcaseRow{'foo-bar', 'foo-bar', true, 'foo_bar', false, 'fooBar', false, 'FooBar', false, 'Foo-bar'},
	VcaseRow{'foo_bar', 'foo-bar', false, 'foo_bar', true, 'fooBar', false, 'FooBar', false, 'Foo_bar'},
	VcaseRow{'foo--bar', 'foo--bar', false, 'foo__bar', false, 'foo-Bar', false, 'Foo-Bar', false, 'Foo--bar'},
	VcaseRow{'-foo', '-foo', false, '_foo', false, 'Foo', false, 'Foo', false, '-foo'},
	VcaseRow{'Foo-Bar', 'foo-bar', false, 'foo_bar', false, 'FooBar', false, 'FooBar', false, 'Foo-Bar'},
	VcaseRow{'FOO', 'f-o-o', false, 'f_o_o', false, 'fOO', false, 'FOO', true, 'FOO'},
	VcaseRow{'fooBAR', 'foo-b-a-r', false, 'foo_b_a_r', false, 'fooBAR', true, 'FooBAR', false, 'FooBAR'},
	VcaseRow{'a1B', 'a1-b', false, 'a1_b', false, 'a1B', true, 'A1B', false, 'A1B'},
	VcaseRow{'a_B', 'a-b', false, 'a__b', false, 'aB', false, 'AB', false, 'A_B'},
	VcaseRow{'Ábc', 'ábc', true, 'ábc', true, 'ábc', true, 'Ábc', true, 'Ábc'},
	VcaseRow{'ábcDéf', 'ábc-déf', false, 'ábc_déf', false, 'ábcDéf', true, 'ÁbcDéf', true, 'ÁbcDéf'},
	VcaseRow{'x-ÿ', 'x-ÿ', true, 'x_ÿ', false, 'x-ÿ', false, 'X-ÿ', false, 'X-ÿ'},
	VcaseRow{'MyComponent', 'my-component', false, 'my_component', false, 'myComponent', false, 'MyComponent', true, 'MyComponent'},
	VcaseRow{'my-component', 'my-component', true, 'my_component', false, 'myComponent', false, 'MyComponent', false, 'My-component'},
	VcaseRow{'my_component', 'my-component', false, 'my_component', true, 'myComponent', false, 'MyComponent', false, 'My_component'},
	VcaseRow{'foo bar', 'foo bar', false, 'foo bar', false, 'foo bar', false, 'Foo bar', false, 'Foo bar'},
	VcaseRow{'foo\$bar', 'foo\$bar', true, 'foo\$bar', true, 'foo\$bar', true, 'Foo\$bar', false, 'Foo\$bar'},
	VcaseRow{'foo.bar', 'foo.bar', false, 'foo.bar', false, 'foo.bar', false, 'Foo.bar', false, 'Foo.bar'},
	VcaseRow{'ǅx', 'ǆx', true, 'ǆx', true, 'ǆx', true, 'Ǆx', true, 'Ǆx'},
	VcaseRow{'ß-x', 'ß-x', true, 'ß_x', false, 'ßX', false, 'SSX', false, 'SS-x'},
	VcaseRow{'İ', 'i̇', true, 'i̇', true, 'i̇', true, 'İ', true, 'İ'},
	VcaseRow{'', '', true, '', true, '', true, '', true, ''},
	VcaseRow{'a', 'a', true, 'a', true, 'a', true, 'A', false, 'A'},
	VcaseRow{'_a', '-a', false, '_a', true, 'A', false, 'A', false, '_a'},
	VcaseRow{'a-', 'a-', true, 'a_', false, 'a-', false, 'A-', false, 'A-'},
	VcaseRow{'A_b-C', 'a-b-c', false, 'a_b_c', false, 'ABC', false, 'ABC', false, 'A_b-C'},
]

fn test_vue_casing() {
	for r in vcase_rows {
		assert vue_kebab_case(r.input) == r.kebab, r.input
		assert vue_is_kebab_case(r.input) == r.is_kebab, r.input
		assert vue_snake_case(r.input) == r.snake, r.input
		assert vue_is_snake_case(r.input) == r.is_snake, r.input
		assert vue_camel_case(r.input) == r.camel, r.input
		assert vue_is_camel_case(r.input) == r.is_camel, r.input
		assert vue_pascal_case(r.input) == r.pascal, r.input
		assert vue_is_pascal_case(r.input) == r.is_pascal, r.input
		assert vue_capitalize(r.input) == r.capitalized, r.input
	}
}
