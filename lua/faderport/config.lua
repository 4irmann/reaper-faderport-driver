--[[-----------------------------------------------------------------------------------

  FaderPort preferences

  Defaults are defined here. Values toggled via actions (emulator, midi dump ...)
  are persisted in REAPER's ExtState section "4irmannFaderPort" and override
  the defaults below.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local config = {}

config.SECTION = "4irmannFaderPort"

local defaults = {

  -- substring (case insensitive) of the MIDI device names as listed in
  -- REAPER Preferences > Audio > MIDI Inputs / MIDI Outputs
  midi_in_name = "FaderPort",
  midi_out_name = "FaderPort",

  dump_midi = false, -- dump received/sent MIDI messages to the console

  show_emulator = false, -- open the emulator window on start

  start_in_dsp_mode = false, -- true: fader/pan are bound to FX parameters on start

  latch_is_default_write_mode = true, -- true: "write" button = latch, shift+write = write
                                      -- false: "write" button = write, shift+write = latch

  sticky_mode_support = true, -- sticky mode available (trns button)

  virtual_pan_resolution = 128, -- resolution of virtual pan control
  anti_suck_min_turns = 3, -- minimum number of encoder ticks for a virtual pan value change

  footswitch_pressed_signal = 1, -- 0 or 1, swaps footswitch pressed/released signal

  fader_release_timeout = 0.3, -- s: fader treated as released without touch messages
                               -- (FaderPort without additional power supply)
  pan_release_timeout = 0.5, -- s: pan/trim encoder treated as released

  device_retry_interval = 2.0, -- s: retry interval for looking up the MIDI devices

  follow_focused_fx = true, -- dsp mode follows the last focused FX window
}

local values = {}

local function parse(default, str)
  if type(default) == "boolean" then
    return str == "true"
  elseif type(default) == "number" then
    return tonumber(str) or default
  end
  return str
end

function config.load()
  for key, default in pairs(defaults) do
    values[key] = default
    if reaper.HasExtState(config.SECTION, key) then
      values[key] = parse(default, reaper.GetExtState(config.SECTION, key))
    end
  end
end

function config.get(key)
  local value = values[key]
  assert(value ~= nil, "unknown preference: " .. tostring(key))
  return value
end

function config.set(key, value)
  assert(defaults[key] ~= nil, "unknown preference: " .. tostring(key))
  values[key] = value
  reaper.SetExtState(config.SECTION, key, tostring(value), true)
end

function config.toggle(key)
  config.set(key, not config.get(key))
  return config.get(key)
end

-- one-shot commands from the helper action scripts to the running driver
function config.post_command(cmd)
  reaper.SetExtState(config.SECTION, "command", cmd, false)
end

function config.fetch_command()
  local cmd = reaper.GetExtState(config.SECTION, "command")
  if cmd ~= "" then
    reaper.DeleteExtState(config.SECTION, "command", false)
    return cmd
  end
  return nil
end

function config.set_running(running)
  if running then
    reaper.SetExtState(config.SECTION, "running", "1", false)
  else
    reaper.DeleteExtState(config.SECTION, "running", false)
  end
end

function config.is_running()
  return reaper.GetExtState(config.SECTION, "running") == "1"
end

return config
