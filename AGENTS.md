# Repository Guidelines

## Project Structure & Module Organization

Gourd is a Swift/SwiftUI macOS notch workspace. `DynamicIsland/` contains `Kernel/` (module contracts), `Host/` (composition and rendering), `Modules/` (features), and `components/` (shared UI). Assets live in `DynamicIsland/Assets.xcassets`; localization uses `Localizable.xcstrings` and `*.lproj`. XCTest suites are in `DynamicIslandTests/`; Python regressions are in `tests/`. `tools/` holds build/signing scripts; `docs/` records designs and `docs/guide/` contains user documentation.

## Build, Test, and Development Commands

Use Xcode on macOS 26+ with Apple Silicon (arm64). Open `DynamicIsland.xcodeproj`, select scheme `DynamicIsland`, and run locally; the product/module is `Gourd`.

- `sh tools/build.sh`: build Release `Gourd.app` and print its path.
- `sh tools/build.sh --install`: build and install `/Applications/壶中天.app`, quitting the previous instance.
- `sh tools/build.sh --dmg`: produce a DMG in `dist/`.
- `sh tools/install-local.sh` (or double-click `install-local.command`): one-click local install — same as `build.sh --install` and then launch the app once. Pass `--no-open` when running from a non-interactive shell (launching from one yields an instance with no UI session).
- `sh install.sh`: the *end-user* installer — downloads the DMG from a GitHub Release. Not for local development.

Provision `Gourd Local` with `sh tools/setup-signing.sh` before running local XCTest or `--dmg`. Retain the project-configured signing identity for local tests; avoid command-line `CODE_SIGN_IDENTITY` overrides. Run tests from the repository root:

```bash
xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/Gourd \
  -only-testing:DynamicIslandTests -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES
python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle
```

## Coding Style & Naming Conventions

Follow Swift API Design Guidelines and surrounding code: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Keep functions focused and document public APIs or complex logic. The checked-in CI workflow defines advisory `xcrun swift-format lint --recursive DynamicIsland`; avoid wholesale formatting.

## Testing Guidelines

Use XCTest (`@testable import Gourd`) with `*Tests.swift` files and descriptive `test…` methods; Python tests use `unittest` and `test_*.py`. Add regression cases for changed behavior using fixtures or injected dependencies. Preserve coverage; no numeric threshold is declared. Code changes must pass local XCTest and the Release build gate.

## Commit & Pull Request Guidelines

Write descriptive subjects; history includes Chinese summaries, `T1:`/`F1:` task prefixes, and `文档：` documentation prefixes. Explain what changed, why, and validation. Keep PRs focused, current with `main`, link related issues, and include screenshots or recordings for UI changes. Address maintainer feedback before merging.

## Architecture, Configuration & Licensing

Read [decisions](docs/00-decisions.md), [architecture](docs/01-architecture.md), and [module protocol](docs/06-module-protocol.md) before changing modules. Inject dependencies through `ModuleContext`; keep lifecycle methods idempotent and `content(for:)` synchronous. Preserve GPL-3.0 and upstream notices. Exclude private configuration, signing keys, and generated build output from commits.

## Secrets & Packaging Red Lines (non-negotiable)

- **Never** put API keys, tokens, passwords, `.key` files, credential JSON, Keychain dumps, real `secretReference` values, or filled AI configuration into the repository, commits, PRs, issues, screenshots, logs, test fixtures, docs, app bundles, DMGs, or release assets.
- The AI API key is **runtime-only**: `~/Library/Application Support/Gourd/AICredentials/<UUID>.key`, directory `0700`, file `0600`. It is created by the user after install and is never part of the repo or build products. The app config stores only the UUID reference.
- Tests must use injected fakes or temporary directories; never read the real credential directory or the user's Keychain.
- Before commit, upload, or packaging, run the repository secret scan. If a secret is found, stop, remove it from the artifact, and **rotate the key**; deleting it later does not undo the exposure.
- `tools/build.sh` must fail rather than package an app bundle that contains any current credential value. Do not weaken or bypass that gate.
- Use only placeholders such as `fixture-secret` and `<your-key>` in tests, docs, and examples.
