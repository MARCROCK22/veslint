// The converter's rules per kind (see convert.go): what tree-sitter's grammar makes of each node
// of TypeScript's AST. tsgo/inproc/build.sh adds this file to internal/parser as
// veslint_convert_kinds.go.
package parser

import (
	"strings"
	"unicode/utf8"

	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/scanner"
)

var (
	sIdentifier                     = namedSymbol("identifier")
	sPropertyIdentifier             = namedSymbol("property_identifier")
	sPrivatePropertyIdentifier      = namedSymbol("private_property_identifier")
	sTypeIdentifier                 = namedSymbol("type_identifier")
	sStatementIdentifier            = namedSymbol("statement_identifier")
	sShorthandPropertyIdentifier    = namedSymbol("shorthand_property_identifier")
	sShorthandPropertyIdentifierPat = namedSymbol("shorthand_property_identifier_pattern")
	sUndefined                      = namedSymbol("undefined")
	sThis                           = namedSymbol("this")
	sSuper                          = namedSymbol("super")
	sTrue                           = namedSymbol("true")
	sFalse                          = namedSymbol("false")
	sNull                           = namedSymbol("null")
	sNumber                         = namedSymbol("number")
	sString                         = namedSymbol("string")
	sStringFragment                 = namedSymbol("string_fragment")
	sEscapeSequence                 = namedSymbol("escape_sequence")
	sTemplateString                 = namedSymbol("template_string")
	sTemplateSubstitution           = namedSymbol("template_substitution")
	sRegex                          = namedSymbol("regex")
	sRegexPattern                   = namedSymbol("regex_pattern")
	sRegexFlags                     = namedSymbol("regex_flags")
	sExpressionStatement            = namedSymbol("expression_statement")
	sLexicalDeclaration             = namedSymbol("lexical_declaration")
	sVariableDeclaration            = namedSymbol("variable_declaration")
	sVariableDeclarator             = namedSymbol("variable_declarator")
	sStatementBlock                 = namedSymbol("statement_block")
	sIfStatement                    = namedSymbol("if_statement")
	sElseClause                     = namedSymbol("else_clause")
	sForStatement                   = namedSymbol("for_statement")
	sForInStatement                 = namedSymbol("for_in_statement")
	sWhileStatement                 = namedSymbol("while_statement")
	sDoStatement                    = namedSymbol("do_statement")
	sWithStatement                  = namedSymbol("with_statement")
	sReturnStatement                = namedSymbol("return_statement")
	sThrowStatement                 = namedSymbol("throw_statement")
	sBreakStatement                 = namedSymbol("break_statement")
	sContinueStatement              = namedSymbol("continue_statement")
	sDebuggerStatement              = namedSymbol("debugger_statement")
	sEmptyStatement                 = namedSymbol("empty_statement")
	sLabeledStatement               = namedSymbol("labeled_statement")
	sSwitchStatement                = namedSymbol("switch_statement")
	sSwitchBody                     = namedSymbol("switch_body")
	sSwitchCase                     = namedSymbol("switch_case")
	sSwitchDefault                  = namedSymbol("switch_default")
	sTryStatement                   = namedSymbol("try_statement")
	sCatchClause                    = namedSymbol("catch_clause")
	sFinallyClause                  = namedSymbol("finally_clause")
	sParenthesizedExpression        = namedSymbol("parenthesized_expression")
	sExportStatement                = namedSymbol("export_statement")
	sAmbientDeclaration             = namedSymbol("ambient_declaration")
	sFunctionDeclaration            = namedSymbol("function_declaration")
	sGeneratorFunctionDeclaration   = namedSymbol("generator_function_declaration")
	sFunctionSignature              = namedSymbol("function_signature")
	sFunctionExpression             = namedSymbol("function_expression")
	sGeneratorFunction              = namedSymbol("generator_function")
	sArrowFunction                  = namedSymbol("arrow_function")
	sFormalParameters               = namedSymbol("formal_parameters")
	sRequiredParameter              = namedSymbol("required_parameter")
	sOptionalParameter              = namedSymbol("optional_parameter")
	sRestPattern                    = namedSymbol("rest_pattern")
	sTypeAnnotation                 = namedSymbol("type_annotation")
	sAssertsAnnotation              = namedSymbol("asserts_annotation")
	sTypePredicateAnnotation        = namedSymbol("type_predicate_annotation")
	sClassDeclaration               = namedSymbol("class_declaration")
	sAbstractClassDeclaration       = namedSymbol("abstract_class_declaration")
	sClass                          = namedSymbol("class")
	sClassHeritage                  = namedSymbol("class_heritage")
	sExtendsClause                  = namedSymbol("extends_clause")
	sImplementsClause               = namedSymbol("implements_clause")
	sClassBody                      = namedSymbol("class_body")
	sDecorator                      = namedSymbol("decorator")
	sMethodDefinition               = namedSymbol("method_definition")
	sMethodSignature                = namedSymbol("method_signature")
	sAbstractMethodSignature        = namedSymbol("abstract_method_signature")
	sPublicFieldDefinition          = namedSymbol("public_field_definition")
	sClassStaticBlock               = namedSymbol("class_static_block")
	sAccessibilityModifier          = namedSymbol("accessibility_modifier")
	sOverrideModifier               = namedSymbol("override_modifier")
	sIndexSignature                 = namedSymbol("index_signature")
	sComputedPropertyName           = namedSymbol("computed_property_name")
	sInterfaceDeclaration           = namedSymbol("interface_declaration")
	sExtendsTypeClause              = namedSymbol("extends_type_clause")
	sInterfaceBody                  = namedSymbol("interface_body")
	sObjectType                     = namedSymbol("object_type")
	sPropertySignature              = namedSymbol("property_signature")
	sCallSignature                  = namedSymbol("call_signature")
	sConstructSignature             = namedSymbol("construct_signature")
	sTypeAliasDeclaration           = namedSymbol("type_alias_declaration")
	sEnumDeclaration                = namedSymbol("enum_declaration")
	sEnumBody                       = namedSymbol("enum_body")
	sEnumAssignment                 = namedSymbol("enum_assignment")
	sModule                         = namedSymbol("module")
	sInternalModule                 = namedSymbol("internal_module")
	sNestedIdentifier               = namedSymbol("nested_identifier")
	sImportStatement                = namedSymbol("import_statement")
	sImportClause                   = namedSymbol("import_clause")
	sNamedImports                   = namedSymbol("named_imports")
	sNamespaceImport                = namedSymbol("namespace_import")
	sImportSpecifier                = namedSymbol("import_specifier")
	sImportAttribute                = namedSymbol("import_attribute")
	sImportRequireClause            = namedSymbol("import_require_clause")
	sImportAlias                    = namedSymbol("import_alias")
	sExportClause                   = namedSymbol("export_clause")
	sExportSpecifier                = namedSymbol("export_specifier")
	sNamespaceExport                = namedSymbol("namespace_export")
	sAssignmentExpression           = namedSymbol("assignment_expression")
	sAugmentedAssignmentExpression  = namedSymbol("augmented_assignment_expression")
	sBinaryExpression               = namedSymbol("binary_expression")
	sSequenceExpression             = namedSymbol("sequence_expression")
	sUnaryExpression                = namedSymbol("unary_expression")
	sUpdateExpression               = namedSymbol("update_expression")
	sAwaitExpression                = namedSymbol("await_expression")
	sYieldExpression                = namedSymbol("yield_expression")
	sTernaryExpression              = namedSymbol("ternary_expression")
	sCallExpression                 = namedSymbol("call_expression")
	sNewExpression                  = namedSymbol("new_expression")
	sArguments                      = namedSymbol("arguments")
	sMemberExpression               = namedSymbol("member_expression")
	sSubscriptExpression            = namedSymbol("subscript_expression")
	sOptionalChain                  = namedSymbol("optional_chain")
	sNonNullExpression              = namedSymbol("non_null_expression")
	sAsExpression                   = namedSymbol("as_expression")
	sSatisfiesExpression            = namedSymbol("satisfies_expression")
	sTypeAssertion                  = namedSymbol("type_assertion")
	sInstantiationExpression        = namedSymbol("instantiation_expression")
	sMetaProperty                   = namedSymbol("meta_property")
	sImport                         = namedSymbol("import")
	sSpreadElement                  = namedSymbol("spread_element")
	sArray                          = namedSymbol("array")
	sObject                         = namedSymbol("object")
	sPair                           = namedSymbol("pair")
	sArrayPattern                   = namedSymbol("array_pattern")
	sObjectPattern                  = namedSymbol("object_pattern")
	sPairPattern                    = namedSymbol("pair_pattern")
	sAssignmentPattern              = namedSymbol("assignment_pattern")
	sObjectAssignmentPattern        = namedSymbol("object_assignment_pattern")
	sPredefinedType                 = namedSymbol("predefined_type")
	sThisType                       = namedSymbol("this_type")
	sLiteralType                    = namedSymbol("literal_type")
	sGenericType                    = namedSymbol("generic_type")
	sNestedTypeIdentifier           = namedSymbol("nested_type_identifier")
	sTypeArguments                  = namedSymbol("type_arguments")
	sTypeParameters                 = namedSymbol("type_parameters")
	sTypeParameter                  = namedSymbol("type_parameter")
	sConstraint                     = namedSymbol("constraint")
	sDefaultType                    = namedSymbol("default_type")
	sArrayType                      = namedSymbol("array_type")
	sTupleType                      = namedSymbol("tuple_type")
	sOptionalType                   = namedSymbol("optional_type")
	sRestType                       = namedSymbol("rest_type")
	sUnionType                      = namedSymbol("union_type")
	sIntersectionType               = namedSymbol("intersection_type")
	sFunctionType                   = namedSymbol("function_type")
	sConstructorType                = namedSymbol("constructor_type")
	sParenthesizedType              = namedSymbol("parenthesized_type")
	sTypeQuery                      = namedSymbol("type_query")
	sIndexTypeQuery                 = namedSymbol("index_type_query")
	sReadonlyType                   = namedSymbol("readonly_type")
	sLookupType                     = namedSymbol("lookup_type")
	sConditionalType                = namedSymbol("conditional_type")
	sInferType                      = namedSymbol("infer_type")
	sTypePredicate                  = namedSymbol("type_predicate")
	sAsserts                        = namedSymbol("asserts")
	sImportType                     = namedSymbol("import_type")
	sTemplateLiteralType            = namedSymbol("template_literal_type")
	sTemplateType                   = namedSymbol("template_type")
	sMappedTypeClause               = namedSymbol("mapped_type_clause")
	sOmittingTypeAnnotation         = namedSymbol("omitting_type_annotation")
	sAddingTypeAnnotation           = namedSymbol("adding_type_annotation")
	sOptingTypeAnnotation           = namedSymbol("opting_type_annotation")
	sNonNullType                    = namedSymbol("non_null_type")
	aUniqueSymbol                   = anonymousSymbol("unique symbol")
	aImport                         = anonymousSymbol("import")
	aMeta                           = anonymousSymbol("meta")
	aTarget                         = anonymousSymbol("target")
	aSlashGreater                   = anonymousSymbol("/>")
	aAmpersand                      = anonymousSymbol("&")
	sJsxElement                     = namedSymbol("jsx_element")
	sJsxSelfClosingElement          = namedSymbol("jsx_self_closing_element")
	sJsxOpeningElement              = namedSymbol("jsx_opening_element")
	sJsxClosingElement              = namedSymbol("jsx_closing_element")
	sJsxIdentifier                  = namedSymbol("jsx_identifier")
	sJsxMemberExpression            = namedSymbol("jsx_member_expression")
	sJsxNamespaceName               = namedSymbol("jsx_namespace_name")
	sJsxAttribute                   = namedSymbol("jsx_attribute")
	sJsxExpression                  = namedSymbol("jsx_expression")
	sJsxText                        = namedSymbol("jsx_text")
	sHTMLCharacterReference         = namedSymbol("html_character_reference")
)

var (
	fAlias          = field("alias")
	fAlternative    = field("alternative")
	fArgument       = field("argument")
	fArguments      = field("arguments")
	fAttribute      = field("attribute")
	fBody           = field("body")
	fCondition      = field("condition")
	fConsequence    = field("consequence")
	fConstraint     = field("constraint")
	fConstructor    = field("constructor")
	fDeclaration    = field("declaration")
	fDecorator      = field("decorator")
	fFinalizer      = field("finalizer")
	fFlags          = field("flags")
	fFunction       = field("function")
	fHandler        = field("handler")
	fIncrement      = field("increment")
	fIndex          = field("index")
	fIndexType      = field("index_type")
	fInitializer    = field("initializer")
	fKey            = field("key")
	fKind           = field("kind")
	fLabel          = field("label")
	fLeft           = field("left")
	fMember         = field("member")
	fModule         = field("module")
	fName           = field("name")
	fObject         = field("object")
	fOperator       = field("operator")
	fOptionalChain  = field("optional_chain")
	fParameter      = field("parameter")
	fParameters     = field("parameters")
	fPattern        = field("pattern")
	fProperty       = field("property")
	fReturnType     = field("return_type")
	fRight          = field("right")
	fSign           = field("sign")
	fSource         = field("source")
	fType           = field("type")
	fTypeArguments  = field("type_arguments")
	fTypeParameters = field("type_parameters")
	fValue          = field("value")
	fOpenTag        = field("open_tag")
	fCloseTag       = field("close_tag")
)

// ---- statements ----

func (c *VeslintConverter) statement(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindExpressionStatement:
		c.open(c.named(sExpressionStatement), field, c.start(n))
		c.expressions(n.Expression(), 0)
		c.closeStatement(n.End())
	case ast.KindVariableStatement, ast.KindFunctionDeclaration, ast.KindClassDeclaration,
		ast.KindInterfaceDeclaration, ast.KindTypeAliasDeclaration, ast.KindEnumDeclaration,
		ast.KindModuleDeclaration, ast.KindImportEqualsDeclaration:
		c.declarationStatement(n, field)
	case ast.KindBlock:
		c.block(n, field)
	case ast.KindIfStatement:
		s := n.AsIfStatement()
		c.open(c.named(sIfStatement), field, c.start(n))
		c.tok(0)
		c.parenthesized(s.Expression, c.field(fCondition))
		c.statement(s.ThenStatement, c.field(fConsequence))
		if s.ElseStatement != nil {
			c.openNext(c.named(sElseClause), c.field(fAlternative))
			c.tok(0)
			c.statement(s.ElseStatement, 0)
			c.close(s.ElseStatement.End())
		}
		c.close(n.End())
	case ast.KindForStatement:
		s := n.AsForStatement()
		c.open(c.named(sForStatement), field, c.start(n))
		c.tok(0)
		c.tok(0)
		if s.Initializer == nil {
			c.emptyStatement(c.field(fInitializer))
		} else if s.Initializer.Kind == ast.KindVariableDeclarationList {
			// The declaration takes the `;` as its own.
			c.declarationList(s.Initializer, c.field(fInitializer), -1, true)
		} else {
			c.expressions(s.Initializer, c.field(fInitializer))
			c.tok(0)
		}
		if s.Condition == nil {
			c.emptyStatement(c.field(fCondition))
		} else {
			c.expressions(s.Condition, c.field(fCondition))
			c.tok(c.field(fCondition))
		}
		if s.Incrementor != nil {
			c.expressions(s.Incrementor, c.field(fIncrement))
		}
		c.tok(0)
		c.statement(s.Statement, c.field(fBody))
		c.close(n.End())
	case ast.KindForInStatement, ast.KindForOfStatement:
		s := n.AsForInOrOfStatement()
		c.open(c.named(sForInStatement), field, c.start(n))
		c.tok(0)
		if s.AwaitModifier != nil {
			c.tokNode(s.AwaitModifier, 0)
		}
		c.tok(0)
		if s.Initializer.Kind == ast.KindVariableDeclarationList {
			c.declarationKind(s.Initializer)
			d := s.Initializer.AsVariableDeclarationList().Declarations.Nodes[0].AsVariableDeclaration()
			c.bindingName(d.Name(), c.field(fLeft))
			if d.Initializer != nil {
				c.tok(0)
				c.expression(d.Initializer, c.field(fValue))
			}
		} else {
			c.assignmentTarget(s.Initializer, c.field(fLeft))
		}
		c.tok(c.field(fOperator))
		c.expressions(s.Expression, c.field(fRight))
		c.tok(0)
		c.statement(s.Statement, c.field(fBody))
		c.close(n.End())
	case ast.KindWhileStatement:
		s := n.AsWhileStatement()
		c.open(c.named(sWhileStatement), field, c.start(n))
		c.tok(0)
		c.parenthesized(s.Expression, c.field(fCondition))
		c.statement(s.Statement, c.field(fBody))
		c.close(n.End())
	case ast.KindDoStatement:
		s := n.AsDoStatement()
		c.open(c.named(sDoStatement), field, c.start(n))
		c.tok(0)
		c.statement(s.Statement, c.field(fBody))
		c.tok(0)
		c.parenthesized(s.Expression, c.field(fCondition))
		c.closeStatement(n.End())
	case ast.KindWithStatement:
		s := n.AsWithStatement()
		c.open(c.named(sWithStatement), field, c.start(n))
		c.tok(0)
		c.parenthesized(s.Expression, c.field(fObject))
		c.statement(s.Statement, c.field(fBody))
		c.close(n.End())
	case ast.KindReturnStatement:
		c.open(c.named(sReturnStatement), field, c.start(n))
		c.tok(0)
		if e := n.Expression(); e != nil {
			c.expressions(e, 0)
			c.closeStatement(n.End())
		} else {
			c.closeRestricted(n.End())
		}
	case ast.KindThrowStatement:
		c.open(c.named(sThrowStatement), field, c.start(n))
		c.tok(0)
		c.expressions(n.Expression(), 0)
		c.closeStatement(n.End())
	case ast.KindBreakStatement, ast.KindContinueStatement:
		symbol := c.named(sBreakStatement)
		if n.Kind == ast.KindContinueStatement {
			symbol = c.named(sContinueStatement)
		}
		label := n.Label()
		c.open(symbol, field, c.start(n))
		c.tok(0)
		if label != nil {
			c.identifier(label, c.named(sStatementIdentifier), c.field(fLabel))
			c.closeStatement(n.End())
		} else {
			c.closeRestricted(n.End())
		}
	case ast.KindDebuggerStatement:
		c.open(c.named(sDebuggerStatement), field, c.start(n))
		c.closeStatement(n.End())
	case ast.KindEmptyStatement:
		c.open(c.named(sEmptyStatement), field, c.start(n))
		c.close(n.End())
	case ast.KindLabeledStatement:
		s := n.AsLabeledStatement()
		c.open(c.named(sLabeledStatement), field, c.start(n))
		c.identifier(s.Label, c.named(sStatementIdentifier), c.field(fLabel))
		c.tok(0)
		c.statement(s.Statement, c.field(fBody))
		c.close(n.End())
	case ast.KindSwitchStatement:
		s := n.AsSwitchStatement()
		c.open(c.named(sSwitchStatement), field, c.start(n))
		c.tok(0)
		c.parenthesized(s.Expression, c.field(fValue))
		block := s.CaseBlock
		c.open(c.named(sSwitchBody), c.field(fBody), c.start(block))
		for _, clause := range block.AsCaseBlock().Clauses.Nodes {
			cc := clause.AsCaseOrDefaultClause()
			if clause.Kind == ast.KindCaseClause {
				c.open(c.named(sSwitchCase), 0, c.start(clause))
				c.tok(0)
				c.expressions(cc.Expression, c.field(fValue))
			} else {
				c.open(c.named(sSwitchDefault), 0, c.start(clause))
				c.tok(0)
			}
			c.tok(0)
			for _, st := range cc.Statements.Nodes {
				c.statement(st, c.field(fBody))
			}
			c.closeHere()
		}
		c.close(block.End())
		c.close(n.End())
	case ast.KindTryStatement:
		s := n.AsTryStatement()
		c.open(c.named(sTryStatement), field, c.start(n))
		c.tok(0)
		c.block(s.TryBlock, c.field(fBody))
		if s.CatchClause != nil {
			cl := s.CatchClause.AsCatchClause()
			c.open(c.named(sCatchClause), c.field(fHandler), c.start(s.CatchClause))
			c.tok(0)
			if cl.VariableDeclaration != nil {
				c.tok(0)
				d := cl.VariableDeclaration.AsVariableDeclaration()
				c.bindingName(d.Name(), c.field(fParameter))
				if d.Type != nil {
					c.typeAnnotation(d.Type, c.field(fType))
				}
				c.tok(0)
			}
			c.block(cl.Block, c.field(fBody))
			c.close(s.CatchClause.End())
		}
		if s.FinallyBlock != nil {
			c.openNext(c.named(sFinallyClause), c.field(fFinalizer))
			c.tok(0)
			c.block(s.FinallyBlock, c.field(fBody))
			c.close(s.FinallyBlock.End())
		}
		c.close(n.End())
	case ast.KindImportDeclaration:
		c.importDeclaration(n, field)
	case ast.KindExportDeclaration:
		c.exportDeclaration(n, field)
	case ast.KindExportAssignment:
		s := n.AsExportAssignment()
		c.open(c.named(sExportStatement), field, c.start(n))
		c.tok(0)
		if s.IsExportEquals {
			c.tok(0)
			c.expression(s.Expression, 0)
		} else {
			c.tok(0)
			c.expression(s.Expression, c.field(fValue))
		}
		c.closeStatement(n.End())
	case ast.KindNamespaceExportDeclaration:
		c.open(c.named(sExportStatement), field, c.start(n))
		c.tok(0)
		c.tok(0)
		c.tok(0)
		c.identifier(n.Name(), c.named(sIdentifier), 0)
		c.closeStatement(n.End())
	default:
		c.generic(n, field)
	}
}

// emptyStatement writes the next `;` as an empty_statement (the empty parts of a for head).
func (c *VeslintConverter) emptyStatement(field uint16) {
	c.openNext(c.named(sEmptyStatement), field)
	c.tok(0)
	c.closeHere()
}

// closeRestricted ends `return`, `break` or `continue` without an argument: the restricted
// automatic semicolon is right after the keyword, so the comments after it are the parent's.
func (c *VeslintConverter) closeRestricted(end int) {
	c.flush(end)
	c.closeHere()
}

func (c *VeslintConverter) block(n *ast.Node, field uint16) {
	c.open(c.named(sStatementBlock), field, c.start(n))
	for _, s := range n.Statements() {
		c.statement(s, 0)
	}
	c.flush(n.End())
	c.absorbComments()
	c.closeHere()
}

// parenthesized writes the `( expression )` of if, while, switch, with and do.
func (c *VeslintConverter) parenthesized(e *ast.Node, field uint16) {
	c.openNext(c.named(sParenthesizedExpression), field)
	c.tok(0)
	c.expressions(e, 0)
	c.closeAfter(ast.KindCloseParenToken)
}

// hasModifier tells whether `n` has a modifier of `kind`.
func hasModifier(n *ast.Node, kind ast.Kind) bool {
	if mods := n.Modifiers(); mods != nil {
		for _, m := range mods.Nodes {
			if m.Kind == kind {
				return true
			}
		}
	}
	return false
}

// declarationStatement writes a declaration with what tree-sitter has around it: `export`
// (export_statement, with the decorators before it) and `declare` (ambient_declaration).
func (c *VeslintConverter) declarationStatement(n *ast.Node, field uint16) {
	mods := n.Modifiers()
	exported := hasModifier(n, ast.KindExportKeyword)
	isDefault := hasModifier(n, ast.KindDefaultKeyword)
	declared := hasModifier(n, ast.KindDeclareKeyword)
	consumed := 0 // the modifiers written by the wrappers
	inner := field
	wrappers := 0
	if exported {
		c.open(c.named(sExportStatement), field, c.start(n))
		wrappers++
		for i, m := range mods.Nodes {
			if m.Kind == ast.KindDecorator {
				c.decorator(m, c.field(fDecorator))
				continue
			}
			if m.Kind == ast.KindExportKeyword {
				c.tokNode(m, 0)
				consumed = i + 1
				break
			}
			break
		}
		inner = c.field(fDeclaration)
		if isDefault && consumed < len(mods.Nodes) && mods.Nodes[consumed].Kind == ast.KindDefaultKeyword {
			c.tokNode(mods.Nodes[consumed], 0)
			consumed++
			if anonymousDefault(n) {
				inner = c.field(fValue)
			}
		}
	}
	// What follows the wrappers' modifiers starts the declaration.
	start := c.start(n)
	if consumed > 0 {
		start = scanner.SkipTrivia(c.text, mods.Nodes[consumed-1].End())
	}
	if declared && consumed < len(mods.Nodes) && mods.Nodes[consumed].Kind == ast.KindDeclareKeyword {
		c.open(c.named(sAmbientDeclaration), inner, start)
		wrappers++
		c.tokNode(mods.Nodes[consumed], 0)
		consumed++
		inner = 0
		start = scanner.SkipTrivia(c.text, mods.Nodes[consumed-1].End())
	}
	var rest []*ast.Node
	if mods != nil {
		rest = mods.Nodes[consumed:]
	}
	c.declaration(n, inner, rest, start)
	for ; wrappers > 0; wrappers-- {
		c.closeHere()
	}
}

// anonymousDefault: `export default class {}` and `export default function () {}` are a class
// and a function_expression (the value of the export), not declarations.
func anonymousDefault(n *ast.Node) bool {
	switch n.Kind {
	case ast.KindClassDeclaration, ast.KindFunctionDeclaration:
		return n.Name() == nil
	}
	return false
}

// declaration writes a declaration whose modifiers left to write are `mods`.
func (c *VeslintConverter) declaration(n *ast.Node, field uint16, mods []*ast.Node, start int) {
	switch n.Kind {
	case ast.KindVariableStatement:
		c.declarationList(n.AsVariableStatement().DeclarationList, field, n.End(), false)
	case ast.KindFunctionDeclaration:
		c.function(n, field, mods, true, start)
	case ast.KindClassDeclaration:
		c.class(n, field, mods, true, start)
	case ast.KindInterfaceDeclaration:
		s := n.AsInterfaceDeclaration()
		c.open(c.named(sInterfaceDeclaration), field, start)
		c.modifiers(mods)
		c.tok(0)
		c.identifier(s.Name(), c.named(sTypeIdentifier), c.field(fName))
		c.typeParameters(s.TypeParameters, c.field(fTypeParameters))
		if s.HeritageClauses != nil {
			for _, h := range s.HeritageClauses.Nodes {
				c.open(c.named(sExtendsTypeClause), 0, c.start(h))
				c.tok(0)
				for _, t := range h.AsHeritageClause().Types.Nodes {
					c.heritageType(t, c.field(fType))
				}
				c.close(h.End())
			}
		}
		c.objectType(s.Members, c.named(sInterfaceBody), c.field(fBody), c.peekStart())
		c.close(n.End())
	case ast.KindTypeAliasDeclaration:
		s := n.AsTypeAliasDeclaration()
		c.open(c.named(sTypeAliasDeclaration), field, start)
		c.modifiers(mods)
		c.tok(0)
		c.identifier(s.Name(), c.named(sTypeIdentifier), c.field(fName))
		c.typeParameters(s.TypeParameters, c.field(fTypeParameters))
		c.tok(0)
		c.typ(s.Type, c.field(fValue))
		c.closeStatement(n.End())
	case ast.KindEnumDeclaration:
		s := n.AsEnumDeclaration()
		c.open(c.named(sEnumDeclaration), field, start)
		c.modifiers(mods)
		c.tok(0)
		c.identifier(s.Name(), c.named(sIdentifier), c.field(fName))
		c.openNext(c.named(sEnumBody), c.field(fBody))
		c.tok(0)
		for _, m := range s.Members.Nodes {
			e := m.AsEnumMember()
			if e.Initializer == nil {
				c.propertyName(e.Name(), c.field(fName))
				continue
			}
			c.open(c.named(sEnumAssignment), 0, c.start(m))
			c.propertyName(e.Name(), c.field(fName))
			c.tok(0)
			c.expression(e.Initializer, c.field(fValue))
			c.close(m.End())
		}
		c.close(n.End())
		c.close(n.End())
	case ast.KindModuleDeclaration:
		c.module(n, field, mods, start)
	case ast.KindImportEqualsDeclaration:
		c.importEquals(n, field, mods, start)
	default:
		c.generic(n, field)
	}
}

// declarationList writes a VariableDeclarationList as lexical_declaration or
// variable_declaration, ending at `end` (-1: after its `;`, in a for statement's head).
func (c *VeslintConverter) declarationList(list *ast.Node, field uint16, end int, forHead bool) {
	symbol := c.named(sLexicalDeclaration)
	if list.Flags&ast.NodeFlagsBlockScoped == 0 {
		symbol = c.named(sVariableDeclaration)
	}
	c.open(symbol, field, c.start(list))
	c.declarationKind(list)
	for _, d := range list.AsVariableDeclarationList().Declarations.Nodes {
		c.variableDeclarator(d)
	}
	if forHead {
		c.closeAfter(ast.KindSemicolonToken)
		return
	}
	c.closeStatement(end)
}

// declarationKind writes `var`, `let`, `const`, `using` or `await using` (the field `kind` but
// on `var`).
func (c *VeslintConverter) declarationKind(list *ast.Node) {
	flags := list.Flags & (ast.NodeFlagsBlockScoped)
	switch flags {
	case 0:
		if list.Parent != nil && (list.Parent.Kind == ast.KindForInStatement || list.Parent.Kind == ast.KindForOfStatement) {
			c.tok(c.field(fKind))
		} else {
			c.tok(0)
		}
	case ast.NodeFlagsAwaitUsing:
		c.tok(c.field(fKind))
		c.tok(c.field(fKind))
	default:
		c.tok(c.field(fKind))
	}
}

func (c *VeslintConverter) variableDeclarator(n *ast.Node) {
	d := n.AsVariableDeclaration()
	c.open(c.named(sVariableDeclarator), 0, c.start(n))
	c.bindingName(d.Name(), c.field(fName))
	if d.ExclamationToken != nil {
		c.tokNode(d.ExclamationToken, 0)
	}
	if d.Type != nil {
		c.typeAnnotation(d.Type, c.field(fType))
	}
	if d.Initializer != nil {
		c.tok(0)
		c.expression(d.Initializer, c.field(fValue))
	}
	c.close(n.End())
}

// modifiers writes modifiers as tree-sitter has them: accessibility_modifier and
// override_modifier around their keyword, decorators, the others as anonymous tokens.
func (c *VeslintConverter) modifiers(mods []*ast.Node) {
	for _, m := range mods {
		c.modifier(m)
	}
}

func (c *VeslintConverter) modifier(m *ast.Node) {
	switch m.Kind {
	case ast.KindDecorator:
		c.decorator(m, c.field(fDecorator))
	case ast.KindPublicKeyword, ast.KindPrivateKeyword, ast.KindProtectedKeyword:
		c.open(c.named(sAccessibilityModifier), 0, c.start(m))
		c.tokNode(m, 0)
		c.close(m.End())
	case ast.KindOverrideKeyword:
		c.open(c.named(sOverrideModifier), 0, c.start(m))
		c.tokNode(m, 0)
		c.close(m.End())
	default:
		c.tokNode(m, 0)
	}
}

func modifierList(n *ast.Node) []*ast.Node {
	if mods := n.Modifiers(); mods != nil {
		return mods.Nodes
	}
	return nil
}

func (c *VeslintConverter) decorator(n *ast.Node, field uint16) {
	c.open(c.named(sDecorator), field, c.start(n))
	c.tok(0)
	c.expression(n.Expression(), 0)
	c.close(n.End())
}

// ---- functions ----

// function writes a function declaration or expression: function_declaration,
// generator_function_declaration, function_signature (no body), function_expression,
// generator_function.
func (c *VeslintConverter) function(n *ast.Node, field uint16, mods []*ast.Node, declaration bool, start int) {
	f := n.FunctionLikeData()
	body := n.Body()
	generator := n.BodyData().AsteriskToken != nil
	var symbol uint16
	switch {
	case body == nil:
		symbol = c.named(sFunctionSignature)
	case declaration && n.Name() != nil && generator:
		symbol = c.named(sGeneratorFunctionDeclaration)
	case declaration && n.Name() != nil:
		symbol = c.named(sFunctionDeclaration)
	case generator:
		symbol = c.named(sGeneratorFunction)
	default:
		symbol = c.named(sFunctionExpression)
	}
	c.open(symbol, field, start)
	c.modifiers(mods)
	c.tok(0) // function
	if generator {
		c.tokNode(n.BodyData().AsteriskToken, 0)
	}
	if name := n.Name(); name != nil {
		c.identifier(name, c.named(sIdentifier), c.field(fName))
	}
	c.callSignature(f.TypeParameters, f.Parameters, f.Type)
	if body != nil {
		c.block(body, c.field(fBody))
		c.closeHere()
		return
	}
	c.closeStatement(n.End())
}

// callSignature writes type_parameters, formal_parameters and the return type.
func (c *VeslintConverter) callSignature(tps *ast.NodeList, params *ast.NodeList, ret *ast.Node) {
	c.typeParameters(tps, c.field(fTypeParameters))
	c.formalParameters(params, c.field(fParameters))
	if ret != nil {
		c.returnType(ret, c.field(fReturnType))
	}
}

func (c *VeslintConverter) formalParameters(params *ast.NodeList, field uint16) {
	c.openNext(c.named(sFormalParameters), field)
	c.tok(0)
	for _, p := range params.Nodes {
		c.parameter(p)
	}
	c.closeAfter(ast.KindCloseParenToken)
}

func (c *VeslintConverter) parameter(n *ast.Node) {
	p := n.AsParameterDeclaration()
	symbol := c.named(sRequiredParameter)
	if p.QuestionToken != nil {
		symbol = c.named(sOptionalParameter)
	}
	c.open(symbol, 0, c.start(n))
	c.modifiers(modifierList(n))
	if p.DotDotDotToken != nil {
		c.open(c.named(sRestPattern), c.field(fPattern), c.start(p.DotDotDotToken))
		c.tokNode(p.DotDotDotToken, 0)
		c.bindingName(p.Name(), 0)
		c.close(p.Name().End())
	} else if p.Name().Kind == ast.KindIdentifier && p.Name().Text() == "this" {
		c.leaf(c.named(sThis), c.field(fPattern), VeslintNamed, c.start(p.Name()), p.Name().End())
	} else {
		c.bindingName(p.Name(), c.field(fPattern))
	}
	if p.QuestionToken != nil {
		c.tokNode(p.QuestionToken, 0)
	}
	if p.Type != nil {
		c.typeAnnotation(p.Type, c.field(fType))
	}
	if p.Initializer != nil {
		c.tok(0)
		c.expression(p.Initializer, c.field(fValue))
	}
	c.close(n.End())
}

// typeAnnotation writes `: T`.
func (c *VeslintConverter) typeAnnotation(t *ast.Node, field uint16) {
	c.openNext(c.named(sTypeAnnotation), field)
	c.tok(0)
	c.typ(t, 0)
	c.close(t.End())
}

// returnType writes the `: T` of a signature: type_annotation, asserts_annotation or
// type_predicate_annotation.
func (c *VeslintConverter) returnType(t *ast.Node, field uint16) {
	if t.Kind == ast.KindTypePredicate {
		p := t.AsTypePredicateNode()
		if p.AssertsModifier != nil {
			c.openNext(c.named(sAssertsAnnotation), field)
		} else {
			c.openNext(c.named(sTypePredicateAnnotation), field)
		}
		c.tok(0)
		c.typePredicate(t, 0)
		c.close(t.End())
		return
	}
	c.typeAnnotation(t, field)
}

func (c *VeslintConverter) arrowFunction(n *ast.Node, field uint16) {
	f := n.FunctionLikeData()
	c.open(c.named(sArrowFunction), field, c.start(n))
	c.modifiers(modifierList(n))
	params := f.Parameters
	if f.TypeParameters == nil && len(params.Nodes) == 1 && f.Type == nil && c.text[c.start(params.Nodes[0])] != '(' && c.start(params.Nodes[0]) == c.peekStart() {
		c.identifier(params.Nodes[0].Name(), c.named(sIdentifier), c.field(fParameter))
	} else {
		c.callSignature(f.TypeParameters, params, f.Type)
	}
	c.tokNode(n.AsArrowFunction().EqualsGreaterThanToken, 0)
	body := n.Body()
	if body.Kind == ast.KindBlock {
		c.block(body, c.field(fBody))
	} else {
		c.expression(body, c.field(fBody))
	}
	c.close(n.End())
}

func (c *VeslintConverter) peekStart() int {
	_, start, _ := c.peek()
	return start
}

// ---- classes ----

func (c *VeslintConverter) class(n *ast.Node, field uint16, mods []*ast.Node, declaration bool, start int) {
	s := n.ClassLikeData()
	symbol := c.named(sClass)
	if declaration && n.Name() != nil {
		symbol = c.named(sClassDeclaration)
		for _, m := range mods {
			if m.Kind == ast.KindAbstractKeyword {
				symbol = c.named(sAbstractClassDeclaration)
			}
		}
	}
	c.open(symbol, field, start)
	c.modifiers(mods)
	c.tok(0) // class
	if name := n.Name(); name != nil {
		c.identifier(name, c.named(sTypeIdentifier), c.field(fName))
	}
	c.typeParameters(s.TypeParameters, c.field(fTypeParameters))
	if s.HeritageClauses != nil && len(s.HeritageClauses.Nodes) > 0 {
		c.openNext(c.named(sClassHeritage), 0)
		for _, h := range s.HeritageClauses.Nodes {
			hc := h.AsHeritageClause()
			if hc.Token == ast.KindExtendsKeyword {
				c.open(c.named(sExtendsClause), 0, c.start(h))
				c.tok(0)
				for _, t := range hc.Types.Nodes {
					if t.Kind == ast.KindTypeReference {
						r := t.AsTypeReferenceNode()
						c.entityAsExpression(r.TypeName, c.field(fValue))
						c.typeArguments(r.TypeArguments, c.field(fTypeArguments))
						continue
					}
					e := t.AsExpressionWithTypeArguments()
					c.expression(e.Expression, c.field(fValue))
					c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
				}
			} else {
				c.open(c.named(sImplementsClause), 0, c.start(h))
				c.tok(0)
				for _, t := range hc.Types.Nodes {
					c.heritageType(t, 0)
				}
			}
			c.close(h.End())
		}
		c.closeHere()
	}
	c.openNext(c.named(sClassBody), c.field(fBody))
	c.tok(0)
	for _, m := range s.Members.Nodes {
		c.classMember(m)
	}
	c.closeAfter(ast.KindCloseBraceToken)
	if symbol != c.named(sClass) {
		// class_declaration ends with an optional automatic semicolon.
		c.absorbComments()
	}
	c.closeHere()
}

// heritageType writes an ExpressionWithTypeArguments of `implements` or of an interface's
// `extends` as a type: type_identifier, nested_type_identifier or generic_type.
func (c *VeslintConverter) heritageType(t *ast.Node, field uint16) {
	if t.Kind == ast.KindTypeReference {
		// 7.1 parses the types of `implements` and of an interface's `extends` as TypeReference.
		c.typ(t, field)
		return
	}
	e := t.AsExpressionWithTypeArguments()
	if e.TypeArguments != nil {
		c.open(c.named(sGenericType), field, c.start(t))
		c.entityName(e.Expression, c.field(fName), true)
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		c.close(t.End())
		return
	}
	c.entityName(e.Expression, field, true)
}

// entityName writes A or A.B.C (an identifier or a property access, or a QualifiedName) as a
// type name (type_identifier, nested_type_identifier) or, with asType false, as
// nested_identifier.
func (c *VeslintConverter) entityName(n *ast.Node, field uint16, asType bool) {
	switch n.Kind {
	case ast.KindIdentifier:
		if asType {
			c.identifier(n, c.named(sTypeIdentifier), field)
		} else {
			c.identifier(n, c.named(sIdentifier), field)
		}
	case ast.KindPropertyAccessExpression, ast.KindQualifiedName:
		var left, right *ast.Node
		if n.Kind == ast.KindQualifiedName {
			q := n.AsQualifiedName()
			left, right = q.Left, q.Right
		} else {
			p := n.AsPropertyAccessExpression()
			left, right = p.Expression, p.Name()
		}
		if asType {
			c.open(c.named(sNestedTypeIdentifier), field, c.start(n))
			c.entityName(left, c.field(fModule), false)
			c.tok(0)
			c.identifier(right, c.named(sTypeIdentifier), c.field(fName))
		} else {
			c.open(c.named(sNestedIdentifier), field, c.start(n))
			c.entityAsExpression(left, c.field(fObject))
			c.tok(0)
			c.identifier(right, c.named(sPropertyIdentifier), c.field(fProperty))
		}
		c.close(n.End())
	default:
		c.expression(n, field)
	}
}

// entityAsExpression writes A.B (a QualifiedName) as the member_expression it is in an
// expression.
func (c *VeslintConverter) entityAsExpression(n *ast.Node, field uint16) {
	if n.Kind != ast.KindQualifiedName {
		c.expression(n, field)
		return
	}
	q := n.AsQualifiedName()
	c.open(c.named(sMemberExpression), field, c.start(n))
	c.entityAsExpression(q.Left, c.field(fObject))
	c.tok(0)
	c.propertyName(q.Right, c.field(fProperty))
	c.close(n.End())
}

func (c *VeslintConverter) classMember(m *ast.Node) {
	mods := modifierList(m)
	switch m.Kind {
	case ast.KindSemicolonClassElement:
		c.tok(0)
	case ast.KindPropertyDeclaration:
		p := m.AsPropertyDeclaration()
		c.open(c.named(sPublicFieldDefinition), 0, c.start(m))
		c.modifiers(mods)
		c.propertyName(p.Name(), c.field(fName))
		if p.PostfixToken != nil {
			c.tokNode(p.PostfixToken, 0)
		}
		if p.Type != nil {
			c.typeAnnotation(p.Type, c.field(fType))
		}
		if p.Initializer != nil {
			c.tok(0)
			c.expression(p.Initializer, c.field(fValue))
		}
		c.closeHere()
	case ast.KindMethodDeclaration, ast.KindConstructor, ast.KindGetAccessor, ast.KindSetAccessor:
		// The decorators of a method are the class body's.
		i := 0
		for i < len(mods) && mods[i].Kind == ast.KindDecorator {
			c.decorator(mods[i], c.field(fDecorator))
			i++
		}
		c.method(m, 0, mods[i:])
	case ast.KindClassStaticBlockDeclaration:
		c.open(c.named(sClassStaticBlock), 0, c.start(m))
		c.tok(0)
		c.block(m.AsClassStaticBlockDeclaration().Body, c.field(fBody))
		c.close(m.End())
	case ast.KindIndexSignature:
		c.indexSignature(m, mods)
	default:
		c.generic(m, 0)
	}
}

// method writes a method, constructor or accessor of a class or object literal:
// method_definition, or method_signature / abstract_method_signature without a body.
func (c *VeslintConverter) method(m *ast.Node, field uint16, mods []*ast.Node) {
	f := m.FunctionLikeData()
	body := m.Body()
	symbol := c.named(sMethodDefinition)
	if body == nil {
		symbol = c.named(sMethodSignature)
		for _, mod := range mods {
			if mod.Kind == ast.KindAbstractKeyword {
				symbol = c.named(sAbstractMethodSignature)
			}
		}
	}
	// After the decorators the class body takes, the method starts at its first modifier or
	// at its name.
	start := c.start(m)
	if len(mods) > 0 {
		start = c.start(mods[0])
	} else if all := modifierList(m); len(all) > 0 {
		start = scanner.SkipTrivia(c.text, all[len(all)-1].End())
	}
	c.open(symbol, field, start)
	c.modifiers(mods)
	switch m.Kind {
	case ast.KindGetAccessor, ast.KindSetAccessor:
		c.tok(0)
	case ast.KindMethodDeclaration:
		if a := m.BodyData().AsteriskToken; a != nil {
			c.tokNode(a, 0)
		}
	}
	if m.Kind == ast.KindConstructor {
		// `constructor` (or "constructor") is the name.
		k, start, end := c.peek()
		if k == ast.KindStringLiteral {
			c.str(start, end, c.field(fName))
		} else {
			c.leaf(c.named(sPropertyIdentifier), c.field(fName), VeslintNamed, start, end)
		}
	} else {
		c.propertyName(m.Name(), c.field(fName))
	}
	if q := m.QuestionToken(); q != nil {
		c.tokNode(q, 0)
	}
	c.callSignature(f.TypeParameters, f.Parameters, f.Type)
	if body != nil {
		c.block(body, c.field(fBody))
		c.close(body.End())
		return
	}
	c.closeHere()
}

func (c *VeslintConverter) indexSignature(m *ast.Node, mods []*ast.Node) {
	s := m.AsIndexSignatureDeclaration()
	c.open(c.named(sIndexSignature), 0, c.start(m))
	c.modifiers(mods)
	c.tok(0) // [
	for _, p := range s.Parameters.Nodes {
		pd := p.AsParameterDeclaration()
		c.identifier(pd.Name(), c.named(sIdentifier), c.field(fName))
		c.tok(0)
		c.typ(pd.Type, c.field(fIndexType))
	}
	c.tok(0) // ]
	if s.Type != nil {
		c.typeAnnotation(s.Type, c.field(fType))
	}
	c.closeHere()
}

// propertyName writes a property name: property_identifier, private_property_identifier,
// string, number or computed_property_name.
func (c *VeslintConverter) propertyName(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindIdentifier:
		c.identifier(n, c.named(sPropertyIdentifier), field)
	case ast.KindPrivateIdentifier:
		c.identifier(n, c.named(sPrivatePropertyIdentifier), field)
	case ast.KindComputedPropertyName:
		c.open(c.named(sComputedPropertyName), field, c.start(n))
		c.tok(0)
		c.expression(n.Expression(), 0)
		c.close(n.End())
	default:
		c.expression(n, field)
	}
}

// ---- modules ----

func (c *VeslintConverter) module(n *ast.Node, field uint16, mods []*ast.Node, start int) {
	s := n.AsModuleDeclaration()
	if s.Keyword == ast.KindGlobalKeyword {
		// `declare global {}` is ambient_declaration(declare global statement_block); a bare
		// `global {}` the same without `declare`.
		if field == 0 && len(c.stack) > 0 && c.rows[c.top().index].Symbol == c.named(sAmbientDeclaration) {
			c.tok(0)
			c.moduleBody(n.Body(), 0)
			return
		}
		c.open(c.named(sAmbientDeclaration), field, start)
		c.modifiers(mods)
		c.tok(0)
		c.moduleBody(n.Body(), 0)
		c.closeHere()
		return
	}
	symbol := c.named(sModule)
	if s.Keyword == ast.KindNamespaceKeyword {
		symbol = c.named(sInternalModule)
	}
	c.open(symbol, field, start)
	c.modifiers(mods)
	c.tok(0)
	// namespace A.B.C {} is nested ModuleDeclarations in TypeScript, one nested_identifier here.
	name := n.Name()
	body := n.Body()
	if body != nil && body.Kind == ast.KindModuleDeclaration {
		parts := []*ast.Node{name}
		for body != nil && body.Kind == ast.KindModuleDeclaration {
			parts = append(parts, body.Name())
			body = body.Body()
		}
		c.nestedIdentifier(parts, c.field(fName))
	} else if name.Kind == ast.KindStringLiteral {
		c.expression(name, c.field(fName))
	} else {
		c.identifier(name, c.named(sIdentifier), c.field(fName))
	}
	if body != nil {
		c.moduleBody(body, c.field(fBody))
	}
	c.closeHere()
}

func (c *VeslintConverter) nestedIdentifier(parts []*ast.Node, field uint16) {
	if len(parts) == 1 {
		c.identifier(parts[0], c.named(sIdentifier), field)
		return
	}
	c.open(c.named(sNestedIdentifier), field, c.start(parts[0]))
	c.memberChain(parts[:len(parts)-1], c.field(fObject))
	c.tok(0)
	last := parts[len(parts)-1]
	c.identifier(last, c.named(sPropertyIdentifier), c.field(fProperty))
	c.close(last.End())
}

// memberChain writes A.B.C, the object of a nested_identifier, as member_expressions.
func (c *VeslintConverter) memberChain(parts []*ast.Node, field uint16) {
	if len(parts) == 1 {
		c.identifier(parts[0], c.named(sIdentifier), field)
		return
	}
	c.open(c.named(sMemberExpression), field, c.start(parts[0]))
	c.memberChain(parts[:len(parts)-1], c.field(fObject))
	c.tok(0)
	last := parts[len(parts)-1]
	c.identifier(last, c.named(sPropertyIdentifier), c.field(fProperty))
	c.close(last.End())
}

func (c *VeslintConverter) moduleBody(body *ast.Node, field uint16) {
	c.open(c.named(sStatementBlock), field, c.start(body))
	for _, s := range body.Statements() {
		c.statement(s, 0)
	}
	c.flush(body.End())
	c.absorbComments()
	c.closeHere()
}

func (c *VeslintConverter) importDeclaration(n *ast.Node, field uint16) {
	s := n.AsImportDeclaration()
	c.open(c.named(sImportStatement), field, c.start(n))
	c.tok(0)
	if s.ImportClause != nil {
		ic := s.ImportClause.AsImportClause()
		if ic.IsTypeOnly() {
			c.tok(0)
		}
		c.openNext(c.named(sImportClause), 0)
		if ic.Name() != nil {
			c.identifier(ic.Name(), c.named(sIdentifier), 0)
		}
		if nb := ic.NamedBindings; nb != nil {
			if nb.Kind == ast.KindNamespaceImport {
				c.open(c.named(sNamespaceImport), 0, c.start(nb))
				c.tok(0)
				c.tok(0)
				c.identifier(nb.Name(), c.named(sIdentifier), 0)
				c.close(nb.End())
			} else {
				c.open(c.named(sNamedImports), 0, c.start(nb))
				c.tok(0)
				for _, e := range nb.AsNamedImports().Elements.Nodes {
					sp := e.AsImportSpecifier()
					c.open(c.named(sImportSpecifier), 0, c.start(e))
					if sp.IsTypeOnly {
						c.tok(0)
					}
					if sp.PropertyName != nil {
						c.moduleExportName(sp.PropertyName, c.field(fName))
						c.tok(0)
						c.identifier(sp.Name(), c.named(sIdentifier), c.field(fAlias))
					} else {
						c.identifier(sp.Name(), c.named(sIdentifier), c.field(fName))
					}
					c.close(e.End())
				}
				c.close(nb.End())
			}
		}
		c.close(s.ImportClause.End())
		c.tok(0) // from
	}
	c.expression(s.ModuleSpecifier, c.field(fSource))
	if s.Attributes != nil {
		c.importAttributes(s.Attributes)
	}
	c.closeStatement(n.End())
}

func (c *VeslintConverter) moduleExportName(n *ast.Node, field uint16) {
	if n.Kind == ast.KindStringLiteral {
		c.expression(n, field)
		return
	}
	c.identifier(n, c.named(sIdentifier), field)
}

func (c *VeslintConverter) importAttributes(n *ast.Node) {
	a := n.AsImportAttributes()
	c.open(c.named(sImportAttribute), 0, c.start(n))
	c.tok(0) // with / assert
	c.openNext(c.named(sObject), 0)
	c.tok(0)
	for _, at := range a.Attributes.Nodes {
		ia := at.AsImportAttribute()
		c.open(c.named(sPair), 0, c.start(at))
		c.propertyName(ia.Name(), c.field(fKey))
		c.tok(0)
		c.expression(ia.Value, c.field(fValue))
		c.close(at.End())
	}
	c.closeAfter(ast.KindCloseBraceToken)
	c.close(n.End())
}

func (c *VeslintConverter) exportDeclaration(n *ast.Node, field uint16) {
	s := n.AsExportDeclaration()
	c.open(c.named(sExportStatement), field, c.start(n))
	c.tok(0)
	if s.IsTypeOnly {
		c.tok(0)
	}
	switch {
	case s.ExportClause == nil:
		c.tok(0) // *
	case s.ExportClause.Kind == ast.KindNamespaceExport:
		e := s.ExportClause
		c.open(c.named(sNamespaceExport), 0, c.start(e))
		c.tok(0)
		c.tok(0)
		c.moduleExportName(e.Name(), 0)
		c.close(e.End())
	default:
		e := s.ExportClause
		c.open(c.named(sExportClause), 0, c.start(e))
		c.tok(0)
		for _, sp := range e.AsNamedExports().Elements.Nodes {
			es := sp.AsExportSpecifier()
			c.open(c.named(sExportSpecifier), 0, c.start(sp))
			if es.IsTypeOnly {
				c.tok(0)
			}
			if es.PropertyName != nil {
				c.moduleExportName(es.PropertyName, c.field(fName))
				c.tok(0)
				c.moduleExportName(es.Name(), c.field(fAlias))
			} else {
				c.moduleExportName(es.Name(), c.field(fName))
			}
			c.close(sp.End())
		}
		c.close(e.End())
	}
	if s.ModuleSpecifier != nil {
		c.tok(0)
		c.expression(s.ModuleSpecifier, c.field(fSource))
	}
	if s.Attributes != nil {
		c.importAttributes(s.Attributes)
	}
	c.closeStatement(n.End())
}

// importEquals writes `import x = require('m')` (import_statement with import_require_clause)
// and `import x = A.B` (import_alias).
func (c *VeslintConverter) importEquals(n *ast.Node, field uint16, mods []*ast.Node, start int) {
	s := n.AsImportEqualsDeclaration()
	ref := s.ModuleReference
	if ref.Kind == ast.KindExternalModuleReference {
		c.open(c.named(sImportStatement), field, start)
		c.modifiers(mods)
		c.tok(0)
		if s.IsTypeOnly {
			c.tok(0)
		}
		c.open(c.named(sImportRequireClause), 0, c.start(s.Name()))
		c.identifier(s.Name(), c.named(sIdentifier), 0)
		c.tok(0)
		c.tok(0)
		c.tok(0)
		c.expression(ref.Expression(), c.field(fSource))
		c.close(ref.End())
		c.closeStatement(n.End())
		return
	}
	c.open(c.named(sImportAlias), field, start)
	c.modifiers(mods)
	c.tok(0)
	if s.IsTypeOnly {
		c.tok(0)
	}
	c.identifier(s.Name(), c.named(sIdentifier), 0)
	c.tok(0)
	c.entityName(ref, 0, false)
	c.closeStatement(n.End())
}

// ---- expressions ----

// expressions writes an expression where tree-sitter allows a sequence_expression.
func (c *VeslintConverter) expressions(n *ast.Node, field uint16) {
	c.expression(n, field)
}

// identifier writes an identifier as `symbol`.
func (c *VeslintConverter) identifier(n *ast.Node, symbol, field uint16) {
	c.leaf(symbol, field, VeslintNamed, c.start(n), n.End())
}

func (c *VeslintConverter) expression(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindIdentifier:
		symbol := c.named(sIdentifier)
		if n.Text() == "undefined" {
			symbol = c.named(sUndefined)
		}
		c.identifier(n, symbol, field)
	case ast.KindPrivateIdentifier:
		c.identifier(n, c.named(sPrivatePropertyIdentifier), field)
	case ast.KindThisKeyword:
		c.identifier(n, c.named(sThis), field)
	case ast.KindSuperKeyword:
		c.identifier(n, c.named(sSuper), field)
	case ast.KindTrueKeyword:
		c.identifier(n, c.named(sTrue), field)
	case ast.KindFalseKeyword:
		c.identifier(n, c.named(sFalse), field)
	case ast.KindNullKeyword:
		c.identifier(n, c.named(sNull), field)
	case ast.KindNumericLiteral, ast.KindBigIntLiteral:
		c.identifier(n, c.named(sNumber), field)
	case ast.KindStringLiteral:
		c.str(c.start(n), n.End(), field)
	case ast.KindNoSubstitutionTemplateLiteral, ast.KindTemplateExpression:
		c.template(n, field)
	case ast.KindRegularExpressionLiteral:
		c.regex(n, field)
	case ast.KindParenthesizedExpression:
		c.open(c.named(sParenthesizedExpression), field, c.start(n))
		c.tok(0)
		c.expressions(n.Expression(), 0)
		c.close(n.End())
	case ast.KindBinaryExpression:
		c.binary(n, field)
	case ast.KindPrefixUnaryExpression:
		e := n.AsPrefixUnaryExpression()
		if e.Operator == ast.KindPlusPlusToken || e.Operator == ast.KindMinusMinusToken {
			c.open(c.named(sUpdateExpression), field, c.start(n))
			c.tok(c.field(fOperator))
			c.expression(e.Operand, c.field(fArgument))
		} else {
			c.open(c.named(sUnaryExpression), field, c.start(n))
			c.tok(c.field(fOperator))
			c.expression(e.Operand, c.field(fArgument))
		}
		c.close(n.End())
	case ast.KindPostfixUnaryExpression:
		e := n.AsPostfixUnaryExpression()
		c.open(c.named(sUpdateExpression), field, c.start(n))
		c.expression(e.Operand, c.field(fArgument))
		c.tok(c.field(fOperator))
		c.close(n.End())
	case ast.KindTypeOfExpression, ast.KindVoidExpression, ast.KindDeleteExpression:
		c.open(c.named(sUnaryExpression), field, c.start(n))
		c.tok(c.field(fOperator))
		c.expression(n.Expression(), c.field(fArgument))
		c.close(n.End())
	case ast.KindAwaitExpression:
		c.open(c.named(sAwaitExpression), field, c.start(n))
		c.tok(0)
		c.expression(n.Expression(), 0)
		c.close(n.End())
	case ast.KindYieldExpression:
		e := n.AsYieldExpression()
		c.open(c.named(sYieldExpression), field, c.start(n))
		c.tok(0)
		if e.AsteriskToken != nil {
			c.tokNode(e.AsteriskToken, 0)
		}
		if e.Expression != nil {
			c.expression(e.Expression, 0)
		}
		c.close(n.End())
	case ast.KindConditionalExpression:
		e := n.AsConditionalExpression()
		c.open(c.named(sTernaryExpression), field, c.start(n))
		c.expression(e.Condition, c.field(fCondition))
		c.tokNode(e.QuestionToken, 0)
		c.expression(e.WhenTrue, c.field(fConsequence))
		c.tokNode(e.ColonToken, 0)
		c.expression(e.WhenFalse, c.field(fAlternative))
		c.close(n.End())
	case ast.KindCallExpression:
		e := n.AsCallExpression()
		c.open(c.named(sCallExpression), field, c.start(n))
		if e.Expression.Kind == ast.KindImportKeyword {
			c.open(c.named(sImport), c.field(fFunction), c.start(e.Expression))
			c.tok(0)
			c.close(e.Expression.End())
		} else {
			c.expression(e.Expression, c.field(fFunction))
		}
		if e.QuestionDotToken != nil {
			c.tokNode(e.QuestionDotToken, 0)
		}
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		c.arguments(e.Arguments, c.field(fArguments))
		c.close(n.End())
	case ast.KindNewExpression:
		e := n.AsNewExpression()
		c.open(c.named(sNewExpression), field, c.start(n))
		c.tok(0)
		c.expression(e.Expression, c.field(fConstructor))
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		if e.Arguments != nil {
			c.arguments(e.Arguments, c.field(fArguments))
		}
		c.close(n.End())
	case ast.KindTaggedTemplateExpression:
		e := n.AsTaggedTemplateExpression()
		c.open(c.named(sCallExpression), field, c.start(n))
		c.expression(e.Tag, c.field(fFunction))
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		c.template(e.Template, c.field(fArguments))
		c.close(n.End())
	case ast.KindPropertyAccessExpression:
		e := n.AsPropertyAccessExpression()
		c.open(c.named(sMemberExpression), field, c.start(n))
		c.expression(e.Expression, c.field(fObject))
		if e.QuestionDotToken != nil {
			c.open(c.named(sOptionalChain), c.field(fOptionalChain), c.start(e.QuestionDotToken))
			c.tokNode(e.QuestionDotToken, 0)
			c.close(e.QuestionDotToken.End())
		} else {
			c.tok(0)
		}
		c.propertyName(e.Name(), c.field(fProperty))
		c.close(n.End())
	case ast.KindElementAccessExpression:
		e := n.AsElementAccessExpression()
		c.open(c.named(sSubscriptExpression), field, c.start(n))
		c.expression(e.Expression, c.field(fObject))
		if e.QuestionDotToken != nil {
			c.open(c.named(sOptionalChain), c.field(fOptionalChain), c.start(e.QuestionDotToken))
			c.tokNode(e.QuestionDotToken, 0)
			c.close(e.QuestionDotToken.End())
		}
		c.tok(0)
		c.expressions(e.ArgumentExpression, c.field(fIndex))
		c.close(n.End())
	case ast.KindNonNullExpression:
		c.open(c.named(sNonNullExpression), field, c.start(n))
		c.expression(n.Expression(), 0)
		c.close(n.End())
	case ast.KindAsExpression, ast.KindSatisfiesExpression:
		symbol := c.named(sAsExpression)
		if n.Kind == ast.KindSatisfiesExpression {
			symbol = c.named(sSatisfiesExpression)
		}
		c.open(symbol, field, c.start(n))
		c.expression(n.Expression(), 0)
		c.tok(0)
		t := n.Type()
		if t.Kind == ast.KindTypeReference && t.AsTypeReferenceNode().TypeName.Kind == ast.KindIdentifier && t.AsTypeReferenceNode().TypeName.Text() == "const" && t.AsTypeReferenceNode().TypeArguments == nil {
			c.tok(0)
		} else {
			c.typ(t, 0)
		}
		c.close(n.End())
	case ast.KindTypeAssertionExpression:
		e := n.AsTypeAssertion()
		c.open(c.named(sTypeAssertion), field, c.start(n))
		c.openNext(c.named(sTypeArguments), 0)
		c.tok(0)
		c.typ(e.Type, 0)
		c.closeAfter(ast.KindGreaterThanToken)
		c.expression(e.Expression, 0)
		c.close(n.End())
	case ast.KindExpressionWithTypeArguments:
		e := n.AsExpressionWithTypeArguments()
		c.open(c.named(sInstantiationExpression), field, c.start(n))
		c.expression(e.Expression, 0)
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		c.close(n.End())
	case ast.KindMetaProperty:
		c.open(c.named(sMetaProperty), field, c.start(n))
		c.tok(0)
		c.tok(0)
		name := n.Name()
		symbol := c.anonymous(aMeta)
		if name.Text() == "target" {
			symbol = c.anonymous(aTarget)
		}
		c.leaf(symbol, 0, 0, c.start(name), name.End())
		c.close(n.End())
	case ast.KindJsxElement, ast.KindJsxSelfClosingElement, ast.KindJsxFragment:
		c.jsx(n, field)
	case ast.KindSpreadElement:
		c.open(c.named(sSpreadElement), field, c.start(n))
		c.tok(0)
		c.expression(n.Expression(), 0)
		c.close(n.End())
	case ast.KindArrayLiteralExpression:
		c.open(c.named(sArray), field, c.start(n))
		c.tok(0)
		for _, e := range n.Elements() {
			if e.Kind == ast.KindOmittedExpression {
				continue
			}
			c.expression(e, 0)
		}
		c.close(n.End())
	case ast.KindObjectLiteralExpression:
		c.object(n, field)
	case ast.KindFunctionExpression:
		c.function(n, field, modifierList(n), false, c.start(n))
	case ast.KindArrowFunction:
		c.arrowFunction(n, field)
	case ast.KindClassExpression:
		c.class(n, field, modifierList(n), false, c.start(n))
	default:
		c.generic(n, field)
	}
}

func (c *VeslintConverter) arguments(args *ast.NodeList, field uint16) {
	c.openNext(c.named(sArguments), field)
	c.tok(0)
	for _, a := range args.Nodes {
		c.expression(a, 0)
	}
	c.closeAfter(ast.KindCloseParenToken)
}

func (c *VeslintConverter) binary(n *ast.Node, field uint16) {
	e := n.AsBinaryExpression()
	op := e.OperatorToken.Kind
	switch {
	case op == ast.KindCommaToken:
		// tree-sitter's sequence_expression is flat: a, b, c.
		c.open(c.named(sSequenceExpression), field, c.start(n))
		c.sequence(n)
		c.close(n.End())
	case op == ast.KindEqualsToken:
		c.open(c.named(sAssignmentExpression), field, c.start(n))
		c.assignmentTarget(e.Left, c.field(fLeft))
		c.tokNode(e.OperatorToken, 0)
		c.expression(e.Right, c.field(fRight))
		c.close(n.End())
	case ast.IsCompoundAssignment(op):
		c.open(c.named(sAugmentedAssignmentExpression), field, c.start(n))
		c.expression(e.Left, c.field(fLeft))
		c.tokNode(e.OperatorToken, c.field(fOperator))
		c.expression(e.Right, c.field(fRight))
		c.close(n.End())
	default:
		c.open(c.named(sBinaryExpression), field, c.start(n))
		c.expression(e.Left, c.field(fLeft))
		c.tokNode(e.OperatorToken, c.field(fOperator))
		c.expression(e.Right, c.field(fRight))
		c.close(n.End())
	}
}

func (c *VeslintConverter) sequence(n *ast.Node) {
	if n.Kind == ast.KindBinaryExpression && n.AsBinaryExpression().OperatorToken.Kind == ast.KindCommaToken {
		e := n.AsBinaryExpression()
		c.sequence(e.Left)
		c.tokNode(e.OperatorToken, 0)
		c.expression(e.Right, 0)
		return
	}
	c.expression(n, 0)
}

// assignmentTarget writes the left side of `=` or of for-in/of: object and array literals are
// patterns there.
func (c *VeslintConverter) assignmentTarget(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindObjectLiteralExpression:
		c.open(c.named(sObjectPattern), field, c.start(n))
		c.tok(0)
		for _, p := range n.Properties() {
			switch p.Kind {
			case ast.KindPropertyAssignment:
				pa := p.AsPropertyAssignment()
				c.open(c.named(sPairPattern), 0, c.start(p))
				c.propertyName(pa.Name(), c.field(fKey))
				c.tok(0)
				c.patternElement(pa.Initializer, c.field(fValue))
				c.close(p.End())
			case ast.KindShorthandPropertyAssignment:
				sp := p.AsShorthandPropertyAssignment()
				if sp.ObjectAssignmentInitializer != nil {
					c.open(c.named(sObjectAssignmentPattern), 0, c.start(p))
					c.identifier(sp.Name(), c.named(sShorthandPropertyIdentifierPat), c.field(fLeft))
					c.tok(0)
					c.expression(sp.ObjectAssignmentInitializer, c.field(fRight))
					c.close(p.End())
				} else {
					c.identifier(sp.Name(), c.named(sShorthandPropertyIdentifierPat), 0)
				}
			case ast.KindSpreadAssignment:
				c.open(c.named(sRestPattern), 0, c.start(p))
				c.tok(0)
				c.assignmentTarget(p.Expression(), 0)
				c.close(p.End())
			default:
				c.generic(p, 0)
			}
		}
		c.close(n.End())
	case ast.KindArrayLiteralExpression:
		c.open(c.named(sArrayPattern), field, c.start(n))
		c.tok(0)
		for _, e := range n.Elements() {
			switch e.Kind {
			case ast.KindOmittedExpression:
			case ast.KindSpreadElement:
				c.open(c.named(sRestPattern), 0, c.start(e))
				c.tok(0)
				c.assignmentTarget(e.Expression(), 0)
				c.close(e.End())
			default:
				c.patternElement(e, 0)
			}
		}
		c.close(n.End())
	default:
		c.expression(n, field)
	}
}

// patternElement writes an element of an assignment pattern: `x = 1` is assignment_pattern.
func (c *VeslintConverter) patternElement(n *ast.Node, field uint16) {
	if n.Kind == ast.KindBinaryExpression && n.AsBinaryExpression().OperatorToken.Kind == ast.KindEqualsToken {
		e := n.AsBinaryExpression()
		c.open(c.named(sAssignmentPattern), field, c.start(n))
		c.assignmentTarget(e.Left, c.field(fLeft))
		c.tokNode(e.OperatorToken, 0)
		c.expression(e.Right, c.field(fRight))
		c.close(n.End())
		return
	}
	c.assignmentTarget(n, field)
}

// bindingName writes the name of a declaration or parameter: an identifier or a binding
// pattern.
func (c *VeslintConverter) bindingName(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindObjectBindingPattern:
		c.open(c.named(sObjectPattern), field, c.start(n))
		c.tok(0)
		for _, e := range n.AsBindingPattern().Elements.Nodes {
			b := e.AsBindingElement()
			switch {
			case b.DotDotDotToken != nil:
				c.open(c.named(sRestPattern), 0, c.start(e))
				c.tokNode(b.DotDotDotToken, 0)
				c.bindingName(b.Name(), 0)
				c.close(e.End())
			case b.PropertyName != nil:
				c.open(c.named(sPairPattern), 0, c.start(e))
				c.propertyName(b.PropertyName, c.field(fKey))
				c.tok(0)
				c.bindingWithDefault(b.Name(), b.Initializer, c.field(fValue))
				c.close(e.End())
			case b.Initializer != nil:
				c.open(c.named(sObjectAssignmentPattern), 0, c.start(e))
				c.identifier(b.Name(), c.named(sShorthandPropertyIdentifierPat), c.field(fLeft))
				c.tok(0)
				c.expression(b.Initializer, c.field(fRight))
				c.close(e.End())
			default:
				c.identifier(b.Name(), c.named(sShorthandPropertyIdentifierPat), 0)
			}
		}
		c.close(n.End())
	case ast.KindArrayBindingPattern:
		c.open(c.named(sArrayPattern), field, c.start(n))
		c.tok(0)
		for _, e := range n.AsBindingPattern().Elements.Nodes {
			if e.Kind == ast.KindOmittedExpression {
				continue
			}
			b := e.AsBindingElement()
			switch {
			case b.Name() == nil:
				// A hole (7.1 writes it as an empty BindingElement).
			case b.DotDotDotToken != nil:
				c.open(c.named(sRestPattern), 0, c.start(e))
				c.tokNode(b.DotDotDotToken, 0)
				c.bindingName(b.Name(), 0)
				c.close(e.End())
			default:
				c.bindingWithDefault(b.Name(), b.Initializer, 0)
			}
		}
		c.close(n.End())
	default:
		c.identifier(n, c.named(sIdentifier), field)
	}
}

func (c *VeslintConverter) bindingWithDefault(name, init *ast.Node, field uint16) {
	if init == nil {
		c.bindingName(name, field)
		return
	}
	c.open(c.named(sAssignmentPattern), field, c.start(name))
	c.bindingName(name, c.field(fLeft))
	c.tok(0)
	c.expression(init, c.field(fRight))
	c.close(init.End())
}

func (c *VeslintConverter) object(n *ast.Node, field uint16) {
	c.open(c.named(sObject), field, c.start(n))
	c.tok(0)
	for _, p := range n.Properties() {
		switch p.Kind {
		case ast.KindPropertyAssignment:
			pa := p.AsPropertyAssignment()
			c.open(c.named(sPair), 0, c.start(p))
			c.propertyName(pa.Name(), c.field(fKey))
			c.tok(0)
			c.expression(pa.Initializer, c.field(fValue))
			c.close(p.End())
		case ast.KindShorthandPropertyAssignment:
			c.identifier(p.Name(), c.named(sShorthandPropertyIdentifier), 0)
		case ast.KindSpreadAssignment:
			c.open(c.named(sSpreadElement), 0, c.start(p))
			c.tok(0)
			c.expression(p.Expression(), 0)
			c.close(p.End())
		case ast.KindMethodDeclaration, ast.KindGetAccessor, ast.KindSetAccessor:
			c.method(p, 0, modifierList(p))
		default:
			c.generic(p, 0)
		}
	}
	c.close(n.End())
}

// str writes a string literal: its quotes, string_fragment and escape_sequence.
func (c *VeslintConverter) str(start, end int, field uint16) {
	c.open(c.named(sString), field, start)
	quote := c.text[start : start+1]
	c.leaf(c.l.quote(quote), 0, 0, start, start+1)
	c.stringPieces(start+1, end-1, false)
	c.leaf(c.l.quote(quote), 0, 0, end-1, end)
	c.close(end)
}

// stringPieces writes the text of a string or template between `from` and `to` as
// string_fragment and escape_sequence rows.
func (c *VeslintConverter) stringPieces(from, to int, template bool) {
	fragment := from
	for i := from; i < to; {
		if c.text[i] != '\\' {
			i++
			continue
		}
		if fragment < i {
			c.leaf(c.named(sStringFragment), 0, VeslintNamed, fragment, i)
		}
		e := escapeEnd(c.text, i, to)
		c.leaf(c.named(sEscapeSequence), 0, VeslintNamed, i, e)
		i = e
		fragment = e
	}
	if fragment < to {
		c.leaf(c.named(sStringFragment), 0, VeslintNamed, fragment, to)
	}
}

// escapeEnd is where tree-sitter's escape_sequence that starts at text[i] (a backslash) ends.
func escapeEnd(text string, i, to int) int {
	j := i + 1
	if j >= to {
		return to
	}
	ch := text[j]
	switch {
	case ch >= '0' && ch <= '7':
		k := j
		for k < to && k < j+3 && text[k] >= '0' && text[k] <= '7' {
			k++
		}
		return k
	case ch == 'x':
		return min(j+3, to)
	case ch == 'u':
		if j+1 < to && text[j+1] == '{' {
			k := strings.IndexByte(text[j:to], '}')
			if k >= 0 {
				return j + k + 1
			}
			return to
		}
		return min(j+5, to)
	case ch == '\r':
		if j+1 < to && text[j+1] == '\n' {
			return j + 2
		}
		return j + 1
	case ch < 0x80:
		return j + 1
	default:
		// One code point.
		k := j + 1
		for k < to && text[k]&0xC0 == 0x80 {
			k++
		}
		return k
	}
}

func (c *VeslintConverter) template(n *ast.Node, field uint16) {
	c.open(c.named(sTemplateString), field, c.start(n))
	start := c.start(n)
	backtick := c.l.tokens[ast.KindBacktickToken]
	c.leaf(backtick, 0, 0, start, start+1)
	if n.Kind == ast.KindNoSubstitutionTemplateLiteral {
		c.stringPieces(start+1, n.End()-1, true)
		c.leaf(backtick, 0, 0, n.End()-1, n.End())
		c.close(n.End())
		return
	}
	t := n.AsTemplateExpression()
	head := t.Head
	c.stringPieces(start+1, head.End()-2, true)
	for _, span := range t.TemplateSpans.Nodes {
		s := span.AsTemplateSpan()
		lit := s.Literal
		litStart := c.start(lit)
		c.open(c.named(sTemplateSubstitution), 0, c.textStartOfSubstitution(span))
		c.leaf(c.l.dollarBrace, 0, 0, c.top().cursor, c.top().cursor+2)
		c.expressions(s.Expression, 0)
		c.leaf(c.l.tokens[ast.KindCloseBraceToken], 0, 0, litStart, litStart+1)
		c.close(litStart + 1)
		if lit.Kind == ast.KindTemplateTail {
			c.stringPieces(litStart+1, lit.End()-1, true)
			c.leaf(backtick, 0, 0, lit.End()-1, lit.End())
		} else {
			c.stringPieces(litStart+1, lit.End()-2, true)
		}
	}
	c.close(n.End())
}

// textStartOfSubstitution is where the `${` before a template span starts: the end of the
// previous literal, minus 2.
func (c *VeslintConverter) textStartOfSubstitution(span *ast.Node) int {
	return span.Pos() - 2
}

func (c *VeslintConverter) regex(n *ast.Node, field uint16) {
	start := c.start(n)
	end := n.End()
	text := c.text[start:end]
	close := strings.LastIndexByte(text, '/')
	c.open(c.named(sRegex), field, start)
	slash := c.l.tokens[ast.KindSlashToken]
	c.leaf(slash, 0, 0, start, start+1)
	c.leaf(c.named(sRegexPattern), c.field(fPattern), VeslintNamed, start+1, start+close)
	c.leaf(slash, 0, 0, start+close, start+close+1)
	if start+close+1 < end {
		c.leaf(c.named(sRegexFlags), c.field(fFlags), VeslintNamed, start+close+1, end)
	}
	c.close(end)
}

// ---- types ----

func (c *VeslintConverter) typ(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindAnyKeyword, ast.KindNumberKeyword, ast.KindBooleanKeyword, ast.KindStringKeyword,
		ast.KindSymbolKeyword, ast.KindVoidKeyword, ast.KindUnknownKeyword, ast.KindNeverKeyword,
		ast.KindObjectKeyword:
		c.open(c.named(sPredefinedType), field, c.start(n))
		c.tokNode(n, 0)
		c.close(n.End())
	case ast.KindUndefinedKeyword:
		c.open(c.named(sLiteralType), field, c.start(n))
		c.identifier(n, c.named(sUndefined), 0)
		c.close(n.End())
	case ast.KindBigIntKeyword, ast.KindIntrinsicKeyword:
		c.identifier(n, c.named(sTypeIdentifier), field)
	case ast.KindThisType:
		c.identifier(n, c.named(sThisType), field)
	case ast.KindLiteralType:
		lit := n.AsLiteralTypeNode().Literal
		c.open(c.named(sLiteralType), field, c.start(n))
		c.expression(lit, 0)
		c.close(n.End())
	case ast.KindTypeReference:
		t := n.AsTypeReferenceNode()
		if t.TypeArguments != nil {
			c.open(c.named(sGenericType), field, c.start(n))
			c.entityName(t.TypeName, c.field(fName), true)
			c.typeArguments(t.TypeArguments, c.field(fTypeArguments))
			c.close(n.End())
			return
		}
		c.entityName(t.TypeName, field, true)
	case ast.KindArrayType:
		c.open(c.named(sArrayType), field, c.start(n))
		c.typ(n.AsArrayTypeNode().ElementType, 0)
		c.close(n.End())
	case ast.KindTupleType:
		c.open(c.named(sTupleType), field, c.start(n))
		c.tok(0)
		for _, e := range n.AsTupleTypeNode().Elements.Nodes {
			c.tupleMember(e)
		}
		c.close(n.End())
	case ast.KindOptionalType:
		c.open(c.named(sOptionalType), field, c.start(n))
		c.typ(n.AsOptionalTypeNode().Type, 0)
		c.close(n.End())
	case ast.KindRestType:
		c.open(c.named(sRestType), field, c.start(n))
		c.tok(0)
		c.typ(n.AsRestTypeNode().Type, 0)
		c.close(n.End())
	case ast.KindUnionType, ast.KindIntersectionType:
		c.unionOrIntersection(n, field)
	case ast.KindFunctionType, ast.KindConstructorType:
		f := n.FunctionLikeData()
		if n.Kind == ast.KindConstructorType {
			c.open(c.named(sConstructorType), field, c.start(n))
			c.modifiers(modifierList(n))
			c.tok(0)
			c.typeParameters(f.TypeParameters, c.field(fTypeParameters))
			c.formalParameters(f.Parameters, c.field(fParameters))
			c.tok(0)
			c.typ(f.Type, c.field(fType))
		} else {
			c.open(c.named(sFunctionType), field, c.start(n))
			c.typeParameters(f.TypeParameters, c.field(fTypeParameters))
			c.formalParameters(f.Parameters, c.field(fParameters))
			c.tok(0)
			if f.Type.Kind == ast.KindTypePredicate {
				c.typePredicate(f.Type, c.field(fReturnType))
			} else {
				c.typ(f.Type, c.field(fReturnType))
			}
		}
		c.close(n.End())
	case ast.KindParenthesizedType:
		c.open(c.named(sParenthesizedType), field, c.start(n))
		c.tok(0)
		c.typ(n.AsParenthesizedTypeNode().Type, 0)
		c.close(n.End())
	case ast.KindTypeQuery:
		t := n.AsTypeQueryNode()
		c.open(c.named(sTypeQuery), field, c.start(n))
		c.tok(0)
		if t.TypeArguments != nil {
			c.open(c.named(sInstantiationExpression), 0, c.start(t.ExprName))
			c.typeQueryName(t.ExprName, c.field(fFunction))
			c.typeArguments(t.TypeArguments, c.field(fTypeArguments))
			c.close(n.End())
		} else {
			c.typeQueryName(t.ExprName, 0)
		}
		c.close(n.End())
	case ast.KindTypeOperator:
		t := n.AsTypeOperatorNode()
		switch t.Operator {
		case ast.KindKeyOfKeyword:
			c.open(c.named(sIndexTypeQuery), field, c.start(n))
			c.tok(0)
			c.typ(t.Type, 0)
		case ast.KindReadonlyKeyword:
			c.open(c.named(sReadonlyType), field, c.start(n))
			c.tok(0)
			c.typ(t.Type, 0)
		default: // unique symbol
			c.open(c.named(sPredefinedType), field, c.start(n))
			c.tokAs(c.anonymous(aUniqueSymbol), 0, 0)
			c.tokAs(c.anonymous(aUniqueSymbol), 0, 0)
		}
		c.close(n.End())
	case ast.KindIndexedAccessType:
		t := n.AsIndexedAccessTypeNode()
		c.open(c.named(sLookupType), field, c.start(n))
		c.typ(t.ObjectType, 0)
		c.tok(0)
		c.typ(t.IndexType, 0)
		c.close(n.End())
	case ast.KindConditionalType:
		t := n.AsConditionalTypeNode()
		c.open(c.named(sConditionalType), field, c.start(n))
		c.typ(t.CheckType, c.field(fLeft))
		c.tok(0)
		c.typ(t.ExtendsType, c.field(fRight))
		c.tok(0)
		c.typ(t.TrueType, c.field(fConsequence))
		c.tok(0)
		c.typ(t.FalseType, c.field(fAlternative))
		c.close(n.End())
	case ast.KindInferType:
		tp := n.AsInferTypeNode().TypeParameter.AsTypeParameterDeclaration()
		c.open(c.named(sInferType), field, c.start(n))
		c.tok(0)
		c.identifier(tp.Name(), c.named(sTypeIdentifier), 0)
		if tp.Constraint != nil {
			c.tok(0)
			c.typ(tp.Constraint, 0)
		}
		c.close(n.End())
	case ast.KindTypePredicate:
		c.typePredicate(n, field)
	case ast.KindTypeLiteral:
		c.objectType(n.AsTypeLiteralNode().Members, c.named(sObjectType), field, c.start(n))
	case ast.KindMappedType:
		c.mappedType(n, field)
	case ast.KindTemplateLiteralType:
		c.templateLiteralType(n, field)
	case ast.KindImportType:
		c.importType(n, field)
	default:
		c.generic(n, field)
	}
}

func (c *VeslintConverter) typeQueryName(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindIdentifier:
		c.identifier(n, c.named(sIdentifier), field)
	case ast.KindThisKeyword:
		c.identifier(n, c.named(sThis), field)
	case ast.KindQualifiedName:
		q := n.AsQualifiedName()
		c.open(c.named(sMemberExpression), field, c.start(n))
		c.typeQueryName(q.Left, c.field(fObject))
		c.tok(0)
		c.propertyName(q.Right, c.field(fProperty))
		c.close(n.End())
	case ast.KindImportType:
		c.importType(n, field)
	default:
		c.expression(n, field)
	}
}

func (c *VeslintConverter) importType(n *ast.Node, field uint16) {
	t := n.AsImportTypeNode()
	if t.IsTypeOf {
		c.open(c.named(sTypeQuery), field, c.start(n))
		c.tok(0)
		field = 0
	}
	c.openNext(c.named(sImportType), field)
	// import("x").A.B<T>: member_expression(call_expression(import, arguments), property)…
	callStart := c.peekStart()
	depth := 0
	if t.Qualifier != nil {
		for q := t.Qualifier; ; q = q.AsQualifiedName().Left {
			depth++
			if q.Kind != ast.KindQualifiedName {
				break
			}
		}
	}
	for i := 0; i < depth; i++ {
		c.open(c.named(sMemberExpression), 0, callStart)
	}
	c.open(c.named(sCallExpression), 0, callStart)
	c.open(c.named(sImport), c.field(fFunction), callStart)
	c.tok(0)
	c.close(callStart + 6)
	c.openNext(c.named(sArguments), c.field(fArguments))
	c.tok(0)
	if lt := t.Argument; lt.Kind == ast.KindLiteralType {
		c.expression(lt.AsLiteralTypeNode().Literal, 0)
	} else {
		c.typ(lt, 0)
	}
	c.closeAfter(ast.KindCloseParenToken)
	c.closeHere()
	var names []*ast.Node
	for q := t.Qualifier; q != nil; {
		if q.Kind == ast.KindQualifiedName {
			names = append([]*ast.Node{q.AsQualifiedName().Right}, names...)
			q = q.AsQualifiedName().Left
		} else {
			names = append([]*ast.Node{q}, names...)
			q = nil
		}
	}
	for i, name := range names {
		if i > 0 {
			c.fixFieldOfLast(c.field(fObject))
		} else {
			c.fixFieldOfLast(c.field(fObject))
		}
		c.tok(0)
		c.propertyName(name, c.field(fProperty))
		c.closeHere()
	}
	c.closeHere()
	if t.IsTypeOf {
		c.closeHere()
	}
}

// fixFieldOfLast gives the last child of the innermost open node `field`.
func (c *VeslintConverter) fixFieldOfLast(field uint16) {
	if p := c.top().prev; p != VeslintNone {
		c.rows[p].Field = field
	}
}

func (c *VeslintConverter) typePredicate(n *ast.Node, field uint16) {
	p := n.AsTypePredicateNode()
	if p.AssertsModifier != nil {
		c.open(c.named(sAsserts), field, c.start(n))
		c.tokNode(p.AssertsModifier, 0)
		if p.Type == nil {
			c.predicateName(p.ParameterName, 0)
			c.close(n.End())
			return
		}
		c.open(c.named(sTypePredicate), 0, c.start(p.ParameterName))
		c.predicateName(p.ParameterName, c.field(fName))
		c.tok(0)
		c.typ(p.Type, c.field(fType))
		c.close(n.End())
		c.close(n.End())
		return
	}
	c.open(c.named(sTypePredicate), field, c.start(n))
	c.predicateName(p.ParameterName, c.field(fName))
	c.tok(0)
	c.typ(p.Type, c.field(fType))
	c.close(n.End())
}

func (c *VeslintConverter) predicateName(n *ast.Node, field uint16) {
	if n.Kind == ast.KindThisType {
		c.identifier(n, c.named(sThis), field)
		return
	}
	c.identifier(n, c.named(sIdentifier), field)
}

func (c *VeslintConverter) unionOrIntersection(n *ast.Node, field uint16) {
	symbol := c.named(sUnionType)
	if n.Kind == ast.KindIntersectionType {
		symbol = c.named(sIntersectionType)
	}
	types := unionTypes(n)
	start := c.start(n)
	// Left-nested: ((A | B) | C) is the tree of A | B | C; a leading operator belongs to the
	// innermost node.
	for i := len(types) - 1; i >= 1; i-- {
		c.open(symbol, field, start)
		field = 0
	}
	if len(types) == 1 {
		c.open(symbol, field, start)
	}
	for i, t := range types {
		c.typ(t, 0)
		if i > 0 || len(types) == 1 {
			c.close(t.End())
		}
	}
}

func (c *VeslintConverter) tupleMember(n *ast.Node) {
	if n.Kind != ast.KindNamedTupleMember {
		c.typ(n, 0)
		return
	}
	m := n.AsNamedTupleMember()
	symbol := c.named(sRequiredParameter)
	if m.QuestionToken != nil {
		symbol = c.named(sOptionalParameter)
	}
	c.open(symbol, 0, c.start(n))
	if m.DotDotDotToken != nil {
		c.open(c.named(sRestPattern), c.field(fName), c.start(n))
		c.tokNode(m.DotDotDotToken, 0)
		c.identifier(m.Name(), c.named(sIdentifier), 0)
		c.close(m.Name().End())
	} else {
		c.identifier(m.Name(), c.named(sIdentifier), c.field(fName))
	}
	if m.QuestionToken != nil {
		c.tokNode(m.QuestionToken, 0)
	}
	c.typeAnnotation(m.Type, c.field(fType))
	c.close(n.End())
}

func (c *VeslintConverter) typeArguments(args *ast.NodeList, field uint16) {
	if args == nil {
		return
	}
	c.openNext(c.named(sTypeArguments), field)
	c.tok(0)
	for _, t := range args.Nodes {
		c.typ(t, 0)
	}
	c.closeAfter(ast.KindGreaterThanToken)
}

func (c *VeslintConverter) typeParameters(tps *ast.NodeList, field uint16) {
	if tps == nil {
		return
	}
	c.openNext(c.named(sTypeParameters), field)
	c.tok(0)
	for _, p := range tps.Nodes {
		tp := p.AsTypeParameterDeclaration()
		c.open(c.named(sTypeParameter), 0, c.start(p))
		c.modifiers(modifierList(p))
		c.identifier(tp.Name(), c.named(sTypeIdentifier), c.field(fName))
		if tp.Constraint != nil {
			c.openNext(c.named(sConstraint), c.field(fConstraint))
			c.tok(0)
			c.typ(tp.Constraint, 0)
			c.close(tp.Constraint.End())
		}
		if tp.DefaultType != nil {
			c.openNext(c.named(sDefaultType), c.field(fValue))
			c.tok(0)
			c.typ(tp.DefaultType, 0)
			c.close(tp.DefaultType.End())
		}
		c.close(p.End())
	}
	c.closeAfter(ast.KindGreaterThanToken)
}

// objectType writes `{ members }` of an interface or a type literal.
func (c *VeslintConverter) objectType(members *ast.NodeList, symbol, field uint16, start int) {
	c.open(symbol, field, start)
	c.tok(0)
	for _, m := range members.Nodes {
		c.typeMember(m)
	}
	c.closeAfter(ast.KindCloseBraceToken)
}

func (c *VeslintConverter) typeMember(m *ast.Node) {
	mods := modifierList(m)
	switch m.Kind {
	case ast.KindPropertySignature:
		p := m.AsPropertySignatureDeclaration()
		c.open(c.named(sPropertySignature), 0, c.start(m))
		c.modifiers(mods)
		c.propertyName(p.Name(), c.field(fName))
		if q := m.PostfixToken(); q != nil {
			c.tokNode(q, 0)
		}
		if p.Type != nil {
			c.typeAnnotation(p.Type, c.field(fType))
		}
		c.closeHere()
	case ast.KindMethodSignature:
		f := m.FunctionLikeData()
		c.open(c.named(sMethodSignature), 0, c.start(m))
		c.modifiers(mods)
		c.propertyName(m.Name(), c.field(fName))
		if q := m.PostfixToken(); q != nil {
			c.tokNode(q, 0)
		}
		c.callSignature(f.TypeParameters, f.Parameters, f.Type)
		c.closeHere()
	case ast.KindCallSignature:
		f := m.FunctionLikeData()
		c.open(c.named(sCallSignature), 0, c.start(m))
		c.callSignature(f.TypeParameters, f.Parameters, f.Type)
		c.closeHere()
	case ast.KindConstructSignature:
		f := m.FunctionLikeData()
		c.open(c.named(sConstructSignature), 0, c.start(m))
		c.tok(0)
		c.typeParameters(f.TypeParameters, c.field(fTypeParameters))
		c.formalParameters(f.Parameters, c.field(fParameters))
		if f.Type != nil {
			c.typeAnnotation(f.Type, c.field(fType))
		}
		c.closeHere()
	case ast.KindIndexSignature:
		c.indexSignature(m, mods)
	default:
		c.generic(m, 0)
	}
}

func (c *VeslintConverter) mappedType(n *ast.Node, field uint16) {
	t := n.AsMappedTypeNode()
	c.open(c.named(sObjectType), field, c.start(n))
	c.tok(0)
	c.openNext(c.named(sIndexSignature), 0)
	if t.ReadonlyToken != nil {
		if t.ReadonlyToken.Kind != ast.KindReadonlyKeyword {
			c.tokNode(t.ReadonlyToken, c.field(fSign))
		}
		c.tok(0)
	}
	c.tok(0) // [
	tp := t.TypeParameter.AsTypeParameterDeclaration()
	c.open(c.named(sMappedTypeClause), 0, c.start(t.TypeParameter))
	c.identifier(tp.Name(), c.named(sTypeIdentifier), c.field(fName))
	c.tok(0)
	c.typ(tp.Constraint, c.field(fType))
	if t.NameType != nil {
		c.tok(0)
		c.typ(t.NameType, c.field(fAlias))
	}
	c.closeHere()
	c.tok(0) // ]
	if t.QuestionToken != nil || t.Type != nil {
		symbol := c.named(sTypeAnnotation)
		if t.QuestionToken != nil {
			switch t.QuestionToken.Kind {
			case ast.KindMinusToken:
				symbol = c.named(sOmittingTypeAnnotation)
			case ast.KindPlusToken:
				symbol = c.named(sAddingTypeAnnotation)
			default:
				symbol = c.named(sOptingTypeAnnotation)
			}
		}
		c.openNext(symbol, c.field(fType))
		if t.QuestionToken != nil {
			if t.QuestionToken.Kind != ast.KindQuestionToken {
				c.tokNode(t.QuestionToken, 0)
			}
			c.tok(0)
		}
		c.tok(0)
		if t.Type != nil {
			c.typ(t.Type, 0)
		}
		c.closeHere()
	}
	c.closeHere()
	c.close(n.End())
}

func (c *VeslintConverter) templateLiteralType(n *ast.Node, field uint16) {
	t := n.AsTemplateLiteralTypeNode()
	start := c.start(n)
	c.open(c.named(sTemplateLiteralType), field, start)
	backtick := c.l.tokens[ast.KindBacktickToken]
	c.leaf(backtick, 0, 0, start, start+1)
	c.stringPieces(start+1, t.Head.End()-2, true)
	for _, span := range t.TemplateSpans.Nodes {
		s := span.AsTemplateLiteralTypeSpan()
		lit := s.Literal
		litStart := c.start(lit)
		c.open(c.named(sTemplateType), 0, span.Pos()-2)
		c.leaf(c.l.dollarBrace, 0, 0, span.Pos()-2, span.Pos())
		c.typ(s.Type, 0)
		c.leaf(c.l.tokens[ast.KindCloseBraceToken], 0, 0, litStart, litStart+1)
		c.close(litStart + 1)
		if lit.Kind == ast.KindTemplateTail {
			c.stringPieces(litStart+1, lit.End()-1, true)
			c.leaf(backtick, 0, 0, lit.End()-1, lit.End())
		} else {
			c.stringPieces(litStart+1, lit.End()-2, true)
		}
	}
	c.close(n.End())
}

func unionTypes(n *ast.Node) []*ast.Node {
	if n.Kind == ast.KindUnionType {
		return n.AsUnionTypeNode().Types.Nodes
	}
	return n.AsIntersectionTypeNode().Types.Nodes
}

// ---- JSX ----

func (c *VeslintConverter) jsx(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindJsxSelfClosingElement:
		e := n.AsJsxSelfClosingElement()
		c.open(c.named(sJsxSelfClosingElement), field, c.start(n))
		c.tok(0)
		c.jsxTagName(e.TagName, c.field(fName))
		c.typeArguments(e.TypeArguments, c.field(fTypeArguments))
		c.jsxAttributes(e.Attributes)
		_, start, _ := c.peek()
		c.leaf(c.anonymous(aSlashGreater), 0, 0, start, n.End())
		c.close(n.End())
	case ast.KindJsxElement:
		e := n.AsJsxElement()
		c.open(c.named(sJsxElement), field, c.start(n))
		o := e.OpeningElement.AsJsxOpeningElement()
		c.open(c.named(sJsxOpeningElement), c.field(fOpenTag), c.start(e.OpeningElement))
		c.tok(0)
		c.jsxTagName(o.TagName, c.field(fName))
		c.typeArguments(o.TypeArguments, c.field(fTypeArguments))
		c.jsxAttributes(o.Attributes)
		c.close(e.OpeningElement.End())
		c.jsxChildren(e.Children)
		cl := e.ClosingElement
		c.open(c.named(sJsxClosingElement), c.field(fCloseTag), c.start(cl))
		c.tok(0)
		c.jsxTagName(cl.AsJsxClosingElement().TagName, c.field(fName))
		c.close(cl.End())
		c.close(n.End())
	case ast.KindJsxFragment:
		e := n.AsJsxFragment()
		c.open(c.named(sJsxElement), field, c.start(n))
		c.open(c.named(sJsxOpeningElement), c.field(fOpenTag), c.start(e.OpeningFragment))
		c.close(e.OpeningFragment.End())
		c.jsxChildren(e.Children)
		c.open(c.named(sJsxClosingElement), c.field(fCloseTag), c.start(e.ClosingFragment))
		c.tok(0)
		c.close(e.ClosingFragment.End())
		c.close(n.End())
	}
}

func (c *VeslintConverter) jsxTagName(n *ast.Node, field uint16) {
	switch n.Kind {
	case ast.KindPropertyAccessExpression:
		e := n.AsPropertyAccessExpression()
		c.open(c.named(sJsxMemberExpression), field, c.start(n))
		c.jsxTagName(e.Expression, c.field(fObject))
		c.tok(0)
		c.identifier(e.Name(), c.named(sJsxIdentifier), c.field(fProperty))
		c.close(n.End())
	case ast.KindJsxNamespacedName:
		c.jsxNamespacedName(n, field)
	default:
		c.identifier(n, c.named(sJsxIdentifier), field)
	}
}

func (c *VeslintConverter) jsxNamespacedName(n *ast.Node, field uint16) {
	e := n.AsJsxNamespacedName()
	c.open(c.named(sJsxNamespaceName), field, c.start(n))
	c.identifier(e.Namespace, c.named(sJsxIdentifier), 0)
	c.tok(0)
	c.identifier(e.Name(), c.named(sJsxIdentifier), 0)
	c.close(n.End())
}

func (c *VeslintConverter) jsxAttributes(attrs *ast.Node) {
	for _, a := range attrs.AsJsxAttributes().Properties.Nodes {
		if a.Kind == ast.KindJsxSpreadAttribute {
			c.open(c.named(sJsxExpression), c.field(fAttribute), c.start(a))
			c.tok(0)
			c.open(c.named(sSpreadElement), 0, c.peekStart())
			c.tok(0)
			c.expression(a.Expression(), 0)
			c.closeHere()
			c.close(a.End())
			continue
		}
		at := a.AsJsxAttribute()
		c.open(c.named(sJsxAttribute), c.field(fAttribute), c.start(a))
		if name := at.Name(); name.Kind == ast.KindJsxNamespacedName {
			c.jsxNamespacedName(name, 0)
		} else {
			c.identifier(name, c.named(sPropertyIdentifier), 0)
		}
		if init := at.Initializer; init != nil {
			c.tok(0)
			switch init.Kind {
			case ast.KindStringLiteral:
				c.jsxString(c.start(init), init.End())
			case ast.KindJsxExpression:
				c.jsxExpression(init)
			default:
				c.expression(init, 0)
			}
		}
		c.close(a.End())
	}
}

// jsxString writes an attribute's string: tree-sitter's fragments stop at a `&` that may start a
// character reference; a reference is html_character_reference, another `&` a fragment of its
// own (around its token).
func (c *VeslintConverter) jsxString(start, end int) {
	c.open(c.named(sString), 0, start)
	quote := c.l.quote(c.text[start : start+1])
	c.leaf(quote, 0, 0, start, start+1)
	fragment := start + 1
	for i := start + 1; i < end-1; {
		if c.text[i] != '&' || i+1 >= end-1 || !isReferenceStart(c.text[i+1]) {
			i++
			continue
		}
		if fragment < i {
			c.leaf(c.named(sStringFragment), 0, VeslintNamed, fragment, i)
		}
		if r := characterReference(c.text[i : end-1]); r > 0 {
			c.leaf(c.named(sHTMLCharacterReference), 0, VeslintNamed, i, i+r)
			i += r
		} else {
			c.open(c.named(sStringFragment), 0, i)
			c.leaf(c.anonymous(aAmpersand), 0, 0, i, i+1)
			c.close(i + 1)
			i++
		}
		fragment = i
	}
	if fragment < end-1 {
		c.leaf(c.named(sStringFragment), 0, VeslintNamed, fragment, end-1)
	}
	c.leaf(quote, 0, 0, end-1, end)
	c.close(end)
}

func isReferenceStart(ch byte) bool {
	return ch == '#' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

// characterReference is the length of the character reference at the start of `s`
// (&name; &#digits; &#xhex;), 0 for none.
func characterReference(s string) int {
	if len(s) < 3 || s[0] != '&' {
		return 0
	}
	i := 1
	n := 0
	switch {
	case s[1] == '#' && len(s) > 2 && (s[2] == 'x' || s[2] == 'X'):
		i = 3
		for i < len(s) && n < 6 && isHex(s[i]) {
			i++
			n++
		}
	case s[1] == '#':
		i = 2
		for i < len(s) && n < 5 && s[i] >= '0' && s[i] <= '9' {
			i++
			n++
		}
	default:
		for i < len(s) && n < 30 && ((s[i] >= 'a' && s[i] <= 'z') || (s[i] >= 'A' && s[i] <= 'Z')) {
			i++
			n++
		}
	}
	if n == 0 || i >= len(s) || s[i] != ';' {
		return 0
	}
	return i + 1
}

func isHex(ch byte) bool {
	return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

func (c *VeslintConverter) jsxExpression(n *ast.Node) {
	e := n.AsJsxExpression()
	c.open(c.named(sJsxExpression), 0, c.start(n))
	c.tok(0)
	if e.DotDotDotToken != nil {
		c.open(c.named(sSpreadElement), 0, c.start(e.DotDotDotToken))
		c.tokNode(e.DotDotDotToken, 0)
		c.expression(e.Expression, 0)
		c.closeHere()
	} else if e.Expression != nil {
		c.expressions(e.Expression, 0)
	}
	c.close(n.End())
}

func (c *VeslintConverter) jsxChildren(children *ast.NodeList) {
	for _, ch := range children.Nodes {
		switch ch.Kind {
		case ast.KindJsxText:
			c.jsxText(ch.Pos(), ch.End())
		case ast.KindJsxExpression:
			c.jsxExpression(ch)
		default:
			c.expression(ch, 0)
		}
	}
}

// jsxText writes the text between `from` and `to` as tree-sitter's scanner splits it: runs of
// text between character references, each a jsx_text unless it is only white space that starts
// a line (scan_jsx_text's saw_text).
func (c *VeslintConverter) jsxText(from, to int) {
	run := from
	sawText, atNewline := false, false
	for i := from; i < to; {
		ch := c.text[i]
		if ch == '&' {
			if r := characterReference(c.text[i:to]); r > 0 {
				if sawText {
					c.leaf(c.named(sJsxText), 0, VeslintNamed, run, i)
				}
				c.leaf(c.named(sHTMLCharacterReference), 0, VeslintNamed, i, i+r)
				i += r
				run = i
				sawText, atNewline = false, false
				continue
			}
			sawText, atNewline = true, false
			i++
			continue
		}
		r, size := utf8.DecodeRuneInString(c.text[i:])
		if c.isLineBreak(i) {
			atNewline = true
		} else {
			space := r == ' ' || r == '\t' || r == 0x0B || r == 0x0C || r == 0x85 || r == 0xA0 || r == 0x1680 || (r >= 0x2000 && r <= 0x200B) || r == 0x202F || r == 0x205F || r == 0x2060 || r == 0x3000 || r == 0xFEFF
			atNewline = atNewline && space
			if !atNewline {
				sawText = true
			}
		}
		i += size
	}
	if sawText && run < to {
		c.leaf(c.named(sJsxText), 0, VeslintNamed, run, to)
	}
}
