module tsgo

import json2

// tsgo API methods and their types. Names and fields from dist/api/sync/api.js and
// dist/api/proto.generated.d.ts (APIMethodInfo) of TypeScript 7.1.0-beta.

pub struct InitializeResponse {
pub:
	case_sensitivity  int    @[json: 'caseSensitivity']
	current_directory string @[json: 'currentDirectory']
}

pub struct ProjectResponse {
pub:
	id                  string
	config_file_name    string            @[json: 'configFileName']
	parsed_command_line ParsedCommandLine @[json: 'parsedCommandLine']
}

// ParsedCommandLine is what veslint uses of the parsed tsconfig of a project: its options and its
// root files.
pub struct ParsedCommandLine {
pub:
	options    CompilerOptions
	file_names []string @[json: 'fileNames']
}

// compiler_options are the options of the tsconfig of the project.
pub fn (p ProjectResponse) compiler_options() CompilerOptions {
	return p.parsed_command_line.options
}

// CompilerOptions are the project options the rules use. tsgo only sends the ones set in the
// tsconfig.
pub struct CompilerOptions {
pub:
	strict                                  ?bool
	no_implicit_this                        ?bool @[json: 'noImplicitThis']
	strict_null_checks                      ?bool @[json: 'strictNullChecks']
	no_unchecked_indexed_access             ?bool @[json: 'noUncheckedIndexedAccess']
	no_property_access_from_index_signature ?bool @[json: 'noPropertyAccessFromIndexSignature']
	exact_optional_property_types           ?bool @[json: 'exactOptionalPropertyTypes']
	lib                                     ?[]string
	target                                  ?int
	jsx_factory                             ?string @[json: 'jsxFactory']
	jsx_fragment_factory                    ?string @[json: 'jsxFragmentFactory']
	emit_decorator_metadata                 ?bool   @[json: 'emitDecoratorMetadata']
	experimental_decorators                 ?bool   @[json: 'experimentalDecorators']
}

// Values of TypeScript's ScriptTarget.
const script_target_es2015 = 2
const script_target_es2025 = 12
const script_target_esnext = 99

// lib_names ports typescript-eslint's getLib: the libs its scope manager takes the global names
// from. They are those of `lib` (which TypeScript keeps as file names, `lib.es2022.d.ts`) or else
// the default lib of `target`; without a target, that of TypeScript 6's default (LatestStandard,
// which is ES2025), the TypeScript ESLint runs on.
pub fn (o CompilerOptions) lib_names() []string {
	if libs := o.lib {
		mut out := []string{}
		for lib in libs {
			if name := lib_file_name(lib) {
				out << name
			}
		}
		return out
	}
	target := o.target or { script_target_es2025 }
	if target == script_target_es2015 {
		return ['es6']
	}
	if target > script_target_es2015 && target <= script_target_es2025 {
		return ['es${2013 + target}.full']
	}
	if target == script_target_esnext {
		return ['esnext.full']
	}
	return ['lib']
}

// lib_file_name is the first group of /lib\.(.+)\.d\.[cm]?ts$/ on the lowercased name.
fn lib_file_name(lib string) ?string {
	lower := lib.to_lower()
	mut end := -1
	for suffix in ['.d.ts', '.d.cts', '.d.mts'] {
		if lower.ends_with(suffix) {
			end = lower.len - suffix.len
		}
	}
	start := lower.index('lib.') or { return none }
	if end < 0 || start + 4 >= end {
		return none
	}
	return lower[start + 4..end]
}

// no_implicit_this_enabled ports isStrictCompilerOptionEnabled(options, 'noImplicitThis') from
// ts-api-utils: the option, else `strict`, else the default of TypeScript ≥ 6 (enabled).
pub fn (o CompilerOptions) no_implicit_this_enabled() bool {
	return o.no_implicit_this or { o.strict or { true } }
}

// strict_null_checks_enabled ports isStrictCompilerOptionEnabled(options, 'strictNullChecks'), like
// no_implicit_this_enabled.
pub fn (o CompilerOptions) strict_null_checks_enabled() bool {
	return o.strict_null_checks or { o.strict or { true } }
}

// no_property_access_from_index_signature_enabled ports isCompilerOptionEnabled(options,
// 'noPropertyAccessFromIndexSignature'): set to true.
pub fn (o CompilerOptions) no_property_access_from_index_signature_enabled() bool {
	return o.no_property_access_from_index_signature or { false }
}

// exact_optional_property_types_enabled ports isCompilerOptionEnabled(options,
// 'exactOptionalPropertyTypes'): set to true.
pub fn (o CompilerOptions) exact_optional_property_types_enabled() bool {
	return o.exact_optional_property_types or { false }
}

// no_unchecked_indexed_access_enabled ports isCompilerOptionEnabled(options,
// 'noUncheckedIndexedAccess'): set to true, and with strictNullChecks.
pub fn (o CompilerOptions) no_unchecked_indexed_access_enabled() bool {
	return (o.no_unchecked_indexed_access or { false }) && o.strict_null_checks_enabled()
}

// UpdateSnapshotResponse is a snapshot and every project it has open (CreateSnapshotResponse).
pub struct UpdateSnapshotResponse {
pub:
	snapshot int
	projects []ProjectResponse
	// What updateSnapshot reports besides the projects it added or replaced.
	changes SnapshotChanges
}

pub struct SnapshotChanges {
pub:
	removed_projects []string @[json: 'removedProjects']
}

struct CreateSnapshotParams {
	open_projects []string @[json: 'openProjects']
}

struct FileNotificationsParams {
	changed        []string
	created        []string
	deleted        []string
	invalidate_all bool @[json: 'invalidateAll']
}

struct SnapshotChangesParams {
	open_projects      []string                @[json: 'openProjects']
	file_notifications FileNotificationsParams @[json: 'fileNotifications']
	// Without it, the projects a change touches stay `dirty`: their programs, and so the answers
	// of the checker, are those of the previous snapshot until something asks to update them.
	ensure_programs bool @[json: 'ensurePrograms']
}

struct UpdateSnapshotParams {
	snapshot int
	changes  SnapshotChangesParams
}

// FileChangeSet is what changed on disk since the last snapshot, as tsgo's FileNotifications has
// it: with invalidate_all, tsgo forgets every file it read (a tsconfig.json or a package changed).
pub struct FileChangeSet {
pub mut:
	changed        []string
	created        []string
	deleted        []string
	invalidate_all bool
}

// is_empty tells that nothing changed.
pub fn (c FileChangeSet) is_empty() bool {
	return c.changed.len == 0 && c.created.len == 0 && c.deleted.len == 0 && !c.invalidate_all
}

struct ReleaseParams {
	snapshot int
}

// create_snapshot asks for a snapshot with the projects of `tsconfigs` open (createSnapshot).
pub fn (mut c Client) create_snapshot(tsconfigs []string) !UpdateSnapshotResponse {
	params := json2.encode(CreateSnapshotParams{
		open_projects: tsconfigs
	})
	return decode_response[UpdateSnapshotResponse]('createSnapshot', c.request('createSnapshot',
		params)!)!
}

struct ParseConfigFileParams {
	file string
}

// parse_config_file asks for the parsed tsconfig `file` (parseConfigFile): its compiler options and
// its root files, as the projects of a snapshot have them, without making a snapshot, so no
// program is built.
pub fn (mut c Client) parse_config_file(file string) !ParsedCommandLine {
	params := json2.encode(ParseConfigFileParams{
		file: file
	})
	return decode_response[ParsedCommandLine]('parseConfigFile', c.request('parseConfigFile',
		params)!)!
}

// update_snapshot_changed asks for the snapshot that follows `base` after `changed` files were
// rewritten on disk: tsgo reads them again. The ids of the previous snapshot (types, signatures)
// are not valid in the new one; release it once it is not needed.
pub fn (mut c Client) update_snapshot_changed(base UpdateSnapshotResponse, changed []string) !UpdateSnapshotResponse {
	return c.next_snapshot(base, SnapshotChangesParams{
		file_notifications: FileNotificationsParams{
			changed: changed
		}
		ensure_programs:    true
	})!
}

// update_snapshot_files asks for the snapshot that follows `base` with the projects of `opened`
// open too and after the changes on disk of `changes` (veslint --server, which keeps tsgo between
// requests). The ids of the previous snapshot are not valid in the new one; release it once it is
// not needed.
pub fn (mut c Client) update_snapshot_files(base UpdateSnapshotResponse, opened []string, changes FileChangeSet) !UpdateSnapshotResponse {
	return c.next_snapshot(base, SnapshotChangesParams{
		open_projects:      opened
		file_notifications: FileNotificationsParams{
			changed:        changes.changed
			created:        changes.created
			deleted:        changes.deleted
			invalidate_all: changes.invalidate_all
		}
		ensure_programs:    true
	})!
}

// next_snapshot sends updateSnapshot. Its response only has the projects added or replaced since
// `base`; the others are those of `base` that were not removed. When nothing changed, tsgo answers
// with `base` itself, which it then holds once more: like the TypeScript client
// (dist/api/sync/api.js), the client releases that hold and keeps `base`.
fn (mut c Client) next_snapshot(base UpdateSnapshotResponse, changes SnapshotChangesParams) !UpdateSnapshotResponse {
	params := json2.encode(UpdateSnapshotParams{
		snapshot: base.snapshot
		changes:  changes
	})
	response := decode_response[UpdateSnapshotResponse]('updateSnapshot', c.request('updateSnapshot',
		params)!)!
	if response.snapshot == base.snapshot {
		c.request('release', json2.encode(ReleaseParams{ snapshot: base.snapshot }))!
		return base
	}
	mut projects := response.projects.clone()
	for p in base.projects {
		if p.id !in response.changes.removed_projects && !response.projects.any(it.id == p.id) {
			projects << p
		}
	}
	return UpdateSnapshotResponse{
		snapshot: response.snapshot
		projects: projects
	}
}

// release_snapshot lets tsgo free a snapshot that is no longer used: without it, every snapshot of
// a long-lived process keeps its programs. The client forgets the symbols last seen in it.
pub fn (mut c Client) release_snapshot(snapshot int) ! {
	c.request('release', json2.encode(ReleaseParams{ snapshot: snapshot }))!
	c.symbols.forget(snapshot)
}

struct PositionsParams {
	snapshot  int
	project   string
	file      string
	positions []int
}

struct PositionParams {
	snapshot int
	project  string
	file     string
	position int
}

struct TypeParams {
	snapshot int
	project  string
	typ      int @[json: 'type']
}

// TypeResponse: a protocol `null` becomes id 0 (real ids start at 1).
pub struct TypeResponse {
pub:
	id             int
	flags          u32
	object_flags   u32    @[json: 'objectFlags']
	intrinsic_name string @[json: 'intrinsicName']
	// Generic type a reference is an instance of. The id alone is not valid in other requests: tsgo
	// accepts it after sending it whole (target_of_type).
	target int
	// In a tuple target, the ElementFlags of each element.
	element_flags []int @[json: 'elementFlags']
	// The symbol and the alias symbol, as ints of the client (0 when absent, see symbols.v). tsgo
	// only sends their compact references: to request something about them, symbol_of_type or
	// alias_symbol_of_type gives them whole.
	symbol       int  @[json: '-']
	alias_symbol int  @[json: '-']
	is_this_type bool @[json: 'isThisType']
	// checker.isTupleType: a reference to a tuple target.
	is_tuple_type bool @[json: 'isTupleType']
	// aliasTypeArguments ids (empty when the type has none: TypeScript leaves them undefined).
	alias_type_arguments []int @[json: 'aliasTypeArguments']
	// In a tuple target, whether it is readonly.
	readonly bool
	// In a conditional type, the ids of its check and extends types: like `target`, only to compare
	// them (part_of_type gives the types).
	check_type   int @[json: 'checkType']
	extends_type int @[json: 'extendsType']
	// Value of a literal type: a string, a number, or a BigInt as a decimal string. json2 leaves an
	// empty array when it is absent (see has_value).
	value json2.Any
	// What tsgo sent for `symbol` and `alias_symbol` (intern_type).
	symbol_reference       CompactSymbolReference @[json: 'symbol']
	alias_symbol_reference CompactSymbolReference @[json: 'aliasSymbol']
}

// has_value tells whether the type carries a literal value.
pub fn (t TypeResponse) has_value() bool {
	return t.value !is []json2.Any && t.value !is json2.Null
}

pub fn (t TypeResponse) is_null() bool {
	return t.id == 0 && t.flags == 0
}

// SymbolResponse: a protocol `null` becomes id 0 and an empty name. The ids are ints of the client
// (see symbols.v), equal for the same symbol.
pub struct SymbolResponse {
pub:
	id                int @[json: '-']
	parent            int @[json: '-'] // symbol that contains it (0 if none)
	name              string
	flags             u32
	check_flags       u32 @[json: 'checkFlags'] // CheckFlags of a transient symbol (Readonly…)
	declarations      []string // tsgo handles of its declarations (see handle_path)
	value_declaration string @[json: 'valueDeclaration']
	// Its export symbol (0 when it has none: then the symbol is its own export symbol).
	export_symbol int @[json: '-']
	// What tsgo sent for `id`, `parent` and `export_symbol` (intern_symbol).
	reference               SymbolReference
	parent_reference        CompactSymbolReference @[json: 'parent']
	export_symbol_reference CompactSymbolReference @[json: 'exportSymbol']
}

// handle_path is the file of a tsgo node handle (`index.kind.path`).
pub fn handle_path(handle string) string {
	first := handle.index('.') or { return '' }
	second := handle.index_after_('.', first + 1)
	return if second < 0 { '' } else { handle[second + 1..] }
}

// handle_kind is the SyntaxKind of the node of a tsgo handle (`index.kind.path`), 0 if malformed.
pub fn handle_kind(handle string) u32 {
	first := handle.index('.') or { return 0 }
	second := handle.index_after_('.', first + 1)
	if second < 0 {
		return 0
	}
	return u32(handle[first + 1..second].int())
}

// handle_index is the index of the node of a tsgo handle (`index.kind.path`) in the node table of
// its file (see AstTree), 0 if malformed.
pub fn handle_index(handle string) int {
	first := handle.index('.') or { return 0 }
	return handle[..first].int()
}

pub fn (s SymbolResponse) is_null() bool {
	return s.id == 0 && s.name == ''
}

fn is_null_payload(payload string) bool {
	trimmed := payload.trim_space()
	return trimmed == '' || trimmed == 'null'
}

fn decode_response[T](method string, payload string) !T {
	return json2.decode[T](payload) or {
		return error('invalid response from `${method}`: ${err.msg()}')
	}
}

pub fn (mut c Client) initialize() !InitializeResponse {
	return decode_response[InitializeResponse]('initialize', c.request('initialize', 'null')!)!
}

// symbol_request sends a request that answers a symbol or `null` (the null symbol).
fn (mut c Client) symbol_request(snapshot int, method string, params string) !SymbolResponse {
	payload := c.request(method, params)!
	if is_null_payload(payload) {
		return SymbolResponse{}
	}
	return c.intern_symbol(snapshot, decode_response[SymbolResponse](method, payload)!)
}

// symbols_request sends a request that answers a list of symbols (`null` is none).
fn (mut c Client) symbols_request(snapshot int, method string, params string) ![]SymbolResponse {
	payload := c.request(method, params)!
	if is_null_payload(payload) {
		return []SymbolResponse{}
	}
	return c.intern_symbols(snapshot, decode_response[[]SymbolResponse](method, payload)!)
}

pub fn (mut c Client) symbols_at(snapshot int, project string, file string, positions []int) ![]SymbolResponse {
	params := json2.encode(PositionsParams{
		snapshot:  snapshot
		project:   project
		file:      file
		positions: positions
	})
	return c.symbols_request(snapshot, 'getSymbolsAtPositions', params)!
}

pub fn (mut c Client) types_at(snapshot int, project string, file string, positions []int) ![]TypeResponse {
	params := json2.encode(PositionsParams{
		snapshot:  snapshot
		project:   project
		file:      file
		positions: positions
	})
	return c.types_request(snapshot, 'getTypesAtPositions', params)!
}

pub fn (mut c Client) symbol_at(snapshot int, project string, file string, position int) !SymbolResponse {
	params := json2.encode(PositionParams{
		snapshot: snapshot
		project:  project
		file:     file
		position: position
	})
	return c.symbol_request(snapshot, 'getSymbolAtPosition', params)!
}

pub fn (mut c Client) type_at(snapshot int, project string, file string, position int) !TypeResponse {
	params := json2.encode(PositionParams{
		snapshot: snapshot
		project:  project
		file:     file
		position: position
	})
	return c.type_request(snapshot, 'getTypeAtPosition', params)!
}

pub fn (mut c Client) type_to_string(snapshot int, project string, type_id int) !string {
	params := json2.encode(TypeParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
	})
	return decode_response[string]('typeToString', c.request('typeToString', params)!)!
}

struct TypeStringParams {
	snapshot int
	project  string
	typ      int @[json: 'type']
	flags    int
}

// type_to_string_flags is typeToString with TypeFormatFlags (TypeScript's values).
pub fn (mut c Client) type_to_string_flags(snapshot int, project string, type_id int, flags int) !string {
	params := json2.encode(TypeStringParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
		flags:    flags
	})
	return decode_response[string]('typeToString', c.request('typeToString', params)!)!
}

struct TypeStringAtParams {
	snapshot int
	project  string
	typ      int @[json: 'type']
	location string
	flags    int
}

// type_to_string_at is typeToString with an enclosing declaration (a node handle) and
// TypeFormatFlags: the names of the type are written as that node sees them.
pub fn (mut c Client) type_to_string_at(snapshot int, project string, type_id int, location string, flags int) !string {
	params := json2.encode(TypeStringAtParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
		location: location
		flags:    flags
	})
	return decode_response[string]('typeToString', c.request('typeToString', params)!)!
}

pub fn (mut c Client) base_type_of_literal(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getBaseTypeOfLiteralType', type_params(snapshot, project,
		type_id))!
}

// Methods the rules use. Names and fields from dist/api/sync/api.js of TypeScript 7.1.0-beta.

struct ObjectParams {
	snapshot  int
	project   string
	object_id int @[json: 'objectId']
}

struct SignatureParams {
	snapshot  int
	project   string
	signature int
}

struct SignaturesOfTypeParams {
	snapshot int
	project  string
	typ      int @[json: 'type']
	kind     int
}

struct ResolveNameParams {
	snapshot int
	project  string
	name     string
	meaning  int
}

pub struct SignatureResponse {
pub:
	id    int
	flags u32
	// Its parameters, only to count them: parameters_of_signature gives them whole.
	parameters []CompactSymbolReference
	// tsgo handle of the declaration ('' for a synthetic signature).
	declaration     string
	type_parameters []int @[json: 'typeParameters'] // ids of its type parameters (sig.getTypeParameters())
	// The `this` parameter as an int of the client (0 if none); this_parameter_of_signature gives
	// it whole.
	this_parameter           int                    @[json: '-']
	this_parameter_reference CompactSymbolReference @[json: 'thisParameter']
}

// type_request sends a request that answers a type or `null` (id 0).
fn (mut c Client) type_request(snapshot int, method string, params string) !TypeResponse {
	payload := c.request(method, params)!
	if is_null_payload(payload) {
		return TypeResponse{}
	}
	return c.intern_type(snapshot, decode_response[TypeResponse](method, payload)!)
}

// types_request sends a request that answers a list of types (`null` is none).
fn (mut c Client) types_request(snapshot int, method string, params string) ![]TypeResponse {
	payload := c.request(method, params)!
	if is_null_payload(payload) {
		return []TypeResponse{}
	}
	return c.intern_types(snapshot, decode_response[[]TypeResponse](method, payload)!)
}

// signature_request sends a request that answers a signature or `null` (id 0).
fn (mut c Client) signature_request(snapshot int, method string, params string) !SignatureResponse {
	payload := c.request(method, params)!
	if is_null_payload(payload) {
		return SignatureResponse{}
	}
	return c.intern_signature(snapshot, decode_response[SignatureResponse](method, payload)!)
}

fn type_params(snapshot int, project string, type_id int) string {
	return json2.encode(TypeParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
	})
}

// object_params are those of the properties of a type or a signature (GetTypePropertyParams,
// GetSignaturePropertyParams).
fn object_params(snapshot int, project string, object_id int) string {
	return json2.encode(ObjectParams{
		snapshot:  snapshot
		project:   project
		object_id: object_id
	})
}

pub fn (mut c Client) signatures_of_type(snapshot int, project string, type_id int, kind int) ![]SignatureResponse {
	params := json2.encode(SignaturesOfTypeParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
		kind:     kind
	})
	payload := c.request('getSignaturesOfType', params)!
	if is_null_payload(payload) {
		return []SignatureResponse{}
	}
	signatures := decode_response[[]SignatureResponse]('getSignaturesOfType', payload)!
	return signatures.map(c.intern_signature(snapshot, it))
}

pub fn (mut c Client) return_type_of_signature(snapshot int, project string, signature_id int) !TypeResponse {
	return c.type_request(snapshot, 'getReturnTypeOfSignature', object_params(snapshot,
		project, signature_id))!
}

pub fn (mut c Client) symbol_of_type(snapshot int, project string, type_id int) !SymbolResponse {
	return c.symbol_request(snapshot, 'getSymbolOfType', object_params(snapshot, project,
		type_id))!
}

pub fn (mut c Client) types_of_type(snapshot int, project string, type_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getTypesOfType', object_params(snapshot, project, type_id))!
}

pub fn (mut c Client) apparent_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getApparentType', object_params(snapshot, project, type_id))!
}

pub fn (mut c Client) constraint_of_type_parameter(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getConstraintOfTypeParameter', object_params(snapshot,
		project, type_id))!
}

pub fn (mut c Client) declared_type_of_symbol(snapshot int, project string, symbol_id int) !TypeResponse {
	return c.type_request(snapshot, 'getDeclaredTypeOfSymbol', c.symbol_params(snapshot, project,
		symbol_id)!)!
}

pub fn (mut c Client) base_types(snapshot int, project string, type_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getBaseTypes', type_params(snapshot, project, type_id))!
}

pub fn (mut c Client) type_arguments(snapshot int, project string, type_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getTypeArguments', type_params(snapshot, project, type_id))!
}

pub fn (mut c Client) is_array_type(snapshot int, project string, type_id int) !bool {
	return decode_response[bool]('isArrayType', c.request('isArrayType', type_params(snapshot,
		project, type_id))!)!
}

pub fn (mut c Client) resolve_name(snapshot int, project string, name string, meaning int) !SymbolResponse {
	return c.symbol_request(snapshot, 'resolveName', json2.encode(ResolveNameParams{
		snapshot: snapshot
		project:  project
		name:     name
		meaning:  meaning
	}))!
}

struct ResolveNameAtParams {
	snapshot        int
	project         string
	name            string
	meaning         int
	location        string
	exclude_globals bool @[json: 'excludeGlobals']
}

// resolve_name_at ports checker.resolveName(name, meaning, location, excludeGlobals) from a node
// (handle from SourceFileAst.handle). Without a symbol it returns the null one.
pub fn (mut c Client) resolve_name_at(snapshot int, project string, name string, meaning int, location string, exclude_globals bool) !SymbolResponse {
	return c.symbol_request(snapshot, 'resolveName', json2.encode(ResolveNameAtParams{
		snapshot:        snapshot
		project:         project
		name:            name
		meaning:         meaning
		location:        location
		exclude_globals: exclude_globals
	}))!
}

// aliased_symbol ports checker.getAliasedSymbol (the symbol must have arrived whole before).
// Returns the null symbol where TypeScript's API throws.
pub fn (mut c Client) aliased_symbol(snapshot int, project string, symbol_id int) !SymbolResponse {
	return c.symbol_request(snapshot, 'getAliasedSymbol', c.symbol_params(snapshot, project,
		symbol_id)!)!
}

// immediate_aliased_symbol ports checker.getImmediateAliasedSymbol: the symbol an alias refers to
// directly (the next one in a chain of re-exports), or the null symbol. tsgo fails if the symbol
// is not an alias.
pub fn (mut c Client) immediate_aliased_symbol(snapshot int, project string, symbol_id int) !SymbolResponse {
	return c.symbol_request(snapshot, 'getImmediateAliasedSymbol', c.symbol_params(snapshot,
		project, symbol_id)!)!
}

// shorthand_assignment_value_symbol ports checker.getShorthandAssignmentValueSymbol of a node
// (handle): for a shorthand property `{ x }`, the symbol of the value `x`; otherwise the null
// symbol.
pub fn (mut c Client) shorthand_assignment_value_symbol(snapshot int, project string, location string) !SymbolResponse {
	return c.symbol_request(snapshot, 'getShorthandAssignmentValueSymbol', json2.encode(LocationParams{
		snapshot: snapshot
		project:  project
		location: location
	}))!
}

// export_symbol_of_symbol ports checker.getExportSymbolOfSymbol like Symbol.getExportSymbol of
// the API: a symbol without an export symbol is its own, and only otherwise is it requested.
pub fn (mut c Client) export_symbol_of_symbol(snapshot int, project string, symbol SymbolResponse) !SymbolResponse {
	if symbol.export_symbol == 0 {
		return symbol
	}
	return c.symbol_request(snapshot, 'getExportSymbolOfSymbol', c.symbol_property_params(symbol.id)!)!
}

struct PropertyParams {
	snapshot int
	project  string
	typ      int @[json: 'type']
	name     string
}

pub fn (mut c Client) property_of_type(snapshot int, project string, type_id int, name string) !SymbolResponse {
	return c.symbol_request(snapshot, 'getPropertyOfType', json2.encode(PropertyParams{
		snapshot: snapshot
		project:  project
		typ:      type_id
		name:     name
	}))!
}

pub fn (mut c Client) properties_of_type(snapshot int, project string, type_id int) ![]SymbolResponse {
	return c.symbols_request(snapshot, 'getPropertiesOfType', type_params(snapshot, project,
		type_id))!
}

pub fn (mut c Client) type_of_symbol(snapshot int, project string, symbol_id int) !TypeResponse {
	return c.type_request(snapshot, 'getTypeOfSymbol', c.symbol_params(snapshot, project,
		symbol_id)!)!
}

struct SourceFileParams {
	snapshot int
	project  string
	file     string
}

// source_file_ast requests the binary AST of a project file and indexes it by range.
pub fn (mut c Client) source_file_ast(snapshot int, project string, file string) !SourceFileAst {
	data := c.request('getSourceFile', json2.encode(SourceFileParams{
		snapshot: snapshot
		project:  project
		file:     file
	}))!
	if data.len == 0 {
		return error('tsgo does not have `${file}` in project ${project}')
	}
	return decode_source_file(data)!
}

// source_file_ast_tree requests the binary AST of any program file (lib.*.d.ts and packages
// included) to navigate it, without indexing it by range.
pub fn (mut c Client) source_file_ast_tree(snapshot int, project string, file string) !AstTree {
	data := c.request('getSourceFile', json2.encode(SourceFileParams{
		snapshot: snapshot
		project:  project
		file:     file
	}))!
	if data.len == 0 {
		return error('tsgo does not have `${file}` in project ${project}')
	}
	return decode_source_file_tree(data)!
}

struct LocationsParams {
	snapshot  int
	project   string
	locations []string
}

// types_at_locations gives the type of each node (handles from SourceFileAst.handle), like
// checker.getTypeAtLocation. A node without a type becomes id 0.
pub fn (mut c Client) types_at_locations(snapshot int, project string, locations []string) ![]TypeResponse {
	return c.types_request(snapshot, 'getTypeAtLocations', json2.encode(LocationsParams{
		snapshot:  snapshot
		project:   project
		locations: locations
	}))!
}

// true_type_of_conditional and false_type_of_conditional are the branches of a conditional type
// (getTrueTypeFromConditionalType and getFalseTypeFromConditionalType), with the type arguments
// of the type applied.
pub fn (mut c Client) true_type_of_conditional(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getTrueTypeOfConditionalType', object_params(snapshot,
		project, type_id))!
}

pub fn (mut c Client) false_type_of_conditional(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getFalseTypeOfConditionalType', object_params(snapshot,
		project, type_id))!
}

// part_of_type gives one of the types a type is made of: `getObjectTypeOfType` and
// `getIndexTypeOfType` for an indexed access (`T[K]`), `getCheckTypeOfType` and
// `getExtendsTypeOfType` for a conditional type. tsgo panics when the type is of another kind.
pub fn (mut c Client) part_of_type(method string, snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, method, object_params(snapshot, project, type_id))!
}

// this_parameter_of_signature is the symbol of the `this` parameter of a signature (the int in
// SignatureResponse.this_parameter only tells that it has one).
pub fn (mut c Client) this_parameter_of_signature(snapshot int, project string, signature_id int) !SymbolResponse {
	return c.symbol_request(snapshot, 'getThisParameterOfSignature', object_params(snapshot,
		project, signature_id))!
}

// type_parameters_of_signature is signature.getTypeParameters().
pub fn (mut c Client) type_parameters_of_signature(snapshot int, project string, signature_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getTypeParametersOfSignature', object_params(snapshot,
		project, signature_id))!
}

// widened_type is checker.getWidenedType: for the type of an object literal, the one without the
// freshness that makes TypeScript check excess properties.
pub fn (mut c Client) widened_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getWidenedType', type_params(snapshot, project, type_id))!
}

// non_nullable_type ports checker.getNonNullableType.
pub fn (mut c Client) non_nullable_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getNonNullableType', object_params(snapshot, project,
		type_id))!
}

// alias_type_arguments_of_type gives type.aliasTypeArguments (whole types).
pub fn (mut c Client) alias_type_arguments_of_type(snapshot int, project string, type_id int) ![]TypeResponse {
	return c.types_request(snapshot, 'getAliasTypeArgumentsOfType', object_params(snapshot,
		project, type_id))!
}

struct ProjectParams {
	snapshot int
	project  string
}

// void_type ports checker.getVoidType.
pub fn (mut c Client) void_type(snapshot int, project string) !TypeResponse {
	return c.type_request(snapshot, 'getVoidType', json2.encode(ProjectParams{
		snapshot: snapshot
		project:  project
	}))!
}

pub fn (mut c Client) base_constraint_of_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getBaseConstraintOfType', type_params(snapshot, project,
		type_id))!
}

pub fn (mut c Client) is_array_like_type(snapshot int, project string, type_id int) !bool {
	return decode_response[bool]('isArrayLikeType', c.request('isArrayLikeType', type_params(snapshot,
		project, type_id))!)!
}

pub struct IndexInfoResponse {
pub:
	key_type    TypeResponse @[json: 'keyType']
	value_type  TypeResponse @[json: 'valueType']
	is_readonly bool         @[json: 'isReadonly']
	declaration string // tsgo handle of the index signature, '' if it has none
}

pub fn (mut c Client) index_infos_of_type(snapshot int, project string, type_id int) ![]IndexInfoResponse {
	payload := c.request('getIndexInfosOfType', type_params(snapshot, project, type_id))!
	if is_null_payload(payload) {
		return []IndexInfoResponse{}
	}
	infos := decode_response[[]IndexInfoResponse]('getIndexInfosOfType', payload)!
	return infos.map(IndexInfoResponse{
		...it
		key_type:   c.intern_type(snapshot, it.key_type)
		value_type: c.intern_type(snapshot, it.value_type)
	})
}

// ParameterResponse is a parameter of a signature: its symbol and its declarations. The
// signatures TypeScript synthesizes (when calling a union of different functions) have parameters
// without a declaration.
pub struct ParameterResponse {
pub:
	id                int
	name              string
	flags             u32      // SymbolFlags (Optional…)
	declarations      []string // tsgo handles of its declarations
	value_declaration string   // tsgo handle, '' if none
}

// parameters_of_signature gives the symbols of the parameters (SignatureResponse.parameters only
// has their compact references).
pub fn (mut c Client) parameters_of_signature(snapshot int, project string, signature_id int) ![]ParameterResponse {
	symbols := c.symbols_request(snapshot, 'getParametersOfSignature', object_params(snapshot,
		project, signature_id))!
	return symbols.map(ParameterResponse{
		id:                it.id
		name:              it.name
		flags:             it.flags
		declarations:      it.declarations
		value_declaration: it.value_declaration
	})
}

struct LocationParams {
	snapshot int
	project  string
	location string
}

// symbols_at_locations gives the symbol of each node (handles of any file of the program), like
// checker.getSymbolAtLocation. A node without a symbol gets the null symbol.
pub fn (mut c Client) symbols_at_locations(snapshot int, project string, locations []string) ![]SymbolResponse {
	return c.symbols_request(snapshot, 'getSymbolsAtLocations', json2.encode(LocationsParams{
		snapshot:  snapshot
		project:   project
		locations: locations
	}))!
}

// type_from_type_node gives the type of a type node (its handle), like
// checker.getTypeFromTypeNode.
pub fn (mut c Client) type_from_type_node(snapshot int, project string, location string) !TypeResponse {
	return c.type_request(snapshot, 'getTypeFromTypeNode', json2.encode(LocationParams{
		snapshot: snapshot
		project:  project
		location: location
	}))!
}

// contextual_type gives the contextual type of a node (handle from SourceFileAst.handle), like
// checker.getContextualType. Without a contextual type it returns id 0.
pub fn (mut c Client) contextual_type(snapshot int, project string, location string) !TypeResponse {
	return c.type_request(snapshot, 'getContextualType', json2.encode(LocationParams{
		snapshot: snapshot
		project:  project
		location: location
	}))!
}

// type_of_symbol_at_location gives the type of a symbol as seen from a node (handle from
// SourceFileAst.handle), like checker.getTypeOfSymbolAtLocation. The symbol must have arrived whole
// before in another response.
pub fn (mut c Client) type_of_symbol_at_location(snapshot int, project string, symbol_id int, location string) !TypeResponse {
	reference := c.symbols.reference(symbol_id)!
	params := '{"snapshot":${snapshot},"project":${json2.encode(project)},"symbol":${reference},"location":${json2.encode(location)}}'
	return c.type_request(snapshot, 'getTypeOfSymbolAtLocation', params)!
}

// alias_symbol_of_type gives the alias symbol of a type (type.aliasSymbol), or the null one.
pub fn (mut c Client) alias_symbol_of_type(snapshot int, project string, type_id int) !SymbolResponse {
	return c.symbol_request(snapshot, 'getAliasSymbolOfType', object_params(snapshot, project,
		type_id))!
}

// SourceFileMetadata is the data of a program file used by the typescript-eslint type specifiers
// (program.isSourceFileDefaultLibrary…).
pub struct SourceFileMetadata {
pub:
	is_default_library       bool @[json: 'isDefaultLibrary']
	is_from_external_library bool @[json: 'isFromExternalLibrary']
}

// source_file_metadata gives the metadata of a program file (the null ones if it is not there).
pub fn (mut c Client) source_file_metadata(snapshot int, project string, file string) !SourceFileMetadata {
	payload := c.request('getSourceFileMetadata', json2.encode(SourceFileParams{
		snapshot: snapshot
		project:  project
		file:     file
	}))!
	if is_null_payload(payload) {
		return SourceFileMetadata{}
	}
	return decode_response[SourceFileMetadata]('getSourceFileMetadata', payload)!
}

// TypePredicateResponse is the type predicate of a signature (`x is T`, `asserts x`…); kind 0 when
// the signature has none (TypePredicateKind: This 0, Identifier 1, AssertsThis 2,
// AssertsIdentifier 3).
pub struct TypePredicateResponse {
pub:
	kind            int
	parameter_index int          @[json: 'parameterIndex']
	typ             TypeResponse @[json: 'type']
	found           bool         @[json: '-']
}

// type_predicate_of_signature gives the type predicate of a signature, if any.
pub fn (mut c Client) type_predicate_of_signature(snapshot int, project string, signature_id int) !TypePredicateResponse {
	payload := c.request('getTypePredicateOfSignature', json2.encode(SignatureParams{
		snapshot:  snapshot
		project:   project
		signature: signature_id
	}))!
	if is_null_payload(payload) {
		return TypePredicateResponse{}
	}
	predicate := decode_response[TypePredicateResponse]('getTypePredicateOfSignature', payload)!
	return TypePredicateResponse{
		...predicate
		typ:   c.intern_type(snapshot, predicate.typ)
		found: true
	}
}

struct AssignableParams {
	snapshot int
	project  string
	source   int
	target   int
}

// is_type_assignable_to ports checker.isTypeAssignableTo.
pub fn (mut c Client) is_type_assignable_to(snapshot int, project string, source int, target int) !bool {
	return decode_response[bool]('isTypeAssignableTo', c.request('isTypeAssignableTo', json2.encode(AssignableParams{
		snapshot: snapshot
		project:  project
		source:   source
		target:   target
	}))!)!
}

// target_of_type gives the target of a type reference, with its elementFlags for a tuple.
pub fn (mut c Client) target_of_type(snapshot int, project string, type_id int) !TypeResponse {
	return c.type_request(snapshot, 'getTargetOfType', object_params(snapshot, project, type_id))!
}

// resolved_signature gives the signature TypeScript picks for a call, a `new` or a tagged template
// (handle from SourceFileAst.handle). Without a signature it returns id 0.
pub fn (mut c Client) resolved_signature(snapshot int, project string, location string) !SignatureResponse {
	return c.signature_request(snapshot, 'getResolvedSignature', json2.encode(LocationParams{
		snapshot: snapshot
		project:  project
		location: location
	}))!
}

// signature_from_declaration ports checker.getSignatureFromDeclaration (handle of a function-like
// declaration; tsgo fails with an error on other nodes). Without a signature it returns id 0.
pub fn (mut c Client) signature_from_declaration(snapshot int, project string, location string) !SignatureResponse {
	return c.signature_request(snapshot, 'getSignatureFromDeclaration', json2.encode(LocationParams{
		snapshot: snapshot
		project:  project
		location: location
	}))!
}
