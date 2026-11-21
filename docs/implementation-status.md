# Implementation Status

## Phase 0 — Contract freeze

| Task | State | Evidence |
| --- | --- | --- |
| P0-01 revisions and versions | complete | compatibility matrix |
| P0-02 Ada Quality contracts | complete with AQ-ID-01 | source, schemas, fixture |
| P0-03 Summary semantics | complete with AQS-PAGE-01 | source, schemas, fixture |
| P0-04 Improve contracts | complete with IMP-APPROVE-01 | CLI/parser/operations source |
| P0-05 /work trace | complete | CLI route → CLI.Work.Run_With → Framework.Work.Execute |
| P0-06 native lifecycle | complete | Work, Tasks, and workspace source |
| P0-07 upstream requirements | complete | upstream-changes.md |
| P0-08 shared libraries | complete | integration-contracts.md |
| P0-09 matrix and fixtures | complete | matrix and tests/fixtures/phase0 |

Gate: **gaps specified and committed as `5605000`; upstream test baselines blocked**. Read-only foundation may
proceed. Write-producing autonomous workflows remain disabled until AQ-ID-01 and MR-HEADLESS-01 pass. Auto-approval
also requires IMP-APPROVE-01.

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
