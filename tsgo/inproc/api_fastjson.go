// This file is not part of TypeScript: veslint's build (tsgo/inproc/build.sh) adds it to the package
// internal/api of the TypeScript checkout with `go build -overlay`, as api_inprocess.go.

package api

import (
	"context"
	"encoding/binary"
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"sync"

	"github.com/microsoft/TypeScript/tsc/internal/api/encoder"
	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/checker"
	"github.com/microsoft/TypeScript/tsc/internal/compiler"
	"github.com/microsoft/TypeScript/tsc/internal/json"
	"github.com/microsoft/TypeScript/tsc/internal/project"
	"github.com/microsoft/TypeScript/tsc/internal/tspath"
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

// uint32s reads a list of numbers of 32 bits.
func (r *fastParamsReader) uint32s(out *[]uint32) bool {
	if !r.byte('[') {
		return false
	}
	list := []uint32{}
	r.space()
	if r.byte(']') {
		*out = list
		return true
	}
	for {
		r.space()
		var v uint32
		if !r.uint32(&v) {
			return false
		}
		list = append(list, v)
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

// Types sent once. A lint asks for the types of hundreds of thousands of nodes, and most of the
// answers are a type the worker was sent before: on the TypeScript compiler 1.02 million types
// came back as 144 MB of JSON, of 96,000 different types, and writing and reading them was a
// tenth of the lint. The methods veslint/typesAtLocations and veslint/typesOfType answer what
// getTypeAtLocations and getTypesOfType answer, but a type the client was already sent whole in
// the same snapshot and project (the registry of a worker) is its id alone. The answer is a JSON
// array whose elements are `null`, an id or a TypeResponse.
//
// Of what TypeResponse holds, only objectFlags changes after a type is made (the checker caches
// what it computed about the type there, such as CouldContainTypeVariables), so a type whose flags
// are not the ones it was sent with is sent whole again: the client then has what
// getTypeAtLocations would have answered. The other fields that may change later (FreshType,
// RegularType, ThisType) are not read by the client.

// veslintSentTypes are the types of a project registry sent whole, with the objectFlags they were
// sent with.
type veslintSentTypes struct {
	mu   sync.Mutex
	sent map[TypeID]uint32
}

// veslintSentFlags is what a TypeResponse of `t` holds in objectFlags (newTypeResponse sets it for
// object types only).
func veslintSentFlags(t *checker.Type) uint32 {
	if t.Flags()&checker.TypeFlagsObject == 0 {
		return 0
	}
	return uint32(t.ObjectFlags())
}

// veslintTypeWriter writes the types of one answer; it holds the registry's sent types until done.
type veslintTypeWriter struct {
	setup checkerSetup
	sent  *veslintSentTypes
	// full: also the TypeResponse of every type, for the check of the client
	// (veslint/typesAtLocationsChecked).
	full []*TypeResponse
	keep bool
}

func newVeslintTypeWriter(setup checkerSetup, keepFull bool) *veslintTypeWriter {
	sent := &setup.sd.getOrCreateProjectRegistry(setup.projectID).veslintSent
	sent.mu.Lock()
	if sent.sent == nil {
		sent.sent = map[TypeID]uint32{}
	}
	return &veslintTypeWriter{setup: setup, sent: sent, keep: keepFull}
}

func (w *veslintTypeWriter) done() {
	w.sent.mu.Unlock()
}

// append writes `t`: its id when the client has it, else the TypeResponse newTypeResponse makes
// (which also registers it).
func (w *veslintTypeWriter) append(b []byte, t *checker.Type) []byte {
	if t == nil {
		if w.keep {
			w.full = append(w.full, nil)
		}
		return append(b, "null"...)
	}
	id := TypeHandle(t)
	flags := veslintSentFlags(t)
	if sent, ok := w.sent.sent[id]; ok && sent == flags && !w.keep {
		return strconv.AppendUint(b, uint64(id), 10)
	}
	resp := w.setup.sd.newTypeResponse(w.setup.projectID, t, w.setup.checker)
	if w.keep {
		w.full = append(w.full, resp)
		if sent, ok := w.sent.sent[id]; ok && sent == flags {
			return strconv.AppendUint(b, uint64(id), 10)
		}
	}
	w.sent.sent[id] = flags
	start := len(b)
	b = appendTypeResponse(b, resp)
	if checkFastJSON {
		checkFastResponse("TypeResponse", resp, b[start:])
	}
	return b
}

// finish closes the array; with keepFull, a line with the JSON getTypeAtLocations would have
// answered follows it.
func (w *veslintTypeWriter) finish(b []byte) []byte {
	b = append(b, ']')
	if w.keep {
		b = append(b, '\n')
		if w.full == nil {
			return append(b, "null"...)
		}
		out, err := json.Marshal(w.full)
		if err != nil {
			panic("veslint: marshaling the types: " + err.Error())
		}
		b = append(b, out...)
	}
	return b
}

// veslintTypesAtLocationsParams are the parameters of veslint/typesAtLocations: the nodes as
// getTypeAtLocations takes them (Locations, their handles), or the nodes of one file (File, the
// path a handle ends with, and Nodes, the index and the kind of each node, one after the other),
// which the client then does not write as a handle each: the path made most of the bytes of a
// request.
type veslintTypesAtLocationsParams struct {
	Snapshot  SnapshotID   `json:"snapshot"`
	Project   project.ID   `json:"project"`
	Locations []NodeHandle `json:"locations"`
	File      string       `json:"file"`
	Nodes     []uint32     `json:"nodes"`
}

func readTypesAtLocationsParams(params []byte) (*veslintTypesAtLocationsParams, error) {
	p := &veslintTypesAtLocationsParams{}
	if !readFastParams(params, func(r *fastParamsReader, key string) bool {
		switch key {
		case "snapshot":
			return r.uint(64, (*uint64)(&p.Snapshot))
		case "project":
			return r.str((*string)(&p.Project))
		case "locations":
			return r.handles(&p.Locations)
		case "file":
			return r.str(&p.File)
		case "nodes":
			return r.uint32s(&p.Nodes)
		}
		return false
	}) {
		p = &veslintTypesAtLocationsParams{}
		if err := json.Unmarshal(params, p); err != nil {
			return nil, err
		}
		return p, nil
	}
	if checkFastJSON {
		want := &veslintTypesAtLocationsParams{}
		if err := json.Unmarshal(params, want); err != nil || !reflect.DeepEqual(want, p) {
			panic(fmt.Sprintf("veslint: the parameters of typesAtLocations read by hand are not json.Unmarshal's:\n%s\n%#v\n%#v", params, p, want))
		}
	}
	return p, nil
}

// typesAtLocations is handleGetTypeAtLocations with types sent once. veslint/typesAtNodes takes the
// nodes of a file in binary parameters (readBinaryParams: File and Nodes), which neither side
// writes or reads as decimal text.
func (p *InProcess) typesAtLocations(ctx context.Context, worker int, params []byte, checked bool, binaryParams bool) (any, error) {
	var in *veslintTypesAtLocationsParams
	var err error
	if binaryParams {
		in = &veslintTypesAtLocationsParams{}
		in.Snapshot, in.Project, in.File, in.Nodes, err = readBinaryParams(params)
	} else {
		in, err = readTypesAtLocationsParams(params)
	}
	if err != nil {
		return nil, fmt.Errorf("%w: %w", ErrInvalidRequest, err)
	}
	if len(in.Nodes)%2 != 0 {
		return nil, fmt.Errorf("%w: typesAtLocations: nodes without a kind", ErrInvalidRequest)
	}
	setup, err := p.veslintSetup(ctx, worker, in.Snapshot, in.Project)
	if err != nil {
		return nil, err
	}
	defer setup.done()
	w := newVeslintTypeWriter(setup, checked)
	defer w.done()
	count := len(in.Locations) + len(in.Nodes)/2
	b := make([]byte, 0, 8*count+2)
	b = append(b, '[')
	var nodes veslintNodeResolver
	for i, loc := range in.Locations {
		node, err := nodes.resolve(setup.sd, setup.program, loc)
		if err != nil {
			return nil, err
		}
		if i > 0 {
			b = append(b, ',')
		}
		// GetTypeAtLocation never answers nil (handleGetTypeAtLocations).
		b = w.append(b, setup.checker.GetTypeAtLocation(node))
	}
	if len(in.Nodes) > 0 {
		file := veslintFileNodes(setup.program, in.File)
		for i := 0; i < len(in.Nodes); i += 2 {
			node, err := file.node(in.Nodes[i], in.Nodes[i+1], in.File)
			if err != nil {
				return nil, err
			}
			if i > 0 || len(in.Locations) > 0 {
				b = append(b, ',')
			}
			b = w.append(b, setup.checker.GetTypeAtLocation(node))
		}
	}
	return RawBinary(w.finish(b)), nil
}

// veslintFile is the index table of a file of a program, to resolve the nodes of the file that
// typesAtLocations takes by index as resolveNodeHandle resolves their handles.
type veslintFile struct {
	valid bool // the path is one a handle may end with
	table *encoder.NodeIndexTable
}

func veslintFileNodes(program *compiler.Program, path string) veslintFile {
	key, ok := tspath.TryPathKeyFromCanonical(path)
	if !ok {
		return veslintFile{}
	}
	file := veslintFile{valid: true}
	if sourceFile := program.GetSourceFileByPath(key); sourceFile != nil {
		file.table = encoder.GetNodeIndexTable(sourceFile)
	}
	return file
}

// node is the node of a handle `index.kind.path`, with resolveNodeHandle's errors.
func (f veslintFile) node(index uint32, kind uint32, path string) (*ast.Node, error) {
	if !f.valid {
		return nil, fmt.Errorf("%w: invalid node handle %q", ErrClientError, fmt.Sprintf("%d.%d.%s", index, kind, path))
	}
	if f.table != nil && int(index) < len(f.table.Nodes) {
		if node := f.table.Nodes[index]; node != nil {
			return node, nil
		}
	}
	return nil, fmt.Errorf("%w: node handle %q could not be resolved (file may not be loaded or handle may be stale)", ErrClientError, fmt.Sprintf("%d.%d.%s", index, kind, path))
}

// readBinaryParams reads the parameters of veslint/nodesAtRanges and veslint/typesAtNodes, written
// by the client in binary, little-endian: the snapshot (64 bits), the project and the file (each a
// length of 32 bits and its bytes) and a list of numbers of 32 bits (its length, then the numbers).
// The lists are long (two or three numbers for each node a rule asks about), and as decimal text
// they were a large part of what the client wrote and this process read.
func readBinaryParams(b []byte) (SnapshotID, project.ID, string, []uint32, error) {
	r := binaryParamsReader{b: b}
	snapshot := SnapshotID(r.uint64())
	projectID := project.ID(r.text())
	file := r.text()
	count := int(r.uint32())
	if r.failed || count < 0 || len(r.b)-r.i != 4*count {
		return 0, "", "", nil, fmt.Errorf("malformed binary parameters (%d bytes)", len(b))
	}
	values := make([]uint32, count)
	for i := range values {
		values[i] = binary.LittleEndian.Uint32(r.b[r.i+4*i:])
	}
	return snapshot, projectID, file, values, nil
}

type binaryParamsReader struct {
	b      []byte
	i      int
	failed bool
}

func (r *binaryParamsReader) take(n int) []byte {
	if r.failed || n < 0 || len(r.b)-r.i < n {
		r.failed = true
		return nil
	}
	r.i += n
	return r.b[r.i-n : r.i]
}

func (r *binaryParamsReader) uint32() uint32 {
	if b := r.take(4); b != nil {
		return binary.LittleEndian.Uint32(b)
	}
	return 0
}

func (r *binaryParamsReader) uint64() uint64 {
	if b := r.take(8); b != nil {
		return binary.LittleEndian.Uint64(b)
	}
	return 0
}

func (r *binaryParamsReader) text() string {
	return string(r.take(int(r.uint32())))
}

// nodesAtRanges finds nodes of a file of the program by their range, as the client found them in
// the whole binary AST of the file (getSourceFile) before: for each range, the index (in the node
// table getSourceFile would send) and the SyntaxKind of the innermost node with exactly that range
// and, if the kind asked is not 0, that kind; index 0 when there is none. The answer is binary,
// little-endian: the length of the file's path (the one of its node handles), the path, and two
// numbers of 32 bits per range. Nothing when the program does not have the file, as getSourceFile.
// The client needs the AST of the file only to find its nodes, nearly always: encoding every node
// of the file (and decoding and indexing it in V) cost more than the lookups.
func (p *InProcess) nodesAtRanges(worker int, params []byte) (any, error) {
	snapshot, projectID, fileName, ranges, err := readBinaryParams(params)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", ErrInvalidRequest, err)
	}
	if len(ranges)%3 != 0 {
		return nil, fmt.Errorf("%w: nodesAtRanges: ranges without an end or a kind", ErrInvalidRequest)
	}
	if fileName == "" {
		// As getSourceFile's parameters (DocumentIdentifier) reject it.
		return nil, fmt.Errorf("%w: DocumentIdentifier: file name must not be empty", ErrInvalidRequest)
	}
	sd, err := p.session.getSnapshotData(snapshot)
	if err != nil {
		return nil, err
	}
	program, err := sd.getProgram(projectID)
	if err != nil {
		return nil, err
	}
	file := DocumentIdentifier{FileName: fileName}
	sourceFile := program.GetSourceFile(file.ToFileName(program.BaseDirectory()))
	if sourceFile == nil {
		return RawBinary(nil), nil
	}
	index := p.rangeIndex(worker, sourceFile)
	path := sourceFile.PathKey()
	count := len(ranges) / 3
	b := make([]byte, 0, 4+len(path)+8*count)
	b = binary.LittleEndian.AppendUint32(b, uint32(len(path)))
	b = append(b, path...)
	for i := 0; i < len(ranges); i += 3 {
		node, kind := index.find(int32(ranges[i]), int32(ranges[i+1]), ranges[i+2])
		b = binary.LittleEndian.AppendUint32(b, node)
		b = binary.LittleEndian.AppendUint32(b, kind)
	}
	return RawBinary(b), nil
}

// veslintRangeIndex gives the nodes of a file by the UTF-16 unit where they start (with their
// leading trivia), as the encoder writes their positions: order[starts[u+1]:starts[u+2]] are the
// indexes of the nodes that start at u, in the order of the node table, and ends[i] is the end of
// node i. It is built in one pass over the file's index table (the nodes in the encoder's order)
// and a counting sort, without encoding anything. NodeLists, which have no node, and nodes without
// a range are not in it, as the client skipped their rows.
type veslintRangeIndex struct {
	file   *ast.SourceFile
	nodes  []*ast.Node
	starts []uint32
	order  []uint32
	ends   []int32
}

func buildRangeIndex(sourceFile *ast.SourceFile) *veslintRangeIndex {
	table := encoder.GetNodeIndexTable(sourceFile)
	positionMap := sourceFile.GetPositionMap()
	ascii := positionMap.IsAsciiOnly()
	// The positions as the encoder writes them (uint32 of the UTF-16 offset) and the client reads
	// them (as int32).
	utf16 := func(pos int) int32 {
		if ascii {
			return int32(uint32(pos))
		}
		return int32(uint32(positionMap.UTF8ToUTF16(pos)))
	}
	nodes := table.Nodes
	pos := make([]int32, len(nodes))
	ends := make([]int32, len(nodes))
	last := int32(-1)
	count := 0
	for i, node := range nodes {
		pos[i] = -1
		if i < 1 || node == nil {
			continue
		}
		start, end := utf16(node.Pos()), utf16(node.End())
		if start < 0 || end < start {
			continue
		}
		pos[i], ends[i] = start, end
		last = max(last, start)
		count++
	}
	// A counting sort: the count of each start at starts[u+1], summed up to each start, and the nodes
	// placed from the last to the first, each at the end of the room left for its start, which leaves
	// starts[u+1] at the first of u's and starts[u+2] at the first of the next start's (or at the
	// count).
	starts := make([]uint32, last+3)
	for _, start := range pos {
		if start >= 0 {
			starts[start+1]++
		}
	}
	for u := 1; u < len(starts)-1; u++ {
		starts[u] += starts[u-1]
	}
	starts[len(starts)-1] = uint32(count)
	order := make([]uint32, count)
	for i := len(pos) - 1; i >= 0; i-- {
		if start := pos[i]; start >= 0 {
			starts[start+1]--
			order[starts[start+1]] = uint32(i)
		}
	}
	return &veslintRangeIndex{file: sourceFile, nodes: nodes, starts: starts, order: order, ends: ends}
}

// find is the innermost node (the last in the table) with that range and, if `kind` is not 0, that
// kind: its index and kind, or 0 and 0.
func (x *veslintRangeIndex) find(pos int32, end int32, kind uint32) (uint32, uint32) {
	if pos < 0 || int(pos) >= len(x.starts)-2 {
		return 0, 0
	}
	for at := int(x.starts[pos+2]) - 1; at >= int(x.starts[pos+1]); at-- {
		i := x.order[at]
		if x.ends[i] != end {
			continue
		}
		nodeKind := uint32(x.nodes[i].Kind)
		if kind == 0 || nodeKind == kind {
			return i, nodeKind
		}
	}
	return 0, 0
}

// veslintRangeIndexes keeps the range index of the last file each worker asked about: a worker
// lints one file at a time and asks about it several times (once per group of rules' nodes).
type veslintRangeIndexes struct {
	mu       sync.Mutex
	byWorker map[int]*veslintRangeIndex
}

func (p *InProcess) rangeIndex(worker int, sourceFile *ast.SourceFile) *veslintRangeIndex {
	p.ranges.mu.Lock()
	index := p.ranges.byWorker[worker]
	p.ranges.mu.Unlock()
	if index != nil && index.file == sourceFile {
		return index
	}
	index = buildRangeIndex(sourceFile)
	p.ranges.mu.Lock()
	if p.ranges.byWorker == nil {
		p.ranges.byWorker = map[int]*veslintRangeIndex{}
	}
	p.ranges.byWorker[worker] = index
	p.ranges.mu.Unlock()
	return index
}

// typesOfType is handleGetTypesOfType (resolveTypeArrayPropertyOfType) with types sent once: null
// for a type without parts.
func (p *InProcess) typesOfType(ctx context.Context, worker int, params []byte, checked bool) (any, error) {
	parsed, err := veslintUnmarshalPayload(string(MethodGetTypesOfType), params)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", ErrInvalidRequest, err)
	}
	in := parsed.(*GetTypePropertyParams)
	setup, err := p.veslintSetup(ctx, worker, in.Snapshot, in.Project)
	if err != nil {
		return nil, err
	}
	defer setup.done()
	t, err := setup.resolveTypeHandle(in.Type)
	if err != nil {
		return nil, err
	}
	types := t.Types()
	if len(types) == 0 {
		return RawBinary("null"), nil
	}
	w := newVeslintTypeWriter(setup, checked)
	defer w.done()
	b := make([]byte, 0, 8*len(types)+2)
	b = append(b, '[')
	for i, sub := range types {
		if i > 0 {
			b = append(b, ',')
		}
		b = w.append(b, sub)
	}
	return RawBinary(w.finish(b)), nil
}

// veslintNodeResolver is snapshotData.resolveNodeHandle for the handles of one request, which are
// nearly always in one file: the file and its index table are looked up once per file, not once
// per handle. Its errors are resolveNodeHandle's.
type veslintNodeResolver struct {
	path  string
	table *encoder.NodeIndexTable
}

func (r *veslintNodeResolver) resolve(sd *snapshotData, program *compiler.Program, handle NodeHandle) (*ast.Node, error) {
	s := string(handle)
	firstDot := strings.IndexByte(s, '.')
	if firstDot == -1 {
		return nil, fmt.Errorf("%w: invalid node handle %q", ErrClientError, handle)
	}
	secondDot := strings.IndexByte(s[firstDot+1:], '.')
	if secondDot == -1 {
		return nil, fmt.Errorf("%w: invalid node handle %q", ErrClientError, handle)
	}
	secondDot += firstDot + 1
	path := s[secondDot+1:]
	if r.table == nil || path != r.path {
		return r.resolveSlow(sd, program, handle, path)
	}
	idx, err := strconv.ParseUint(s[:firstDot], 10, 32)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid node handle %q: %w", ErrClientError, handle, err)
	}
	if idx < uint64(len(r.table.Nodes)) {
		if node := r.table.Nodes[idx]; node != nil {
			return node, nil
		}
	}
	return nil, fmt.Errorf("%w: node handle %q could not be resolved (file may not be loaded or handle may be stale)", ErrClientError, handle)
}

// resolveSlow resolves a handle of a file not seen yet in the request, and keeps the file's table.
func (r *veslintNodeResolver) resolveSlow(sd *snapshotData, program *compiler.Program, handle NodeHandle, path string) (*ast.Node, error) {
	node, err := sd.resolveNodeHandle(program, handle)
	if err != nil {
		return nil, err
	}
	key, _ := tspath.TryPathKeyFromCanonical(path)
	if sourceFile := program.GetSourceFileByPath(key); sourceFile != nil {
		if table := encoder.GetNodeIndexTable(sourceFile); table != nil {
			r.path = path
			r.table = table
		}
	}
	return node, nil
}
