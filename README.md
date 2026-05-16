<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" width="96" alt="MenuBarManager icon">
</p>

<h1 align="center">MenuBarManager</h1>

<p align="center">
  A tiny macOS menu bar utility for hiding the clutter and keeping the items you actually need.
</p>

<p align="center">
  <a href="https://github.com/Jonathanm10/MenuBarManager/releases/latest"><strong>Download the latest DMG</strong></a>
  ·
  <a href="#local-development">Build from source</a>
  ·
  <a href="#permissions">Permissions</a>
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white">
  <img alt="Tuist" src="https://img.shields.io/badge/Tuist-managed-5D5FEF">
  <img alt="Release" src="https://img.shields.io/badge/release-DMG-0A7EA4">
</p>

## What It Does

MenuBarManager adds a small three-dot control to your macOS menu bar. Click it to collapse or reveal the hidden section; right-click it to open the configuration window.

It works with real macOS status item windows rather than drawing a fake overlay. The app keeps selected items visible, moves the rest into a hidden section, and replays your saved choices on future launches when those items are detected again.

## Highlights

- Keep only selected menu bar items visible.
- Collapse and reveal hidden items from a persistent menu bar control.
- Search, filter, bulk-hide, bulk-show, and reset saved rules.
- Preserve stable item choices across launches using resolved item identities.
- Show captured menu bar thumbnails when Screen Recording permission is granted.
- Fall back to app icons, system glyphs, or initials when previews are unavailable.
- Run as a proper menu bar app with `LSUIElement`, no Dock icon, and no main window.

## Install

Download `MenuBarManager.dmg` from [GitHub Releases](https://github.com/Jonathanm10/MenuBarManager/releases/latest), open it, and drag `MenuBarManager.app` into Applications.

The app is designed to be distributed as a DMG. If no release is published yet, use the source build flow below.

## Usage

1. Launch `MenuBarManager`.
2. Right-click the three-dot menu bar item to open configuration.
3. Check the items that should stay visible.
4. Left-click the three-dot item to collapse or reveal the hidden section.
5. Use reset when you want to clear all saved visibility rules and start over.

The app starts collapsed by default while keeping the `MB` control reachable, so the hidden section can always be toggled back.

## Permissions

MenuBarManager can run without extra permissions, but macOS permissions improve the experience:

| Permission | Why it helps |
| --- | --- |
| Accessibility | Improves item names and makes managed menu bar movement more reliable. |
| Screen Recording | Enables captured thumbnails for real menu bar items. |

Permission state can be inspected locally:

```bash
./Scripts/doctor-permissions.sh
```

Open the relevant macOS Settings panes:

```bash
./Scripts/doctor-permissions.sh --open-settings
```

Reset only this app's TCC rows when a development signing identity changed:

```bash
./Scripts/doctor-permissions.sh --reset-tcc
```

## Local Development

Build, install to `~/Applications/MenuBarManager.app`, sign with a stable Apple Development certificate when available, and launch:

```bash
./run-menubar.sh
```

Relaunch an already-built app:

```bash
./run-menubar.sh --skip-build
```

Launch and print signing/permission diagnostics:

```bash
./run-menubar.sh --doctor
```

Force a specific signing identity:

```bash
MENUBAR_MANAGER_CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./run-menubar.sh
```

If `tuist` is not installed globally, the scripts use `mise x tuist@4.194.3`.

## Validation

Run the unit test suite:

```bash
./Scripts/test-unit.sh
```

Validate saved visibility replay without relying on XCUITest:

```bash
./Scripts/validate-saved-visibility-rules.sh
```

Run visual layout diagnostics:

```bash
./Scripts/visual-validate-menubar.sh
```

## Project Shape

```text
Sources/      SwiftUI, AppKit, store, model, and menu bar control code
Tests/        Unit tests for rules, identity, and store behavior
UITests/      Diagnostic UI and polling coverage
Scripts/      Local run, permissions, validation, and icon tooling
Resources/    App icon and bundled assets
```

## Requirements

- macOS 14 or newer
- Xcode with the macOS SDK
- Tuist, or `mise` so the scripts can run Tuist automatically

