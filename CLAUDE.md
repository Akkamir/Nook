# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

All repository guidance lives in **[AGENTS.md](./AGENTS.md)** — read it first. It is the single source of truth and covers architecture (data flow, the daemon, the Bits economy, and the **ledger schema duplicated across both targets**), build/test commands, coding style, testing, and commit/PR conventions.

Quick reference:
- `make daemon` / `swift test` — build and test the SwiftPM daemon (`Tests/NookTests`, `import NookDaemon`).
- `make app` — regenerate `NookApp.xcodeproj` from `project.yml` (source of truth; don't hand-edit the `.xcodeproj`).
- `xcodebuild test -scheme NookApp -project NookApp.xcodeproj` — run app tests (`Tests/NookAppTests`, `import Nook`). Single test: append `-only-testing:NookAppTests/<TestClass>/<testMethod>`.
