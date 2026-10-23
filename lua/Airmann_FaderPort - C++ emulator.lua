--[[
  Airmann's FaderPort Driver: emulator window for the C++ driver extension
  (reaper_airmann_faderport). Same window as the Lua emulator, connected to the
  C++ driver via its ReaScript API. Run again to close.
]]

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

local Bridge = require("cpp_bridge")
if not Bridge.available() then
  reaper.MB("The C++ FaderPort extension (reaper_airmann_faderport) is not installed.", "FaderPort", 0)
  return
end

local config = require("config")
config.load()
local Emulator = require("emulator")

if reaper.set_action_options then
  reaper.set_action_options(1) -- re-launch terminates the running instance
end
local _, _, section_id, command_id = reaper.get_action_context()

local bridge = Bridge.new()
local emulator = Emulator.new(bridge)

local function loop()
  bridge:run()
  if emulator:run() then
    reaper.defer(loop)
  end
end

reaper.atexit(function()
  emulator:close()
  reaper.SetToggleCommandState(section_id, command_id, 0)
  reaper.RefreshToolbar2(section_id, command_id)
end)

reaper.SetToggleCommandState(section_id, command_id, 1)
reaper.RefreshToolbar2(section_id, command_id)
emulator:open()
loop()
