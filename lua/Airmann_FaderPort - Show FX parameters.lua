--[[
  Airmann's FaderPort Driver: show FX parameters and DSP bindings (replaces the
  Renoise "Device Infos" dialog).

  Prints the focused FX (or the first FX of the selected track) with its 1-based
  parameter indices and the resolved binding pairs to the ReaScript console.
  Use the indices/names for your own entries in faderport/bindings.lua.
]]

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

local params = require("params")
local Driver = require("driver")

local track, fx
local retval, track_number, item_index, fx_index = reaper.GetFocusedFX2()
if (retval & 1) == 1 and item_index == -1 and fx_index < 0x1000000 then
  track = track_number == 0 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, track_number - 1)
  fx = fx_index
else
  track = reaper.GetSelectedTrack2(0, 0, true)
  if track and reaper.TrackFX_GetCount(track) > 0 then
    fx = 0
  end
end

if not (track and fx) then
  reaper.MB("Focus an FX window or select a track with FX.", "FaderPort", 0)
  return
end

local lines = {}
lines[#lines + 1] = ("%s  /  %s"):format(params.track_name(track), params.fx_name(track, fx))

-- binding pairs as the driver resolves them
local pairs_list = Driver.binding_pairs({ pairs_cache = {} }, track, fx, reaper.TrackFX_GetFXGUID(track, fx))
local binding_text = {}
for _, pair in ipairs(pairs_list) do
  binding_text[#binding_text + 1] = ("[%s,%s]"):format(
    pair[1] and tostring(pair[1] + 1) or "0", pair[2] and tostring(pair[2] + 1) or "0")
end
lines[#lines + 1] = "bindings (fader,pan): " .. (#binding_text > 0 and table.concat(binding_text, " ") or "none")
lines[#lines + 1] = ""

for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
  local _, name = reaper.TrackFX_GetParamName(track, fx, p, "")
  local _, value = reaper.TrackFX_GetFormattedParamValue(track, fx, p, "")
  lines[#lines + 1] = ("%3d ]  %-32s %s"):format(p + 1, name, value)
end

reaper.ClearConsole()
reaper.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
