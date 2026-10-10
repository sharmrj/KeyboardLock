# Keyboard Lock

A deliberately small, local macOS utility with one switch. Turning the switch on suppresses keyboard events in the current login session; turning it off restores normal input.

## Build and install

The app uses only Apple frameworks and has no third-party runtime dependencies.

```sh
cd KeyboardLock
make app
cp -R "dist/Keyboard Lock.app" /Applications/
open "/Applications/Keyboard Lock.app"
```

On the first attempt to turn the switch on, macOS asks for Accessibility access. Allow **Keyboard Lock** in **System Settings → Privacy & Security → Accessibility**, return to the app, and turn the switch on again. Install the app in its final location before granting permission; moving or rebuilding an ad-hoc-signed app can make macOS ask again.

The application is intentionally not sandboxed: a sandboxed app cannot install the active session event filter needed to discard global key events.

## Safety behavior

- The window floats above other windows and cannot be closed or minimized while the keyboard is locked, so the switch remains reachable with the pointer.
- Quitting or crashing the process removes the event tap automatically, restoring keyboard input.
- The app always starts unlocked and never persists the locked state.
- If a key was already held when locking began, its unmatched key-up event is allowed through to prevent a logically “stuck” key.
- The app refuses to lock while a modifier key is held.
- If macOS disables the event tap because its callback timed out, the app immediately re-enables it.

## Scope and platform limitation

This uses a supported active `CGEventTap` at `cgSessionEventTap`, filtering key-down, key-up, modifier, and system-defined/media-key events. It affects ordinary keyboards for the active graphical login session, including built-in and external keyboards.

macOS does not let a normal non-root GUI app place a filter at the HID event tap. Consequently, no user-session utility can promise to suppress hardware/firmware controls (for example, the power/Touch ID button), pre-login/FileVault input, recoveryOS, or protected operating-system shortcuts handled outside the session event stream. Those are intentionally outside this app's scope.

## Development

```sh
make build   # debug compile
make app     # release .app bundle in dist/
make clean
```

For reliable TCC/Accessibility identity, test the bundled app rather than `swift run`.
