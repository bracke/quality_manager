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

## Phase 6 — Verification and retry engine

| Task | State | Evidence |
| --- | --- | --- |
| P6-01 native completion gate | complete | explicit completed + integrated predicate |
| P6-02 integrated-source identity | complete | candidate revision/source and qualified project binding |
| P6-03 fresh assessment | complete | no-reuse check, durable run identity, ambiguity escalation |
| P6-04 exact Improve verification | complete | exact task/revision/run invocation and task-result selection |
| P6-05 explicit regression baseline | complete | selected baseline/current comparison with compatibility handling |
| P6-06 full predicate | complete | `N and Q and R and F`, with independent diagnostics |
| P6-07 failure classification | complete | unresolved, regression, evidence, policy, execution, authorization |
| P6-08 bounded retry/replanning | complete | cause-specific actions and non-resetting attempt budget |
| P6-09 rejection/blocking | complete | regression rejection, evidence repair, durable terminal/escalated states |
| P6-10 acceptance tests | complete for coordinator workflow | success and negative remediation paths |

The verification workflow journals the authoritative assessment and Improve verification without holding a database
transaction across either process. Because Ada Quality does not expose a durable caller operation ID, an interruption
at its ambiguous invoking boundary is escalated instead of blindly repeating the assessment. Improve’s exact
task/revision/run verification is idempotently recoverable. Verification evidence is append-only and binds the
candidate revision, source, policy, toolchain, assessment, and acceptance contract.

Gate: **passed**. The 16-test suite covers verified remediation, a completed
agent that leaves the finding unresolved, candidate regression, incomplete evidence, incompatible baselines, bounded
retry exhaustion, durable verification records, and ambiguous-assessment recovery. The warnings-as-errors test run,
forced validation build, and GNATdoc generation passed.

## Phase 7 — Scheduler and continuous maintenance

| Task | State | Evidence |
| --- | --- | --- |
| P7-01 persistent priority selection | complete | six normative bands, age and stable-ID tie breaking |
| P7-02 protected worker coordination | complete | Ada protected pending/active queues |
| P7-03 inventory synchronization | complete | validated qualified Ada Quality project inventory |
| P7-04 source/policy/toolchain detection | complete | explicit evidence-identity due-reason classifier |
| P7-05 due assessment scheduling | complete | enabled projects receive durable assessment work |
| P7-06 maintenance discovery | complete | independent project cycles and assessment objectives |
| P7-07 reservations and fairness | complete | global assessment/agent bounds and project writer exclusion |
| P7-08 pause/resume/shutdown | complete | protected stop state; no dispatch while stopping |
| P7-09 daemon and one-shot modes | complete | `maintenance`, `daemon`, and `daemon --once` CLI routes |
| P7-10 repeated/multi-project tests | complete | restart rebuild, deduplication, blocked isolation, three-project inventory |

The persisted `Queued` state is authoritative; the protected queue is rebuilt by scanning committed work. Eligibility
uses fail-closed facts and records the first failed condition in the atomic blocked transition event. Reconciliation
does not enqueue an already-active identity. Current project inventory is the only replaceable record class;
historical cycles, events, attempts, and verification evidence remain append-only.

Gate: **passed**. The 18-test suite covers deterministic priority, resource limits, restart reconstruction,
eligibility persistence, cooperative pause/resume, qualified inventory, disabled-project isolation, and multi-project
assessment scheduling. The warnings-as-errors run, forced validation build, and GNATdoc generation passed.

## Phase 8 — Autonomous improvement campaigns

| Task | State | Evidence |
| --- | --- | --- |
| P8-01 versioned specification | complete | strict `campaign-v1` JSON and immutable definition records |
| P8-02 frozen population/baselines | complete | enabled qualified inventory and per-revision target records |
| P8-03 target evaluation | complete | assessment-bound pass/violation/incomplete/applicability outcomes |
| P8-04 deterministic priority | complete | campaign scheduler band with age/stable-ID ordering |
| P8-05 cross-workflow deduplication | complete | active global-remediation lookup and attachment |
| P8-06 work budgets | complete | durable used/budget counters and fail-closed exhaustion |
| P8-07 lifecycle control | complete | start, pause, resume, cancellation, and revision reconciliation |
| P8-08 completion/blocking | complete | all-current-target predicate; stale/unknown evidence never satisfies |
| P8-09 progress reports | complete | versioned campaign-progress JSON |
| P8-10 concurrency/history tests | complete | shared work, revision history, baseline preservation, budget stop |

The policy layer intersects coordinator, project, workflow, and task permissions so a lower layer cannot expand
authority. It deterministically escalates unknown scope, unavailable checks, public API, security, and repeated-failure
risk. Approval validation binds the qualified project, exact plan revision/content, action, policy, and expiration.

Gate: **passed**. The 20-test suite covers campaign creation, replay, pause/resume, stale evidence, complete target
reconciliation, immutable baseline history, shared remediation, budget exhaustion, cancellation, structured progress,
policy intersection, deterministic risk, and exact approval validation. Warnings-as-errors, forced validation, and
GNATdoc passed.

## Phase 9 — Release qualification

| Task | State | Evidence |
| --- | --- | --- |
| P9-01 immutable candidate identities | complete | project, commit, source, policy, toolchain, config, generation |
| P9-02 release policy selection | complete | initial `release` profile and authoritative Ada Quality plan identities |
| P9-03 complete assessment | complete | configured qualification runs a fresh full release assessment |
| P9-04 blocking findings | complete | any violation or incomplete evidence blocks qualification |
| P9-05 remediation generations | complete | source-changing work invalidates and creates a new generation |
| P9-06 release checks | complete | journaled clean/reproducible Alire, AUnit, and proof execution |
| P9-07 final-source verification | complete | commit/source/policy/toolchain/config alignment |
| P9-08 qualification/invalidation | complete | qualified state and supersession on source change |
| P9-09 evidence bundle/export | complete | bounded chunk storage, versioned schema, canonical digest, verified export |
| P9-10 qualification tests | complete for coordinator workflow | configured fresh assessment, local gates, export, invalidation, recovery |

Candidate creation uses Ada Quality's dry-run release plan for exact source, policy, and toolchain identities rather
than synthesizing them locally. The authoritative assessment and local release checks use durable operations; a
repeated qualification adopts the exact assessment run and check evidence. An observed result is persisted before its
journal commits. Qualification never treats a failed gate as an execution failure and never publishes a tag, pushes a
branch, or releases an Alire crate.

Gate: **passed for the coordinator workflow**. The 24-test suite covers below-90% rejection, configured fresh-evidence
qualification, chunked evidence export, post-qualification invalidation, new candidate generation, and interrupted
check adoption. The final real-project qualification record remains a Phase 11 environment gate.

## Phase 10 — Operational control and reporting

| Task | State | Evidence |
| --- | --- | --- |
| P10-01 status views | complete | terminal, JSON, and Markdown durable-state views |
| P10-02 queue inspection | complete | work, dispatch, and attempt records |
| P10-03 authorization inspection | complete | append-only approval view |
| P10-04 approve/reject administration | complete | versioned exact decision import and mismatch rejection |
| P10-05 recovery/reconciliation | complete | recovery journal view and campaign reconciliation command |
| P10-06 workflow history | complete | cycle, campaign, release, and verification history |
| P10-07 event export | complete | versioned JSON event stream |
| P10-08 doctor diagnostics | complete | configuration and live model_runner capability negotiation |
| P10-09 completion and manpage | complete | Bash completion and `docs/quality-manager.1` |
| P10-10 CLI acceptance | complete | strict operand and structured-output tests |

Operational views are read-only and fail if the coordinator database is absent or incompatible. Authorization
records bind the qualified project, exact Improve revision and content digest, policy digest, action, approver, and
lifetime. Rejections are append-only audit events and cannot remove or rewrite an earlier approval.

Gate: **passed**. The 24-test suite exercises all command routes, output formats, decision imports, recovery views,
configuration propagation, and failure exits. Warnings-as-errors, forced validation, and GNATdoc passed.

## Phase 11 — Full release stabilization

| Task | State | Evidence |
| --- | --- | --- |
| P11-01 complete AUnit suites | complete | 24/24 tests pass, including executable CLI acceptance |
| P11-02 90% production coverage | complete | 4,451/4,940 body lines, 90.0996% |
| P11-03 applicable GNATprove | complete | Journal state machine SPARK flow/proof passes |
| P11-04 GNATdoc | complete | project documentation generation succeeds |
| P11-05 clean Alire validation | complete | forced warnings-as-errors validation build succeeds |
| P11-06 real maintenance scenario | pending release environment | requires configured multi-project quality inventory |
| P11-07 real campaign scenario | pending release environment | requires current baselines and authorization records |
| P11-08 real release scenario | pending release environment | requires exact candidate evidence and model credentials |
| P11-09 crash/concurrency stress | partial | assessment/check replay, current-record idempotency, fencing, and process tests pass; full soak remains |
| P11-10 packaging/docs/CI | partial | manifests, manpage, schemas, catalog, checklist present; final release archive remains |

The stabilization work fixes explicit configuration propagation for maintenance, campaigns, and release export,
uses the recovery state machine in operational reporting, and tests release evidence corruption, process failures,
native replay, policy drift, campaign contract errors, and scheduler resource accounting. `quality-manager doctor`
negotiates the pinned model_runner headless contract successfully. Release status remains **blocked** until P11-06
through P11-10 are completed with archived real-system evidence; fixture-backed acceptance tests do not replace those
records.

The available `ada_quality/.ada-quality.db` cannot supply those records: it is legacy schema 3 and Ada Quality's own
schema-6 migration/integrity check rejects a noncanonical measurement. The attempted migration was rolled back by
restoring a byte-identical pre-migration copy. A valid schema-6 multi-project inventory is therefore an explicit
release-environment prerequisite, not a condition the coordinator may silently repair.
