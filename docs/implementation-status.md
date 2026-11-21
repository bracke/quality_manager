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
