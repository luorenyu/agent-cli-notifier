# Agent CLI Notifier Implementation Plan

Date: 2026-03-09
Source Design: `docs/plans/2026-03-09-agent-cli-notifier-design.md`
Status: Draft for execution

## Summary

This plan converts the approved `agent-cli-notifier` design into an execution sequence that can be implemented incrementally without breaking the current notifier behavior.

The implementation should prioritize:

- preserving existing functionality during the transition
- establishing a real CLI package boundary first
- getting `npx agent-cli-notifier init --auto` working before Homebrew work

## Execution Principles

- Keep the current shell-based installer working until the new CLI path is verified.
- Avoid mixing repository rename work with large behavior refactors in the same commit when possible.
- Keep the new CLI package thin at first and reuse existing notifier scripts before deeper rewrites.
- Add diagnostics early so each phase has a way to prove the installation still works.

## Phase 0: Baseline and Safety

Objective:

- establish a safe baseline before refactoring packaging and installer logic

Tasks:

- inventory all current install targets and generated files
- document current runtime locations under `~/.claude`, `~/.gemini`, and `~/.codex`
- identify all hard-coded references to `claude-code-notifier`, `.claude`, and Claude-specific titles
- capture current manual install and uninstall flows from the existing scripts
- define a lightweight manual verification checklist for Claude, Gemini, and Codex

Deliverables:

- updated technical notes in the repository or issue tracker
- a verification checklist for existing behavior

Acceptance criteria:

- every current installed file and config mutation is known
- there is a repeatable checklist to compare old and new behavior

## Phase 1: Repository and Branding Preparation

Objective:

- align naming and documentation with the new product identity before distribution work

Tasks:

- rename project references in README and user-facing text from `claude-code-notifier` to `agent-cli-notifier`
- define the executable command name as `agent-notifier` in docs
- add a migration note that the project was formerly `claude-code-notifier`
- audit scripts and config defaults for Claude-specific titles and replace them with target-aware titles where appropriate
- prepare repository metadata for rename, including badges, release URLs, and install examples

Deliverables:

- README updated to new branding
- internal strings ready for multi-agent naming

Dependencies:

- phase 0 inventory complete

Acceptance criteria:

- no top-level docs describe the project as Claude-only
- install examples no longer depend on `git clone`

## Phase 2: CLI Package Scaffold

Objective:

- introduce a real distributable CLI package without yet removing the legacy installer

Tasks:

- add `package.json` with package name `agent-cli-notifier`
- add `bin/agent-notifier` as the executable entrypoint
- create initial command modules for `init`, `status`, `doctor`, and `uninstall`
- move reusable assets into a new `resources/` directory
- add shared utilities for path resolution, platform detection, file copying, and JSON mutation
- make the CLI runnable locally via `node` and package `bin`

Deliverables:

- CLI package scaffold
- local development entrypoint for `agent-notifier`

Dependencies:

- phase 1 branding decisions applied

Acceptance criteria:

- `agent-notifier --help` works locally
- package metadata exposes the correct binary name
- resources are bundled from a single canonical location

## Phase 3: Extract Installer Modules

Objective:

- split the current shell installer behavior into target-specific install modules

Tasks:

- implement `claude` installer module with `detect`, `install`, `doctor`, and `uninstall`
- implement `gemini` installer module with the same interface
- implement `codex` installer module with the same interface
- centralize file operations and JSON edits instead of embedding them directly in one large script
- keep the legacy `install.sh` and `uninstall.sh` available during this phase as fallback

Deliverables:

- `lib/installers/claude.*`
- `lib/installers/gemini.*`
- `lib/installers/codex.*`

Dependencies:

- phase 2 CLI scaffold exists

Acceptance criteria:

- each target can be detected independently
- installer modules can be called from the new CLI without requiring interactive shell menus

## Phase 4: Resource Parameterization

Objective:

- remove brittle path rewriting and make runtime resources reusable across targets

Tasks:

- refactor `notify.sh` to read config and asset paths from generated environment variables, flags, or wrapper files
- refactor the Gemini bridge and Codex wrapper to consume shared path conventions
- stop mutating copied files with repeated `sed` replacements where possible
- generate thin target-specific wrappers that inject the correct runtime values
- validate that titles, icon paths, and config file paths are target-aware

Deliverables:

- parameterized runtime resources
- thin generated wrappers per target

Dependencies:

- phase 3 installer modules are functional

Acceptance criteria:

- installer logic no longer depends on broad string replacement inside copied scripts
- one resource set can support Claude, Gemini, and Codex

## Phase 5: Implement Core CLI Commands

Objective:

- make the new command surface usable for real installations

Tasks:

- implement `agent-notifier init`
- implement `agent-notifier init --targets ... --auto`
- implement `agent-notifier status`
- implement `agent-notifier doctor`
- implement `agent-notifier uninstall`
- optionally implement `agent-notifier rename-migrate`
- add concise terminal output and non-zero exits for failed diagnostics

Deliverables:

- end-to-end local CLI workflow

Dependencies:

- phases 3 and 4 complete enough for real target installs

Acceptance criteria:

- non-interactive init works for available targets
- status reports installed versus skipped targets clearly
- doctor can detect common misconfigurations
- uninstall removes notifier-owned integration only

## Phase 6: Legacy Migration Support

Objective:

- avoid breaking existing users during the rename and packaging transition

Tasks:

- detect legacy install footprints under old paths or old naming conventions
- decide migration behavior for existing installs: reuse, replace, or prompt
- add explicit migration messaging to `init` and `doctor`
- ensure old Codex wrapper conventions are recognized
- add deprecation language for old project naming in docs

Deliverables:

- legacy migration path
- compatibility messages and migration checks

Dependencies:

- phase 5 command flow in place

Acceptance criteria:

- existing users can upgrade without manually deleting old config
- doctor distinguishes legacy installs from broken installs

## Phase 7: Packaging and npm Release

Objective:

- make the product publicly installable through npm and npx

Tasks:

- verify packaged files include binaries and runtime resources
- test `npx agent-cli-notifier init --auto` on a clean environment
- add release scripts for npm publishing
- define versioning strategy and changelog expectations
- document npm install, npx usage, upgrade, and uninstall behavior

Deliverables:

- first npm-publishable package
- validated `npx` install flow

Dependencies:

- phase 5 complete

Acceptance criteria:

- `npx agent-cli-notifier init --auto` works end-to-end on supported systems
- package contents are deterministic and complete

## Phase 8: GitHub Release Automation

Objective:

- standardize artifact publishing and release versioning

Tasks:

- add GitHub Actions workflow for release tagging and packaging
- produce a release artifact suitable for external distribution
- ensure release notes link to npm and installation docs
- verify release asset naming is aligned with the new project name

Deliverables:

- GitHub release workflow
- tagged release process

Dependencies:

- phase 7 package structure stable

Acceptance criteria:

- a tag can produce a reproducible release artifact
- release documentation matches the actual install commands

## Phase 9: Homebrew Tap

Objective:

- provide a stable Homebrew install path without duplicating installer logic

Tasks:

- create a tap repository or formula location
- write the `agent-notifier` formula
- point the formula to the published release artifact
- add `caveats` that instruct the user to run `agent-notifier init --auto`
- test install, upgrade, and uninstall via brew

Deliverables:

- working Homebrew tap formula

Dependencies:

- phases 7 and 8 complete

Acceptance criteria:

- `brew install <tap>/agent-notifier` installs the CLI correctly
- post-install guidance is accurate
- upgrades do not require a second packaging system

## Testing Strategy

Minimum test coverage for rollout:

- manual smoke tests for Claude, Gemini, and Codex installs
- command-level tests for argument parsing and target selection
- fixture-based tests for config file mutation
- regression tests for legacy install detection
- packaging tests that assert resources are included in the published artifact

Suggested verification matrix:

- macOS with Claude only
- macOS with Codex only
- macOS with Claude + Codex + Gemini
- Linux with Claude only
- Linux with Gemini only

## Suggested Commit Sequence

Recommended high-level commit order:

1. docs and branding updates
2. package scaffold and command entrypoint
3. shared utilities and resource relocation
4. Claude installer extraction
5. Gemini installer extraction
6. Codex installer extraction
7. parameterized resources
8. core CLI command wiring
9. migration support
10. npm packaging
11. GitHub release automation
12. Homebrew tap

This keeps early commits reviewable and reduces the blast radius of failures.

## Risks and Mitigations

- Risk: packaging refactor breaks a working install path
  Mitigation: keep legacy installer working until the CLI path is validated

- Risk: Codex wrapper behavior changes during refactor
  Mitigation: preserve wrapper behavior first, then refactor internals behind tests and smoke checks

- Risk: path and config templating becomes too abstract too early
  Mitigation: parameterize only what is currently hard-coded and necessary for multi-target reuse

- Risk: Homebrew work expands scope too early
  Mitigation: delay brew until npm flow is stable

## Exit Criteria

The project can be considered successfully transitioned when all of the following are true:

- the repository and docs consistently use `agent-cli-notifier`
- users can install with `npx agent-cli-notifier init --auto`
- `agent-notifier status` and `agent-notifier doctor` work for supported targets
- legacy installs are recognized and guided through migration
- npm publishing is repeatable
- Homebrew installation works through a tap without separate installer logic
