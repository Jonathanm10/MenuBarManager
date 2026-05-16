# MenuBarManager

Minimal macOS menu bar manager built with SwiftUI, AppKit, and Tuist.

It creates a visible three-dot menu bar control and a separate invisible divider
immediately to its left. When collapsed, the divider expands to push the hidden
section of real macOS menu bar items offscreen. When expanded, it shrinks back
so that section is visible again.

Right-click the three-dot item to open a configuration window. It inventories the
real menu bar windows exposed by macOS, keeps them in menu-bar order, and lets
you choose which items stay visible. Saved choices are stored by item identity
and replayed on later launches when the item is found again.

The configuration window is an allow-list: checked items stay in the menu bar,
while every other manageable item is automatically moved into the hidden section.
Left-click the three-dot item to reveal or collapse the hidden section without opening config.

The manager is designed for dense 14-inch menu bars: it shows visible/hidden
counts, supports filtering, can hide or show every currently filtered item in
one action, and exposes a reset for saved visibility rules when you want to
start over.

Layout sections render menu bar items as icon-only glyphs, matching the real
menu bar more closely than text chips. The app uses a captured menu bar window
thumbnail when Screen Recording is granted to MenuBarManager; the configuration
window exposes an icon preview button when that permission is missing. Without
that permission it falls back to the owning app icon or a known system glyph for
regular menu extras.

## Local run

```bash
./run-menubar.sh
```

The script generates the Tuist project without opening Xcode, builds the app,
stops any previous running instance, copies the new build to
`~/Applications/MenuBarManager.app`, signs that installed app with the first
available Apple Development certificate, and launches it through LaunchServices
so the menu bar item stays alive like a normal app. Keeping both the app path and
the signing requirement stable lets macOS privacy permissions survive normal
rebuilds.

For faster relaunches after a build already exists:

```bash
./run-menubar.sh --skip-build
```

To print signing and permission diagnostics immediately after launch:

```bash
./run-menubar.sh --doctor
```

If you want to force a specific certificate, set:

```bash
MENUBAR_MANAGER_CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./run-menubar.sh
```

## Permission debugging

Use the doctor before changing macOS privacy toggles:

```bash
./Scripts/doctor-permissions.sh
```

It checks the stable app bundle, bundle identifier, code signature, running
process path, duplicate app copies with the same bundle id, and readable TCC
rows for Screen Recording and Accessibility. If Settings appears to show the
wrong app, first make sure the running executable is
`~/Applications/MenuBarManager.app/Contents/MacOS/MenuBarManager`.

Local debug builds are signed with Xcode's ad-hoc "Sign to Run Locally"
identity inside DerivedData, then `./run-menubar.sh` re-signs the installed app
with a stable Apple Development certificate. If the selected signing identity
changes, reset this app's TCC rows once and grant the permissions again.

To open the relevant panes:

```bash
./Scripts/doctor-permissions.sh --open-settings
```

If a development build identity changed and macOS is stuck on an old decision,
reset only this app's TCC rows and grant the permissions again:

```bash
./Scripts/doctor-permissions.sh --reset-tcc
```

## Validation

```bash
./Scripts/test-unit.sh
```

If `tuist` is not installed globally, the run script uses `mise x tuist@4.194.3`.
The unit-test script builds the app and test bundle through the generated Tuist
workspace, then runs the standalone `MenuBarManagerTests.xctest` bundle with
`xcrun xctest`. This avoids macOS UI Automation prompts for logic tests.

For visual layout validation:

```bash
./Scripts/visual-validate-menubar.sh
```

That script builds through `xcodebuildmcp` when available, launches the app in a
diagnostic mode, opens the panel, and verifies real CGS menu bar frames.

For saved per-item rules without relying on XCUITest:

```bash
./Scripts/validate-saved-visibility-rules.sh
```

That script launches the app with isolated diagnostic preferences, injects a
saved `hidden` rule for a temporary uniquely named menu bar probe item, applies
the same replay path used on launch, and verifies the targeted CG window was
moved into the hidden set.

## Usage

1. Launch the app.
2. Right-click the three-dot item to open configuration.
3. Keep checked only the items that should always remain in the menu bar.
4. Left-click the three-dot item to reveal or collapse the hidden section.
5. Use `Grant Accessibility` when macOS exposes generic item names and you want
   better labels.

The app starts collapsed by default while keeping the `MB` control visible, so
the hidden state can always be toggled back. Accessibility access is not prompted
on refresh; grant it explicitly only if you want better item names. Screen
Recording is treated as optional: already-granted access enables captured menu
bar thumbnails, otherwise fallback icons and initials are used. The core
divider-based visibility mode continues to use real macOS status item layout
rather than drawing an overlay.
