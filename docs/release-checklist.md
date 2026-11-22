# Release Stabilization Checklist

Run from a clean checkout on Linux with the pinned sibling repositories.

- Confirm alr exec -- gnatls --version reports the validated GNAT 15.2 toolchain.
- Run QUALITY_MANAGER_WARNINGS_AS_ERRORS=true alr test.
- Run QUALITY_MANAGER_WARNINGS_AS_ERRORS=true alr build --validation -- -f.
- Measure production body coverage with the matching toolchain’s gcov; require
  at least 90%, without excluding failed or defensive paths.
- Run GNATprove on units carrying SPARK_Mode, then generate GNATdoc.
- Run quality-manager doctor against the actual pinned model_runner.
- Execute and archive one real multi-project maintenance cycle.
- Execute and archive one real campaign with frozen baselines.
- Execute and archive one exact-source release qualification and verify its
  exported evidence digest.
- Exercise termination at each journal boundary and competing coordinator
  leases; confirm no duplicate upstream operation.
- Confirm manifests contain only source, schemas, documentation, completion,
  and license files; generated databases, reports, objects, and coverage data
  must remain absent.

Release is blocked if any item is missing. In particular, a passing build does
not replace the coverage threshold or the three real-system workflow records.
