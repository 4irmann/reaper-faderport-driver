#include "config.h"

#include "reaper_api.h"

#include <cstdlib>

namespace faderport {

namespace {

const char *ext(const char *key)
{
  if (!HasExtState(Config::SECTION, key))
    return nullptr;
  return GetExtState(Config::SECTION, key);
}

void load_value(const char *key, std::string &value)
{
  if (const char *s = ext(key))
    value = s;
}

void load_value(const char *key, bool &value)
{
  if (const char *s = ext(key))
    value = std::string(s) == "true";
}

void load_value(const char *key, int &value)
{
  if (const char *s = ext(key))
  {
    char *end = nullptr;
    long v = std::strtol(s, &end, 10);
    if (end != s)
      value = static_cast<int>(v);
  }
}

void load_value(const char *key, double &value)
{
  if (const char *s = ext(key))
  {
    char *end = nullptr;
    double v = std::strtod(s, &end);
    if (end != s)
      value = v;
  }
}

} // namespace

void Config::load()
{
  load_value("midi_in_name", midi_in_name);
  load_value("midi_out_name", midi_out_name);
  load_value("dump_midi", dump_midi);
  load_value("start_in_dsp_mode", start_in_dsp_mode);
  load_value("latch_is_default_write_mode", latch_is_default_write_mode);
  load_value("sticky_mode_support", sticky_mode_support);
  load_value("follow_focused_fx", follow_focused_fx);
  load_value("virtual_pan_resolution", virtual_pan_resolution);
  load_value("anti_suck_min_turns", anti_suck_min_turns);
  load_value("footswitch_pressed_signal", footswitch_pressed_signal);
  load_value("fader_release_timeout", fader_release_timeout);
  load_value("pan_release_timeout", pan_release_timeout);
  load_value("device_retry_interval", device_retry_interval);

  if (virtual_pan_resolution < 2)
    virtual_pan_resolution = 2;
  if (anti_suck_min_turns < 1)
    anti_suck_min_turns = 1;
}

void Config::save_bool(const char *key, bool value)
{
  SetExtState(SECTION, key, value ? "true" : "false", true);
}

} // namespace faderport
