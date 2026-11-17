# Designs

One design document per feature, one line each here. A design is written and agreed before the
feature's code.

Each design is one Markdown file, saved here for review. Review it in the file: edit it, or
leave comments as `> REVIEW: …` or in its review table. Each round answers them.

Each design states, explicitly:

- which boxes and arrows of the [C4 diagrams](../diagrams/README.md) the feature works on, and
  the diagram changes it proposes, with each changed diagram redrawn in full (added parts in
  green, changed parts in orange);
- the findings that came up while designing it;
- which coding-style sheets apply to the feature, and which do not, with a reason;
- for each sheet that applies (structure and errors, rate limiting, backpressure, circuit
  breakers and retries, concurrency, object storage), the feature's own decisions on that
  sheet's points;
- whether a distributed algorithm is being written, and if so its specification in the terms of
  [distributed-algorithms.md](../coding-style/distributed-algorithms.md);
- whether the feature goes in the deterministic simulation, and if so its faults, checks and
  mutants ([simulation-testing.md](../coding-style/simulation-testing.md));
- the testing approach, with every decision and property traced to a test.

To start one, use the `feature-design` skill (`.claude/skills/feature-design/SKILL.md`). It
copies the template, fills a short first draft, then iterates with you in rounds: specification,
tests, resilience. An agent without skills follows that file by hand.

Status: **Draft** (being worked out; no code yet), **Agreed** (ready to build),
**Implemented**.

| # | Design | Status | Components |
|---|---|---|---|
| | *(none yet)* | | |
