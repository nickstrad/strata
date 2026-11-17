---
name: feature-design
description: This skill should be used when the user asks to "design a feature", "design the gateway/owner/flusher/control plane", "write a design doc", "spec this out", "plan this component", "what's the test approach for X", "which coding style applies to X", or starts work on a new strata component or a change to how components interact. Produces a design document saved as a Markdown file in docs/designs/ for the user to review, which names the C4 diagram elements the feature works on, records the findings, and explicitly works through each coding-style sheet that applies (structure and errors, rate limiting, backpressure, circuit breakers and retries, concurrency, object storage, distributed algorithms) with the feature's own decisions for each, plus the testing approach, then iterates on the spec and tests with the user before any code is written.
---

# Feature design

Produce a design document for a strata feature, then refine it with the user. The document makes
three things explicit that are otherwise left implicit: **which parts of the coding style apply**,
**whether a distributed algorithm is being written**, and **how the feature will be tested**.

No implementation code is written while a design is in `Draft`. The design is agreed first.

## When to use

Use for a new component, a new interaction between components, a change to durability, ownership,
ordering or failure behaviour, or anything the user calls a feature. Skip for a bug fix, a rename
or a change that touches one function and no boundary.

## Process

### 1. Orient (read indexes, not folders)

- Read `docs/coding-style/README.md`: the sheet index, how the patterns fit, and the component
  design checklist.
- Read `docs/diagrams/README.md`: the architecture and the open design questions.
- Run `kb search "<the feature in plain words>" --caller claude` for prior decisions.
- Read `docs/designs/README.md` for related designs.
- Open a coding-style sheet only when step 3 marks it as applying.

### 2. Create the document

Copy `assets/design-template.md` to `docs/designs/NNNN-short-name.md`, where `NNNN` is the next
number in `docs/designs/README.md`. Add its line to that index in the same change. Set
`Status: Draft` and `Round: 1`.

### 3. First pass (round 1): short, complete, explicit

Fill every section of the template. Keep it short; depth comes in later rounds. Five sections
have rules:

**C4 elements worked on.** Open the diagram files the feature touches and fill the table in
section 2.1: for each C4 level (context, container, component, dynamic), the diagram file, the
exact box or arrow as it is labelled there, and whether the feature leaves it unchanged, uses
it, implements it, changes it, adds to it or removes it. Then list the diagram changes the
design proposes (each box, arrow, label or flow step, and its file) and the numbered open design
questions from `docs/diagrams/README.md` that the feature touches or answers. If the feature
does not fit the diagrams as drawn, that is a finding: record it, do not bend the design to
hide it. Do not edit the diagrams while the design is in Draft.

**Findings.** Record in section 7 everything the work turned up that a reviewer should check: a
risk, a conflict with a diagram or a sheet, a smell from a sheet's list that the design comes
near, a gap in the docs, an assumption, a fact that was checked (and how). Each finding names
where it came from and what the design does about it. Nothing is left only in the chat.

**Coding style that applies.** Every sheet gets the same attention; the distributed-algorithm
check is one of them, not the main one.

- List **every** sheet in the table, each with `Yes` or `No` and one line of reason. A `No` is
  stated, never omitted: the point is to show the sheet was considered.
- For each `Yes`, **open that sheet** and fill its subsection in the template (3.1 structure and
  errors, 3.2 rate limiting, 3.3 backpressure, 3.4 circuit breakers and retries, 3.5 concurrency,
  3.6 object storage). Each line is a decision for *this* feature: the queue and its capacity,
  the full-queue policy, the fairness key, what is retried and by whom, the lock order, the
  publish order, the fencing token, and so on.
- Use the sheet's "Decide before you build" table and its "In strata" section as the prompts.
  Check the feature against the sheet's "Smells" list and name any that the design risks.
- Point at the rule a decision comes from; do not restate the sheet.
- Carry every "(not set yet)" item the feature depends on into Open questions.
- A decision that cannot be made yet is written as an open question, not left blank.

When several sheets apply, also say how they compose for this feature, in the order from
`docs/coding-style/README.md`: rate limit → admission → bulkhead → breaker → bounded retry, with
a deadline on each step.

**Distributed algorithm check.** Answer the eight questions in
`docs/coding-style/distributed-algorithms.md` with yes or no. If any is yes:

- say so in the first line of the section;
- name the abstraction from that sheet's catalogue, and what in strata provides it;
- write the module specification in the book's form (Name, Events, Properties marked safety or
  liveness and uniform or not, Model, Uses, Stable storage);
- use the sheet's vocabulary exactly (correct, uniform, epoch, lock-in, ◇P, stable storage).

If a new agreement protocol seems to be needed, stop and raise it with the user before going on.

**Testing approach.** Fill the table: one row per test level in the template, each with what it
covers for this feature and which property, rule or checklist answer it proves. Take the tests
from the "Tests" section of each sheet that applies. Then the traceability list: every decision
in the coding-style subsections, every property from the module specification and every answer
in the component design checklist maps to at least one named test. A property with no test is listed
under Open questions, not left out.

Answer the ten questions of the component design checklist in their own section. "Not
applicable" needs a reason.

### 4. Save for review, present and stop

**The Markdown file is the deliverable.** The specification, the decisions, the findings and the
open questions are all saved in `docs/designs/NNNN-short-name.md` before anything is said in the
chat. Fill "How to review this round" in section 10 with the sections that changed and what most
needs a decision, and set `Review: Waiting for review of round N`. Then give the user the file's
path and ask them to review it there. The chat message is a pointer to the file, not a copy of
it.

Give the user a short summary: the C4 elements the feature works on and any diagram changes it
proposes; what the feature is; **for each sheet that applies, the two or
three aspects of it that matter most for this feature** (for example "backpressure: the tenant
mailbox is bounded and refuses new; concurrency: one goroutine per tenant, no lock order
needed"); which sheets do not apply and why; whether a distributed algorithm is involved; the
test levels chosen; the findings that most need a look; and the open questions. Then ask the questions
that block the next round, most important first, at most four. Do not start implementing.

### 5. Iterate (rounds 2+)

Start each round by reading the file again: the user may have edited it or left comments
(`> REVIEW: …` inline, or rows in section 10). Copy every comment into the review table, answer
each one in the document, and record the resolution. A comment given in the chat is recorded the
same way. Never drop a comment without a resolution.

Each round deepens one area, chosen with the user:

- **Spec round**: tighten the module specification. Add missing properties, argue each from what
  it uses, state what is in stable storage and when relative to each acknowledgement, and walk
  the crash points and the zombie case.
- **Test round**: turn the test table into a test plan. Name each test, its level, its fault or
  input, its oracle and the property it proves. Add the fault table for each adapter, the
  model-based fuzz script format, and what is checked after every step.
- **Style round** (one sheet at a time, or all that apply): go back through a sheet's rules and
  smells against the design and deepen its subsection. For rate limiting, backpressure and
  breakers this means limits, deadlines, queue sizes, breaker and retry settings, and what users
  see when each dependency is down. For concurrency: every goroutine, lock and blocking point.
  For object storage: every object, its key, the publish order and the cleanup rule.

After each round: save the document, raise `Round`, add a line to its change log, add new
findings, rewrite "How to review this round", and point the user at the file again, saying what
changed and what is still open. Move an answered question from Open questions into the
section it settles.

### 6. Agree

Set `Status: Agreed` only when the user says so and no open question blocks implementation.
Questions that can wait stay listed with an owner. Then:

- apply the diagram changes listed in section 2.1 to `docs/diagrams/`, and resolve or add open
  questions there;
- add or update a kb entry for each durable decision (`kb add`, `kb edit`);
- if a "(not set yet)" in a coding-style sheet is now decided, replace it in that sheet.

### 7. During implementation

The design is the checklist. Each test named in it is written with the code it covers. If the
implementation shows the design is wrong, change the design first, note it in the change log,
then change the code. Set `Status: Implemented` when the done checklist in
`docs/coding-style/rules.md` passes.

## Rules

- Write designs in plain, direct language. State decisions; do not survey options that were not
  chosen beyond one line each under Alternatives.
- Do not invent numbers. A limit or timeout without a measurement is written as a starting value
  to validate, or as an open question.
- Do not restate the coding-style sheets. Link to the rule and say what the feature decides.
- Do not name other repositories or projects of the user in the document.
- Keep a design to one file. If it grows past about 400 lines, split a sub-feature into its own
  design and link it.

## Resources

- **`assets/design-template.md`**: the document template. Copy it; do not edit it in place.
