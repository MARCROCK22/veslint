module tsgo

import json2

// More methods of the tsgo API the rules use: the tables of a symbol, the parameter types of a
// signature and the intrinsic types. Names and fields from dist/api/sync/api.js of TypeScript
// 7.1.0-beta (the server side is internal/api/session.go).

// members_of_symbol gives `symbol.members`: what a class, an interface or a type literal declares
// (properties and methods, and also its type parameters, `__constructor`, `__call`, `__index`…),
// in the checker's order of symbols. The names are escaped (`__a` is `___a`); the internal ones
// (`__constructor`) are not.
pub fn (mut c Client) members_of_symbol(snapshot int, project string, symbol_id int) ![]SymbolResponse {
	return c.symbols_request(snapshot, 'getMembersOfSymbol', c.symbol_property_params(symbol_id)!)!
}

// exports_of_symbol gives `symbol.exports`: the exports of a module or a namespace, the members of
// an enum and the static members of a class.
pub fn (mut c Client) exports_of_symbol(snapshot int, project string, symbol_id int) ![]SymbolResponse {
	return c.symbols_request(snapshot, 'getExportsOfSymbol', c.symbol_property_params(symbol_id)!)!
}

struct ParameterTypeParams {
	snapshot  int
	project   string
	signature int
	index     int
}

// parameter_type ports the checker's getTypeAtPosition(signature, index): the type of the parameter
// at that position, which for a rest parameter is that of the element at the position, and `any`
// beyond the parameters.
pub fn (mut c Client) parameter_type(snapshot int, project string, signature_id int, index int) !TypeResponse {
	return c.type_request(snapshot, 'getParameterType', json2.encode(ParameterTypeParams{
		snapshot:  snapshot
		project:   project
		signature: signature_id
		index:     index
	}))!
}

// intrinsic_type gives one of the types the checker has a getter for: `getAnyType`,
// `getStringType`, `getNumberType`, `getBooleanType`, `getVoidType`, `getUndefinedType`,
// `getNullType`, `getNeverType`, `getUnknownType`, `getBigIntType` and `getESSymbolType`.
pub fn (mut c Client) intrinsic_type(method string, snapshot int, project string) !TypeResponse {
	return c.type_request(snapshot, method, json2.encode(ProjectParams{
		snapshot: snapshot
		project:  project
	}))!
}

// type_parameters_of_type gives the type parameters of the declared type of a class or an
// interface (`InterfaceType.typeParameters`, the outer ones included). tsgo panics on a type of
// another kind.
pub fn (mut c Client) type_parameters_of_type(snapshot int, project string, type_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getTypeParametersOfType', object_params(snapshot, project,
		type_id))!
}

// awaited_type ports checker.getAwaitedType (in the API since TypeScript 7.1): the type `await`
// gives for a type, or the null type where TypeScript gives none (a `then` that takes no callback,
// a promise of itself…).
pub fn (mut c Client) awaited_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getAwaitedType', type_params(snapshot, project, type_id))!
}

struct ContextualArgumentParams {
	snapshot int
	project  string
	location string
	index    int
}

// contextual_type_for_argument ports checker.getContextualTypeForArgumentAtIndex (in the API since
// TypeScript 7.1): the contextual type of the argument at `index` of a call, a `new`, a tagged
// template or a decorator (the handle of that node), counting the arguments as written; the null
// type when there is none.
pub fn (mut c Client) contextual_type_for_argument(snapshot int, project string, call string, index int) !TypeResponse {
	return c.type_request(snapshot, 'getContextualTypeForArgument', json2.encode(ContextualArgumentParams{
		snapshot: snapshot
		project:  project
		location: call
		index:    index
	}))!
}
