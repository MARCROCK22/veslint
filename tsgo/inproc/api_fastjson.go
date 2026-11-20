// This file is not part of TypeScript: veslint's build (tsgo/inproc/build.sh) adds it to the package
// internal/api of the TypeScript checkout with `go build -overlay`, as api_inprocess.go.

package api

import (
	"fmt"
	"reflect"
	"strconv"

	"github.com/microsoft/TypeScript/tsc/internal/json"
)

// appendFastResponse appends the JSON of the answers most requests of a lint give (types, symbols
// and signatures, alone or in lists) as json.Marshal writes them, byte for byte, without its
// reflection: in a lint of zod json.Marshal took a tenth of TypeScript's time in this process. It
// reports false for any other answer, which json.Marshal then writes. With VESLINT_TSGO_CHECK_JSON
// set, InProcess.Request compares both on every answer.
func appendFastResponse(b []byte, result any) ([]byte, bool) {
	switch r := result.(type) {
	case *TypeResponse:
		return appendTypeResponse(b, r), true
	case []*TypeResponse:
		b = append(b, '[')
		for i, t := range r {
			if i > 0 {
				b = append(b, ',')
			}
			b = appendTypeResponse(b, t)
		}
		return append(b, ']'), true
	case *SymbolResponse:
		return appendSymbolResponse(b, r), true
	case []*SymbolResponse:
		b = append(b, '[')
		for i, s := range r {
			if i > 0 {
				b = append(b, ',')
			}
			b = appendSymbolResponse(b, s)
		}
		return append(b, ']'), true
	case *SignatureResponse:
		return appendSignatureResponse(b, r), true
	case []*SignatureResponse:
		b = append(b, '[')
		for i, s := range r {
			if i > 0 {
				b = append(b, ',')
			}
			b = appendSignatureResponse(b, s)
		}
		return append(b, ']'), true
	}
	return b, false
}

// fastJSONPlain tells whether json.Marshal writes the bytes of s as they are between the quotes:
// printable ASCII without `"` and `\`. Any other string goes through json.Marshal.
func fastJSONPlain(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < 0x20 || c >= 0x7f || c == '"' || c == '\\' {
			return false
		}
	}
	return true
}

func appendJSONString(b []byte, s string) []byte {
	if fastJSONPlain(s) {
		b = append(b, '"')
		b = append(b, s...)
		return append(b, '"')
	}
	out, err := json.Marshal(s)
	if err != nil {
		panic("veslint: marshaling a string: " + err.Error())
	}
	return append(b, out...)
}

// appendJSONAny is a field of type `any` (TypeResponse.Value): what literalValueToJSON gives.
func appendJSONAny(b []byte, v any) []byte {
	switch x := v.(type) {
	case nil:
		return append(b, "null"...)
	case string:
		return appendJSONString(b, x)
	case bool:
		return strconv.AppendBool(b, x)
	}
	out, err := json.Marshal(v)
	if err != nil {
		panic("veslint: marshaling a value: " + err.Error())
	}
	return append(b, out...)
}

func appendKey(b []byte, first *bool, key string) []byte {
	if *first {
		*first = false
		b = append(b, '{')
	} else {
		b = append(b, ',')
	}
	b = append(b, '"')
	b = append(b, key...)
	return append(b, '"', ':')
}

func appendTypeIDs(b []byte, ids []TypeID) []byte {
	b = append(b, '[')
	for i, id := range ids {
		if i > 0 {
			b = append(b, ',')
		}
		b = strconv.AppendUint(b, uint64(id), 10)
	}
	return append(b, ']')
}

func appendStrings[S ~string](b []byte, values []S) []byte {
	b = append(b, '[')
	for i, s := range values {
		if i > 0 {
			b = append(b, ',')
		}
		b = appendJSONString(b, string(s))
	}
	return append(b, ']')
}

func appendCompactSymbolReference(b []byte, r *CompactSymbolReference) []byte {
	b = append(b, `{"id":`...)
	b = strconv.AppendUint(b, uint64(r.Id), 10)
	if r.File != "" {
		b = append(b, `,"file":`...)
		b = appendJSONString(b, r.File)
	}
	return append(b, '}')
}

// The fields below are those of proto.go, in its order, with its `omitempty` (no empty string,
// array or object, or null) and `omitzero` (no zero value).

func appendTypeResponse(b []byte, t *TypeResponse) []byte {
	if t == nil {
		return append(b, "null"...)
	}
	first := true
	b = appendKey(b, &first, "id")
	b = strconv.AppendUint(b, uint64(t.Id), 10)
	b = appendKey(b, &first, "flags")
	b = strconv.AppendUint(b, uint64(t.Flags), 10)
	b = appendKey(b, &first, "objectFlags")
	b = strconv.AppendUint(b, uint64(t.ObjectFlags), 10)
	b = appendKey(b, &first, "isTupleType")
	b = strconv.AppendBool(b, t.IsTupleType)
	b = appendKey(b, &first, "value")
	b = appendJSONAny(b, t.Value)
	b = appendTypeIDField(b, &first, "target", t.Target)
	b = appendTypeIDsField(b, &first, "typeParameters", t.TypeParameters)
	b = appendTypeIDsField(b, &first, "outerTypeParameters", t.OuterTypeParameters)
	b = appendTypeIDsField(b, &first, "localTypeParameters", t.LocalTypeParameters)
	if len(t.ElementFlags) > 0 {
		b = appendKey(b, &first, "elementFlags")
		b = append(b, '[')
		for i, f := range t.ElementFlags {
			if i > 0 {
				b = append(b, ',')
			}
			b = strconv.AppendUint(b, uint64(f), 10)
		}
		b = append(b, ']')
	}
	if t.FixedLength != nil {
		b = appendKey(b, &first, "fixedLength")
		b = strconv.AppendInt(b, int64(*t.FixedLength), 10)
	}
	if t.TupleReadonly != nil {
		b = appendKey(b, &first, "readonly")
		b = strconv.AppendBool(b, *t.TupleReadonly)
	}
	if len(t.LabeledElementDeclarations) > 0 {
		b = appendKey(b, &first, "labeledElementDeclarations")
		b = appendStrings(b, t.LabeledElementDeclarations)
	}
	b = appendTypeIDField(b, &first, "objectType", t.ObjectType)
	b = appendTypeIDField(b, &first, "indexType", t.IndexType)
	b = appendTypeIDField(b, &first, "checkType", t.CheckType)
	b = appendTypeIDField(b, &first, "extendsType", t.ExtendsType)
	b = appendTypeIDField(b, &first, "baseType", t.BaseType)
	b = appendTypeIDField(b, &first, "substConstraint", t.SubstConstraint)
	b = appendTypeIDField(b, &first, "typeParameter", t.TypeParameter)
	b = appendTypeIDField(b, &first, "constraintType", t.ConstraintType)
	b = appendTypeIDField(b, &first, "nameType", t.NameType)
	b = appendTypeIDField(b, &first, "templateType", t.TemplateType)
	if len(t.Texts) > 0 {
		b = appendKey(b, &first, "texts")
		b = appendStrings(b, t.Texts)
	}
	b = appendTypeIDField(b, &first, "freshType", t.FreshType)
	b = appendTypeIDField(b, &first, "regularType", t.RegularType)
	b = appendKey(b, &first, "isThisType")
	b = strconv.AppendBool(b, t.IsThisType)
	b = appendTypeIDField(b, &first, "thisType", t.ThisType)
	if t.IntrinsicName != "" {
		b = appendKey(b, &first, "intrinsicName")
		b = appendJSONString(b, t.IntrinsicName)
	}
	b = appendTypeIDsField(b, &first, "aliasTypeArguments", t.AliasTypeArguments)
	if t.AliasSymbol != nil {
		b = appendKey(b, &first, "aliasSymbol")
		b = appendCompactSymbolReference(b, t.AliasSymbol)
	}
	if t.Symbol != nil {
		b = appendKey(b, &first, "symbol")
		b = appendCompactSymbolReference(b, t.Symbol)
	}
	return append(b, '}')
}

func appendTypeIDField(b []byte, first *bool, key string, id TypeID) []byte {
	if id == 0 {
		return b
	}
	b = appendKey(b, first, key)
	return strconv.AppendUint(b, uint64(id), 10)
}

func appendTypeIDsField(b []byte, first *bool, key string, ids []TypeID) []byte {
	if len(ids) == 0 {
		return b
	}
	b = appendKey(b, first, key)
	return appendTypeIDs(b, ids)
}

func appendSymbolResponse(b []byte, s *SymbolResponse) []byte {
	if s == nil {
		return append(b, "null"...)
	}
	b = append(b, `{"reference":{"kind":`...)
	r := &s.Reference
	b = strconv.AppendUint(b, uint64(r.Kind), 10)
	if f := r.File; f != nil {
		b = append(b, `,"file":{"fileName":`...)
		b = appendJSONString(b, string(f.FileName))
		b = append(b, `,"path":`...)
		b = appendJSONString(b, string(f.Path))
		b = append(b, `,"contentHash":`...)
		b = appendJSONString(b, f.ContentHash)
		b = append(b, `,"parseOptionsKey":`...)
		b = appendJSONString(b, f.ParseOptionsKey)
		b = append(b, `,"scriptKind":`...)
		b = strconv.AppendInt(b, int64(f.ScriptKind), 10)
		b = append(b, `,"nodeId":`...)
		b = appendJSONString(b, f.NodeID)
		b = append(b, '}')
	}
	if r.Snapshot != 0 {
		b = append(b, `,"snapshot":`...)
		b = strconv.AppendUint(b, uint64(r.Snapshot), 10)
	}
	if r.Project != "" {
		b = append(b, `,"project":`...)
		b = appendJSONString(b, string(r.Project))
	}
	b = append(b, `,"id":`...)
	b = strconv.AppendUint(b, uint64(r.Id), 10)
	b = append(b, `},"name":`...)
	b = appendJSONString(b, s.Name)
	b = append(b, `,"flags":`...)
	b = strconv.AppendUint(b, uint64(s.Flags), 10)
	b = append(b, `,"checkFlags":`...)
	b = strconv.AppendUint(b, uint64(s.CheckFlags), 10)
	if len(s.Declarations) > 0 {
		b = append(b, `,"declarations":`...)
		b = appendStrings(b, s.Declarations)
	}
	if s.ValueDeclaration != "" {
		b = append(b, `,"valueDeclaration":`...)
		b = appendJSONString(b, string(s.ValueDeclaration))
	}
	if s.Parent != nil {
		b = append(b, `,"parent":`...)
		b = appendCompactSymbolReference(b, s.Parent)
	}
	if s.ExportSymbol != nil {
		b = append(b, `,"exportSymbol":`...)
		b = appendCompactSymbolReference(b, s.ExportSymbol)
	}
	return append(b, '}')
}

func appendSignatureResponse(b []byte, s *SignatureResponse) []byte {
	if s == nil {
		return append(b, "null"...)
	}
	b = append(b, `{"id":`...)
	b = strconv.AppendUint(b, uint64(s.Id), 10)
	b = append(b, `,"flags":`...)
	b = strconv.AppendUint(b, uint64(s.Flags), 10)
	if s.Declaration != "" {
		b = append(b, `,"declaration":`...)
		b = appendJSONString(b, string(s.Declaration))
	}
	if len(s.TypeParameters) > 0 {
		b = append(b, `,"typeParameters":`...)
		b = appendTypeIDs(b, s.TypeParameters)
	}
	if len(s.Parameters) > 0 {
		b = append(b, `,"parameters":[`...)
		for i := range s.Parameters {
			if i > 0 {
				b = append(b, ',')
			}
			b = appendCompactSymbolReference(b, &s.Parameters[i])
		}
		b = append(b, ']')
	}
	if s.ThisParameter != nil {
		b = append(b, `,"thisParameter":`...)
		b = appendCompactSymbolReference(b, s.ThisParameter)
	}
	if s.Target != 0 {
		b = append(b, `,"target":`...)
		b = strconv.AppendUint(b, uint64(s.Target), 10)
	}
	return append(b, '}')
}

// veslintUnmarshalPayload is unmarshalPayload (proto.go) with the parameters of the requests a
// lint sends most read by hand: those are flat objects of numbers, strings and lists of strings,
// and json.Unmarshal's reflection took a twentieth of TypeScript's time in this process. Anything
// the hand-written reader does not expect (another key, a key twice, an escape, a byte outside
// printable ASCII, a number with a sign, a fraction, an exponent, a leading zero or too large for
// its field, a null) goes to unmarshalPayload, which then answers as it always did. With
// VESLINT_TSGO_CHECK_JSON set, every parameter read by hand is compared with unmarshalPayload's.
func veslintUnmarshalPayload(method string, payload json.Value) (any, error) {
	parsed := fastParams(method, payload)
	if parsed == nil {
		return unmarshalPayload(method, payload)
	}
	if checkFastJSON {
		want, err := unmarshalPayload(method, payload)
		if err != nil || !reflect.DeepEqual(want, parsed) {
			panic(fmt.Sprintf("veslint: the parameters of %s read by hand are not json.Unmarshal's:\n%s\n%#v\n%#v", method, payload, parsed, want))
		}
	}
	return parsed, nil
}

// fastParams reads the parameters of `method` by hand, or answers nil.
func fastParams(method string, payload []byte) any {
	switch Method(method) {
	case MethodGetTypeAtLocations:
		p := &GetTypeAtLocationsParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "locations":
				return r.handles(&p.Locations)
			}
			return false
		}) {
			return p
		}
	case MethodGetSymbolsAtLocations:
		p := &GetSymbolsAtLocationsParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "locations":
				return r.handles(&p.Locations)
			}
			return false
		}) {
			return p
		}
	case MethodGetPropertyOfType, MethodGetTypeOfPropertyOfType:
		p := &GetPropertyOfTypeParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "type":
				return r.uint32((*uint32)(&p.Type))
			case "name":
				return r.str(&p.Name)
			}
			return false
		}) {
			return p
		}
	case MethodGetSignaturesOfType:
		p := &GetSignaturesOfTypeParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "type":
				return r.uint32((*uint32)(&p.Type))
			case "kind":
				var kind uint32
				if !r.uint32(&kind) || kind > 1<<31-1 {
					return false
				}
				p.Kind = int32(kind)
				return true
			}
			return false
		}) {
			return p
		}
	case MethodGetAwaitedType, MethodGetBaseTypes, MethodGetPropertiesOfType, MethodGetIndexInfosOfType,
		MethodGetBaseConstraintOfType, MethodGetTypeArguments, MethodIsArrayType:
		p := &CheckerTypeParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "type":
				return r.uint32((*uint32)(&p.Type))
			}
			return false
		}) {
			return p
		}
	case MethodGetSymbolOfType, MethodGetTargetOfType, MethodGetTypesOfType, MethodGetAliasTypeArgumentsOfType,
		MethodGetAliasSymbolOfType, MethodGetNonNullableType, MethodGetApparentPropertiesOfType,
		MethodGetApparentType:
		p := &GetTypePropertyParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "objectId":
				return r.uint32((*uint32)(&p.Type))
			}
			return false
		}) {
			return p
		}
	case MethodGetTypeParametersOfSignature, MethodGetParametersOfSignature, MethodGetReturnTypeOfSignature:
		p := &GetSignaturePropertyParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "objectId":
				return r.uint(64, (*uint64)(&p.Signature))
			}
			return false
		}) {
			return p
		}
	case MethodGetContextualType, MethodIsContextSensitive:
		p := &GetContextualTypeParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "location":
				return r.str((*string)(&p.Location))
			}
			return false
		}) {
			return p
		}
	case MethodIsTypeAssignableTo:
		p := &IsTypeAssignableToParams{}
		if readFastParams(payload, func(r *fastParamsReader, key string) bool {
			switch key {
			case "snapshot":
				return r.uint(64, (*uint64)(&p.Snapshot))
			case "project":
				return r.str((*string)(&p.Project))
			case "source":
				return r.uint32((*uint32)(&p.Source))
			case "target":
				return r.uint32((*uint32)(&p.Target))
			}
			return false
		}) {
			return p
		}
	}
	return nil
}

// fastParamsReader reads a JSON object of the shapes fastParams knows.
type fastParamsReader struct {
	b    []byte
	i    int
	seen []string
}

// readFastParams reads the members of the object in `b`, each with `member`, which reads the
// value of a key it knows and reports false for any other. It reports false when anything is not
// as expected, and nothing it read is used then.
func readFastParams(b []byte, member func(r *fastParamsReader, key string) bool) bool {
	r := fastParamsReader{b: b}
	r.space()
	if !r.byte('{') {
		return false
	}
	r.space()
	if r.byte('}') {
		r.space()
		return r.i == len(r.b)
	}
	for {
		r.space()
		var key string
		if !r.str(&key) {
			return false
		}
		for _, k := range r.seen {
			if k == key {
				return false
			}
		}
		r.seen = append(r.seen, key)
		r.space()
		if !r.byte(':') {
			return false
		}
		r.space()
		if !member(&r, key) {
			return false
		}
		r.space()
		if r.byte(',') {
			continue
		}
		if !r.byte('}') {
			return false
		}
		r.space()
		return r.i == len(r.b)
	}
}

func (r *fastParamsReader) space() {
	for r.i < len(r.b) {
		switch r.b[r.i] {
		case ' ', '\t', '\n', '\r':
			r.i++
		default:
			return
		}
	}
}

func (r *fastParamsReader) byte(c byte) bool {
	if r.i < len(r.b) && r.b[r.i] == c {
		r.i++
		return true
	}
	return false
}

// str reads a string of printable ASCII without escapes.
func (r *fastParamsReader) str(out *string) bool {
	if !r.byte('"') {
		return false
	}
	start := r.i
	for r.i < len(r.b) {
		c := r.b[r.i]
		if c == '"' {
			*out = string(r.b[start:r.i])
			r.i++
			return true
		}
		if c < 0x20 || c >= 0x7f || c == '\\' {
			return false
		}
		r.i++
	}
	return false
}

// uint reads a non-negative integer of at most `bits` bits, without a sign, a leading zero, a
// fraction or an exponent.
func (r *fastParamsReader) uint(bits int, out *uint64) bool {
	start := r.i
	limit := ^uint64(0) >> (64 - bits)
	var v uint64
	for r.i < len(r.b) && r.b[r.i] >= '0' && r.b[r.i] <= '9' {
		d := uint64(r.b[r.i] - '0')
		if v > (limit-d)/10 {
			return false
		}
		v = v*10 + d
		r.i++
	}
	n := r.i - start
	if n == 0 || (n > 1 && r.b[start] == '0') {
		return false
	}
	if r.i < len(r.b) {
		switch r.b[r.i] {
		case '.', 'e', 'E':
			return false
		}
	}
	*out = v
	return true
}

func (r *fastParamsReader) uint32(out *uint32) bool {
	var v uint64
	if !r.uint(32, &v) {
		return false
	}
	*out = uint32(v)
	return true
}

// handles reads a list of node handles (strings).
func (r *fastParamsReader) handles(out *[]NodeHandle) bool {
	if !r.byte('[') {
		return false
	}
	list := []NodeHandle{}
	r.space()
	if r.byte(']') {
		*out = list
		return true
	}
	for {
		r.space()
		var s string
		if !r.str(&s) {
			return false
		}
		list = append(list, NodeHandle(s))
		r.space()
		if r.byte(',') {
			continue
		}
		if !r.byte(']') {
			return false
		}
		*out = list
		return true
	}
}
