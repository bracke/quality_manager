# Quality Manager

Quality Manager coordinates Ada Quality measurement, Ada Quality Summary
portfolio reporting, Improve remediation plans, and model_runner native task
execution. It owns durable scheduling and workflow state; it does not replace
the evidence, approval, publication, or workspace semantics of those systems.

The implementation currently includes the Phase 1 foundation, durable Phase 2
storage and recovery, Phase 3 quality/planning adapters, Phase 5 native
execution integration, Phase 6 independent verification, and Phase 7 durable
maintenance scheduling, Phase 8 improvement campaigns, Phase 9 release
qualification, and Phase 10 operational control. The model_runner path in
`config/quality-manager.toml`
must identify an implementation of `headless-work-v1`.
The same configuration explicitly selects Improve's executable, configuration file,
and Improve-owned state database; remediation planning binds `--run` to the
assessment selected by the coordinator.

```sh
alr -n build
./bin/quality-manager doctor
./bin/quality-manager --format json doctor
./bin/quality-manager maintenance --dry-run
./bin/quality-manager daemon --once --dry-run
./bin/quality-manager --format json status
./bin/quality-manager queue
./bin/quality-manager recover
./bin/quality-manager approvals
alr test
```

`doctor` performs a live, read-only model_runner capability handshake. Native
execution and conflict-free integration are exact-identity, leased, journaled,
and restart-safe. A native completion is not accepted until fresh Ada Quality
evidence, exact Improve verification, and an explicit regression comparison all
pass. Autonomous approval uses Improve's atomic revision-and-content-qualified
contract; coordinator authorization must still match the exact plan, policy, action, and lifetime.

Phase 7 adds a restart-reconstructible priority scheduler and one-shot/daemon
maintenance entry points. Enabled projects receive independent durable cycles;
assessment work is committed before it becomes visible to workers. Workers
revalidate the exact plan, journal the check, retain its durable assessment ID,
and reject incomplete or mismatched evidence. Complete assessments with
violations create an exact-run Improve plan and durable remediation work in
`Awaiting_Approval`; maintenance does not bypass approval or publish it.
Disabled or ineligible projects cannot stop unrelated portfolio work.

Phase 8 adds revisioned improvement campaigns. Campaign definitions use
`schemas/campaign-v1.schema.json`, bind qualified projects and baseline
assessments, retain historical target records, enforce work budgets, and emit
versioned progress JSON. Compatible active work is shared by global
remediation identity while every campaign retains independent target evidence.

Phase 9 adds immutable release candidate generations and qualification evidence.
Qualification requires exact identity alignment, all 33 indicators complete and
passing, reproducible validation builds, AUnit, applicable proof, release checks,
and at least 90% production-line coverage. `release-create` supports the initial
`release` profile and binds the candidate to Ada Quality's current source,
policy, and toolchain plan. `release-qualify` obtains a fresh assessment and
runs the journaled local gates. Evidence is stored in bounded chunks and exports
are accepted only after the canonical SHA-256 bundle digest is revalidated.

Phase 10 exposes read-only status, queue, approval, history, event, and recovery
views in terminal, JSON, and Markdown formats. Administrative `approve` and
`reject` commands import a versioned decision record conforming to
`schemas/approval-decision-v1.schema.json`; the command and record decision must
match. An ambiguous assessment can be adopted only through
`reconcile-assessment OPERATION RUN`, which verifies the exact persisted intent.
Campaign and release lifecycle commands are listed by `quality-manager help`.
See `docs/quality-manager.1` for the operator reference.

Phase 11 stabilization currently passes the 25-test AUnit suite and the
warnings-as-errors validation build. Real maintenance and campaign records are
complete. The exact-candidate release run is correctly blocked by quality
failures. Full-scope production coverage is 6,391/7,099 lines (90.0268%), which
passes the stabilization threshold. See `docs/release-checklist.md` and
`docs/implementation-status.md`.
