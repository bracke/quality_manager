# Repository Guidelines

## Purpose and Architecture

`quality_manager` coordinates autonomous maintenance, improvement campaigns, and release qualification. Preserve upstream ownership: `ada_quality` owns measurements, `ada_quality_summary` reporting, `improve` plans/approvals/publication/verification, and `model_runner` execution and workspaces. This crate owns scheduling, persistence, budgets, retries, recovery, and cross-project coordination. Never duplicate an upstream engine or let a coding agent certify its own result.

Prefer supported Ada APIs, otherwise declared versioned CLI/JSON contracts, especially for Improve. Integrate models through a headless `Model_Runner.Framework.Work` adapter, not a new runner.

## Project Structure

Keep manifests and documentation at the root. Production child units belong in `src/`; preserve the specified separation among domain types, persistence, integrations, coordination, workflows, reporting, and CLI. Put defaults in `config/`, JSON schemas in `schemas/`, technical records in `docs/`, AUnit code and fixtures under `tests/`, and validation utilities in `tools/`. Do not commit generated `alire/`, `bin/`, `obj/`, coverage, database, or report artifacts.

## Build, Test, and Development Commands

Phase 0 contract validation precedes crate creation. After Phase 1 establishes the manifests:

- `alr exec -- gnatls --version` — confirm pinned GNAT 15.2.1.
- `alr build` — build the development profile.
- `alr test` — run the AUnit action.
- `alr build --validation -- -f` — force warnings-as-errors validation.

Invoke all GNAT tools through `alr exec --`. Linux is the only initially supported platform.

## Coding and Integrity Rules

Use Ada 2022, three-space indentation, no tabs, 120-character lines, `Title_Case` identifiers, and lowercase GNAT filenames. Use Ada tasks and protected objects; do not add Python, shell orchestration, or replacement process frameworks.

Use typed identities and normalized results. Missing evidence is never success. Journal external side effects using persist-intent/invoke/reconcile transactions; never hold a transaction across external work. Enforce length-framed SHA-256 idempotency identities, fenced leases, append-only history, exact source/evidence binding, bounded retries, and explicit authorization. Unknown upstream states or schemas are compatibility errors.

## Testing and Change Submission

Implement phases in dependency order and pass each gate before proceeding. Add AUnit success, failure, boundary, persistence, and recovery coverage plus applicable `AT-001`–`AT-030` cases. Maintain 90% production line coverage at stabilization; run applicable GNATprove and GNATdoc checks. Simulators do not replace the required real-model end-to-end test.

Use focused, imperative commits, preferably one validated phase or upstream contract change per commit. Pull requests must identify specification task IDs, upstream revisions/contracts, schema effects, authorization implications, commands run, and observed results. Never weaken gates, tests, permissions, or quality thresholds to obtain a pass.
