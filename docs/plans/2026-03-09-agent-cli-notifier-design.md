# Agent CLI Notifier Design

Date: 2026-03-09
Status: Approved

## Summary

This project should evolve from a shell-script installer for a Claude-focused notifier into a public, multi-agent CLI product.

Approved naming:

- Project and repository name: `agent-cli-notifier`
- Primary CLI command: `agent-notifier`

Approved distribution goal:

- Public distribution for general users
- Install experience should be as close to one command as possible
- `npx` should be the primary entry point
- `brew` should be a first-class secondary distribution path

## Goals

- Replace the `claude-code-notifier` branding with a multi-agent brand.
- Make installation suitable for public distribution without requiring `git clone`.
- Support Claude Code, OpenAI Codex, and Google Gemini CLI from one unified installer.
- Expose a stable CLI surface for install, uninstall, diagnostics, and status.
- Keep the underlying notifier resources reusable across targets.

## Non-Goals

- Full implementation in this phase
- Adding support for new agent CLIs beyond Claude, Codex, and Gemini
- Windows-specific packaging
- Publishing to Homebrew core in the first release

## Product Shape

The product should be a general-purpose installer CLI rather than a loose collection of scripts.

External product surface:

- Brand: `agent-cli-notifier`
- Executable: `agent-notifier`
- Positioning: add native notifications, sound prompts, and optional terminal focus behavior to supported agent CLIs

## CLI Surface

The initial command surface should be:

- `agent-notifier init`
- `agent-notifier init --targets claude,codex,gemini --auto`
- `agent-notifier status`
- `agent-notifier doctor`
- `agent-notifier uninstall`
- `agent-notifier rename-migrate`

Command intent:

- `init`: detect the environment and install configuration for supported targets
- `status`: report which integrations are currently installed and whether they are healthy
- `doctor`: validate dependencies, hooks, wrappers, aliases, and configuration state
- `uninstall`: remove notifier integration for selected targets without deleting unrelated user settings
- `rename-migrate`: optional migration helper for users coming from older naming and layout conventions

Recommended install commands:

```bash
npx agent-cli-notifier init --auto
```

```bash
brew install <tap>/agent-notifier
agent-notifier init --auto
```

## Architecture

The codebase should move from a script-centric layout to a CLI package with reusable installer modules and bundled runtime resources.

Recommended structure:

```text
agent-cli-notifier/
  bin/
    agent-notifier
  lib/
    cli/
      init.js
      status.js
      doctor.js
      uninstall.js
    installers/
      claude.js
      codex.js
      gemini.js
    shared/
      paths.js
      prompts.js
      platform.js
      json-edit.js
      template.js
  resources/
    notify.sh
    codex_wrapper.py
    gemini_bridge.sh
    notifier.conf
    logo.png
  README.md
  package.json
```

Responsibilities:

- `bin/agent-notifier`: command dispatch only
- `lib/cli/*`: argument handling, output, interactive prompts, and command orchestration
- `lib/installers/*`: target-specific install, uninstall, detect, and doctor flows
- `lib/shared/*`: cross-cutting utilities such as path resolution, JSON edits, templating, and platform detection
- `resources/*`: files copied into user home directories for runtime use

## Resource Strategy

Current install logic relies heavily on copying files and mutating hard-coded paths with `sed`. That should be replaced with parameterized or templated runtime resources.

Target outcome:

- `notify.sh` should not hard-code a single home path such as `~/.claude/notifier.conf`
- Runtime resources should read configuration from environment variables, arguments, or generated wrapper files
- Installers should copy resources and generate thin target-specific launchers instead of rewriting the same script in place

Benefits:

- Renaming the project stops being a broad search-and-replace exercise
- Adding more agents becomes incremental
- Upgrades and diagnostics become more predictable

## Installer Interface

Each supported target installer should implement the same conceptual actions:

- `detect()`
- `install()`
- `doctor()`
- `uninstall()`

Expected behavior:

- `detect()`: confirm whether the target CLI and writable config locations are present
- `install()`: copy resources, inject hooks or wrappers, and print a clear result summary
- `doctor()`: verify the final configuration is actually active
- `uninstall()`: remove only the notifier-owned integration

This allows the top-level CLI to stay consistent even though Claude, Codex, and Gemini each integrate differently.

## Distribution Strategy

### Primary Path: npm and npx

The main user-facing install flow should be:

```bash
npx agent-cli-notifier init --auto
```

Requirements:

- Publish the project as an npm package
- Expose `agent-notifier` through `package.json` `bin`
- Include runtime resources in the package
- Ensure `init --auto` can run non-interactively
- Skip unsupported targets rather than failing the whole run

Why npm should be primary:

- Lowest friction for new users
- No repository cloning
- Natural cross-platform support for macOS and Linux
- Easy documentation and upgrade path

### Secondary Path: Homebrew

Homebrew should install the CLI and then delegate setup to the same initializer.

Recommended user flow:

```bash
brew install <tap>/agent-notifier
agent-notifier init --auto
```

Formula behavior:

- Install the executable and packaged resources
- Avoid directly mutating user home directory configuration during formula install
- Print a post-install hint that runs `agent-notifier init --auto`

Rationale:

- This stays aligned with Homebrew user expectations
- It reduces hidden side effects during install
- It reuses the same tested initialization path as npm users

## Release Model

Recommended release flow:

1. Create a git tag
2. Build a GitHub release artifact
3. Publish the npm package
4. Update the Homebrew tap formula version and checksum

Upgrade paths:

- `npx` users receive the latest package on execution
- npm global users can upgrade with npm
- Homebrew users can upgrade with `brew upgrade`

## Migration and Compatibility

Migration should be soft rather than abrupt.

Recommended compatibility strategy:

- Rename the GitHub repository to `agent-cli-notifier`
- Keep a visible note that the project was formerly `claude-code-notifier`
- Teach `doctor` and `init` to recognize legacy installs
- Offer a migration path that can either reuse, replace, or migrate legacy files
- If an old package name is ever published, mark it deprecated and direct users to the new package

The project should not silently break existing users if old paths or old wrappers are present.

## Risks

- Converting from shell-first install scripts to a public CLI package is a structural refactor, not a cosmetic rename.
- Codex support currently depends on a wrapper-based approach, so compatibility and diagnostics must stay explicit.
- Homebrew packaging adds release maintenance overhead and should not be treated as the primary implementation driver.

## Recommended Rollout

Implementation should proceed in stages:

1. Rename branding and restructure the repository around a real CLI package
2. Implement `init`, `status`, `doctor`, and `uninstall`
3. Make `npx agent-cli-notifier init --auto` work end-to-end
4. Add GitHub release artifacts
5. Add a Homebrew tap formula

Reasoning:

- The real product boundary is the CLI, not the brew formula
- Once the npm path works, brew becomes a packaging layer rather than a second installation system
- This order keeps maintenance cost and release risk lower

## Open Follow-Up

The next step should be an implementation plan broken down into concrete tasks across:

- repository rename and branding updates
- CLI scaffolding
- installer module extraction
- resource parameterization
- npm packaging
- GitHub release automation
- Homebrew tap setup

The current skill set in this environment does not expose the expected `writing-plans` skill referenced by the brainstorming workflow, so that implementation plan should be produced manually or via the next available planning workflow.
