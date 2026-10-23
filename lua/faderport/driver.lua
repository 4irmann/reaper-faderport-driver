--[[-----------------------------------------------------------------------------------

  FaderPort driver main (port of the Renoise driver FaderPort.lua / MidiHandler.lua)

  Differences to the Renoise driver:
    - REAPER has no observables for scripts. Instead run() is called on every
      defer cycle (~30 Hz) and compares the current REAPER state with the last
      state sent to the FaderPort (lights, motor fader, bindings).
    - Automation is written by REAPER itself according to the track automation
      mode (read/touch/write/latch). The FaderPort mode buttons switch that mode,
      parameter changes are sent as gestures (SetTrackUIVolume & co.).
    - Renoise pre/post mixer is replaced by track volume/pan, DSP devices by
      track FX. The "ugly undo workaround" isn't needed anymore.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local util = require("util")
local protocol = require("protocol")
local config = require("config")
local params = require("params")
local bindings = require("bindings")
local MidiIO = require("midi_io")

local BTN = protocol.BTN
local LIGHT = protocol.LIGHT

-- REAPER track automation modes
local AUTO_TRIM = 0
local AUTO_READ = 1
local AUTO_TOUCH = 2
local AUTO_WRITE = 3
local AUTO_LATCH = 4

-- REAPER actions
local CMD_TOGGLE_MIXER = 40078
local CMD_SCROLL_TRACKS_INTO_VIEW = 40913
local CMD_PREV_MARKER = 40172
local CMD_NEXT_MARKER = 40173
local CMD_PROJECT_START = 40042
local CMD_PROJECT_END = 40043
local CMD_RECMODE_AUTOPUNCH = 40076
local CMD_RECMODE_NORMAL = 40252
local CMD_ALL_NOTES_OFF = 40345

local Driver = {}
Driver.__index = Driver

function Driver.new()
  local self = setmetatable({}, Driver)
  self.midi = MidiIO.new(config.get("midi_in_name"), config.get("midi_out_name"))
  self.midi.dump = config.get("dump_midi")
  self.sinks = {} -- additional receivers of sent messages (emulator)
  self.next_device_retry = 0
  self.device_notice_shown = false
  self.status = ""
  self:init_members()
  return self
end

-- member variable initialization (song/project specific state)
function Driver:init_members()

  self.project = reaper.EnumProjects(-1)

  -- track 'n fx
  self.track = nil -- track bound to fader/pan
  self.prev_track = nil -- track before master was selected via output button
  self.fx_guid = nil -- FX bound in dsp mode
  self.fx_index = nil -- cached index of self.fx_guid
  self.fx_by_track = {} -- track guid -> last fx guid
  self.last_focus_sig = nil -- last focused FX window

  self.dsp_mode = config.get("start_in_dsp_mode") -- fader and pan are bound to FX parameters
  self.sticky_mode = false -- binding ignores track/FX selection changes
  self.fader_pan_swapped = false

  -- dsp bindings
  self.pairs_cache = {} -- fx guid -> list of {fader, pan} (0-based param index or nil)
  self.binding_index_by_fx = {} -- fx guid -> selected binding pair

  -- bound parameters
  self.bound_key = nil
  self.fader_param = nil
  self.pan_param = nil

  -- fader
  self.last_msb = 0
  self.fader_pos = nil -- last fader position received from a surface
  self.motor_pos = nil -- last fader position sent to the surfaces
  self.fader_res = 1024
  self.fader_touched = false -- reflects the hardware touch event (needs power supply)
  self.fader_editing = false
  self.last_fader_rx = nil

  -- pan
  self.pan_res = config.get("virtual_pan_resolution")
  self.virtual_pan_value = 0
  self.pan_left_count = 0
  self.pan_right_count = 0
  self.pan_steps = 0 -- steps received during the current defer cycle
  self.last_pan_time = nil
  self.last_pan_rx = nil
  self.pan_editing = false

  -- fader trim (shift + pan)
  self.trim_left_count = 0
  self.trim_right_count = 0
  self.trim_steps = 0
  self.last_trim_time = nil
  self.last_trim_rx = nil
  self.trim_editing = false

  -- button states
  self.shift_pressed = false
  self.rewind_pressed = false
  self.forward_pressed = false
  self.momentary = {} -- light nr -> true while the button is pressed

  self.light_cache = {}
end

---------------------------------------------------------------------- MIDI out

function Driver:add_sink(fn)
  self.sinks[#self.sinks + 1] = fn
end

function Driver:remove_sink(fn)
  for i, sink in ipairs(self.sinks) do
    if sink == fn then
      table.remove(self.sinks, i)
      return
    end
  end
end

function Driver:send(message)
  self.midi:send(message)
  for _, sink in ipairs(self.sinks) do
    sink(message)
  end
end

-- force resending lights and fader position, e.g. after (re)connect
function Driver:invalidate()
  self.light_cache = {}
  self.motor_pos = nil
end

function Driver:switch_off_lights()
  for nr = 0, 0x30 do
    self:send(protocol.light_message(nr, false))
  end
  self.light_cache = {}
end

------------------------------------------------------------ connect / reset

function Driver:connect_hardware()
  if self.midi:open() then
    util.trace("connected")
    self.device_notice_shown = false
    self.midi:send(protocol.native_mode_message())
    self:invalidate()
    return true
  end
  if not self.device_notice_shown then
    self.device_notice_shown = true
    util.log(("MIDI device '%s' / '%s' not found or not enabled in REAPER preferences. "
      .. "Retrying in the background, the emulator works anyway.")
      :format(config.get("midi_in_name"), config.get("midi_out_name")))
  end
  return false
end

function Driver:reset()
  self:end_all_edits()
  self:switch_off_lights()
  self.midi:close()
  self.device_notice_shown = false
  self:connect_hardware()
  self:invalidate()
end

function Driver:shutdown()
  self:end_all_edits()
  self:switch_off_lights()
  self.midi:close()
end

function Driver:set_dump_midi(dump)
  self.midi.dump = dump
end

------------------------------------------------------------------- main loop

function Driver:run()
  local now = util.now()

  if not self.midi:is_open() and now >= self.next_device_retry then
    self.next_device_retry = now + config.get("device_retry_interval")
    self:connect_hardware()
  end

  -- project tab changed
  local project = reaper.EnumProjects(-1)
  if project ~= self.project then
    self:end_all_edits()
    self:init_members()
  end

  self.midi:poll(function(msg) self:midi_callback(msg) end)

  self:update_track()
  if self.dsp_mode then
    self:update_fx()
  end
  self:update_binding()
  self:apply_encoders(now)
  self:check_release_timeouts(now)
  self:update_motor(now)
  self:sync_virtual_pan(now)
  self:update_lights()
end

----------------------------------------------------------- track / fx follow

function Driver:select_track(track)
  if not params.track_valid(track) then
    return
  end
  reaper.SetOnlyTrackSelected(track)
  if not params.is_master(track) then
    reaper.SetMixerScroll(track)
  end
  reaper.Main_OnCommand(CMD_SCROLL_TRACKS_INTO_VIEW, 0)
end

function Driver:update_track()
  if self.sticky_mode then
    if params.track_valid(self.track) then
      return
    end
    -- track is no more: switch off sticky mode
    self:toggle_sticky_mode()
  end

  local track = reaper.GetSelectedTrack2(0, 0, true)
  if track then
    self.track = track
  elseif not params.track_valid(self.track) then
    self.track = reaper.GetMasterTrack(0)
  end
end

function Driver:focused_track_fx()
  local retval, track_number, item_index, fx = reaper.GetFocusedFX2()
  local sig = ("%d:%d:%d:%d"):format(retval, track_number, item_index, fx)
  if sig == self.last_focus_sig then
    return nil
  end
  self.last_focus_sig = sig
  -- track FX only, no item/input/container FX
  if (retval & 1) == 0 or item_index ~= -1 or fx >= 0x1000000 then
    return nil
  end
  local track
  if track_number == 0 then
    track = reaper.GetMasterTrack(0)
  else
    track = reaper.GetTrack(0, track_number - 1)
  end
  return track, fx
end

function Driver:update_fx()
  local track = self.track

  if self.sticky_mode and params.find_fx(track, self.fx_guid, self.fx_index) then
    return
  end

  if config.get("follow_focused_fx") and not self.sticky_mode then
    local focused_track, fx = self:focused_track_fx()
    if focused_track then
      if focused_track ~= track then
        self:select_track(focused_track)
        self.track = focused_track
        track = focused_track
      end
      self.fx_guid = reaper.TrackFX_GetFXGUID(track, fx)
    end
  end

  local track_guid = reaper.GetTrackGUID(track)
  local index = params.find_fx(track, self.fx_guid, self.fx_index)
  if not index then
    if self.sticky_mode then
      -- FX is no more: switch off sticky mode
      self:toggle_sticky_mode()
    end
    -- last FX used on this track or first FX
    self.fx_guid = self.fx_by_track[track_guid]
    index = params.find_fx(track, self.fx_guid, nil)
    if not index and reaper.TrackFX_GetCount(track) > 0 then
      index = 0
      self.fx_guid = reaper.TrackFX_GetFXGUID(track, 0)
    end
  end
  if not index then
    self.fx_guid = nil
  end
  self.fx_index = index
  self.fx_by_track[track_guid] = self.fx_guid
end

function Driver:select_fx_delta(delta)
  local count = reaper.TrackFX_GetCount(self.track)
  if count == 0 then
    return
  end
  local index = util.wrap((self.fx_index or 0) + delta, 0, count - 1)
  self.fx_index = index
  self.fx_guid = reaper.TrackFX_GetFXGUID(self.track, index)
  self.fx_by_track[reaper.GetTrackGUID(self.track)] = self.fx_guid
  -- keep visible FX chain in sync
  if reaper.TrackFX_GetChainVisible(self.track) ~= -1 then
    reaper.TrackFX_Show(self.track, index, 1)
  end
end

---------------------------------------------------------------- dsp bindings

local function resolve_binding_entry(entry, names)
  if type(entry) == "number" then
    if entry >= 1 and entry <= #names then
      return entry - 1
    end
  elseif type(entry) == "string" then
    local prefix = entry:lower()
    for i, name in ipairs(names) do
      if name:lower():sub(1, #prefix) == prefix then
        return i - 1
      end
    end
  end
  return nil
end

-- list of binding pairs {fader, pan} (0-based parameter index or nil) for an FX
function Driver:binding_pairs(track, fx, fx_guid)
  local cached = self.pairs_cache[fx_guid]
  if cached then
    return cached
  end

  local names = {}
  for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
    local _, name = reaper.TrackFX_GetParamName(track, fx, p, "")
    names[#names + 1] = name
  end

  local pairs_list = {}
  local fx_name = params.fx_name(track, fx):lower()
  for _, binding in ipairs(bindings.fx) do
    if fx_name:find(binding.match:lower(), 1, true) then
      for _, pair in ipairs(binding.pairs) do
        local fader = resolve_binding_entry(pair[1], names)
        local pan = resolve_binding_entry(pair[2], names)
        if fader or pan then
          pairs_list[#pairs_list + 1] = { fader, pan }
        end
      end
      break
    end
  end

  if #pairs_list == 0 and bindings.generic_fallback then
    for p = 0, #names - 1, 2 do
      pairs_list[#pairs_list + 1] = { p, (p + 1 < #names) and p + 1 or nil }
    end
  end

  self.pairs_cache[fx_guid] = pairs_list
  return pairs_list
end

function Driver:current_pairs()
  if not (self.fx_guid and self.fx_index) then
    return nil
  end
  return self:binding_pairs(self.track, self.fx_index, self.fx_guid)
end

function Driver:select_binding_delta(delta)
  local pairs_list = self:current_pairs()
  if not pairs_list or #pairs_list < 2 then
    return
  end
  local index = self.binding_index_by_fx[self.fx_guid] or 1
  self.binding_index_by_fx[self.fx_guid] = util.wrap(index + delta, 1, #pairs_list)
end

-- compute parameters that shall be bound and rebind on changes
function Driver:update_binding()
  local fader, pan

  if not params.track_valid(self.track) then
    -- nothing
  elseif not self.dsp_mode then
    fader = params.track_volume(self.track)
    pan = params.track_pan(self.track)
  else
    local pairs_list = self:current_pairs()
    if pairs_list and #pairs_list > 0 then
      local index = util.clamp(self.binding_index_by_fx[self.fx_guid] or 1, 1, #pairs_list)
      local pair = pairs_list[index]
      if pair[1] then
        fader = params.fx_param(self.track, self.fx_guid, self.fx_index, pair[1])
      end
      if pair[2] then
        pan = params.fx_param(self.track, self.fx_guid, self.fx_index, pair[2])
      end
    end
  end

  if self.fader_pan_swapped then
    fader, pan = pan, fader
  end

  local key = (fader and fader:key() or "-") .. "|" .. (pan and pan:key() or "-")
  if key ~= self.bound_key then
    self.bound_key = key
    self:bind(fader, pan)
  end
end

function Driver:end_all_edits()
  if self.fader_param and (self.fader_editing or self.trim_editing) and self.fader_param:valid() then
    self.fader_param:end_edit()
  end
  if self.pan_param and self.pan_editing and self.pan_param:valid() then
    self.pan_param:end_edit()
  end
  self.fader_editing = false
  self.trim_editing = false
  self.pan_editing = false
end

function Driver:bind(fader, pan)
  util.trace("bind", self.bound_key)

  self:end_all_edits()

  self.fader_param = fader
  self.pan_param = pan

  -- fader
  self.motor_pos = nil -- force motor update
  self.fader_res = fader and fader:resolution(1024) or 1024
  self.last_trim_time = nil
  self.trim_left_count = 0
  self.trim_right_count = 0
  self.trim_steps = 0

  -- pan
  self.pan_res = pan and pan:resolution(config.get("virtual_pan_resolution"))
                 or config.get("virtual_pan_resolution")
  self.last_pan_time = nil
  self.last_pan_rx = nil
  self.pan_left_count = 0
  self.pan_right_count = 0
  self.pan_steps = 0
  if pan then
    self.virtual_pan_value = math.floor(pan:get_norm() * (self.pan_res - 1) + 0.5)
  end

  self:status_display_binding()
end

------------------------------------------------------------------ status line

function Driver:status_prefix()
  local message = params.track_name(self.track)
  if self.dsp_mode then
    if self.fx_index then
      message = message .. "  " .. params.fx_name(self.track, self.fx_index)
    else
      message = message .. "  (no FX)"
    end
  end
  if self.sticky_mode then
    message = message .. "  [sticky]"
  end
  return message
end

function Driver:show_status(message)
  self.status = message
  reaper.Help_Set("FaderPort: " .. message, false)
end

function Driver:status_display_binding()
  local message = self:status_prefix()
  if self.fader_param then
    message = message .. "   ^" .. self.fader_param:name()
  end
  if self.pan_param then
    message = message .. "   >" .. self.pan_param:name()
  end
  self:show_status(message)
end

function Driver:status_display_value(param, symbol)
  if not param then
    self:show_status(self:status_prefix() .. "   n/a")
    return
  end
  self:show_status(self:status_prefix() .. "   " .. symbol .. param:name()
    .. " -> " .. param:value_string())
end

------------------------------------------------------------------------ fader

-- handler for received FaderPort fader values
function Driver:on_receive_fader_value(intval)
  self.fader_pos = intval
  self.last_fader_rx = util.now()

  local param = self.fader_param
  if not (param and param:valid()) then
    return
  end

  local n = intval / protocol.FADER_MAX

  -- round to exact center value (snap to center)
  if param.bipolar and math.abs(n - 0.5) < 1 / 1024 then
    n = 0.5
  end

  -- quantize discrete parameters
  if self.fader_res < 1024 then
    n = math.floor(n * (self.fader_res - 1) + 0.5) / (self.fader_res - 1)
  end

  param:set_norm(n)
  self.fader_editing = true
  self:status_display_value(param, "^")
end

function Driver:on_fader_touch(touched)
  self.fader_touched = touched
  if not touched then
    if self.fader_editing and self.fader_param and self.fader_param:valid() then
      self.fader_param:end_edit()
    end
    self.fader_editing = false
    self.last_fader_rx = nil
    self.motor_pos = nil -- sync fader with REAPER
  end
end

-- reset value of the parameter bound to fader to its default value
function Driver:reset_fader_param_to_default()
  local param = self.fader_param
  if not (param and param:valid()) then
    return
  end
  local default = param:default_norm()
  if not default then
    self:show_status(self:status_prefix() .. "   reset to default n/a for FX parameters")
    return
  end
  param:set_norm(default)
  param:end_edit()
  self:status_display_value(param, "^")
end

-- motor fader follows the bound parameter (incl. automation playback)
function Driver:update_motor(now)
  local param = self.fader_param
  if not (param and param:valid()) then
    return
  end
  if self.fader_touched then
    return
  end
  if self.last_fader_rx and now - self.last_fader_rx < config.get("fader_release_timeout") then
    return
  end
  local pos = math.floor(param:get_norm() * protocol.FADER_MAX + 0.5)
  if self.motor_pos == nil or math.abs(pos - self.motor_pos) > 1 then
    self.motor_pos = pos
    local msb, lsb = protocol.fader_messages(pos)
    self:send(msb)
    self:send(lsb)
  end
end

-- fake release detection for fader (no touch messages without power supply),
-- pan and trim (encoders never send touch messages)
function Driver:check_release_timeouts(now)
  if self.fader_editing and not self.fader_touched and self.last_fader_rx
     and now - self.last_fader_rx > config.get("fader_release_timeout") then
    self.fader_editing = false
    if self.fader_param and self.fader_param:valid() then
      self.fader_param:end_edit()
    end
  end

  local pan_timeout = config.get("pan_release_timeout")
  if self.pan_editing and self.last_pan_rx and now - self.last_pan_rx > pan_timeout then
    self.pan_editing = false
    if self.pan_param and self.pan_param:valid() then
      self.pan_param:end_edit()
    end
  end

  if self.trim_editing and self.last_trim_rx and now - self.last_trim_rx > pan_timeout then
    self.trim_editing = false
    if self.fader_param and self.fader_param:valid() then
      self.fader_param:end_edit()
    end
  end
end

-------------------------------------------------------------------- pan/trim

-- encoder speed based on the interval between two effective steps
-- (Renoise ballistics: speed = 1 + 0.2 s / interval, min speed = 1, max speed = 20).
-- HINT: MIDI input is polled once per defer cycle, so all ticks of a cycle carry
-- the same time stamp. The interval is derived from the steps per cycle instead.
local function compute_speed(steps, last_time, now)
  if not last_time then
    return 1
  end
  local interval = math.max(now - last_time, 0.001) / math.abs(steps)
  return util.clamp(1 + math.floor(0.20 / interval + 0.5), 1, 20)
end

-- evaluate encoder tick with anti suck handling.
-- returns direction (0 if nothing changed) and the updated counters
local function encoder_delta(value, left_count, right_count, min_turns)
  if value < 63 then -- turn right
    if value ~= protocol.PAN_RIGHT then
      return 0, left_count, right_count
    end
    right_count = right_count + 1
    if right_count < min_turns then
      return 0, left_count, right_count
    end
    return 1, 0, 0
  else -- turn left
    if value ~= protocol.PAN_LEFT then
      return 0, left_count, right_count
    end
    left_count = left_count + 1
    if left_count < min_turns then
      return 0, left_count, right_count
    end
    return -1, 0, 0
  end
end

-- handler for received pan encoder ticks, steps are applied in apply_encoders()
function Driver:on_receive_pan_value(value)
  if not (self.pan_param and self.pan_param:valid()) then
    return
  end
  self.last_pan_rx = util.now()

  local direction
  direction, self.pan_left_count, self.pan_right_count = encoder_delta(
    value, self.pan_left_count, self.pan_right_count, config.get("anti_suck_min_turns"))
  self.pan_steps = self.pan_steps + direction
end

-- shift + pan: fine adjustment of the parameter bound to fader
function Driver:on_receive_trim_value(value)
  if not (self.fader_param and self.fader_param:valid()) then
    return
  end
  self.last_trim_rx = util.now()

  local direction
  direction, self.trim_left_count, self.trim_right_count = encoder_delta(
    value, self.trim_left_count, self.trim_right_count, config.get("anti_suck_min_turns"))
  self.trim_steps = self.trim_steps + direction
end

-- apply encoder steps collected during the last defer cycle
function Driver:apply_encoders(now)
  local param = self.pan_param
  if self.pan_steps ~= 0 and param and param:valid() then
    -- if resolution is low, don't use speed feature at all
    local speed = 1
    if self.pan_res > 20 then
      speed = compute_speed(self.pan_steps, self.last_pan_time, now)
    end
    self.last_pan_time = now

    local pan_max_value = self.pan_res - 1
    self.virtual_pan_value = util.clamp(self.virtual_pan_value + self.pan_steps * speed, 0, pan_max_value)

    local n = self.virtual_pan_value / pan_max_value

    -- round to exact center value (snap to center)
    if param.bipolar and math.abs(n - 0.5) < 1 / (pan_max_value + 1) then
      n = 0.5
    end

    param:set_norm(n)
    self.pan_editing = true
    self:status_display_value(param, ">")
  end
  self.pan_steps = 0

  param = self.fader_param
  if self.trim_steps ~= 0 and param and param:valid() then
    local speed = compute_speed(self.trim_steps, self.last_trim_time, now)
    self.last_trim_time = now

    local n = util.clamp(param:get_norm() + 0.0005 * self.trim_steps * speed, 0, 1)
    param:set_norm(n)
    self.trim_editing = true
    self:status_display_value(param, "^")
  end
  self.trim_steps = 0
end

-- keep virtual pan value in sync with REAPER while the encoder isn't moved
function Driver:sync_virtual_pan(now)
  local param = self.pan_param
  if self.pan_editing or not (param and param:valid()) then
    return
  end
  if self.last_pan_rx and now - self.last_pan_rx < config.get("pan_release_timeout") then
    return
  end
  self.virtual_pan_value = math.floor(param:get_norm() * (self.pan_res - 1) + 0.5)
end

---------------------------------------------------------------- automation

function Driver:toggle_automation_mode(mode)
  local track = self.track
  if not params.track_valid(track) then
    return
  end
  local current = reaper.GetTrackAutomationMode(track)
  local is_write = function(m) return m == AUTO_WRITE or m == AUTO_LATCH end

  -- if the mode was already set, toggle to trim/read (off)
  if current == mode or (is_write(current) and is_write(mode)) then
    reaper.SetTrackAutomationMode(track, AUTO_TRIM)
  else
    reaper.SetTrackAutomationMode(track, mode)
  end
  self.motor_pos = nil -- force update in order to be in sync with REAPER
end

------------------------------------------------------------------ transport

local function is_playing()
  return (reaper.GetPlayState() & 5) ~= 0 -- playing or recording
end

function Driver:toggle_play()
  if is_playing() then
    reaper.CSurf_OnStop()
  else
    reaper.CSurf_OnPlay()
  end
end

-- shift time selection by its length (replacement for Renoise loop block move)
function Driver:move_time_selection(direction)
  local start_pos, end_pos = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local length = end_pos - start_pos
  if length <= 0 then
    return
  end
  local new_start = math.max(0, start_pos + direction * length)
  reaper.GetSet_LoopTimeRange(true, false, new_start, new_start + length, false)
end

function Driver:toggle_auto_punch()
  if reaper.GetToggleCommandState(CMD_RECMODE_AUTOPUNCH) == 1 then
    reaper.Main_OnCommand(CMD_RECMODE_NORMAL, 0)
  else
    reaper.Main_OnCommand(CMD_RECMODE_AUTOPUNCH, 0)
  end
end

--------------------------------------------------------------- window views

function Driver:toggle_fx_chain()
  local track = self.track
  if not params.track_valid(track) then
    return
  end
  if reaper.TrackFX_GetChainVisible(track) ~= -1 then
    reaper.TrackFX_Show(track, 0, 0)
  elseif reaper.TrackFX_GetCount(track) > 0 then
    reaper.TrackFX_Show(track, self.fx_index or 0, 1)
  else
    reaper.Main_OnCommand(40291, 0) -- Track: View FX chain for current/last touched track
  end
end

function Driver:toggle_fx_float()
  local track = self.track
  if not params.track_valid(track) or reaper.TrackFX_GetCount(track) == 0 then
    return
  end
  local fx = self.fx_index or 0
  if reaper.TrackFX_GetFloatingWindow(track, fx) then
    reaper.TrackFX_Show(track, fx, 2)
  else
    reaper.TrackFX_Show(track, fx, 3)
  end
end

-- switch sticky mode on/off
function Driver:toggle_sticky_mode()
  self.sticky_mode = not self.sticky_mode
  -- if switched off, the binding follows the selection again with the next run()
  self:status_display_binding()
end

function Driver:toggle_master_track()
  if params.track_valid(self.track) and params.is_master(self.track) then
    if params.track_valid(self.prev_track) then
      self:select_track(self.prev_track)
    end
  else
    self.prev_track = self.track
    self:select_track(reaper.GetMasterTrack(0))
  end
end

function Driver:navigate_track(delta)
  local count = reaper.CountTracks(0)
  if count == 0 then
    return
  end
  local index -- 0-based
  if not params.track_valid(self.track) or params.is_master(self.track) then
    index = delta > 0 and 0 or count - 1
  else
    local number = reaper.GetMediaTrackInfo_Value(self.track, "IP_TRACKNUMBER")
    index = util.wrap(math.floor(number) - 1 + delta, 0, count - 1)
  end
  self:select_track(reaper.GetTrack(0, index))
end

------------------------------------------------------------------- lights

function Driver:update_lights()
  local desired = {}
  local track = self.track
  local track_valid = params.track_valid(track)

  if track_valid then
    desired[LIGHT.MUTE] = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    desired[LIGHT.SOLO] = reaper.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
    desired[LIGHT.REC] = reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
    desired[LIGHT.OUTPUT] = params.is_master(track)
    desired[LIGHT.PROJ] = reaper.TrackFX_GetChainVisible(track) ~= -1

    local mode = reaper.GetTrackAutomationMode(track)
    desired[LIGHT.READ] = mode == AUTO_READ
    desired[LIGHT.TOUCH] = mode == AUTO_TOUCH
    desired[LIGHT.WRITE] = mode == AUTO_WRITE or mode == AUTO_LATCH
  end

  desired[LIGHT.BANK] = self.dsp_mode
  desired[LIGHT.MIX] = reaper.GetToggleCommandState(CMD_TOGGLE_MIXER) == 1
  desired[LIGHT.TRNS] = self.sticky_mode
  desired[LIGHT.SHIFT] = self.shift_pressed
  desired[LIGHT.PUNCH] = reaper.GetToggleCommandState(CMD_RECMODE_AUTOPUNCH) == 1
  desired[LIGHT.USER] = self.fader_pan_swapped
  desired[LIGHT.LOOP] = reaper.GetSetRepeat(-1) == 1

  local play_state = reaper.GetPlayState()
  desired[LIGHT.PLAY] = (play_state & 1) ~= 0
  desired[LIGHT.STOP] = play_state == 0
  desired[LIGHT.RECORD] = (play_state & 4) ~= 0

  -- HINT: the OFF light is a momentary light only. Whenever it is on,
  -- the FaderPort doesn't send fader values (see handling of the off button)
  for nr = 0, protocol.LIGHT_COUNT - 1 do
    local on = (desired[nr] or self.momentary[nr]) and true or false
    if self.light_cache[nr] ~= on then
      self.light_cache[nr] = on
      self:send(protocol.light_message(nr, on))
    end
  end
end

---------------------------------------------------------------- MIDI input

-- MIDI message handler, receives messages from FaderPort or emulator
function Driver:midi_callback(msg)
  local status, data1, data2 = msg[1], msg[2], msg[3]

  -- fader value
  if status == 0xb0 then
    if data1 == 0x00 then
      self.last_msb = data2 -- store msb, wait for lsb
    elseif data1 == 0x20 then
      self:on_receive_fader_value(protocol.decode_fader(self.last_msb, data2))
    end

  -- pan and trim value
  elseif status == 0xe0 and data1 == 0x00 then
    if self.shift_pressed then
      self:on_receive_trim_value(data2) -- trim parameter bound to fader
    else
      self:on_receive_pan_value(data2)
    end

  -- buttons
  elseif status == 0xa0 then
    self:on_button(data1, data2)
  end
end

local function momentary_light(self, light, pressed)
  self.momentary[light] = pressed or nil
end

function Driver:on_button(button, value)
  local pressed = value == 1
  local track = self.track
  local track_valid = params.track_valid(track)

  -- fader touch state
  if button == BTN.FADER_TOUCH then
    self:on_fader_touch(pressed)

  -- transport shift
  elseif button == BTN.SHIFT then
    self.shift_pressed = pressed

  -- transport play or footswitch
  elseif (button == BTN.PLAY and pressed) or
         (button == BTN.FOOTSWITCH and value == config.get("footswitch_pressed_signal")) then
    if self.shift_pressed and button == BTN.PLAY then
      reaper.CSurf_OnPause()
    else
      self:toggle_play()
    end

  -- transport stop
  elseif button == BTN.STOP and pressed then
    if reaper.GetPlayState() ~= 0 then
      reaper.CSurf_OnStop()
    else
      reaper.Main_OnCommand(CMD_ALL_NOTES_OFF, 0) -- panic
    end

  -- transport record
  elseif button == BTN.RECORD and pressed then
    reaper.CSurf_OnRecord()

  -- transport loop
  elseif button == BTN.LOOP then
    if pressed and self.shift_pressed then
      self:status_display_binding()
    elseif pressed then
      reaper.GetSetRepeat(2) -- toggle
    end
    momentary_light(self, LIGHT.LOOP, pressed and self.shift_pressed)

  -- transport punch
  elseif button == BTN.PUNCH and pressed then
    if self.shift_pressed then
      self:move_time_selection(-1)
    else
      self:toggle_auto_punch()
    end

  -- transport user: swap fader and pan
  elseif button == BTN.USER then
    if pressed and self.shift_pressed then
      self:move_time_selection(1)
    elseif pressed then
      self.fader_pan_swapped = not self.fader_pan_swapped
    end
    momentary_light(self, LIGHT.USER, pressed and self.shift_pressed)

  -- transport rewind
  elseif button == BTN.REWIND then
    momentary_light(self, LIGHT.REWIND, pressed)
    if pressed then
      self.rewind_pressed = true
      if self.forward_pressed then
        self:reset_fader_param_to_default()
      end
    else
      if not self.forward_pressed then
        if self.shift_pressed then
          reaper.Main_OnCommand(CMD_PROJECT_START, 0)
        else
          reaper.Main_OnCommand(CMD_PREV_MARKER, 0)
        end
        self.rewind_pressed = false
      else
        self.forward_pressed = false
      end
    end

  -- transport fast forward
  elseif button == BTN.FORWARD then
    momentary_light(self, LIGHT.FORWARD, pressed)
    if pressed then
      self.forward_pressed = true
      if self.rewind_pressed then
        self:reset_fader_param_to_default()
      end
    else
      if not self.rewind_pressed then
        if self.shift_pressed then
          reaper.Main_OnCommand(CMD_PROJECT_END, 0)
        else
          reaper.Main_OnCommand(CMD_NEXT_MARKER, 0)
        end
        self.forward_pressed = false
      else
        self.rewind_pressed = false
      end
    end

  -- channel mute
  elseif button == BTN.MUTE and pressed and track_valid then
    reaper.SetTrackUIMute(track, -1, 0)

  -- channel solo
  elseif button == BTN.SOLO and pressed and track_valid then
    if not params.is_master(track) then
      reaper.SetTrackUISolo(track, -1, 0)
    end

  -- channel rec arm
  elseif button == BTN.REC and pressed and track_valid then
    if not params.is_master(track) then
      reaper.SetTrackUIRecArm(track, -1, 0)
    end

  -- fader mode read
  elseif button == BTN.READ and pressed then
    self:toggle_automation_mode(AUTO_READ)

  -- fader mode touch
  elseif button == BTN.TOUCH and pressed then
    self:toggle_automation_mode(AUTO_TOUCH)

  -- fader mode write / latch
  elseif button == BTN.WRITE and pressed then
    local latch = self.shift_pressed
    if config.get("latch_is_default_write_mode") then
      latch = not latch
    end
    self:toggle_automation_mode(latch and AUTO_LATCH or AUTO_WRITE)

  -- fader mode: fader off
  -- HINT: as long as the button is pressed the light is switched on.
  -- Whenever the light is switched on, no fader values are sent
  -- from FaderPort while fader is being moved !
  -- This may be helpful for doing fader readjustments in write modes
  -- without actually writing values.
  elseif button == BTN.OFF then
    momentary_light(self, LIGHT.OFF, pressed)

  -- channel select left / right
  elseif button == BTN.LEFT or button == BTN.RIGHT then
    local delta = button == BTN.LEFT and -1 or 1
    momentary_light(self, button == BTN.LEFT and LIGHT.LEFT or LIGHT.RIGHT, pressed)
    if pressed then
      if not self.dsp_mode then
        self:navigate_track(delta)
      elseif self.shift_pressed then
        self:select_fx_delta(delta) -- select FX
      else
        self:select_binding_delta(delta) -- select dsp binding
      end
    end

  -- channel select bank: toggle dsp mode
  elseif button == BTN.BANK and pressed then
    self.dsp_mode = not self.dsp_mode
    if self.dsp_mode then
      self.last_focus_sig = nil -- take over currently focused FX
    end

  -- channel select output: toggle master track
  elseif button == BTN.OUTPUT and pressed then
    self:toggle_master_track()

  -- window view mix
  elseif button == BTN.MIX and pressed then
    reaper.Main_OnCommand(CMD_TOGGLE_MIXER, 0)

  -- window view proj: FX chain (shift: floating FX window)
  elseif button == BTN.PROJ and pressed then
    if self.shift_pressed then
      self:toggle_fx_float()
    else
      self:toggle_fx_chain()
    end

  -- window view trns: sticky mode (shift: floating FX window)
  elseif button == BTN.TRNS and pressed then
    if config.get("sticky_mode_support") and not self.shift_pressed then
      self:toggle_sticky_mode()
    else
      self:toggle_fx_float()
    end

  -- window view undo / redo
  elseif button == BTN.UNDO then
    momentary_light(self, LIGHT.UNDO, pressed)
    if pressed then
      if self.shift_pressed then
        reaper.Undo_DoRedo2(0)
      else
        reaper.Undo_DoUndo2(0)
      end
    end
  end
end

return Driver
