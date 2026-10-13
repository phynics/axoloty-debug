# Agent instructions for axoloty-debug

This file is the contributor policy for this repository. It owns the runtime
and debug tooling behind the Core build harness command `axoloty-tool serve`.

## Related repositories

[`phynics/axoloty`](https://github.com/phynics/axoloty) is Core. It owns the
portable protocol, runtime, Coaty models, and the build/test orchestration
(`axoloty-tool`, `AxolotyTooling`). Its
[`AGENTS.md`](https://github.com/phynics/axoloty/blob/main/AGENTS.md) governs
changes there, including how Core consumes this package.

[`phynics/axoloty-embedded`](https://github.com/phynics/axoloty-embedded) owns
concrete firmware products and device qualification.

## Ownership boundary

This repository owns:

- the `serve mqtt|mcp|dev` command surface and its parser,
- the managed Mosquitto and `axoloty-mcp` service runners and the development
  stack supervisor,
- the process-launch and signal-disposition shim (`AxolotyProcessLauncher`),
- the `MCPPathPolicy` helper.

It does not own build, test, release, or repository-authority policy. Nothing
here may read the Axoloty checkout layout, a test manifest, or a package list.
It reaches the broker and the `axoloty-mcp` product only.

Core's `Tools` package consumes this repository as a sibling path dependency
(`../axoloty-debug`). Keep the manifest product names (`AxolotyDebug`,
`AxolotyProcessLauncher`) stable so that dependency keeps resolving.

## Invariants

- No dependency on Axoloty's packages, source tree, or `.build`. The only
  inputs are the child executable paths and the environment.
- The embedding process owns signals. Service runners take `installSignalHandler`
  and an `AxolotyDebugCancellation`; they never install a handler the caller did
  not ask for.
- Machine-readable readiness JSON goes to standard output; human readiness and
  diagnostics go to standard error. Keep that split.
- `AxolotyProcessLauncher` stays a thin C shim: process launch, exit-code
  decoding, and signal-disposition capture are its whole surface.

## Supported workflow

Swift Testing is the only test framework:

```sh
swift build
swift test
```

The package has no external dependencies, so both run offline.

## Source conventions

- Add `// Copyright (c) <year> <contributor>. Licensed under the MIT License.`
  to new comment-capable source files, using the first publication year.
- Add DocC to public types, properties, methods, initializers, and protocols.
  Document parameters, returns, and errors when present.
- Spell the error type on new and changed signatures (`throws(SomeError)`).
- Write Swift tests with Swift Testing, never XCTest.

## GitHub-centered work

- Fetch and compare `origin/main` before branching.
- Keep designs, plans, and decisions in GitHub issues or comments.
- One fix per PR, opened against `main`.
- Use Conventional Commits with the configured identity and no bot co-author
  trailer.
- Ask before creating an issue the user did not request.
