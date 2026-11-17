# Go coding style

A project-agnostic guide to structuring and writing Go services and CLIs: domain/integration split, contracts, errors, logging, concurrency.
It is self-contained. Copy it into a repo's `docs/`, or reference it from `AGENTS.md` / `CLAUDE.md` ("follow docs/go-coding-style.md").
Templates target Go 1.22+. Sources: Aniche, *Effective Software Testing* (ch. 4); Cox-Buday, *Concurrency in Go* (ch. 4, 5). Companion: `go-testing.md`.

## 1. Package layout

| Place | Holds |
|-------|-------|
| module root | A reusable library, if the project is one. Public API only |
| `internal/<pkg>/` | App-only packages. Export only what another package needs |
| `cmd/<name>/` | One `main` per binary: flags, wiring, output. Nothing else |
| `internal/<pkg>/<pkg>test/` | Helpers shared across packages: fakes, contract suites (like `httptest`) |
| `export_test.go` | Exposes unexported names to an external `<pkg>_test` package |

- Name packages after what they provide (`billing`, `store`), not what they hold (`utils`, `models`).
- Write a `doc.go` or package comment stating the package's role and its error module name.
- Avoid package-level mutable state. A function variable used as a test seam is the one exception.

## 2. Domain vs integration

| Kind | Holds | Rules |
|------|-------|-------|
| **Domain** (`orders`, `billing`) | Data structures, algorithms, business rules | No I/O: no `net/http`, `os`, `encoding/json`, logging. Reaches the world only through interfaces it defines |
| **Integration / adapters** (`store`, `httpapi`, CLI) | HTTP, files, databases | Thin. Translate between the outside world and domain types. Validate input. Log |

- **Ports and adapters.** The consumer defines the interface, and adapters implement it. Keep it small: only the methods the consumer calls.
- **Pure functions for decisions.** `plan(have, want) []Move` has no I/O and tests with plain maps. A thin layer around it does the I/O.
- **Wire only in `main`.** Build adapters, inject them into the domain, run. `main` calls a `realMain(ctx, args, stdout, stderr) int` so tests can drive it.

## 3. Validation vs contracts

| | Validation | Contracts |
|--|-----------|-----------|
| Protects against | Bad input from users, network, files | Bugs in our own code |
| Where | The edge: public API, handlers, loaders | Inside: pre/postconditions, invariants |
| On failure | Return an error (4xx over HTTP) | `assert.That` panics, before bad data spreads |
| Tests | Always | Mostly covered by other tests; a few show a key check can fail |

- **Validate once at the edge, then trust the data inside.** Repeat a check as a contract only where it guards something worth it (Aniche 4.5.2), such as an interface any future adapter could break.
- **Never assert on input.** Ask: "could a typo, a bad file, or a hostile client trip this?" If yes, return an error.
- **Document contracts** in the doc comment, one line each:

  ```go
  // Charge debits the account.
  //
  //  pre:  amount > 0 (callers validate; Charge does not)
  //  post: err == nil ⇒ balance fell by exactly amount
  //  Invariant: balance >= 0
  ```
- **`invariant()` runs at the end of every method that mutates state**, never on reads. Wrap O(n) checks in `if assert.Enabled { ... }`, because `That` still evaluates its arguments when disabled.
- **Assertions are on by default.** `-tags noassert` compiles them out. CI tests both builds.
- **Checked wrappers on interfaces.** Document pre/post on the interface, then wrap any implementation in a decorator that asserts them (Aniche 4.4):

  ```go
  type Store interface {
  	// Put stores value under key.
  	//  pre:  key != ""
  	//  post: err == nil ⇒ a following Get(key) returns value
  	Put(ctx context.Context, key, value string) error
  	Get(ctx context.Context, key string) (string, error)
  }

  type checked struct{ Store }

  func Checked(s Store) Store { return checked{s} }

  func (c checked) Put(ctx context.Context, key, value string) error {
  	assert.That(key != "", "Put: empty key")
  	err := c.Store.Put(ctx, key, value)
  	if assert.Enabled && err == nil {
  		got, gerr := c.Store.Get(ctx, key)
  		assert.That(gerr == nil && got == value, "Put then Get disagree: %q, %v", got, gerr)
  	}
  	return err
  }
  ```
- **Liskov rule.** An implementation may accept more than its interface (weaker precondition) and promise more (stronger postcondition). Never the reverse. Run one shared contract suite against every implementation, real and fake (see `go-testing.md`).

### Template: `internal/assert` (3 files)

```go
// assert.go
// Package assert checks internal contracts. A failure is a bug in this
// program, never bad input. On by default; build with -tags noassert to
// compile out. Arguments to That are evaluated even when disabled, so
// guard expensive checks with `if assert.Enabled`.
package assert

import "fmt"

func That(cond bool, format string, args ...any) {
	if Enabled && !cond {
		panic(fmt.Sprintf("assertion failed: "+format, args...))
	}
}
```
```go
// enabled.go
//go:build !noassert

package assert

const Enabled = true
```
```go
// disabled.go
//go:build noassert

package assert

const Enabled = false
```

Test it in both builds: `That(false, ...)` must panic when `Enabled` and must not when disabled.

## 4. Error handling

**A user-visible error carries four things** (Cox-Buday ch. 5):
1. what happened (the cause, `Inner`)
2. when and where (UTC time, stack, module, context such as path or URL)
3. a friendly one-line message
4. how to get more information (a log ID, added by the top level)

**Rules**
- **Wrap at module boundaries only.** Every error leaving a package's public API is that package's well-formed error: `errs.Wrap("billing", err, "cannot charge account %s, nothing changed", id)`. Do not wrap at every internal call. Add context only where you know something new.
- **`Error()` returns `message: cause`**, the standard Go wrapping convention. State only your own context. Never repeat the cause with `%v`.
- **Each layer's message is human-friendly** and says whether anything changed and whether retrying is safe.
- **Capture the stack once, at the origin**: only when the wrapped error is not already well-formed.
- **Sentinels + `errors.Is`.** Declare `var ErrNotFound = errors.New("not found")` in the domain. Wrapping keeps them visible through `Unwrap`. Use `errors.As` for typed errors. Never match on message text.
- **Do not log and return.** Return the error. The caller or top level logs it once.

**Top level classifies** (the `cmd` package):

| Outermost error | Meaning | User sees | Exit |
|-----------------|---------|-----------|------|
| Well-formed error from a module the top level calls, or its own module | Known edge case | `error: <message> [log ID x]` | 1 |
| Raw error, or any panic (incl. failed assertion) | Bug | Short "this is a bug, report log ID x" | 70 |
| Bad flags / no command | Usage | Usage text | 2 |

Never print a stack trace to the user. The log keeps it. Check only the outermost error (`Outermost`), not the chain: an error that skipped a module's wrapping is malformed.

### Template: `internal/errs`

```go
// Package errs is the well-formed error type.
package errs

import (
	"errors"
	"fmt"
	"runtime/debug"
	"time"
)

type Error struct {
	Module  string         // module boundary that wrapped it, e.g. "billing"
	Message string         // this layer's friendly text; no cause
	Inner   error          // the cause; nil if this module found the problem
	Time    time.Time      // UTC
	Stack   string         // set only at the origin
	Misc    map[string]any // path, url, request ID, ...
}

// Wrap returns a well-formed error. err may be nil.
//
//	pre: module != "" && the message is not empty
func Wrap(module string, err error, format string, args ...any) *Error {
	e := &Error{Module: module, Message: fmt.Sprintf(format, args...), Inner: err,
		Time: time.Now().UTC(), Misc: map[string]any{}}
	var inner *Error
	if !errors.As(err, &inner) { // origin: first well-formed layer
		e.Stack = string(debug.Stack())
	}
	return e
}

func (e *Error) With(k string, v any) *Error { e.Misc[k] = v; return e }

func (e *Error) Error() string {
	if e.Inner == nil {
		return e.Message
	}
	return e.Message + ": " + e.Inner.Error()
}

func (e *Error) Unwrap() error { return e.Inner }

// Outermost returns err as *Error only if it is one; it does not search the chain.
func Outermost(err error) (*Error, bool) { e, ok := err.(*Error); return e, ok }

// Layer is one step of the chain, for logs.
type Layer struct {
	Module  string         `json:"module,omitempty"`
	Message string         `json:"message"`
	Misc    map[string]any `json:"misc,omitempty"`
}

// Chain lists layers outermost first. Raw errors show only their text,
// which is how a log reveals where wrapping stopped.
func Chain(err error) []Layer {
	var out []Layer
	for ; err != nil; err = errors.Unwrap(err) {
		if e, ok := err.(*Error); ok {
			out = append(out, Layer{e.Module, e.Message, e.Misc})
		} else {
			out = append(out, Layer{Message: err.Error()})
		}
	}
	return out
}

// Stack returns the stack captured at the origin ("" if none).
func Stack(err error) string {
	s := ""
	for ; err != nil; err = errors.Unwrap(err) {
		if e, ok := err.(*Error); ok && e.Stack != "" {
			s = e.Stack
		}
	}
	return s
}
```

Test: `Error()` text, `errors.Is` through two layers, one stack for a two-layer chain, `Outermost` rejects `fmt.Errorf("x: %w", e)`.

### Template: top-level `reporter` (`cmd/app/main.go`)

```go
const (
	exitOK, exitError, exitUsage, exitBug = 0, 1, 2, 70
)

type reporter struct {
	logger *slog.Logger
	stderr io.Writer
	logs   string // log location, shown for bugs
}

func (r reporter) report(err error) int {
	if e, ok := errs.Outermost(err); ok && (e.Module == "billing" || e.Module == "app") {
		id := r.log(slog.LevelWarn, "command failed", err, errs.Stack(err))
		fmt.Fprintf(r.stderr, "error: %s [log ID %s]\n", e.Error(), id)
		return exitError
	}
	return r.bug(err, errs.Stack(err))
}

func (r reporter) bug(err error, stack string) int {
	id := r.log(slog.LevelError, "unexpected error (bug)", err, stack)
	fmt.Fprintf(r.stderr, "error: something unexpected went wrong. This is a bug; "+
		"please report log ID %s (details in %s)\n", id, r.logs)
	return exitBug
}

func (r reporter) log(level slog.Level, msg string, err error, stack string) string {
	id := logx.NewID()
	attrs := []slog.Attr{slog.String("log_id", id), slog.String("error", err.Error()),
		slog.Any("chain", errs.Chain(err))}
	if stack != "" {
		attrs = append(attrs, slog.String("stack", stack))
	}
	r.logger.LogAttrs(context.Background(), level, msg, attrs...)
	return id
}
```
In `realMain`, install `defer func(){ if p := recover(); p != nil { code = r.bug(fmt.Errorf("panic: %v", p), string(debug.Stack())) } }()` with a named result `code`, and cancel via `signal.NotifyContext(ctx, os.Interrupt)` in `main`.

## 5. Logging

- **Format:** `log/slog` JSON lines, UTC timestamps, so logs from different machines line up.
- **Only integration code logs.** Domain code returns errors and reports (values describing what happened). The caller decides what to log.
- **Log:** every error (log ID, whole chain, stack), audit-worthy state changes, and one line per request on servers.
- **Correlate across processes.** The server gives each request an ID and returns it in a response header (`X-Request-Id`). Clients copy it into their errors (`.With("request_id", id)`), so a client log line matches the server's.
- **Do not drop errors you cannot act on.** A handler whose client hung up passes the error to the logging layer (a context-carried slot), which records it with the request.
- **Compose middleware in one constructor, in a fixed order:** request ID (outermost), then logging, then recover, then routes. Recover sits inside logging so a panic still produces a logged 500.

### Template: `internal/logx`

```go
package logx

import (
	"crypto/rand"
	"encoding/hex"
	"io"
	"log/slog"
)

func New(w io.Writer, level slog.Level) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey && len(groups) == 0 {
				a.Value = slog.TimeValue(a.Value.Time().UTC())
			}
			return a
		},
	}))
}

// NewID returns a short random ID, e.g. "3f9a1c0b", shown to users and logged.
func NewID() string {
	b := make([]byte, 4)
	rand.Read(b) // never fails (Go 1.24+)
	return hex.EncodeToString(b)
}
```

### Template: HTTP `Handler` constructor (`internal/httpapi`)

```go
const RequestIDHeader = "X-Request-Id"

// Handler is the only place middleware order is decided.
func Handler(logger *slog.Logger, svc *orders.Service) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /orders/{id}", getOrder(svc)) // getOrder: your handler
	return requestID(logging(logger)(recoverer(logger)(mux)))
}

func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set(RequestIDHeader, logx.NewID())
		next.ServeHTTP(w, r)
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (s *statusWriter) WriteHeader(c int) { s.status = c; s.ResponseWriter.WriteHeader(c) }

func logging(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			sw := &statusWriter{ResponseWriter: w, status: 200}
			start := time.Now()
			next.ServeHTTP(sw, r)
			level := slog.LevelInfo
			if sw.status >= 500 {
				level = slog.LevelError
			} else if sw.status >= 400 {
				level = slog.LevelWarn
			}
			logger.LogAttrs(r.Context(), level, "request",
				slog.String("request_id", w.Header().Get(RequestIDHeader)),
				slog.String("method", r.Method), slog.String("path", r.URL.Path),
				slog.Int("status", sw.status), slog.Duration("duration", time.Since(start)))
		})
	}
}

func recoverer(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				p := recover()
				if p == nil {
					return
				}
				if p == http.ErrAbortHandler {
					panic(p)
				}
				id := w.Header().Get(RequestIDHeader)
				logger.Error("panic serving request", "request_id", id,
					"panic", fmt.Sprint(p), "stack", string(debug.Stack()))
				http.Error(w, "internal error (request id "+id+")", http.StatusInternalServerError)
			}()
			next.ServeHTTP(w, r)
		})
	}
}
```
(`statusWriter` hides `Flusher`/`Hijacker`; use `http.NewResponseController` or a library wrapper if you need them. Add the error-slot from the rule above when handlers must report unactionable errors.)

## 6. Concurrency

- **Goroutines report; parents decide.** Send result and error together as one value on one channel (the Result pattern, Cox-Buday ch. 4). Policy ("stop at first error", "collect all") lives in the parent.
- **No leaks.** Whoever starts a goroutine makes sure it can finish:
  - pass a `context.Context`; cancel it when stopping early
  - buffer result channels to the sender count, so no sender blocks after the reader leaves
  - close each channel from a single owner, after `wg.Wait()`
- **Read every result, even after the first error.** Cancel the rest, keep draining, so a panic or error behind the first is not lost.
- **Panics do not cross goroutines.** An unrecovered one kills the process. Recover inside the goroutine, put it in the result, re-panic in the parent so the top-level recover sees it.
- **Ctrl-C:** root context from `signal.NotifyContext`.
- Prefer `errgroup` only when "first error wins, drop the rest" is truly the policy.

### Template: Result-pattern fan-out with panic forwarding

```go
type result struct {
	id    string
	data  []byte
	err   error
	panic any // set if the goroutine panicked: a bug; the parent re-panics
}

// fetchAll starts one goroutine per id. Exactly one result per id arrives,
// then the channel closes. Buffering means senders never block.
func fetchAll(ctx context.Context, ids []string, fetch func(context.Context, string) ([]byte, error)) <-chan result {
	out := make(chan result, len(ids))
	var wg sync.WaitGroup
	for _, id := range ids {
		wg.Add(1)
		go func() {
			defer wg.Done()
			defer func() {
				if p := recover(); p != nil {
					out <- result{id: id, panic: fmt.Sprintf("%v\n%s", p, debug.Stack())}
				}
			}()
			data, err := fetch(ctx, id)
			out <- result{id: id, data: data, err: err}
		}()
	}
	go func() { wg.Wait(); close(out) }()
	return out
}

// Parent: first error cancels the rest, but every result is still read.
func collect(ctx context.Context, ids []string, fetch func(context.Context, string) ([]byte, error)) (map[string][]byte, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	got := map[string][]byte{}
	var first error
	for r := range fetchAll(ctx, ids, fetch) {
		if r.panic != nil {
			panic(r.panic)
		}
		if r.err != nil {
			if first == nil {
				first = r.err
				cancel()
			}
			continue
		}
		got[r.id] = r.data
	}
	return got, first
}
```
(Go 1.22 gives each loop iteration its own `id`. On older Go, copy it.)

## 7. State changes

- **Order steps so a failure cannot lose data:** copy, then commit, then clean up. Each step's error says what state the system is in ("copied but not committed; safe to retry").
- **One source of truth** when copies can disagree. Never let a stale copy overwrite a newer one. Delete stale copies; never copy them.
- **Write limits down.** If the design is unsafe under some condition (concurrent writers during a migration), say so in the doc comment and README.
- Write files atomically: write a temp file in the same directory, `fsync`, then `os.Rename`.

## 8. Style checklist

- [ ] Domain packages import no I/O packages and do not log
- [ ] Interfaces are small and defined by the consumer; wiring is only in `cmd/`
- [ ] Input validated at the edge with errors; no assertion can be tripped by input
- [ ] Contracts (`pre:`, `post:`, `Invariant:`) documented; `invariant()` after each mutator
- [ ] Every exported error is well-formed; messages say what changed and whether retry is safe; no `%v` of the cause
- [ ] Sentinels checked with `errors.Is`, never by string
- [ ] Top level maps errors to exit 1, usage to 2, bugs to 70, and prints a log ID
- [ ] Logs are slog JSON in UTC; request IDs flow server to client
- [ ] Goroutines have a context, buffered result channels, one closer, and panic forwarding
- [ ] Doc comments on every exported name, explaining why; comments short and plain
- [ ] Before done: `gofmt -l .`, `go vet ./...`, `go test -race ./...`, and `go test -tags noassert ./...`
