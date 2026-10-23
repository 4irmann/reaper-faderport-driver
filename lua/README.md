# Airmann's FaderPort Driver for REAPER

A ReaScript (Lua) driver for the **PreSonus FaderPort (classic, 2010)** DAW controller.
Port of the Renoise tool *Airmann's FaderPort Driver* (v1.1).

- Pure Lua: Windows, macOS, and Linux, nothing to compile
- Motor fader and pan encoder with ballistics and anti-suck handling, shift+pan for fine trim
- Native REAPER automation modes on the read, write/latch, and touch buttons
- DSP mode: fader and pan control FX parameters through a binding list (`faderport/bindings.lua`)
- Sticky mode: the binding stays on its track and FX while the selection changes
- Emulator window: a virtual FaderPort, usable with or without the hardware

Requires REAPER 6.x or later. Development and testing use REAPER 7.

## Installation

1. Copy this folder to your REAPER resource path under `Scripts/` (Options → Show REAPER resource path).
   For example: `%APPDATA%\REAPER\Scripts\Reaper-Faderport\`.
2. Actions → Show action list → *New action… → Load ReaScript…* and load these files:
   - `Airmann_FaderPort.lua`: starts and stops the driver (toggle action, toolbar friendly)
   - `Airmann_FaderPort - Toggle emulator.lua`
   - `Airmann_FaderPort - Reset.lua`
   - `Airmann_FaderPort - Show FX parameters.lua`
   - `Airmann_FaderPort - Toggle MIDI dump.lua`
   - `Airmann_FaderPort - C++ emulator.lua`: emulator window for the [C++ variant](../cpp/README.md)
     (only needed if you use it)
3. Set up MIDI under Preferences → Audio → MIDI Inputs / MIDI Outputs:
   - **Enable** the FaderPort input and output.
   - **Disable** REAPER's built-in FaderPort control surface (Preferences → Control/OSC/web), if one is
     configured for this device.
   - Recommended: enable the FaderPort input **for control messages only**. Otherwise armed tracks that
     use "All MIDI inputs" receive the FaderPort data. `MIDI_GetRecentInputEvent` still reports
     control-only devices; it sets flag `0x10000` on the device index, and the driver masks that flag.

### Auto start

Copy the command ID of `Airmann_FaderPort.lua` from the action list (right click → *Copy selected
action command ID*) and add this line to `Scripts/__startup.lua`:

```lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS<your id>"), 0)
```

## Button mapping

| Button | REAPER | Shift + button | Renoise driver had |
|---|---|---|---|
| Fader | Volume of the current track (DSP mode: FX parameter) | – | pre/post volume |
| Pan | Pan of the current track (DSP mode: FX parameter) | Fine trim of the fader parameter | same |
| Mute / Solo / Rec | Track mute, solo, rec arm | – | Rec = sample record dialog |
| ◀ Left / Right ▶ | Previous/next track (DSP mode: previous/next binding pair) | DSP mode: previous/next FX | same |
| Bank | DSP mode on/off | – | same |
| Output | Master track ↔ last track | – | pre/post mixer |
| Read / Touch | Track automation mode read / touch (pressing again switches to trim/read) | – | pattern automation |
| Write | Latch (default) | Write | same, `latch_is_default_write_mode` |
| Off | Light stays on while pressed, and the FaderPort sends no fader values. Use it to move the fader without writing. | – | same |
| Mix | Show/hide mixer | – | mixer frame |
| Proj | Show/hide FX chain of the track | Floating FX window | pattern editor |
| Trns | Sticky mode | Floating FX window | sticky / sample editor |
| Undo | Undo | Redo | same |
| Punch | Record mode auto-punch (time selection) | Move time selection left | loop block |
| User | Swap fader and pan | Move time selection right | same / loop block |
| Loop | Repeat on/off | Show binding in the status line | pattern loop |
| Rewind / Fwd | Previous/next marker | Project start/end | sequence step |
| Rewind + Fwd | Reset the fader parameter to its default (volume 0 dB) | – | same |
| Stop | Stop (if already stopped: all notes off) | – | stop / panic |
| Play / footswitch | Play/stop | Pause | restart / continue |
| Record | Record | – | edit mode |

In DSP mode the driver follows the most recently focused FX window. The driver shows its state in
REAPER's help/status line and in the emulator window.

## Configuration

- `faderport/config.lua`: defaults (device name pattern, resolution, timeouts, …). Values you toggle
  with the helper actions (emulator, MIDI dump) are stored in REAPER's ExtState and override these defaults.
- `faderport/bindings.lua`: DSP bindings by FX name, with parameter index or name prefix.
  The *Show FX parameters* action prints the parameter list of the focused FX. If an FX has no entry,
  its parameters are bound pairwise (1,2), (3,4), …

## Differences from the Renoise driver

- ReaScript can't open MIDI ports itself. The driver reads input by polling `MIDI_GetRecentInputEvent`
  (sequence-numbered, no events lost) and sends output with `StuffMIDIMessage`. Both directions
  need the device enabled in REAPER.
- REAPER has no observables for scripts. Each defer cycle (about 30 Hz) the driver compares REAPER's state
  with what it last sent, and sends only the changes.
- REAPER records the automation itself. The driver only sends gestures
  (`SetTrackUIVolume`, `TrackFX_SetParamNormalized`, `TrackFX_EndParamEdit`). This makes the
  "ugly undo workaround" unnecessary.
- Without the FaderPort's power supply there are no touch messages. The fader then counts as
  released after `fader_release_timeout`.

## Tests

```
lua tests/run_tests.lua
```

The tests use a mocked REAPER API (`tests/mock_reaper.lua`) and need a plain Lua 5.4 interpreter.

## License

Apache License 2.0, see `LICENSE.txt`.
