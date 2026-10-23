--[[------------------------------------------------------------------------------------

  Airmann's FaderPort Driver for REAPER

  A REAPER ReaScript for the integration of the PreSonus FaderPort (classic) DAW
  controller. Port of the Renoise tool "Airmann's FaderPort Driver".

  Run this action to start the driver, run it again to stop it (toggle state).
  For auto start, add it to your __startup.lua or the SWS startup action.

  Copyright 2010-2026 Matthias Ehrmann,

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific
  language governing permissions and limitations under the License.

-------------------------------------------------------------------------------------]]--

local script_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])")
package.path = script_path .. "faderport/?.lua;" .. package.path

-- required REAPER API (REAPER 6.x and later)
for _, fn in ipairs({ "MIDI_GetRecentInputEvent", "SetTrackUIVolume", "TrackFX_EndParamEdit",
                      "GetFocusedFX2", "time_precise" }) do
  if not reaper[fn] then
    reaper.MB("This REAPER version is too old (missing reaper." .. fn .. ").\n"
      .. "Please update REAPER.", "FaderPort", 0)
    return
  end
end

local config = require("config")
config.load()

-- never run two drivers on the same device
if reaper.GetExtState(config.SECTION, "running_cpp") == "1" then
  reaper.MB("The C++ FaderPort driver (reaper_airmann_faderport) is active.\n"
    .. "Disable it with the action 'Airmann FaderPort (C++): Enable/disable driver' first.", "FaderPort", 0)
  return
end

local util = require("util")
local Driver = require("driver")
local Emulator = require("emulator")

-- toggle state of this action
local _, _, section_id, command_id = reaper.get_action_context()
if reaper.set_action_options then
  reaper.set_action_options(1) -- re-launch terminates the running instance
end

local driver = Driver.new()
local emulator = Emulator.new(driver)

local function set_toggle_state(state)
  reaper.SetToggleCommandState(section_id, command_id, state)
  reaper.RefreshToolbar2(section_id, command_id)
end

local function toggle_emulator()
  if emulator:is_open() then
    emulator:close()
  else
    emulator:open()
  end
  config.set("show_emulator", emulator:is_open())
end

-- commands of the helper action scripts
local function handle_command(cmd)
  util.trace("command", cmd)
  if cmd == "reset" then
    driver:reset()
  elseif cmd == "toggle_emulator" then
    toggle_emulator()
  elseif cmd == "toggle_dump" then
    local dump = config.toggle("dump_midi")
    driver:set_dump_midi(dump)
    util.log("MIDI dump " .. (dump and "on" or "off"))
  end
end

local function loop()
  local cmd = config.fetch_command()
  if cmd then
    handle_command(cmd)
  end

  driver:run()

  if emulator:is_open() and not emulator:run() then
    config.set("show_emulator", false) -- closed by user
  end

  reaper.defer(loop)
end

local function shutdown()
  emulator:close()
  driver:shutdown()
  config.set_running(false)
  set_toggle_state(0)
  reaper.Help_Set("", false)
end

--[[ initialize ]] -------------------------------------------------------------

config.fetch_command() -- discard stale commands
config.set_running(true)
set_toggle_state(1)
reaper.atexit(shutdown)

if config.get("show_emulator") then
  emulator:open()
end

loop()
