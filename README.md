# Quality Manager

Quality Manager coordinates Ada Quality measurement, Ada Quality Summary
portfolio reporting, Improve remediation plans, and model_runner native task
execution. It owns durable scheduling and workflow state; it does not replace
the evidence, approval, publication, or workspace semantics of those systems.

The implementation currently includes the Phase 1 foundation, durable Phase 2
storage and recovery, Phase 3 quality/planning adapters, and Phase 5 native
execution integration. The model_runner path in `config/quality-manager.toml`
must identify an implementation of `headless-work-v1`.

```sh
alr -n build
./bin/quality-manager doctor
./bin/quality-manager --format json doctor
alr test
```

`doctor` performs a live, read-only model_runner capability handshake. Native
execution and conflict-free integration are exact-identity, leased, journaled,
and restart-safe. Autonomous Improve approval remains disabled until the atomic
exact-revision contract in `docs/upstream-changes.md` is implemented.
