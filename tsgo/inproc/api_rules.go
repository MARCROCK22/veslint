// This file is not part of TypeScript: veslint's build (tsgo/inproc/build.sh) adds it to the package
// internal/api of the TypeScript checkout with `go build -overlay`, as api_inprocess.go.

package api

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/checker"
	"github.com/microsoft/TypeScript/tsc/internal/json"
	"github.com/microsoft/TypeScript/tsc/internal/project"
)

// veslint's rules walk some types through many small requests (a union, its parts, a property
// of each, its declaration…): each one costs the client and this process more than the checker's
// work it asks for. The methods `veslint/…` run such a walk here, on the checker of the worker,
// with the same calls of the checker in the same order as the rule's code in V, which stays the
// reference (and what veslint runs with `tsc --api` in a process of its own). They are not part
// of TypeScript's API.

const veslintMethodPrefix = "veslint/"

// veslintRequest answers a `veslint/…` method.
func (p *InProcess) veslintRequest(ctx context.Context, worker int, method string, params []byte) (any, error) {
	switch strings.TrimPrefix(method, veslintMethodPrefix) {
	case "unboundMethodChecks":
		return p.unboundMethodChecks(ctx, worker, params)
	}
	return nil, fmt.Errorf("%w: unknown method %s", ErrInvalidRequest, method)
}

// veslintSetup is the checker of the worker in the project of a snapshot, as setupChecker gives
// it for a request whose project veslintTagProject tagged.
func (p *InProcess) veslintSetup(ctx context.Context, worker int, snapshot SnapshotID, projectID project.ID) (checkerSetup, error) {
	if worker > 0 && projectID != "" {
		projectID += project.ID(veslintWorkerSeparator + strconv.Itoa(worker))
	}
	return p.session.setupChecker(ctx, snapshot, projectID)
}

// unboundMethodChecksParams: the groups of checks of a file, each a list of steps. A step is a
// type, a property name and whether the parts of the type are walked
// (checkUnionConstituentsAndReport) or the type is asked directly; the steps of a group stop at
// the first that reports.
type unboundMethodChecksParams struct {
	Snapshot     SnapshotID `json:"snapshot"`
	Project      project.ID `json:"project"`
	IgnoreStatic bool       `json:"ignoreStatic"`
	// The steps, group after group: Groups[i] is the number of steps of group i.
	Groups []int    `json:"groups"`
	Types  []TypeID `json:"types"`
	Names  []string `json:"names"`
	Walk   []bool   `json:"walk"`
}

// unboundMethodChecks answers, for each group, 0 when no step reports, else the step that reports
// (1 for the first) times 4 plus the message: 1 for `unbound`, 2 for
// `unboundWithoutThisAnnotation`. It ports ubm_check_union_constituents and ubm_check_if_method of
// rules/unbound_method.v.
func (p *InProcess) unboundMethodChecks(ctx context.Context, worker int, params []byte) (any, error) {
	var in unboundMethodChecksParams
	if err := json.Unmarshal(params, &in); err != nil {
		return nil, fmt.Errorf("%w: %w", ErrInvalidRequest, err)
	}
	if len(in.Types) != len(in.Names) || len(in.Types) != len(in.Walk) {
		return nil, fmt.Errorf("%w: unboundMethodChecks: lists of different lengths", ErrInvalidRequest)
	}
	setup, err := p.veslintSetup(ctx, worker, in.Snapshot, in.Project)
	if err != nil {
		return nil, err
	}
	defer setup.done()
	out := make([]byte, 0, 2+2*len(in.Groups))
	out = append(out, '[')
	step := 0
	for g, count := range in.Groups {
		if count < 0 || step+count > len(in.Types) {
			return nil, fmt.Errorf("%w: unboundMethodChecks: bad groups", ErrInvalidRequest)
		}
		answer := 0
		for i := range count {
			t, err := setup.resolveTypeHandle(in.Types[step+i])
			if err != nil {
				return nil, err
			}
			var message int
			if in.Walk[step+i] {
				message = ubmCheckUnionConstituents(setup.checker, t, in.Names[step+i], in.IgnoreStatic)
			} else {
				message = ubmCheckIfMethod(setup.checker.GetPropertyOfType(t, in.Names[step+i]), in.IgnoreStatic)
			}
			if message != 0 {
				answer = (i+1)*4 + message
				break
			}
		}
		step += count
		if g > 0 {
			out = append(out, ',')
		}
		out = strconv.AppendInt(out, int64(answer), 10)
	}
	if step != len(in.Types) {
		return nil, fmt.Errorf("%w: unboundMethodChecks: bad groups", ErrInvalidRequest)
	}
	return RawBinary(append(out, ']')), nil
}

const (
	ubmUnbound                      = 1
	ubmUnboundWithoutThisAnnotation = 2
)

// ubmCheckUnionConstituents: the parts of a union (the union's types, as getTypesOfType gives
// them), and of each the parts of an intersection; the first whose property is a dangerous method.
func ubmCheckUnionConstituents(c *checker.Checker, t *checker.Type, name string, ignoreStatic bool) int {
	unionParts := []*checker.Type{t}
	if t.Flags()&checker.TypeFlagsUnion != 0 {
		unionParts = t.Types()
	}
	for _, unionPart := range unionParts {
		parts := []*checker.Type{unionPart}
		if unionPart.Flags()&checker.TypeFlagsIntersection != 0 {
			parts = unionPart.Types()
		}
		for _, part := range parts {
			if message := ubmCheckIfMethod(c.GetPropertyOfType(part, name), ignoreStatic); message != 0 {
				return message
			}
		}
	}
	return 0
}

// ubmCheckIfMethod ports checkIfMethod on the value declaration of the property.
func ubmCheckIfMethod(symbol *ast.Symbol, ignoreStatic bool) int {
	if symbol == nil {
		return 0
	}
	declaration := symbol.ValueDeclaration()
	if declaration == nil {
		return 0
	}
	switch declaration.Kind {
	case ast.KindPropertyDeclaration, ast.KindPropertyAssignment:
		// A property whose initializer is a function expression is checked as that function.
		initializer := declaration.Initializer()
		if initializer == nil || initializer.Kind != ast.KindFunctionExpression {
			return 0
		}
		return ubmCheckMethod(initializer, ignoreStatic)
	case ast.KindMethodDeclaration, ast.KindMethodSignature:
		return ubmCheckMethod(declaration, ignoreStatic)
	}
	return 0
}

// ubmCheckMethod ports checkMethod: dangerous unless the first parameter is `this: void` (or the
// method is static with ignoreStatic).
func ubmCheckMethod(node *ast.Node, ignoreStatic bool) int {
	firstParamIsThis := false
	thisIsVoid := false
	if parameters := node.Parameters(); len(parameters) > 0 {
		name := parameters[0].Name()
		firstParamIsThis = name != nil && name.Kind == ast.KindIdentifier && name.Text() == "this"
		if firstParamIsThis {
			typeNode := parameters[0].Type()
			thisIsVoid = typeNode != nil && typeNode.Kind == ast.KindVoidKeyword
		}
	}
	if thisIsVoid {
		return 0
	}
	if ignoreStatic {
		for _, modifier := range node.ModifierNodes() {
			if modifier.Kind == ast.KindStaticKeyword {
				return 0
			}
		}
	}
	if firstParamIsThis {
		return ubmUnbound
	}
	return ubmUnboundWithoutThisAnnotation
}
