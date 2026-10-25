-- 4irmann's FaderPort Driver: reset MIDI devices, FaderPort controller and light states
local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

local config = require("config")
if not config.is_running() then
  reaper.MB("The FaderPort driver is not running.\nStart the action '4irmann_FaderPort.lua' first.", "FaderPort", 0)
  return
end
config.post_command("reset")
