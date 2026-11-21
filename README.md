# Quality Manager

Quality Manager coordinates Ada Quality measurement, Ada Quality Summary
portfolio reporting, Improve remediation plans, and model_runner native task
execution. It owns durable scheduling and workflow state; it does not replace
the evidence, approval, publication, or workspace semantics of those systems.

The implementation currently includes the Phase 1 foundation, durable Phase 2
storage and recovery, Phase 3 quality/planning adapters, Phase 5 native
execution integration, Phase 6 independent verification, and Phase 7 durable
maintenance scheduling, plus Phase 8 improvement campaigns. The model_runner path in
`config/quality-manager.toml`
must identify an implementation of `headless-work-v1`.

```sh
alr -n build
./bin/quality-manager doctor
./bin/quality-manager --format json doctor
./bin/quality-manager maintenance --dry-run
./bin/quality-manager daemon --once --dry-run
alr test
```

`doctor` performs a live, read-only model_runner capability handshake. Native
execution and conflict-free integration are exact-identity, leased, journaled,
and restart-safe. A native completion is not accepted until fresh Ada Quality
evidence, exact Improve verification, and an explicit regression comparison all
pass. Autonomous Improve approval remains disabled until the atomic
exact-revision contract in `docs/upstream-changes.md` is implemented.

Phase 7 adds a restart-reconstructible priority scheduler and one-shot/daemon
maintenance entry points. Enabled projects receive independent durable cycles;
assessment work is committed before it becomes visible to workers. Disabled or
ineligible projects cannot stop unrelated portfolio work.

Phase 8 adds revisioned improvement campaigns. Campaign definitions use
`schemas/campaign-v1.schema.json`, bind qualified projects and baseline
assessments, retain historical target records, enforce work budgets, and emit
versioned progress JSON. Compatible active work is shared by global
remediation identity while every campaign retains independent target evidence.

Phase 9 adds immutable release candidate generations and qualification evidence.
Qualification requires exact identity alignment, all 33 indicators complete and
passing, reproducible validation builds, AUnit, applicable proof, release checks,
and at least 90% production-line coverage. Evidence exports are accepted only
after their canonical SHA-256 envelope is revalidated.
