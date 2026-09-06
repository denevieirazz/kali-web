# CloudOS Flutter Autonomy Contract

## Canonical rule

**Flutter owns the product experience. C++ owns system authority. SystemBroker exposes typed capabilities, commands and events between them.**

This refines the existing rule:

> Flutter desenha. C++ controla.

into:

> Flutter decides how the CloudOS experience looks, behaves and flows. Native code performs privileged/system operations and reports authoritative state.

## Flutter owns

Flutter is the primary authority for all user-visible CloudOS product behavior:

- Desktop layout and interaction
- Taskbar
- Start Menu and search UX
- Quick Settings presentation and interaction model
- Settings information architecture
- Files UI, tabs, views, breadcrumbs, previews and thumbnails
- Terminal UI, tabs and profile presentation
- Browser chrome and navigation UX
- Window chrome and CloudOS logical window state
- Workspaces
- Context menus
- Notifications and Notification Center
- Themes, transparency, animations and accessibility
- Onboarding and first-run UX
- Empty/loading/error states
- User preferences, pins, recents and layout preferences
- Product-level state machines that do not require privileged Windows authority

Changing those surfaces should normally require Flutter changes only.

## Native C++ owns

Native code remains the sole authority for operations that interact directly with Windows/WSL or require OS security/privilege:

- HWND discovery, ownership and containment
- Process creation/termination and Job Objects
- Win32/COM/WinRT system APIs
- Display driver operations
- Audio endpoints
- Hardware/device operations
- Filesystem mutation and Recycle Bin
- WSL/WSLg integration
- ConPTY
- WebView2 host lifecycle
- Session and recovery infrastructure
- Installer/update/rollback
- Security-sensitive registry access
- Power/system operations

Flutter must not replace this authority with `Process.run`, PowerShell, cmd.exe, ad-hoc registry writes or direct privileged Win32 logic.

## SystemBroker role

SystemBroker should increasingly expose four concepts rather than UI-specific RPCs:

1. **Capabilities** — what this machine/session can actually do.
2. **State** — authoritative current system state.
3. **Commands** — typed user intents that native code validates and executes.
4. **Events** — state changes/progress/lifecycle notifications pushed back to Flutter.

Examples:

```text
system.capabilities
display.capabilities
window.capabilities
files.capabilities
audio.capabilities
network.capabilities
terminal.capabilities
browser.capabilities
```

Commands should describe intent, not presentation:

```text
display.applyMode
files.copy
files.move
files.delete
window.launchManaged
window.close
terminal.createSession
audio.setVolume
```

Events should make Flutter reactive instead of polling:

```text
display.changed
files.progress
files.changed
window.created
window.attached
window.closed
terminal.output
terminal.exited
audio.changed
network.changed
```

## Capability-driven UI

Native code should not tell Flutter what button, card or layout to render. It should report facts such as:

```json
{
  "supported": true,
  "available": true,
  "permission": "allowed",
  "capabilities": ["toggle", "enumerate"]
}
```

Flutter decides whether that becomes a tile, button, submenu, disabled control or explanatory state.

Missing native capability must not crash or hollow out the Flutter surface. Flutter should remain functional and present an explicit unavailable/unsupported state.

## Display example

Correct direction:

```text
C++ enumerates real driver modes
        ↓
Broker exposes capabilities + stable mode identities
        ↓
Flutter decides sorting/filtering/recommended UX/confirmation countdown
        ↓
Flutter sends display.applyMode(modeId)
        ↓
C++ validates and applies exact supported mode
        ↓
Broker emits display.changed
        ↓
Flutter refreshes authoritative state
```

Flutter must never invent unsupported display modes. Native code must never decide how the mode picker looks.

## Managed Windows app example

Flutter should request an intent such as:

```text
window.launchManaged(appId)
```

Native code handles process/package/HWND attribution and emits lifecycle events such as:

```text
launchStarted
processDiscovered
windowDiscovered
windowAttached
windowDetached
processExited
launchFailed
```

Flutter decides how that managed app is represented inside the CloudOS desktop.

## Window management boundary

Flutter owns logical CloudOS window behavior: layout, taskbar representation, snap UX, workspace membership, focus presentation and chrome.

Native owns physical HWND operations for external/native apps and reports their lifecycle/state. Native must not encode visual layout policy unless required by Win32 constraints.

## Files boundary

Flutter owns Files UX: multiple windows/tabs, list/grid/gallery mode, thumbnails/previews, sorting/filtering/search presentation, selection, navigation history and context menus.

Native owns actual filesystem enumeration/mutation, shell metadata extraction, file associations, recycle operations and safe launch. Opening an ordinary file should be an intent with a clear policy/result rather than silently escaping to Explorer or Windows desktop.

## Quick Settings boundary

Flutter owns the panel, interaction model and presentation. Native reports real hardware/system capabilities and authoritative state. A tile must never pretend a capability exists; unsupported controls remain usable as UI with an explicit unavailable state or an internal CloudOS detail page.

## Performance rules

- Prefer event-driven state updates.
- Avoid 60 Hz system polling.
- Use bounded snapshots for startup/recovery/resync only.
- Use delta events for steady state.
- Browser, WSL and expensive providers remain lazy.
- Economy/Balanced/Performance profiles may alter visual/background cost, but not system correctness.

## Safety invariants

This autonomy change does **not** authorize persistent shell activation.

Until the physical login/reboot gates are completed:

- Explorer remains the official Windows shell.
- Winlogon Shell remains `explorer.exe`.
- Userinit remains intact.
- No custom HKCU shell persistence.
- No reboot/logoff is required for autonomy work.

## Migration strategy

Do not rewrite CloudOS all at once. Migrate one vertical slice at a time:

1. Inventory current UI-specific RPCs.
2. Introduce capability/state/command/event contracts beside them.
3. Move presentation decisions into Flutter.
4. Keep native authority intact.
5. Add tests for unsupported/degraded states.
6. Physically test installed CloudOS.
7. Remove old UI-specific RPC only after all consumers migrate.

Priority vertical slices:

1. Quick Settings
2. Settings
3. Files/open-with/managed launch
4. Window Manager and external app containment
5. Start Menu/search
6. Browser chrome
7. Desktop/context menus

## Definition of success

Flutter autonomy is successful when a substantial UX redesign of Start, Taskbar, Settings or Files can be implemented primarily in Dart/Flutter without modifying native code, while real Windows operations still remain secure, authoritative and testable in C++ through SystemBroker.
