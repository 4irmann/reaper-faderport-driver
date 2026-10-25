/*------------------------------------------------------------------------------------

  FaderPort DSP bindings

  Text format (one FX per line, '#' starts a comment):

    generic_fallback = true
    <fx name substring>: <fader>,<pan>; <fader>,<pan>; ...

  <fader>/<pan>: 1-based parameter index, parameter name prefix or 0 (nothing).
  Matching is case insensitive, the first matching line wins. See the Lua
  variant's bindings.lua for a detailed description.

  The built-in defaults are replaced by <REAPER resource path>/4irmann_faderport_bindings.txt
  if that file exists.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include <string>
#include <vector>

namespace faderport {

struct BindingEntry
{
  int index = 0; // 1-based parameter index, 0 = by name or nothing
  std::string name; // parameter name prefix (lower case), empty = by index
};

struct FxBinding
{
  std::string match; // lower case
  std::vector<std::pair<BindingEntry, BindingEntry>> pairs;
};

struct Bindings
{
  bool generic_fallback = true;
  std::vector<FxBinding> fx;

  static Bindings parse(const std::string &text);
  static const char *default_text();
  static Bindings load(); // user file or defaults

  const FxBinding *find(const std::string &fx_name) const;
};

std::string to_lower(std::string s);

} // namespace faderport
