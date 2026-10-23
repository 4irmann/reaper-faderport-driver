#include "bindings.h"

#include "reaper_api.h"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace faderport {

namespace {

// IMPORTANT HINT (taken over from the Renoise driver)
// the order/focus of the bindings is laid on (final) mixing and not creative sound
// design. Means: level and stereo parameters like wet/gain/pan/width are usually
// the first binding pairs.
const char *DEFAULT_TEXT = R"(# Airmann's FaderPort Driver: DSP bindings
# <fx name substring>: <fader>,<pan>; <fader>,<pan>; ...
# entries: 1-based parameter index, parameter name prefix or 0 (nothing)

generic_fallback = true

# REAPER stock plugins
# TODO verify parameter names with "Show FX parameters" for your REAPER version
ReaEQ: 2,1; 5,4; 8,7; 11,10; 3,6; 9,12
ReaComp: Thresh,Ratio; Attack,Release; Wet,Dry; Knee,Pre-comp
ReaXcomp: Wet,Dry
ReaGate: Thresh,Hold; Attack,Release; Wet,Dry
ReaLimit: Threshold,Ceiling
ReaDelay: Wet,Dry
ReaVerbate: Wet,Dry; Room size,Dampening; Stereo width,Initial delay
ReaVerb: Wet,Dry
ReaFIR: Gain,0

# Voxengo (indices taken over from the Renoise driver)
Elephant: 3,4
Polysquasher: 5,1; 3,4; 2,2
)";

std::string trim(const std::string &s)
{
  size_t b = s.find_first_not_of(" \t\r\n");
  if (b == std::string::npos)
    return "";
  size_t e = s.find_last_not_of(" \t\r\n");
  return s.substr(b, e - b + 1);
}

std::vector<std::string> split(const std::string &s, char sep)
{
  std::vector<std::string> parts;
  std::string part;
  std::istringstream stream(s);
  while (std::getline(stream, part, sep))
    parts.push_back(trim(part));
  return parts;
}

BindingEntry parse_entry(const std::string &s)
{
  BindingEntry entry;
  if (!s.empty() && std::all_of(s.begin(), s.end(), [](unsigned char c) { return std::isdigit(c); }))
    entry.index = std::atoi(s.c_str());
  else
    entry.name = to_lower(s);
  return entry;
}

} // namespace

std::string to_lower(std::string s)
{
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return s;
}

const char *Bindings::default_text() { return DEFAULT_TEXT; }

Bindings Bindings::parse(const std::string &text)
{
  Bindings bindings;
  std::istringstream stream(text);
  std::string line;
  while (std::getline(stream, line))
  {
    line = trim(line.substr(0, line.find('#')));
    if (line.empty())
      continue;

    size_t eq = line.find('=');
    size_t colon = line.find(':');
    if (eq != std::string::npos && (colon == std::string::npos || eq < colon))
    {
      if (trim(line.substr(0, eq)) == "generic_fallback")
        bindings.generic_fallback = to_lower(trim(line.substr(eq + 1))) == "true";
      continue;
    }
    if (colon == std::string::npos)
      continue;

    FxBinding fx;
    fx.match = to_lower(trim(line.substr(0, colon)));
    for (const std::string &pair : split(line.substr(colon + 1), ';'))
    {
      if (pair.empty())
        continue;
      std::vector<std::string> entries = split(pair, ',');
      BindingEntry fader = parse_entry(entries[0]);
      BindingEntry pan = entries.size() > 1 ? parse_entry(entries[1]) : BindingEntry{};
      fx.pairs.emplace_back(fader, pan);
    }
    if (!fx.match.empty())
      bindings.fx.push_back(std::move(fx));
  }
  return bindings;
}

Bindings Bindings::load()
{
  std::string path = std::string(GetResourcePath()) + "/airmann_faderport_bindings.txt";
  std::ifstream file(std::filesystem::u8path(path));
  if (file)
  {
    std::stringstream text;
    text << file.rdbuf();
    return parse(text.str());
  }
  return parse(DEFAULT_TEXT);
}

const FxBinding *Bindings::find(const std::string &fx_name) const
{
  std::string name = to_lower(fx_name);
  for (const FxBinding &binding : fx)
  {
    if (name.find(binding.match) != std::string::npos)
      return &binding;
  }
  return nullptr;
}

} // namespace faderport
