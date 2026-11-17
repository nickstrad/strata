# Go testing guide

A project-agnostic guide to testing Go services and CLIs: unit, integration, system tests, coverage, fuzzing, contract suites.
It is self-contained. Copy it into a repo's `docs/`, or reference it from `AGENTS.md` / `CLAUDE.md` ("follow docs/go-testing.md").
Definitions follow Aniche, *Effective Software Testing*. Companion: `go-coding-style.md` (assertions, errors, layout).

The techniques build on each other:
1. Derive tests from the spec.
2. Use coverage to find what the spec missed.
3. Turn examples into properties and fuzz them.
4. Add a few large tests on top.

## The pyramid

| Level | What runs | Speed | Use for |
|-------|-----------|-------|---------|
| **Unit** | Domain code with in-memory fakes for its interfaces | ms | All business rules. Aniche: "I favor unit tests as much as possible" |
| **Integration** | One adapter against real infrastructure: `httptest` server, `t.TempDir()`, a test database | ms to s | The edges: encoding, file formats, status codes, error wrapping |
| **System / e2e** | Real binaries as separate processes, driven only through the public interface (CLI, HTTP) | seconds | The few main and riskiest flows |

Aniche calls the top level *system tests*. Here "e2e" means real processes, behind a build tag:

```sh
go test -race ./...             # unit + integration
go test -tags noassert ./...    # same, assertions compiled out
go test -tags e2e -count=1 ./e2e
```

Go gives the lower levels cheaply, so keep most tests low and the e2e suite small.

## 1. Specification-based tests (Aniche ch. 2)

Derive tests from the requirements before reading the code.

1. Understand the requirement: inputs and outputs.
2. Explore what the program does with a few inputs.
3. **Find the partitions**: each input alone, then combinations, then outputs. One test per partition.
4. **Find the boundaries.** Test the **on point** (exactly on the boundary) and the **off point** (the nearest value that flips the outcome). Typical: 0, 1, many; empty vs non-empty; the limit and one over it.
5. Write the cases.
6. Automate them as table-driven tests where cases share a shape.
7. Add cases from experience: odd characters, a dependency that is down, a retry after failure.

Write a spec for each public operation in its doc comment: valid inputs, error cases, guarantees. Then test each part black box, from the documented behaviour.

```go
func TestDiscount(t *testing.T) {
	tests := []struct {
		name    string
		qty     int
		want    float64
		wantErr error
	}{
		{"zero is invalid", 0, 0, orders.ErrInvalidQty},   // off point
		{"one, no discount", 1, 0, nil},                    // on point
		{"just below tier", 9, 0, nil},                     // off point
		{"tier boundary", 10, 0.1, nil},                    // on point
		{"large", 1000, 0.1, nil},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := orders.Discount(tc.qty)
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("err = %v, want %v", err, tc.wantErr)
			}
			if got != tc.want {
				t.Fatalf("Discount(%d) = %v, want %v", tc.qty, got, tc.want)
			}
		})
	}
}
```

- Use `t.Fatalf` with inputs and the want/got in the message. Call `t.Helper()` in helpers.
- Compare errors with `errors.Is` / `errors.As`, never message text.
- Use `t.Parallel()` only on tests that share no state.

## 2. Structural tests (Aniche ch. 3)

Coverage **finds** partitions the spec tests missed. It is a tool, not a target. Read the uncovered blocks, not the percentage.

### Commands

```sh
# Unit + integration. -coverpkg counts code exercised from other packages.
go test -coverpkg=./... -coverprofile=unit.out ./...
go tool cover -func=unit.out      # per function
go tool cover -html=unit.out      # per line, in a browser
```

### Coverage of binaries run by e2e tests

Build the e2e test binary, then run it directly with coverage on. The e2e harness builds the app binaries with `go build -cover`, and they write data to `GOCOVERDIR`.

```sh
mkdir -p e2ecov && rm -f e2ecov/*
go test -tags e2e -c -o e2e.test ./e2e
(cd e2e && GOFLAGS=-cover GOCOVERDIR=$PWD/../e2ecov ../e2e.test -test.v)
go tool covdata textfmt -i=e2ecov -o=e2e.out
```

`GOFLAGS=-cover` is inherited by the `go build` calls inside `TestMain`, so the binaries are instrumented. Make the harness pass `GOCOVERDIR` through to child processes (the default of inheriting the environment does this).

**Merge profiles.** A block counts as covered if either run covered it.
Both methods below were checked against an independent union and agree.

Cleanest: have the unit tests write the same binary format as the e2e run,
then merge the directories:

```sh
go test -cover -coverpkg=./... ./... -args -test.gocoverdir=$PWD/unitcov
go tool covdata percent -i=unitcov,e2ecov             # per package
go tool covdata textfmt -i=unitcov,e2ecov -o=all.out
go tool cover -func=all.out | tail -1                 # total
```

Quick: concatenate the text profiles. `go tool cover` merges duplicate
blocks itself:

```sh
(head -1 unit.out; tail -n +2 -q unit.out e2e.out) > all.out
go tool cover -func=all.out | tail -1
```

### Gotchas
- **SIGKILL loses coverage.** A killed process never writes its data. Stop processes gracefully (SIGTERM/SIGINT) if you want their coverage. Crash-simulation tests will not show up.
- **`go test` overrides `GOCOVERDIR`.** Run the compiled test binary directly (as above) so children write to your directory.
- The directory must exist before the run.

### What uncovered blocks mean
- **Error branch:** inject the failure with a fake (section 7).
- **Code that should be impossible:** use an assertion instead of a branch.
- **Dead code:** delete it.
- **A check whose failing side never runs.** An assertion or test oracle that has never failed proves nothing. Think like a mutation tester: flip a comparison, delete a line, return early. Does some test fail? If not, the oracle is weak. Make sure each assertion can fail in at least one test.

### Criteria
- Aim for branch coverage of the domain code.
- Use MC/DC (each condition shown to change the outcome on its own) for complex conditions that matter.
- Test loops with 0, 1, and many iterations.

## 3. Property-based tests with native fuzzing (Aniche ch. 5)

State a **property** that must hold for every input, and let the fuzzer search for a counterexample.

| Property-based testing | Go fuzzing |
|------------------------|------------|
| Generator | Fuzzer mutates `string`, `[]byte`, ints, bools. For structure, decode bytes into a script |
| Property | The body of `f.Fuzz`, using `t.Fatalf` and assertions |
| Precondition (`assume`) | `t.Skip()` |
| Example seeds | `f.Add(...)` |
| Search | Coverage-guided, favouring inputs that reach new code |
| Shrinking | Minimises a failing input before reporting |
| Regression tests | Failures saved to `testdata/fuzz/<FuzzName>/`. **Commit them** |

```sh
go test ./...                                       # seeds + committed corpus only; fast; for CI
go test -run='^$' -fuzz=FuzzRoundTrip -fuzztime=30s ./internal/store
```
Only one fuzz target runs per `-fuzz` invocation, and the pattern must match exactly one.

### Property kinds
- **Round trip:** `decode(encode(x)) == x`. Examples: save then load, put then get, escape then unescape.
- **Invariants:** always true after any operation (sorted, no duplicates, total conserved).
- **Model-based (stateful):** bytes become a script of operations. Run it against the real system and a trivial model, and compare after each step. Finds bugs in sequences no one would write by hand. **Highest value.**
- **Metamorphic:** a relation between two runs ("add then remove restores the original state"; "order of independent ops does not matter").
- **Differential:** two implementations (real vs reference) agree.

**Assertions are oracles.** With assertions on, every contract in the code is checked on every fuzzed input for free (Aniche 4.4).

### Template: round trip

```go
func FuzzRoundTrip(f *testing.F) {
	f.Add("plain", "v")
	f.Add("with/slash and space", "")
	f.Add("ünï", "\x00\n")
	f.Fuzz(func(t *testing.T, key, value string) {
		if key == "" {
			t.Skip() // the spec rejects empty keys
		}
		s := store.NewMemory()
		if err := s.Put(ctx, key, value); err != nil {
			t.Fatalf("Put(%q): %v", key, err)
		}
		got, err := s.Get(ctx, key)
		if err != nil || got != value {
			t.Fatalf("round trip: Get(%q) = %q, %v; want %q", key, got, err, value)
		}
	})
}
```

### Template: model-based (byte script vs map model)

```go
// Each op is two bytes (kind, arg) over a pool of 8 keys:
//   kind%3  0 Put(k, unique value)   1 Delete(k)   2 toggle fault (Down)
func FuzzStoreModel(f *testing.F) {
	f.Add([]byte{0, 1, 0, 2, 1, 1})                  // put, put, delete
	f.Add([]byte{0, 1, 2, 0, 0, 1, 2, 0, 0, 1})      // fault on and off
	f.Fuzz(func(t *testing.T, script []byte) {
		fake := storetest.NewFake()
		s := store.Checked(fake)                      // contracts as oracles
		model := map[string]string{}
		for i := 0; i+1 < len(script); i += 2 {
			kind, arg := script[i]%3, int(script[i+1])
			key := fmt.Sprintf("k%d", arg%8)
			switch kind {
			case 0:
				val := fmt.Sprintf("v%d", i)
				if err := s.Put(ctx, key, val); err == nil {
					model[key] = val
				} else if !fake.Down {
					t.Fatalf("step %d: Put failed while up: %v", i/2, err)
				}
			case 1:
				if err := s.Delete(ctx, key); err == nil {
					delete(model, key)
				}
			case 2:
				fake.Down = !fake.Down
			}
			if fake.Down {
				continue // compare only when the system is reachable
			}
			for k := 0; k < 8; k++ {
				key := fmt.Sprintf("k%d", k)
				got, err := s.Get(ctx, key)
				want, ok := model[key]
				if ok && (err != nil || got != want) {
					t.Fatalf("step %d: Get(%s) = %q, %v; model has %q", i/2, key, got, err, want)
				}
				if !ok && !errors.Is(err, store.ErrNotFound) {
					t.Fatalf("step %d: Get(%s) = %q, %v; model has none", i/2, key, got, err)
				}
			}
		}
	})
}
```

Tips: document the script format in the comment above the target. Add seeds for each guard rail and each fault path. Check error well-formedness inside the loop. Keep ops sequential; document concurrency you do not model.

## 4. Contract test suites

When an interface has several implementations (real adapters and fakes), write **one** suite for its contract and run it against each. This keeps fakes honest, so a unit test that passes against a fake means something. It also enforces the Liskov rule (implementations may weaken preconditions and strengthen postconditions, never the reverse).

```go
// package storetest
func RunStoreSuite(t *testing.T, newStore func(t *testing.T) store.Store) {
	t.Run("get missing returns ErrNotFound", func(t *testing.T) {
		_, err := newStore(t).Get(ctx, "nope")
		if !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("err = %v", err)
		}
	})
	t.Run("put then get", func(t *testing.T) { /* ... */ })
	t.Run("delete is idempotent", func(t *testing.T) { /* ... */ })
}

// in each implementation's test file
func TestMemoryContract(t *testing.T) {
	storetest.RunStoreSuite(t, func(t *testing.T) store.Store { return store.NewMemory() })
}
func TestFileContract(t *testing.T) {
	storetest.RunStoreSuite(t, func(t *testing.T) store.Store { return store.NewFile(t.TempDir()) })
}
func TestFakeContract(t *testing.T) {
	storetest.RunStoreSuite(t, func(t *testing.T) store.Store { return storetest.NewFake() })
}
```
Wrap each implementation with `store.Checked` in the suite run, so the documented pre/postconditions are asserted too.

## 5. Integration tests

- **Run real infrastructure in-process:** `httptest.NewServer(httpapi.Handler(...))`, `t.TempDir()`, a throwaway database.
- **Test the adapter's job:** encoding, escaping, status codes, file formats, request-ID header on responses, and that the client copies it into its errors.
- **Cover failure paths:** server down (close it first), corrupt file, failed write, timeout via a short context, a handler that panics (expect 500 with a request ID).
- **Check error wrapping:** every error leaving the adapter is well-formed (right module), and sentinels still match with `errors.Is`.

```go
func TestClientServerDown(t *testing.T) {
	srv := httptest.NewServer(httpapi.Handler(logger, svc))
	c := client.New(srv.URL)
	srv.Close()
	_, err := c.Get(ctx, "o1")
	e, ok := errs.Outermost(err)
	if !ok || e.Module != "client" {
		t.Fatalf("want a client error, got %T: %v", err, err)
	}
}
```

## 6. System / e2e tests

- **Build real binaries once** in `TestMain`, into a temp dir, behind `//go:build e2e`.
- **Start processes on free ports** (listen on `:0`, read the port, close, pass it) and **wait until healthy** by polling a health endpoint with a deadline. Never `time.Sleep` for correctness.
- **Clean up with `t.Cleanup`**: graceful `Stop` (SIGTERM, wait) for normal teardown; `Kill` (SIGKILL) only to simulate a crash.
- **Drive them only through the public interface** (CLI args, HTTP). **Verify by querying components directly** rather than trusting the system's report about itself.
- **Keep few and deterministic:** the main flows and riskiest failure modes (a dependency down, a restart), plus a check that errors show a log ID and the right exit code.
- **Model-check one seeded workload.** A fixed-seed random sequence of operations through the real processes, mirrored in a plain map, checks the core rule (no lost writes, no stale reads, no resurrected deletes). Fixed seed means reproducible. Random exploring belongs in the fuzz test, where faults can be injected precisely.
- Print a table or summary with `t.Log` for the reader.

```go
//go:build e2e

var binDir string

func TestMain(m *testing.M) {
	dir, _ := os.MkdirTemp("", "e2e")
	binDir = dir
	if out, err := exec.Command("go", "build", "-o", dir, "../cmd/...").CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "build: %v\n%s", err, out)
		os.Exit(1)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

func freePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func startApp(t *testing.T) (addr string, stop func(), kill func()) {
	port := freePort(t)
	cmd := exec.Command(filepath.Join(binDir, "app"), "-addr", fmt.Sprintf("127.0.0.1:%d", port))
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	done := false
	stop = func() {
		if !done {
			done = true
			cmd.Process.Signal(syscall.SIGTERM)
			cmd.Wait()
		}
	}
	kill = func() {
		if !done {
			done = true
			cmd.Process.Kill()
			cmd.Wait()
		}
	}
	t.Cleanup(stop)
	addr = fmt.Sprintf("http://127.0.0.1:%d", port)
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		if resp, err := http.Get(addr + "/healthz"); err == nil {
			resp.Body.Close()
			return addr, stop, kill
		}
	}
	t.Fatal("app did not become healthy")
	return
}
```

For the model-checked workload use `rand.New(rand.NewSource(seed))`, apply each op through the CLI or HTTP, apply it to a `map`, and after each step (or at the end) read every key through the interface and compare.

## 7. Fault injection in fakes

Fakes are in-memory implementations in a `<pkg>test` package with public switches, so tests and fuzzers can break them on purpose.

```go
type Fake struct {
	mu          sync.Mutex
	data        map[string]string
	Down        bool // every call fails: a crashed dependency
	FailDeletes bool // only Delete fails: a failed clean-up step
	PutBudget   int  // >0: accept this many more Puts, then fail (fail part-way)
}
```

- Each switch returns the same well-formed error the real adapter would (including sentinels).
- Use switches to test: error branches, "nothing changed" claims, partial failures, retries, recovery after the dependency returns.
- Guard fakes with a mutex so `-race` stays clean.
- Run the contract suite against the fake with all switches off.

## Makefile

```make
.PHONY: test race noassert vet check e2e fuzz cover
test:     ; go test ./...
race:     ; go test -race ./...
noassert: ; go vet -tags noassert ./... && go test -tags noassert ./...
vet:      ; go vet ./... && go vet -tags e2e ./e2e
check: vet race noassert  # fails if gofmt would change anything
	@test -z "$$(gofmt -l .)" || (echo "needs gofmt:"; gofmt -l .; exit 1)
e2e:      ; go test -tags e2e -count=1 -v ./e2e
fuzz:     ; go test -run='^$$' -fuzz=$(F) -fuzztime=$(or $(T),30s) $(P)   # make fuzz F=FuzzStoreModel P=./internal/store
cover:    ; go test -coverpkg=./... -coverprofile=coverage.out ./... && go tool cover -func=coverage.out | tail -1
```
(Recipes need tab indentation in a real Makefile.) CI runs `make check e2e`. Run `make fuzz` on a schedule or before releases, and commit any new `testdata/fuzz/` files.

## Checklist for a new feature

- [ ] Specification-based tests for each partition and boundary
- [ ] Validation errors tested; contracts documented and asserted
- [ ] Coverage checked; each uncovered branch tested, injected via a fake, or explained
- [ ] Each new assertion or oracle can fail in at least one test
- [ ] A fuzz or property test if the feature has a round trip, an invariant, or state
- [ ] A contract-suite run if the feature adds an implementation of an interface
- [ ] Integration tests for each new adapter, including failure paths and error wrapping
- [ ] An e2e flow only if the feature changes a main or risky user flow
- [ ] `make check` passes in both assertion builds
