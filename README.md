# 4irmann's FaderPort Driver for REAPER

A driver for the **PreSonus FaderPort (classic)** in REAPER. It is a port of the Renoise tool
*4irmann's FaderPort Driver*, and it comes in two variants with the same features and button mapping:

| Folder | Variant | When to use it |
|---|---|---|
| [lua/](lua/README.md) | ReaScript (Lua) | No build step and runs on every platform. Has the built-in emulator. |
| [cpp/](cpp/README.md) | Native C++ extension | Native control surface with exact encoder ballistics, `GetTouchState` touch automation, and no MIDI preferences setup. Needs a build. |

Only one variant can run at a time; the two lock each other out. They share their settings through
REAPER's ExtState section `4irmannFaderPort`.

## Installation on Windows

1. Download `reaper-faderport-driver-<version>-setup.exe` from
   [Releases](https://github.com/4irmann/reaper-faderport-driver/releases) and run it.
   No administrator rights are needed.
2. Choose the components: the C++ extension (recommended), the emulator window, and/or the Lua driver.
   The installer detects the REAPER resource path (`%APPDATA%\REAPER`); for a portable REAPER,
   select its folder.
3. Start REAPER. On first start the installed Lua scripts register themselves in the action list. If you
   selected it, the Lua driver also starts automatically.
4. Set up MIDI. **C++ extension:** disable the FaderPort in Preferences → Audio → MIDI devices.
   **Lua driver:** enable it for control messages (see [lua/README.md](lua/README.md)).

Uninstall from Windows Settings → Apps. This removes the files, the startup entry, and the registered actions
(`reaper-kb.ini` is backed up to `reaper-kb.ini.faderport-backup`).

macOS/Linux: copy the `.dylib`/`.so` from the release to `UserPlugins`, or load the Lua scripts
manually; see the READMEs of the variants.

To create a release, push a tag `v<version>`, for example `git tag v2.0.0 && git push origin v2.0.0`. CI then
builds the installer and all binaries and attaches them to a GitHub release.

## Tests

```
lua lua/tests/run_tests.lua                    # Lua 5.4
cmake -S cpp -B cpp/build && cmake --build cpp/build && ctest --test-dir cpp/build
```

## License

Apache License 2.0, see [LICENSE.txt](LICENSE.txt).
