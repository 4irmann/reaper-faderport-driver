-- Airmann's FaderPort Driver: dump received/sent FaderPort MIDI messages to the console
local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

local config = require("config")
if not config.is_running() then
  reaper.MB("The FaderPort driver is not running.\nStart the action 'Airmann_FaderPort.lua' first.", "FaderPort", 0)
  return
end
config.post_command("toggle_dump")
