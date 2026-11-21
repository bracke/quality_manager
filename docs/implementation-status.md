# Implementation Status

## Phase 0 — Contract freeze

| Task | State | Evidence |
| --- | --- | --- |
| P0-01 revisions and versions | complete | compatibility matrix |
| P0-02 Ada Quality contracts | complete; AQ-ID-01 implemented | source, schemas, fixture, Ada Quality `3a85a5b` |
| P0-03 Summary semantics | complete with AQS-PAGE-01 | source, schemas, fixture |
| P0-04 Improve contracts | complete with IMP-APPROVE-01 | CLI/parser/operations source |
| P0-05 /work trace | complete | CLI route → CLI.Work.Run_With → Framework.Work.Execute |
| P0-06 native lifecycle | complete | Work, Tasks, and workspace source |
| P0-07 upstream requirements | complete | upstream-changes.md |
| P0-08 shared libraries | complete | integration-contracts.md |
| P0-09 matrix and fixtures | complete | matrix and tests/fixtures/phase0 |

Gate: **contracts frozen and gaps specified in `5605000`**. AQ-ID-01 subsequently passed in Ada Quality `3a85a5b`,
and MR-HEADLESS-01 passed in model_runner `a0522e83`. Autonomous approval remains disabled until IMP-APPROVE-01
passes.

## Phase 1 — Crate foundation

| Task | State | Evidence |
| --- | --- | --- |
| P1-01 Alire application and MIT license | complete | `alire.toml`, `quality_manager.gpr`, `LICENSE` |
| P1-02 separate AUnit crate | complete | `tests/alire.toml`, `tests/quality_manager_tests.gpr` |
| P1-03 packages and dependencies | complete for Phase 1 | `src/`, pinned Config and Jsonlib |
| P1-04 typed domain contracts | complete | `Quality_Manager.Model`, `Quality_Manager.Identities` |
| P1-05 strict configuration | complete | TOML, UTF-8, unknown-key, range, and path validation |
| P1-06 normalized results | complete | bounded diagnostics and durable optional operation identity |
| P1-07 base CLI | complete | strict `help`, `version`, and `doctor`; mutation commands rejected |
| P1-08 output foundations | complete | terminal, versioned JSON, and Markdown doctor output |
| P1-09 validation | complete | Alire test action, validation build, GNATdoc |

Gate: **implementation and validation passed**. `alr test` ran 7/7 tests, `alr build --validation -- -f` passed, GNATdoc
completed, and `quality-manager doctor` ran without a coordinator database. The compiler package is pinned as
`gnat_native=15.2.1` (the compiler itself reports `GNATLS 15.2.0`).

## Phase 2 — Persistence, transitions, and journal

| Task | State | Evidence |
| --- | --- | --- |
| P2-01 logical schema and indexes | complete | 14 logical record types; unique entity, kind, and state indexes |
| P2-02 creation and migrations | complete | atomic 0→1 initialization and version compatibility registry |
| P2-03 atomic typed records | complete | typed envelope plus project/work/dispatch/approval/verification facade |
| P2-04 transition validator | complete | explicit graph and terminal-state protection |
| P2-05 deterministic identities | complete | typed, length-framed SHA-256 work/dispatch/execution/coalescing keys |
| P2-06 external-operation journal | complete | prepared/invoking/reconciling/terminal lifecycle |
| P2-07 leases and fencing | complete | compare-and-advance generation updates |
| P2-08 event history | complete | state update and append-only event share one transaction |
| P2-09 startup reconstruction | complete | bounded recovery scan with state-specific recovery actions |
| P2-10 failure tests | complete | corruption, rollback, restart boundaries, stale leases, read-only mutation |

Gate: **implementation and validation passed and committed**. The 11-test suite exercises reopen after every
recoverable journal boundary and confirms that a failed event insert leaves its work item unchanged. Forced validation
builds and GNATdoc completed. Compiler warnings shown during forced builds originate in the pinned Database and
Representation dependencies; Quality Manager units compile without warnings.

## Phase 3 — Measurement, reporting, and planning adapters

| Task | State | Evidence |
| --- | --- | --- |
| P3-01 bounded process adapter | complete | no-shell argv, environment replacement, deadline/cancellation, bounded output |
| P3-02 inventory and assessment | complete | exact Ada Quality project/check/assessment commands |
| P3-03 identity and freshness | complete | schema-6 UUID contract; canonical UUID validation and fail-closed tests |
| P3-04 exact comparison | complete | explicit `assessment diff BASE CURRENT` invocation |
| P3-05 Summary reports | complete | version-1 summary/problems/regressions/indicators/trends/project adapters |
| P3-06 planning and revision inspection | complete | version-2 plan/create/show exact-revision adapters |
| P3-07 approval and publication inspection | complete, approval-fenced | exact plan inspection; autonomous approval returns compatibility error |
| P3-08 publication and recovery | complete | Improve preflight/apply/recover adapters |
| P3-09 task and project verification | complete | task/project verification requires exact revision and assessment |
| P3-10 compatibility/error tests | complete for coordinator adapters | exit classes, UTF-8, schema, discriminator, command construction |

Gate: **passed**. Ada Quality commit `3a85a5b` passed its validation build, 59/59 tests, 90.03% production coverage,
release checker, and GNATdoc generation. Against a real schema-6 database, assessment 1 for `quality_manager`
completed with actionable violations and Improve stored `PLAN-000001` revision 1 with exact assessment and project
provenance. All 13 coordinator tests pass, including valid, missing, and malformed database-identity cases. Versioned
responses are accepted only when their Summary `report_type` or Improve `command` matches the invoked operation.

## Phase 4 — Headless model_runner support

Repository: model_runner, commit `a0522e83`.

| Task | State | Evidence |
| --- | --- | --- |
| P4-01 reusable headless entry | complete | native CLI route wraps `Framework.Work` |
| P4-02 configured runner reuse | complete | same `Model_Agent` and model initialization as `/work` |
| P4-03 readiness/effective inspection | complete | exact task and effective fingerprints in work-operation-v1 |
| P4-04 request/result schema | complete | `docs/headless-work-v1.schema.json` |
| P4-05 idempotent start | complete | durable operation intent/outcome and mismatch rejection |
| P4-06 status/cancel/recover | complete | versioned noninteractive commands |
| P4-07 workspace/integration status | complete | native workspace ID/state and conflict-free authorization |
| P4-08 native gates | complete | `Work.Execute` and `Work.Take_In`, no parallel engine |
| P4-09 CLI | complete | `model_runner work` command group |
| P4-10 tests | complete | AUnit, replay, cancellation, recovery, and real-model exercise |

Gate: **passed and committed**. The full 942-test suite had 941 direct passes and one stale-diagnostic release-gate
artifact; rebuilding the corrected unit and rerunning that exact gate passed. Validation with warnings as errors
passed. A real model invocation was recorded as a native failure when its response violated the agent contract, and
idempotent replay did not invoke it again.

## Phase 5 — Native execution integration

| Task | State | Evidence |
| --- | --- | --- |
| P5-01 capabilities handshake | complete | strict required flags and command-set validation |
| P5-02 inspection/readiness | complete | typed work snapshot and explicit normalized-state decoder |
| P5-03 task-to-dispatch mapping | complete | exact Improve/native mapping with one active remediation |
| P5-04 durable requests | complete | operation ID, intent journal, exact identity validation |
| P5-05 monitoring | complete | durable status lookup and typed outcome reconciliation |
| P5-06 cancellation/recovery | complete | cancel adapter; invoking restart queries status, never executes |
| P5-07 workspace status | complete | native workspace identity/state retained |
| P5-08 integration | complete | conflict-free native integration command only |
| P5-09 execution/integration leases | complete | fenced project resource lease before journal preparation |
| P5-10 crash/concurrency tests | complete for coordinator boundary | restart at invoking, replay, stale lease, deduplication |

Gate: **passed**. The 14-test coordinator suite includes an interrupted
native execution that survives coordinator-store reopen. Recovery observes `status-audit`, proving it queried the
durable external operation rather than invoking the agent again. A repeated committed operation adopts its existing
attempt record without reacquiring the project lease or creating duplicate execution state. Native integration has a
separate fenced lease and journal and advances only to `Awaiting_Assessment`. The warnings-as-errors test run,
forced validation build, and GNATdoc generation passed. A live `quality-manager doctor` negotiated
`headless-work-v1` with model_runner `a0522e83` and reported native execution available.
