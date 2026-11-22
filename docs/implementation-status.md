# Implementation Status

## Phase 0 — Contract freeze

| Task | State | Evidence |
| --- | --- | --- |
| P0-01 revisions and versions | complete | compatibility matrix |
| P0-02 Ada Quality contracts | complete; AQ-ID-01 and legacy migration implemented | source, schemas, fixture, Ada Quality `81b414f` |
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
| P3-06 planning and revision inspection | complete | exact-run plan/create and exact-revision show adapters |
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
| P7-05 due assessment scheduling | complete | enabled projects receive and execute durable assessment work |
| P7-06 maintenance discovery | complete | journaled assessments and exact-run remediation planning |
| P7-07 reservations and fairness | complete | global assessment/agent bounds and project writer exclusion |
| P7-08 pause/resume/shutdown | complete | protected stop state; no dispatch while stopping |
| P7-09 daemon and one-shot modes | complete | `maintenance`, `daemon`, and `daemon --once` CLI routes |
| P7-10 repeated/multi-project tests | complete | restart rebuild, deduplication, blocked isolation, three-project inventory |

The persisted `Queued` state is authoritative; the protected queue is rebuilt by scanning committed work. A worker
revalidates the exact check plan, journals the external assessment, adopts its durable run identity, and independently
checks completeness and provenance. Ada Quality exit code 3 is accepted only as a completed but incomplete assessment:
it commits the known run identity and leaves the work inconclusive. Reconciliation does not enqueue an already-active
identity. Current project inventory is the only replaceable record class; historical cycles, events, attempts, and
verification evidence remain append-only.

A complete assessment containing violations invokes Improve with the exact `--run` identity. The version-2 response
must match the qualified project, assessment, and working source. Each deterministic Improve task becomes one
globally coalescible work item in `Awaiting_Approval`; this handoff neither approves nor publishes the plan. Planning
replay reads the exact stored revision and does not duplicate remediation work.

Gate: **passed**. The 24-test suite covers deterministic priority, resource limits, restart reconstruction,
eligibility persistence, cooperative pause/resume, qualified inventory, disabled-project isolation, complete and
incomplete assessment execution, and multi-project scheduling. The warnings-as-errors run and forced validation build
passed.

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
| P10-05 recovery/reconciliation | complete | journal view, exact assessment adoption, campaign reconciliation |
| P10-06 workflow history | complete | cycle, campaign, release, and verification history |
| P10-07 event export | complete | versioned JSON event stream |
| P10-08 doctor diagnostics | complete | configuration and live model_runner capability negotiation |
| P10-09 completion and manpage | complete | Bash completion and `docs/quality-manager.1` |
| P10-10 CLI acceptance | complete | strict operand and structured-output tests |

Operational views are read-only and fail if the coordinator database is absent or incompatible. Authorization
records bind the qualified project, exact Improve revision and content digest, policy digest, action, approver, and
lifetime. Rejections are append-only audit events and cannot remove or rewrite an earlier approval.

Gate: **passed**. The 25-test suite exercises all command routes, output formats, decision imports, recovery views,
configuration propagation, and failure exits. Warnings-as-errors, forced validation, and GNATdoc passed.

## Phase 11 — Full release stabilization

| Task | State | Evidence |
| --- | --- | --- |
| P11-01 complete AUnit suites | complete | 25/25 tests pass, including executable CLI acceptance |
| P11-02 90% production coverage | complete | 6,391/7,099 production body lines, 90.0268%; full implemented scope is measured |
| P11-03 applicable GNATprove | complete | Journal state machine SPARK flow/proof passes |
| P11-04 GNATdoc | complete | project documentation generation succeeds |
| P11-05 clean Alire validation | complete | forced warnings-as-errors validation build succeeds |
| P11-06 real maintenance scenario | complete | assessments 19–24 cover all six projects; each cycle has a terminal coordination event |
| P11-07 real campaign scenario | complete | `phase11-structure-20261122` advanced STR-01 from baseline 19 to passing assessment 25 |
| P11-08 real release scenario | blocked | assessment 26 found 11 violations and one unknown result; no evidence bundle was issued |
| P11-09 crash/concurrency stress | complete | abrupt termination recovery, ownership contention, stale fencing, and 128 lease cycles pass |
| P11-10 packaging/docs/CI | implemented | source-only manifest passes; pinned Linux CI validates and creates a source archive |

The stabilization work fixes explicit configuration propagation for maintenance, campaigns, and release export,
uses the recovery state machine in operational reporting, and tests release evidence corruption, process failures,
native replay, policy drift, campaign contract errors, and scheduler resource accounting. `quality-manager doctor`
negotiates the pinned model_runner headless contract successfully. Release status remains **blocked** by the measured
candidate's quality failures; fixture-backed tests do not replace that gate.

Ada Quality `81b414f` adds a tested migration for the early schema-3 measurement semantics and finding identities.
The live database passed migration and integrity checks with its durable identity preserved, and contains the six
projects selected for release-environment validation. Successful inventory migration alone does not satisfy a
workflow or release gate.

On 22 November 2026, a live maintenance worker assessed `quality_manager` and Ada Quality persisted assessment 2.
The run completed with 85 findings but incomplete evidence because coverage and the release checker were unavailable
and GNATprove failed. Source changes made during the long-running check also caused its final source fingerprint to
differ from the persisted invocation intent. Exact manual reconciliation therefore rejected the run, moved the work
to `Blocked`, and closed the journal as `Aborted`; the recovery queue is now empty. The coordinator cannot claim
compliance, and the environment still needs repair before the multi-project P11-06 record can pass.

Later that day, a real six-project maintenance cycle attempted every registered project and persisted Ada Quality
assessments 3 through 8. Assessments 3–6 and 8 completed; assessment 7 for `improve` was interrupted and its
coordinator journal remains at the ambiguous invoking boundary for explicit reconciliation. The completed results are
not compliant: coverage and release-check evidence are unavailable across several projects, `ada_quality` could not
resolve its test subcrate in the staged environment, and `model_runner` exceeded warning/proof tool limits. The
coordinator therefore retained five `Inconclusive` work items and one `Needs_Intervention`; it did not report the
cycle as healthy.

That run also exposed an upstream source-identity defect: Quality Manager's ignored `var/quality-manager.db` was part
of Ada Quality's portable tree fingerprint, so journaling changed the candidate during self-assessment. Ada Quality
commit `4ee421b` excludes conventional `var/` runtime state and adds regression tests. Live database mutation then
preserved fingerprint `e4830d6b7ca287b1`, and the follow-up assessment 10 matched both its invocation and subsequent
plan. Quality Manager adopted assessment 10 and classified it `Inconclusive` only because production coverage and the
release checker remain unavailable. P11-06 now has a genuine multi-project execution record, but it remains incomplete
until those measurement gaps and assessment 7 are resolved.

Two isolated retries reproduced the `improve` interruption as assessments 11 and 12. The supported Ada Quality CLI
reported that transitive development pins containing multiple parent components were rejected before their normalized
staged destination was checked. Ada Quality commit `a1111a1` now validates canonical containment in the private
staging root, preserving isolation while accepting legitimate nested pins. The full upstream test action, forced
production build, and GNATdoc generation passed. Live assessment 13 then completed with source fingerprint
`56d874a4f119e656`, and Quality Manager adopted it as `Inconclusive` because required evidence remained unavailable.

Assessment 13 also showed that the pinned `model_runner/framework` Alire subcrate depends on sibling files from the
same VCS source layout. Ada Quality commit `3f3942f` now stages the bounded repository source closure for such subcrate
pins while excluding VCS metadata and generated artifacts. Live assessment 14 completed with the same exact source and
toolchain fingerprints. Its build, validation build, AUnit suite, deterministic rerun, GNATdoc, and dependency gates
all executed successfully. Quality Manager correctly retained `Inconclusive`: production coverage is not a complete
inventory, the release checker is absent from the clean staged build, and measured warning, source, documentation, and
proof violations remain. These are now quality/evidence results rather than orchestration or staging failures.

Ada Quality commit `fe57295` closes the clean release-checker gap by discovering the checker GPR project and building
its declared `check_all` main inside the isolated workspace. Live assessment 15 retained the same exact source and
toolchain fingerprints, recorded a successful `release-checker-build`, and executed the checker. REL-01 now reports a
real violation for an oversized test source, schema lines over 120 columns, and coverage evidence that does not match
the current source. Quality Manager adopted the completed assessment as `Inconclusive`; no evidence-unavailable claim
or false pass was produced.

Improve commit `a0ceb66` migrates its evidence generator and repository checker to Ada Quality's complete v3 coverage
contract, records every production unit, and binds the evidence to the exact Ada Quality toolchain fingerprint. The
same change brings the staged repository checker into compliance without removing a test. Live assessment 16 completed
against source `bb123ce7732cee51` and toolchain `7a5b142391f2b96c`: TST-03 passes at 91.31%, REL-01 passes, and both
release-checker operations exited zero. The assessment remains noncompliant with 19 passing and 14 violating
indicators, including BLD-03 and PRF-01; Quality Manager therefore does not claim project health.

Ada Quality commit `325ddb7` corrects the canonical inventory for named GPR object directories such as `obj-e2e` and
`obj-signal`. Assessment 17 confirmed that generated binder sources no longer affect authored-source or security
indicators, then correctly rejected coverage carrying the former source identity. Improve commit `c304f3f` refreshed
the evidence without changing its measured 91.31% coverage. Final assessment 18 retained source
`3172b2a8e66504a8` and toolchain `7a5b142391f2b96c`, passed TST-03 and REL-01, and reduced the result to 24 passing
and 9 violating indicators. The remaining violations are genuine project or release-environment work; the
coordinator still does not claim project health.

Journaled authorized publication is implemented. It requires a durable coordinator approval matching project, plan
revision, complete content fingerprint, action, policy, and lifetime; confirms Improve's atomic approval; preflights
and publishes the exact revision; persists the authoritative native task mapping; and safely replays both external
operations. Fixture-backed acceptance coverage passes; live publication still requires an applicable approved plan.

Published remediation can now be reconstructed from the coordinator database and dispatched through model_runner's
native headless engine. The worker binds execution to the assessed source fingerprint retained with the Improve work,
the exact active publication mapping, native task revision, project identity, execution policy, and a fenced project
lease. Source drift is rejected before execution, and a completed isolated task advances only to
`Awaiting_Integration`; replay cannot start a second native execution.

Maintenance now discovers exact durable approvals, rejects approvals that are premature or expired, confirms Improve's
atomic approval and publication contracts, persists native readiness as `Queued`, and reserves an agent scheduler slot
before execution. Restart reconstruction includes queued and executing remediation. One project's unavailable approval
or native readiness does not prevent unrelated projects from progressing.

Completed isolated remediation is now reconstructed from its active dispatch and deterministic execution operation,
then scheduled under the separate per-project integration resource. The coordinator queries the authoritative native
execution, validates task, source, project, revision, and policy provenance, and invokes only model_runner's controlled
integration operation. Integration has its own fenced lease and recovery journal. A confirmed integrated source moves
to `Awaiting_Assessment`; replay cannot integrate it twice.

Maintenance remediation now retains its exact originating assessment as the comparison baseline. After integration,
the coordinator reconstructs the completed native operation, revalidates the integrated source against a fresh Ada
Quality execution plan, runs a no-reuse assessment, performs the explicit baseline comparison, and invokes Improve
verification for the exact plan revision, task, and new assessment. The append-only verification record binds native,
quality, regression, policy, toolchain, and contract evidence. Only the full independent predicate advances work to
`Verified`; negative outcomes retain their bounded retry or intervention state. The fixture-backed maintenance test now
executes the complete approval → publication → agent → integration → reassessment → verification loop.

The final six-project maintenance execution produced assessments 19 through 24. Five assessments completed and the
model_runner assessment was invalid; the coordinator preserved each independent `Verified`, `Inconclusive`, or
intervention outcome and atomically closed all six cycle records. `Verified` on a cycle means that coordination
finished, not that the project is healthy; its completion event retains the associated work state.

The real campaign `phase11-structure-20261122` froze project 1 at assessment 19 and required STR-01 to pass. Fresh
assessment 25 supplied current evidence, and Summary reconciliation advanced the campaign to `Verified`. The exact
release candidate `27d1550a00258e7ed7c5bb319c4cf2ab520182068dfc7680fa27a02d99f080c2` then produced assessment
26. It was correctly blocked with 11 violations and unknown TST-03 evidence, so qualification issued no bundle.

Coordinator ownership now uses an expiry-aware durable lease with fencing generations and renewal before external
work. The suite kills a helper process without finalization, reopens its database, reconstructs the prepared journal
intent, rejects a competing opener, verifies expired-owner takeover, and completes 128 acquire/release cycles. The
full production measurement is 6,391/7,099 lines (90.0268%), satisfying the stabilization gate without exclusions or
carrying forward an earlier partial-scope result.
