--[[-----------------------------------------------------------------------------------

  Bridge between the emulator window and the C++ driver extension

  Implements the part of the Lua driver interface the emulator uses
  (midi_callback, add_sink, remove_sink, invalidate, status, midi:is_open) on top
  of the ReaScript API exported by reaper_4irmann_faderport.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local Bridge = {}
Bridge.__index = Bridge

function Bridge.available()
  return reaper.FaderPort_4irmann_EmuSend ~= nil
end

function Bridge.new()
  local self = setmetatable({}, Bridge)
  self.sinks = {}
  self.status = ""
  self.midi = { is_open = function() return reaper.FaderPort_4irmann_IsHardwareConnected() end }
  return self
end

function Bridge:midi_callback(msg)
  reaper.FaderPort_4irmann_EmuSend(msg[1], msg[2], msg[3])
end

function Bridge:add_sink(fn)
  self.sinks[#self.sinks + 1] = fn
  reaper.FaderPort_4irmann_EmuAttach(true)
end

function Bridge:remove_sink(fn)
  for i, sink in ipairs(self.sinks) do
    if sink == fn then
      table.remove(self.sinks, i)
      break
    end
  end
  if #self.sinks == 0 then
    reaper.FaderPort_4irmann_EmuAttach(false)
  end
end

function Bridge:invalidate()
  reaper.FaderPort_4irmann_EmuAttach(true) -- attach resends lights and fader position
end

-- fetch messages the C++ driver sent and dispatch them to the sinks
function Bridge:run()
  local queue = reaper.FaderPort_4irmann_EmuReceive()
  for hex in queue:gmatch("%x%x%x%x%x%x") do
    local msg = { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
    for _, sink in ipairs(self.sinks) do
      sink(msg)
    end
  end
  self.status = reaper.FaderPort_4irmann_GetStatus()
end

return Bridge
