# 4irmann's FaderPort Driver for REAPER: C++ extension

A native REAPER extension (`reaper_4irmann_faderport.dll` / `.dylib` / `.so`) for the
**PreSonus FaderPort (classic)**. It has the same features and the same button mapping as the
[Lua variant](../lua/README.md). The two variants share their settings through REAPER's ExtState
(section `4irmannFaderPort`). The [manual](../MANUAL.md) describes all functions in detail.

## Differences from the Lua variant

| | Lua (ReaScript) | C++ (extension) |
|---|---|---|
| MIDI devices | Polled with `MIDI_GetRecentInputEvent`. The device must be **enabled** in REAPER's MIDI preferences. | The extension opens the device itself, like REAPER's own control surfaces. The device must be **disabled** in REAPER's MIDI preferences. |
| Encoder ballistics | Timing per defer cycle | Every MIDI event has its own time stamp (1/1024000 s), which gives exact ballistics per tick as in the Renoise original |
| Touch/latch automation | Gestures via `SetTrackUIVolume(…, done)` | REAPER queries the surface via `GetTouchState()` |
| Focused FX | Polls `GetFocusedFX2` | Callback `CSURF_EXT_SETFOCUSEDFX` |
| Emulator | Built in | `lua/4irmann_FaderPort - C++ emulator.lua` (same window, connected through the ReaScript API) |
| DSP bindings | `lua/faderport/bindings.lua` | Built-in defaults, or `<resource path>/4irmann_faderport_bindings.txt` (template: [4irmann_faderport_bindings.txt](4irmann_faderport_bindings.txt)) |
| Installation | No build step | Prebuilt binaries in the releases, or build per platform |

**Resolution:** The FaderPort transmits the fader with 10 bits (1024 steps) in both directions. That
is a limit of the hardware and protocol, and it applies to both variants. The pan encoder sends
relative ticks, so its resolution is purely virtual (`virtual_pan_resolution`, default 128). Shift+pan
trims the fader parameter in steps of 1/2000.

## Build

Requirements: CMake ≥ 3.20, Git, and a C++17 compiler.
On Windows this must be **MSVC** (Visual Studio 2022 or the Build Tools with "Desktop development with C++").
MinGW does not work, because REAPER expects the MSVC ABI for its C++ interfaces.

```
cd cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

CMake downloads the REAPER SDK, and WDL on macOS/Linux, at pinned commits.

The version shown in the DLL properties and in REAPER defaults to the project version. Set it with
`-DFADERPORT_VERSION=2.0.1`; CI uses the release tag for this.

## Installation

**Windows:** use the installer from the [releases](https://github.com/4irmann/reaper-faderport-driver/releases),
installation type "C++ extension (recommended)". It installs the extension and the emulator, and
removes files of older versions. After that, only the MIDI setup (step 2) is left.

**Manual installation:** the release contains the prebuilt `reaper_4irmann_faderport.dll`, `.dylib`
and `.so`. To build it yourself, see [Build](#build).

1. Copy `reaper_4irmann_faderport.dll` (Windows), `.dylib` (macOS), or `.so` (Linux) to
   `<REAPER resource path>/UserPlugins/` and restart REAPER.
2. Preferences → Audio → MIDI Inputs/Outputs: **disable** the FaderPort, and remove REAPER's built-in
   FaderPort control surface if one is configured.
3. The driver starts automatically. These actions are available:
   - `4irmann FaderPort (C++): Enable/disable driver` (toggle; the state is saved)
   - `4irmann FaderPort (C++): Reset`
   - `4irmann FaderPort (C++): Toggle MIDI dump`
   - `4irmann FaderPort (C++): Show FX parameters`
4. Optional emulator: copy the `lua` folder (or the Lua ZIP from the release) to
   `<REAPER resource path>/Scripts/reaper-faderport-driver/`, and load
   `4irmann_FaderPort - C++ emulator.lua` from there as an action. The script needs the `faderport/`
   subfolder next to it.

The Lua and C++ drivers lock each other out. Only one of them can run at a time.

## Structure

| File | Purpose |
|---|---|
| `src/plugin.cpp` | Entry point: API loading, `csurf_inst` registration, actions, ReaScript API for the emulator |
| `src/surface.h` | `IReaperControlSurface`: Run, GetTouchState, Extended callbacks |
| `src/driver.*` | Driver logic (port of `lua/faderport/driver.lua`) |
| `src/params.*` | Track volume/pan, FX parameters |
| `src/midi_io.*` | Device lookup by name, MIDI I/O with time stamps |
| `src/bindings.*`, `src/config.*`, `src/protocol.h` | DSP bindings, settings, FaderPort protocol |
| `src/version.rc.in` | Windows version resource (description and version in REAPER's extension list) |
| `tests/` | Unit tests against a mocked REAPER API |
