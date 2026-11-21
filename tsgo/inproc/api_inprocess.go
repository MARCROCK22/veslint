// This file is not part of TypeScript: veslint's build (tsgo/inproc/build.sh) adds it to the package
// internal/api of the TypeScript checkout with `go build -overlay`, because it needs what the
// package does not export (newCallbackFS, the msgpack message types).

package api

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"reflect"
	"runtime"
	"runtime/debug"
	"runtime/pprof"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/microsoft/TypeScript/tsc/internal/api/encoder"
	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/bundled"
	"github.com/microsoft/TypeScript/tsc/internal/checker"
	"github.com/microsoft/TypeScript/tsc/internal/compiler"
	"github.com/microsoft/TypeScript/tsc/internal/json"
	"github.com/microsoft/TypeScript/tsc/internal/lsp/lsproto"
	"github.com/microsoft/TypeScript/tsc/internal/project"
	"github.com/microsoft/TypeScript/tsc/internal/tspath"
	"github.com/microsoft/TypeScript/tsc/internal/vfs/osvfs"
)

// InProcess is the API server of `tsc --api` (StdioServer with the msgpack protocol) for a client
// in the same process: a request is a function call that returns the message type and the payload
// the stdio server would have written for it. The filesystem callbacks the client registers are
// answered here, from the files the client gives (InProcessFiles), as veslint's client answers them
// over the pipe (tsgo/client.v), so that calling back into the client is never needed.
type InProcess struct {
	session *Session
	files   *InProcessFiles
	ctx     context.Context
	cancel  context.CancelFunc
	// The range index of the file each worker last asked about (nodesAtRanges).
	ranges veslintRangeIndexes
}

// InProcessOptions are the flags of `tsc --api` that veslint uses.
type InProcessOptions struct {
	// Cwd is `--cwd`.
	Cwd string
	// DefaultLibraryPath is the directory of the lib.*.d.ts files; empty means the ones embedded in
	// this build (bundled.LibPath). The `tsc` of the npm package uses the directory it is in.
	DefaultLibraryPath string
	// Callbacks is `--callbacks`.
	Callbacks []string
}

// NewInProcess starts a session as StdioServer.Run and runAPI (cmd/tsc/api.go) start it.
func NewInProcess(options InProcessOptions) (*InProcess, error) {
	wd, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("getting the current directory: %w", err)
	}
	cwd := tspath.ToRootedDirectoryPath(options.Cwd, tspath.RootedDirectoryPathFromAbsolute(wd))
	defaultLibraryPath := bundled.LibPath()
	if options.DefaultLibraryPath != "" {
		defaultLibraryPath = tspath.RootedDirectoryPathFromAbsolute(options.DefaultLibraryPath)
	}
	for _, name := range options.Callbacks {
		if !isCallbackName(name) {
			return nil, fmt.Errorf("unknown callback name: %s", name)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	// runAPI always passes --useCaseSensitiveFileNames (its default is the OS file system's), so
	// the stdio server always wraps the file system in a callbackFS.
	caseSensitive := osvfs.FS().CaseSensitivity().IsCaseSensitive()
	fs := newCallbackFS(bundled.WrapFS(osvfs.FS()), options.Callbacks, &caseSensitive)
	files := newInProcessFiles()
	sessionInit := &project.SessionInit{
		BackgroundCtx: ctx,
		Logger:        nil,
		FS:            fs,
		Options: &project.SessionOptions{
			CurrentDirectory:   cwd,
			DefaultLibraryPath: defaultLibraryPath,
			PositionEncoding:   lsproto.PositionEncodingKindUTF8,
			LoggingEnabled:     false,
			RunExternalCode:    false,
		},
	}
	session := NewStandaloneSession(sessionInit, &SessionOptions{UseBinaryResponses: true})
	fs.SetConnection(ctx, files)
	session.SetConnection(files)
	return &InProcess{session: session, files: files, ctx: ctx, cancel: cancel}, nil
}

// Files are the texts and virtual files the callbacks answer with.
func (p *InProcess) Files() *InProcessFiles {
	return p.files
}

// Request answers a request as SyncConn.handleRequest and MessagePackProtocol write it: the
// message type (MessageTypeResponse or MessageTypeError) and the payload. A panic is an error
// whose payload is "panic: <value>\n<stack>", as the stdio server sends it. MessageTypeUnknown
// means that the stdio server would have failed writing the answer and closed the connection.
//
// `worker` is 0 for the session's own API checker, as the stdio server answers, or the number of
// one of veslint's lint workers, which share the session's snapshots and programs and ask on
// threads of their own: the checker requests of a worker are answered by a checker of its own
// (veslintWorkerCheckers), so that they do not wait for each other's. The answers of
// appendFastResponse are appended to `dst`.
func (p *InProcess) Request(worker int, method string, params []byte, dst []byte) (messageType MessageType, payload []byte) {
	defer func() {
		if r := recover(); r != nil {
			messageType = MessageTypeError
			payload = fmt.Appendf(nil, "panic: %v\n%s", r, debug.Stack())
		}
	}()
	ctx := p.ctx
	if worker > 0 {
		ctx = context.WithValue(ctx, veslintWorkerKey{}, worker)
	}
	var start time.Time
	if profiling {
		start = time.Now()
	}
	var result any
	var err error
	if strings.HasPrefix(method, veslintMethodPrefix) {
		result, err = p.veslintRequest(ctx, worker, method, params)
	} else {
		result, err = p.session.HandleRequest(ctx, method, json.Value(params))
	}
	var handled time.Time
	if profiling {
		handled = time.Now()
	}
	if err != nil {
		return MessageTypeError, []byte(err.Error())
	}
	if raw, ok := result.(RawBinary); ok {
		return MessageTypeResponse, raw
	}
	out, fast := appendFastResponse(dst, result)
	if fast && checkFastJSON {
		checkFastResponse(method, result, out)
	}
	if !fast {
		out, err = json.Marshal(result)
	}
	if profiling {
		profileRequest(method, handled.Sub(start), time.Since(handled), len(out))
	}
	if err != nil {
		return MessageTypeUnknown, []byte("ipc: failed to write response: " + err.Error())
	}
	return MessageTypeResponse, out
}

// Close closes the session, as the stdio server does when its client goes away.
func (p *InProcess) Close() {
	stopProfile()
	p.session.Close()
	p.cancel()
}

// InProcessFiles answers the filesystem callbacks (readFile, fileExists, stat and
// getAccessibleEntries) as veslint's client does (answer_read_file and answer_virtual_fs in
// tsgo/client.v): served texts, virtual files that exist only for TypeScript, and "use the OS"
// for everything else. It is the ipc.Conn of the callbackFS. Paths are keyed as veslint's
// path_key keys them.
type InProcessFiles struct {
	mu          sync.RWMutex
	served      map[string]string
	virtual     map[string]bool
	virtualDirs map[string][]string
}

func newInProcessFiles() *InProcessFiles {
	return &InProcessFiles{
		served:      map[string]string{},
		virtual:     map[string]bool{},
		virtualDirs: map[string][]string{},
	}
}

// Serve makes `text` the content of `path` (Client.serve).
func (f *InProcessFiles) Serve(path string, text string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.served[inProcessPathKey(path)] = text
}

// StopServing makes `path` read from disk again (Client.stop_serving).
func (f *InProcessFiles) StopServing(path string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.served, inProcessPathKey(path))
}

// AddVirtual makes `path` a file though it is not on disk (Client.add_virtual).
func (f *InProcessFiles) AddVirtual(path string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := inProcessPathKey(path)
	if f.virtual[key] {
		return
	}
	f.virtual[key] = true
	dir := inProcessPathKey(inProcessDir(path))
	f.virtualDirs[dir] = append(f.virtualDirs[dir], inProcessBase(path))
}

// RemoveVirtual makes `path` no longer a file, and no longer served (Client.remove_virtual).
func (f *InProcessFiles) RemoveVirtual(path string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := inProcessPathKey(path)
	delete(f.served, key)
	delete(f.virtual, key)
	dir := inProcessPathKey(inProcessDir(path))
	name := inProcessBase(path)
	if names, ok := f.virtualDirs[dir]; ok {
		kept := []string{}
		for _, n := range names {
			if n != name {
				kept = append(kept, n)
			}
		}
		f.virtualDirs[dir] = kept
	}
}

const inProcessUseOS = `{"kind":"useOS"}`

// Call answers a callback of the callbackFS (ipc.Conn).
func (f *InProcessFiles) Call(_ context.Context, method string, params any) (json.Value, error) {
	path, ok := params.(string)
	if !ok {
		return nil, fmt.Errorf("protocol: the %s callback has no path (%v)", method, params)
	}
	f.mu.RLock()
	defer f.mu.RUnlock()
	key := inProcessPathKey(path)
	switch method {
	case callbackReadFile:
		text, ok := f.served[key]
		if !ok {
			return json.Value(inProcessUseOS), nil
		}
		return json.Marshal(struct {
			Kind  string `json:"kind"`
			Value string `json:"value"`
		}{Kind: "value", Value: text})
	case callbackFileExists:
		if f.virtual[key] {
			return json.Value(`{"kind":"value","value":true}`), nil
		}
		return json.Value(inProcessUseOS), nil
	case callbackStat:
		if f.virtual[key] {
			return json.Value(`{"kind":"fakeStat"}`), nil
		}
		return json.Value(inProcessUseOS), nil
	case callbackGetAccessibleEntries:
		names, ok := f.virtualDirs[key]
		if !ok {
			return json.Value(inProcessUseOS), nil
		}
		return inProcessDirectoryEntries(path, names)
	}
	return nil, fmt.Errorf("protocol: TypeScript asked for the `%s` callback, which veslint does not register", method)
}

// inProcessDirectoryEntries is directory_entries of tsgo/client.v: the files and directories on
// disk in their directory order (V's os.ls is readdir; a symbolic link counts as what it points
// to, a broken one is left out), and the virtual files.
func inProcessDirectoryEntries(dir string, virtualNames []string) (json.Value, error) {
	files := []string{}
	directories := []string{}
	if d, err := os.Open(dir); err == nil {
		names, _ := d.Readdirnames(-1)
		d.Close()
		for _, name := range names {
			info, err := os.Stat(inProcessJoin(dir, name))
			if err != nil {
				continue
			}
			if info.IsDir() {
				directories = append(directories, name)
			} else {
				files = append(files, name)
			}
		}
	}
	for _, name := range virtualNames {
		found := false
		for _, file := range files {
			if file == name {
				found = true
				break
			}
		}
		if !found {
			files = append(files, name)
		}
	}
	entries := struct {
		Files       []string `json:"files"`
		Directories []string `json:"directories"`
	}{Files: files, Directories: directories}
	value, err := json.Marshal(entries)
	if err != nil {
		return nil, err
	}
	return json.Value(`{"kind":"value","value":` + string(value) + `}`), nil
}

// Notify is not used by the callbackFS (ipc.Conn).
func (f *InProcessFiles) Notify(context.Context, string, any) error {
	return nil
}

// Run is not used: there is no connection to read (ipc.Conn).
func (f *InProcessFiles) Run(context.Context) error {
	return nil
}

// inProcessPathKey is path_key of tsgo/platform.v: on Windows `\` is `/` and case is ignored (V's
// to_lower: ASCII when the path is ASCII, else rune by rune).
func inProcessPathKey(path string) string {
	if runtime.GOOS != "windows" {
		return path
	}
	path = strings.ReplaceAll(path, `\`, "/")
	ascii := true
	for i := 0; i < len(path); i++ {
		if path[i] >= 0x80 {
			ascii = false
			break
		}
	}
	if ascii {
		b := []byte(path)
		for i, c := range b {
			if c >= 'A' && c <= 'Z' {
				b[i] = c + ('a' - 'A')
			}
		}
		return string(b)
	}
	return strings.Map(unicode.ToLower, path)
}

func inProcessIsSeparator(c byte) bool {
	return c == '/' || (runtime.GOOS == "windows" && c == '\\')
}

// inProcessDir and inProcessBase are V's os.dir and os.file_name for the paths veslint gives.
func inProcessDir(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if inProcessIsSeparator(path[i]) {
			if i == 0 {
				return path[:1]
			}
			return path[:i]
		}
	}
	return "."
}

func inProcessBase(path string) string {
	for i := len(path) - 1; i >= 0; i-- {
		if inProcessIsSeparator(path[i]) {
			return path[i+1:]
		}
	}
	return path
}

func inProcessJoin(dir string, name string) string {
	if dir != "" && inProcessIsSeparator(dir[len(dir)-1]) {
		return dir + name
	}
	if runtime.GOOS == "windows" {
		return dir + `\` + name
	}
	return dir + "/" + name
}

// A lint worker of veslint has a checker of its own in every program it asks about, as tsgolint's
// workers have: a program hands out several checkers (its checker pool does), each with its own
// types. The session keeps its types and signatures by project, since their ids are those of the
// checker that made them (registerType), so a worker's requests name a project of their own: the
// project's id, veslintWorkerSeparator and the worker's number. HandleRequest gives that name to
// the project of each request of a worker (veslintTagProject, a line veslint's build patches into
// session.go, see tsgo/inproc/session.patch); getProject looks the project up by its id
// (veslintProject), setupChecker answers with the worker's checker (veslintWorkerOf), and
// registerSymbol keeps the project's id as a symbol's canonical project, so that the answers are
// the ones the session's own checker gives. A type or signature handle is then never resolved by
// another checker than the one that made it.

// veslintWorkerSeparator cannot be in a project's id, which is a path or a name made of letters.
const veslintWorkerSeparator = "\x00"

type veslintWorkerKey struct{}

// veslintProject is the project of a project handle that may name a worker.
func veslintProject(id project.ID) project.ID {
	if i := strings.IndexByte(string(id), 0); i >= 0 {
		return id[:i]
	}
	return id
}

// veslintWorkerOf is the worker a project handle names, or 0.
func veslintWorkerOf(id project.ID) int {
	i := strings.IndexByte(string(id), 0)
	if i < 0 {
		return 0
	}
	worker, err := strconv.Atoi(string(id[i+1:]))
	if err != nil || worker < 0 {
		return 0
	}
	return worker
}

var (
	projectIDType      = reflect.TypeFor[project.ID]()
	projectFieldsMu    sync.RWMutex
	projectFieldByType = map[reflect.Type][]int{}
)

// projectField is the index of the field `Project` of type project.ID of the parameters of a
// request, or nil when they have none.
func projectField(t reflect.Type) []int {
	projectFieldsMu.RLock()
	index, ok := projectFieldByType[t]
	projectFieldsMu.RUnlock()
	if ok {
		return index
	}
	if field, found := t.FieldByName("Project"); found && field.Type == projectIDType {
		index = field.Index
	}
	projectFieldsMu.Lock()
	projectFieldByType[t] = index
	projectFieldsMu.Unlock()
	return index
}

// veslintTagProject makes the project of the parameters of a worker's request the worker's.
func veslintTagProject(ctx context.Context, params any) {
	worker, _ := ctx.Value(veslintWorkerKey{}).(int)
	if worker <= 0 || params == nil {
		return
	}
	// The parameters of the requests a lint sends most, without reflection.
	var id *project.ID
	switch p := params.(type) {
	case *GetTypeAtLocationsParams:
		id = &p.Project
	case *GetSymbolsAtLocationsParams:
		id = &p.Project
	case *GetPropertyOfTypeParams:
		id = &p.Project
	case *GetSignaturesOfTypeParams:
		id = &p.Project
	case *CheckerTypeParams:
		id = &p.Project
	case *GetTypePropertyParams:
		id = &p.Project
	case *GetSignaturePropertyParams:
		id = &p.Project
	case *GetContextualTypeParams:
		id = &p.Project
	case *IsTypeAssignableToParams:
		id = &p.Project
	}
	if id != nil {
		if *id != "" {
			*id += project.ID(veslintWorkerSeparator + strconv.Itoa(worker))
		}
		return
	}
	value := reflect.ValueOf(params)
	if value.Kind() != reflect.Pointer || value.IsNil() || value.Elem().Kind() != reflect.Struct {
		return
	}
	index := projectField(value.Elem().Type())
	if index == nil {
		return
	}
	field, err := value.Elem().FieldByIndexErr(index)
	if err != nil || field.String() == "" || !field.CanSet() {
		return
	}
	field.SetString(field.String() + veslintWorkerSeparator + strconv.Itoa(worker))
}

// veslintNodeHandle is the handle nodeHandleFrom gives a node, `index.kind.path`, without the cost
// of fmt.Sprintf: every declaration of every symbol of an answer has one.
func veslintNodeHandle(index uint32, kind ast.Kind, path tspath.PathKey) NodeHandle {
	b := make([]byte, 0, 16+len(path))
	b = strconv.AppendUint(b, uint64(index), 10)
	b = append(b, '.')
	b = strconv.AppendInt(b, int64(kind), 10)
	b = append(b, '.')
	b = append(b, path...)
	return NodeHandle(b)
}

// veslintNodeIndex is NodeIndexTable.GetIndex: the index of a node in the node table of its file (0
// when it is not there). GetIndex sorts the table by node id the first time, which reads every node
// (and gives an id to each that has none) at random places in memory, and nodeHandleFrom asks it
// for every declaration of every symbol and signature sent, so nearly every file of the program was
// sorted, the default libraries among them: that sort was 1.5% of a typed lint of the TypeScript
// compiler. The table is in preorder, where the start of the nodes (their Pos) never decreases but
// at the nodes parsed in JSDoc, which come after the children of the node they document: the node
// is looked for among the others by its start (veslintNodeIndexByPosition), and GetIndex is asked
// only when it is not found there (a JSDoc node, a table out of order), so the index is always the
// one GetIndex gives.
func veslintNodeIndex(sourceFile *ast.SourceFile, node *ast.Node) uint32 {
	table := encoder.GetNodeIndexTable(sourceFile)
	if index := veslintNodeIndexByPosition(table.Nodes, node); index != 0 {
		return index
	}
	return table.GetIndex(node)
}

// veslintNodeIndexByPosition finds `node` in `nodes` (a node table, index 0 unused) by binary search
// on the start of the nodes that are not parsed in JSDoc, then among those with its start; 0 when
// it is not there.
func veslintNodeIndexByPosition(nodes []*ast.Node, node *ast.Node) uint32 {
	skipped := func(n *ast.Node) bool {
		return n == nil || n.Flags&ast.NodeFlagsJSDoc != 0
	}
	if skipped(node) {
		return 0
	}
	pos := node.Pos()
	// lo ends at the first place after every node (not skipped) that starts before `pos`.
	lo, hi := 1, len(nodes)
	for lo < hi {
		mid := lo + (hi-lo)/2
		at := mid
		for at < hi && skipped(nodes[at]) {
			at++
		}
		if at < hi && nodes[at].Pos() < pos {
			lo = at + 1
		} else {
			hi = mid
		}
	}
	for i := lo; i < len(nodes); i++ {
		n := nodes[i]
		if skipped(n) {
			continue
		}
		if n == node {
			return uint32(i)
		}
		if n.Pos() != pos {
			break
		}
	}
	return 0
}

// veslintWorkerCheckers are the checkers of the workers in the programs of a snapshot; they go
// with the snapshot when it is released.
type veslintWorkerCheckers struct {
	mu        sync.Mutex
	byProgram map[*compiler.Program]map[int]*checker.Checker
}

// get is the checker of `worker` in `program`, made the first time. A worker asks on one thread,
// one request at a time, so the checker is not held: its release does nothing.
func (w *veslintWorkerCheckers) get(program *compiler.Program, worker int) (*checker.Checker, func()) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.byProgram == nil {
		w.byProgram = map[*compiler.Program]map[int]*checker.Checker{}
	}
	checkers := w.byProgram[program]
	if checkers == nil {
		checkers = map[int]*checker.Checker{}
		w.byProgram[program] = checkers
	}
	c := checkers[worker]
	if c == nil {
		c, _ = checker.NewChecker(program, nil)
		checkers[worker] = c
	}
	return c, func() {}
}

// checkFastJSON makes every answer appendFastResponse writes compared with json.Marshal's (a test
// of tsgo/inproc, see tests/run.sh): a difference panics, and the request answers the panic.
var checkFastJSON = os.Getenv("VESLINT_TSGO_CHECK_JSON") != ""

func checkFastResponse(method string, result any, fast []byte) {
	want, err := json.Marshal(result)
	if err != nil || !bytes.Equal(want, fast) {
		panic(fmt.Sprintf("veslint: the JSON of the answer to %s is not json.Marshal's:\n%s\n%s", method, fast, want))
	}
}

// VESLINT_TSGO_PROFILE=<file> profiles TypeScript in this process (a tool to find where its time
// goes, not a feature): Go's CPU profile of the whole process goes to <file> and, for each method,
// the requests, the time TypeScript took to answer them, the time of their JSON and its size go
// to <file>.methods, when the first session closes.
var (
	profiling   bool
	profileFile *os.File
	profileMu   sync.Mutex
	profileData = map[string]*methodProfile{}
)

type methodProfile struct {
	count          int
	handle, encode time.Duration
	bytes          int
}

func init() {
	path := os.Getenv("VESLINT_TSGO_PROFILE")
	if path == "" {
		return
	}
	file, err := os.Create(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "veslint: VESLINT_TSGO_PROFILE:", err)
		return
	}
	if err := pprof.StartCPUProfile(file); err != nil {
		fmt.Fprintln(os.Stderr, "veslint: VESLINT_TSGO_PROFILE:", err)
		file.Close()
		return
	}
	profiling = true
	profileFile = file
}

func profileRequest(method string, handle time.Duration, encode time.Duration, size int) {
	profileMu.Lock()
	defer profileMu.Unlock()
	m := profileData[method]
	if m == nil {
		m = &methodProfile{}
		profileData[method] = m
	}
	m.count++
	m.handle += handle
	m.encode += encode
	m.bytes += size
}

func stopProfile() {
	profileMu.Lock()
	defer profileMu.Unlock()
	if profileFile == nil {
		return
	}
	pprof.StopCPUProfile()
	profileFile.Close()
	methods := make([]string, 0, len(profileData))
	for method := range profileData {
		methods = append(methods, method)
	}
	sort.Slice(methods, func(i, j int) bool {
		return profileData[methods[i]].handle+profileData[methods[i]].encode > profileData[methods[j]].handle+profileData[methods[j]].encode
	})
	var table strings.Builder
	fmt.Fprintf(&table, "%-36s %8s %10s %10s %10s\n", "method", "requests", "handle_ms", "json_ms", "json_kb")
	for _, method := range methods {
		m := profileData[method]
		fmt.Fprintf(&table, "%-36s %8d %10.1f %10.1f %10d\n", method, m.count, float64(m.handle)/1e6, float64(m.encode)/1e6, m.bytes/1024)
	}
	if err := os.WriteFile(profileFile.Name()+".methods", []byte(table.String()), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "veslint: VESLINT_TSGO_PROFILE:", err)
	}
	profileFile = nil
}
