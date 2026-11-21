# Quality Manager

Quality Manager coordinates Ada Quality measurement, Ada Quality Summary
portfolio reporting, Improve remediation plans, and model_runner native task
execution. It owns durable scheduling and workflow state; it does not replace
the evidence, approval, publication, or workspace semantics of those systems.

The current implementation is the Phase 1 read-only foundation. It provides
typed domain contracts, strict TOML configuration, versioned JSON validation,
and a database-independent diagnostic command:

```sh
alr -n build
./bin/quality-manager doctor
./bin/quality-manager --format json doctor
cd tests && alr -n build && ./bin/quality_manager_tests
```

Write-producing coordination remains disabled until the Phase 0 upstream
identity, exact-approval, and headless-execution contracts recorded in
`docs/compatibility-matrix.md` are available.
