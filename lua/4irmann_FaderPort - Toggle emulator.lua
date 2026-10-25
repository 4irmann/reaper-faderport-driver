-- 4irmann's FaderPort Driver: show/hide the FaderPort emulator window
local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

local config = require("config")
if not config.is_running() then
  -- driver not running: open the emulator with the next driver start
  reaper.SetExtState(config.SECTION, "show_emulator", "true", true)
  reaper.MB("The FaderPort driver is not running.\n"
    .. "The emulator will be shown when '4irmann_FaderPort.lua' is started.", "FaderPort", 0)
  return
end
config.post_command("toggle_emulator")
