# macOS 15 on Intel

Upstream Tinycast targets macOS 26: Liquid Glass is the design baseline and several features are
built on frameworks that shipped with it. This tree keeps the same app running from macOS 15 on an
Intel Mac, and builds it with the Command Line Tools alone — no Xcode, no `xcodebuild`, no `actool`.

## Build

```sh
./Scripts/build-macos15.sh          # → build/macos15/Tinycast Dev.app
open "build/macos15/Tinycast Dev.app"
```

Requirements: an Intel Mac on macOS 15 or later, Xcode **or** the Command Line Tools for macOS 15+.
The script compiles `x86_64-apple-macos15.0` against whatever SDK `xcrun` reports, which on a
Command Line Tools-only machine is the macOS 26 SDK — availability checks still refuse anything the
older system cannot run.

The result is the Debug channel (`Tinycast Dev.app`, `com.abueammar.tinycast.dev`), so it neither
reads nor overwrites an installed copy's settings, caches, TCC grants or login item. It is signed
ad-hoc, which is enough to run locally and to keep asking for Accessibility once.

## What the script assembles by hand

`xcodebuild` and `actool` are part of Xcode. Where the script stands in for them:

| Xcode step | Script |
| --- | --- |
| `swiftc` for the app and three helpers | same compiler, same Swift 6 mode, `-DDEBUG` |
| `$(VAR)` substitution in `Info.plist` | `Scripts/render-plist.py` |
| `Assets.car` for `Image("…")` | each imageset copied beside the bundle under its own name |
| `Localizable.xcstrings` via `xcstringstool` | `Scripts/localize-xcstrings.py` → `.lproj/Localizable.strings` + `.stringsdict` |
| `tinycast.icon` via `actool` | `Scripts/make-icon.swift` renders an `.icns` from the mark |
| code signing | `codesign --sign -` on every helper and the app |

A missing catalog is why `MenuBarLabel` loads the mark by name and sets `isTemplate` itself: the
catalog's `template-rendering-intent` only exists inside `Assets.car`.

## Source changes

The app is otherwise unmodified, but each of these is a macOS 26 API that macOS 15 does not have:

| Area | macOS 26 | macOS 15 |
| --- | --- | --- |
| Glass | `.glassEffect`, `GlassEffectContainer`, `NSGlassEffectView` | `DesignSystem/GlassCompat.swift`: `.ultraThinMaterial` + hairline stroke, `NSVisualEffectView` |
| Typed observation | `NotificationCenter.ObservationToken`, `addObserver(of:for:)` | block-based observers on `.main` |
| Loopback servers | `NetworkListener`, `NetworkConnection<TCP>` | `NWListener`/`NWConnection` with wrapped callbacks |
| Apple Intelligence | `FoundationModels` | provider reports `requiresNewerSystem`; the framework is weak-linked |
| Translation | `TranslationSession(installedSource:target:)` | reports that macOS 26 is required |
| Environment | `@Entry` (SwiftUI macro) | explicit `EnvironmentKey` types |
| Spawn | `posix_spawn_file_actions_addchdir` | `…_addchdir_np` |

Two more changes are compiler workarounds rather than API ones: `CalcEngine`'s `??` chain became a
loop of evaluators, and `RootPaletteView.stateObservers` was split into three chains, both because
the type checker timed out on macOS 15's SDK.

## What is different on macOS 15

- **No Liquid Glass.** Surfaces use the same shapes and hit areas over `.ultraThinMaterial`, with a
 1 pt rim instead of the glass highlight. On macOS 26 the real effect is used again.
- **Apple Intelligence and Apple Translate** need macOS 26: the routes report that and stay out of
  the picker. Every other provider is unaffected.
- **The app icon** is generated from the mark, so it lacks Icon Composer's layered treatment.
- No asset catalog, so an imageset without a single vector file (none today) would render empty.

Everything else — launcher, clipboard history, hotkeys, snippets, quicklinks, extensions, notes,
window management, dictation, file search, MCP/OpenCode bridges — runs unchanged.

## Tests

`./Scripts/run-tests.sh` compiles each harness against the shipped sources. On macOS 15 the
`AppleIntelligenceTests` harness weak-links `FoundationModels` and skips the transcript and
failure-mapping assertions, which need the macOS 26 framework; the rest of the suite is unaffected.

## Verification

Checked on an Intel Mac running macOS 15.8.3 with the Command Line Tools only:

- `./Scripts/build-macos15.sh` produces a signed `Tinycast Dev.app` that launches and renders its
  palette and onboarding surfaces; no crash report is written.
- The executable is `Mach-O thin (x86_64)`, ad-hoc signed, and weak-links `FoundationModels`, so the
  app starts on a system without it.
- `LSMinimumSystemVersion` is `15.0`, and the bundle carries its `.lproj` strings, images and icon.
- `AppleIntelligenceTests` and `HyperKeyEngineTests` pass through `./Scripts/run-tests.sh`.

Not verified automatically: the global hotkey and menu-bar click need Accessibility permission, so
they are exercised by hand — the palette appears on ⌥Space.
