/*------------------------------------------------------------------------------------

  FaderPort preferences

  Same ExtState section and keys as the Lua driver, so both variants share the
  settings. Values persisted in ExtState override the defaults below.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include <string>

namespace faderport {

struct Config
{
  static constexpr const char *SECTION = "4irmannFaderPort";

  // substring (case insensitive) of the MIDI device names
  std::string midi_in_name = "FaderPort";
  std::string midi_out_name = "FaderPort";

  bool dump_midi = false; // dump received/sent MIDI messages to the console
  bool start_in_dsp_mode = false; // fader/pan are bound to FX parameters on start
  bool latch_is_default_write_mode = true; // "write" button = latch, shift+write = write
  bool sticky_mode_support = true; // sticky mode available (trns button)
  bool follow_focused_fx = true; // dsp mode follows the last focused FX window

  int virtual_pan_resolution = 128; // resolution of virtual pan control
  int anti_suck_min_turns = 3; // minimum number of encoder ticks for a virtual pan value change
  int footswitch_pressed_signal = 1; // 0 or 1, swaps footswitch pressed/released signal

  double fader_release_timeout = 0.3; // s: fader released without touch messages (no power supply)
  double pan_release_timeout = 0.5; // s: pan/trim encoder treated as released
  double device_retry_interval = 2.0; // s: retry interval for looking up the MIDI devices

  void load();
  void save_bool(const char *key, bool value);
};

} // namespace faderport
