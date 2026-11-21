# Phase 1 Foundation

The initial executable is deliberately read-only. `quality-manager doctor` validates the effective TOML settings and
reports that write coordination is disabled. It neither creates a database nor probes an upstream project.

Configuration is parsed through the shared Config library. The coordinator rejects malformed TOML, invalid UTF-8,
unknown keys, invalid types, and out-of-range concurrency or retry limits. Relative database paths are converted to
canonical absolute lexical paths before entering application state.

The CLI rejects duplicate options and all workflow commands that have not yet acquired their persistence,
authorization, and recovery guarantees. Machine output is versioned JSON and is parsed by Jsonlib with duplicate
members refused. Integration adapters will reuse the same normalized result taxonomy; negative quality findings are
therefore distinct from execution failures from the beginning.

Validation commands:

```sh
alr -n build
alr -n test
alr -n build --validation -- -f
alr exec -- gnatdoc -P quality_manager.gpr --no-subprojects
./bin/quality-manager --format json doctor
```
