--[[-----------------------------------------------------------------------------------

  FaderPort MIDI I/O for ReaScript

  ReaScript can't open MIDI ports itself. Instead:
    - input : the FaderPort input must be enabled in REAPER's MIDI preferences.
              Recent events are polled via MIDI_GetRecentInputEvent and filtered
              by device index. Sequence numbers guarantee that nothing is
              processed twice or skipped between two defer cycles.
    - output: the FaderPort output must be enabled in REAPER's MIDI preferences.
              Messages are sent via StuffMIDIMessage(16 + device index, ...)

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local util = require("util")

local MidiIO = {}
MidiIO.__index = MidiIO

function MidiIO.new(in_name, out_name)
  local self = setmetatable({}, MidiIO)
  self.in_name = in_name
  self.out_name = out_name
  self.in_dev = nil
  self.out_dev = nil
  self.last_seq = nil
  self.dump = false
  return self
end

local function find_device(count, get_name, pattern)
  pattern = pattern:lower()
  for i = 0, count - 1 do
    local ok, name = get_name(i, "")
    if ok and name and name:lower():find(pattern, 1, true) then
      return i, name
    end
  end
  return nil
end

-- look up MIDI devices, returns true if input and output were found
function MidiIO:open()
  local in_name, out_name
  self.in_dev, in_name = find_device(reaper.GetNumMIDIInputs(), reaper.GetMIDIInputName, self.in_name)
  self.out_dev, out_name = find_device(reaper.GetNumMIDIOutputs(), reaper.GetMIDIOutputName, self.out_name)
  self.last_seq = nil
  if self.in_dev then
    util.trace("midi in", self.in_dev, in_name)
  end
  if self.out_dev then
    util.trace("midi out", self.out_dev, out_name)
  end
  return self:is_open()
end

function MidiIO:close()
  self.in_dev = nil
  self.out_dev = nil
  self.last_seq = nil
end

function MidiIO:is_open()
  return self.in_dev ~= nil and self.out_dev ~= nil
end

function MidiIO:send(message)
  if not self.out_dev then
    return
  end
  if self.dump then
    util.log(("send %02X %02X %02X"):format(message[1], message[2], message[3]))
  end
  reaper.StuffMIDIMessage(16 + self.out_dev, message[1], message[2], message[3])
end

-- poll new input events of the FaderPort, oldest first
function MidiIO:poll(callback)
  if not self.in_dev then
    return
  end

  local newest = reaper.MIDI_GetRecentInputEvent(0)

  -- first poll after open: ignore events received before
  if self.last_seq == nil then
    self.last_seq = newest
    return
  end

  if newest == 0 or newest == self.last_seq then
    return
  end

  local events = {}
  local idx = 0
  while true do
    local seq, buf, _, dev = reaper.MIDI_GetRecentInputEvent(idx)
    if seq == 0 or seq <= self.last_seq then
      break
    end
    -- low 16 bits: device index, 0x10000: device enabled for control only
    if (dev & 0xffff) == self.in_dev and #buf >= 3 then
      events[#events + 1] = { buf:byte(1), buf:byte(2), buf:byte(3) }
    elseif self.dump then
      util.log(("ignored MIDI from device %d (%d bytes)"):format(dev, #buf))
    end
    idx = idx + 1
  end
  self.last_seq = newest

  for i = #events, 1, -1 do
    local msg = events[i]
    if self.dump then
      util.log(("received %02X %02X %02X"):format(msg[1], msg[2], msg[3]))
    end
    callback(msg)
  end
end

return MidiIO
