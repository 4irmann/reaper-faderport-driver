--[[
  Minimal mock of the REAPER API used by the FaderPort driver.
  Only behaviour relevant for the driver is emulated.
]]

local M = {}

local state

local function new_track(name, number)
  return { name = name, number = number, guid = "{T" .. number .. "}", vol = 1, pan = 0,
           mute = 0, solo = 0, arm = 0, automode = 0, fx = {}, chain_visible = -1,
           vol_calls = {}, pan_calls = {} }
end

function M.reset()
  state = {
    now = 0, ext = {}, tracks = {}, selected = {}, sent = {}, input = {}, seq = 0,
    play_state = 0, repeat_state = 0, toggles = {}, commands = {}, console = {},
    focused = { 0, 0, -1, 0 }, help = "", undo = 0, redo = 0, loop = { 0, 0 },
    project = "project1", end_edits = {},
    midi_inputs = { [0] = "USB Keyboard", [1] = "FaderPort" },
    midi_outputs = { [0] = "Microsoft GS Wavetable", [1] = "FaderPort" },
  }
  state.master = new_track("MASTER", -1)
  return state
end

function M.state() return state end

function M.add_track(name)
  local track = new_track(name, #state.tracks + 1)
  state.tracks[#state.tracks + 1] = track
  return track
end

function M.remove_track(track)
  for i, t in ipairs(state.tracks) do
    if t == track then
      table.remove(state.tracks, i)
      break
    end
  end
  for i, t in ipairs(state.tracks) do
    t.number = i
  end
  state.selected = {}
end

function M.add_fx(track, name, param_names)
  local fx = { name = name, guid = "{FX" .. name .. #track.fx .. track.number .. "}", params = {} }
  for i, pname in ipairs(param_names) do
    fx.params[i] = { name = pname, value = 0.5 }
  end
  track.fx[#track.fx + 1] = fx
  return fx
end

function M.select(track)
  state.selected = { track }
end

-- simulate a MIDI message received from an input device
function M.push_midi(dev, b1, b2, b3)
  state.seq = state.seq + 1
  state.input[#state.input + 1] = { seq = state.seq, buf = string.char(b1, b2, b3), dev = dev }
end

function M.advance(seconds)
  state.now = state.now + seconds
end

function M.sent_clear()
  state.sent = {}
end

-- messages sent to output device dev
function M.sent_to(dev)
  local result = {}
  for _, s in ipairs(state.sent) do
    if s[1] == 16 + dev then
      result[#result + 1] = { s[2], s[3], s[4] }
    end
  end
  return result
end

local function valid_track(track)
  if track == state.master then return true end
  for _, t in ipairs(state.tracks) do
    if t == track then return true end
  end
  return false
end

function M.install()
  M.reset()
  local r = {}

  r.time_precise = function() return state.now end
  r.ShowConsoleMsg = function(msg) state.console[#state.console + 1] = msg end
  r.ClearConsole = function() state.console = {} end
  r.MB = function() return 1 end
  r.Help_Set = function(str) state.help = str end

  -- ext state
  r.HasExtState = function(s, k) return state.ext[s .. "/" .. k] ~= nil end
  r.GetExtState = function(s, k) return state.ext[s .. "/" .. k] or "" end
  r.SetExtState = function(s, k, v) state.ext[s .. "/" .. k] = v end
  r.DeleteExtState = function(s, k) state.ext[s .. "/" .. k] = nil end

  -- project / tracks
  r.EnumProjects = function() return state.project, "" end
  r.CountTracks = function() return #state.tracks end
  r.GetTrack = function(_, i) return state.tracks[i + 1] end
  r.GetMasterTrack = function() return state.master end
  r.ValidatePtr2 = function(_, ptr) return valid_track(ptr) end
  r.GetTrackGUID = function(t) return t.guid end
  r.GetTrackName = function(t) return true, t.name end
  r.GetSelectedTrack2 = function(_, i, want_master)
    local t = state.selected[i + 1]
    if t == state.master and not want_master then return nil end
    return t
  end
  r.SetOnlyTrackSelected = function(t) state.selected = { t } end
  r.SetMixerScroll = function(t) state.mixer_scroll = t end
  r.GetMediaTrackInfo_Value = function(t, key)
    if key == "IP_TRACKNUMBER" then return t.number
    elseif key == "B_MUTE" then return t.mute
    elseif key == "I_SOLO" then return t.solo
    elseif key == "I_RECARM" then return t.arm
    end
    error("unknown track info " .. key)
  end
  r.GetTrackUIVolPan = function(t) return true, t.vol, t.pan end
  r.SetTrackUIVolume = function(t, vol, _, done)
    t.vol = vol
    t.vol_calls[#t.vol_calls + 1] = { vol = vol, done = done }
    return vol
  end
  r.SetTrackUIPan = function(t, pan, _, done)
    t.pan = pan
    t.pan_calls[#t.pan_calls + 1] = { pan = pan, done = done }
    return pan
  end
  local function toggle_or_set(old, v) if v < 0 then return old == 0 and 1 or 0 end return v end
  r.SetTrackUIMute = function(t, v) t.mute = toggle_or_set(t.mute, v) end
  r.SetTrackUISolo = function(t, v) t.solo = toggle_or_set(t.solo, v) end
  r.SetTrackUIRecArm = function(t, v) t.arm = toggle_or_set(t.arm, v) end
  r.GetTrackAutomationMode = function(t) return t.automode end
  r.SetTrackAutomationMode = function(t, m) t.automode = m end

  -- fx
  r.TrackFX_GetCount = function(t) return #t.fx end
  r.TrackFX_GetFXGUID = function(t, i) local fx = t.fx[i + 1] return fx and fx.guid end
  r.TrackFX_GetFXName = function(t, i) return true, "VST: " .. t.fx[i + 1].name end
  r.TrackFX_GetNamedConfigParm = function(t, i, key)
    if key == "fx_name" then return true, "VST: " .. t.fx[i + 1].name end
    return false, ""
  end
  r.TrackFX_GetNumParams = function(t, i) return #t.fx[i + 1].params end
  r.TrackFX_GetParamName = function(t, i, p) return true, t.fx[i + 1].params[p + 1].name end
  r.TrackFX_GetParamNormalized = function(t, i, p) return t.fx[i + 1].params[p + 1].value end
  r.TrackFX_SetParamNormalized = function(t, i, p, v) t.fx[i + 1].params[p + 1].value = v return true end
  r.TrackFX_EndParamEdit = function(t, i, p) state.end_edits[#state.end_edits + 1] = { t, i, p } return true end
  r.TrackFX_GetFormattedParamValue = function(t, i, p)
    return true, ("%.2f"):format(t.fx[i + 1].params[p + 1].value)
  end
  r.TrackFX_GetParameterStepSizes = function() return false end
  r.TrackFX_GetParam = function(t, i, p) return t.fx[i + 1].params[p + 1].value, 0, 1 end
  r.TrackFX_GetChainVisible = function(t) return t.chain_visible end
  r.TrackFX_Show = function(t, i, flag)
    if flag == 1 then t.chain_visible = i elseif flag == 0 then t.chain_visible = -1 end
  end
  r.TrackFX_GetFloatingWindow = function() return nil end
  r.GetFocusedFX2 = function() return table.unpack(state.focused) end

  -- transport
  r.GetPlayState = function() return state.play_state end
  r.CSurf_OnPlay = function() state.play_state = 1 end
  r.CSurf_OnStop = function() state.play_state = 0 end
  r.CSurf_OnPause = function() state.play_state = 2 end
  r.CSurf_OnRecord = function() state.play_state = state.play_state == 5 and 0 or 5 end
  r.GetSetRepeat = function(v)
    if v == 2 then state.repeat_state = 1 - state.repeat_state
    elseif v >= 0 then state.repeat_state = v end
    return state.repeat_state
  end
  r.GetSet_LoopTimeRange = function(is_set, _, s, e)
    if is_set then state.loop = { s, e } end
    return state.loop[1], state.loop[2]
  end
  r.GetToggleCommandState = function(cmd) return state.toggles[cmd] or 0 end
  r.Main_OnCommand = function(cmd)
    state.commands[#state.commands + 1] = cmd
    if cmd == 40078 then state.toggles[cmd] = 1 - (state.toggles[cmd] or 0)
    elseif cmd == 40076 then state.toggles[40076] = 1
    elseif cmd == 40252 then state.toggles[40076] = 0 end
  end
  r.Undo_DoUndo2 = function() state.undo = state.undo + 1 end
  r.Undo_DoRedo2 = function() state.redo = state.redo + 1 end

  -- volume helpers (simplified, but invertible)
  r.SLIDER2DB = function(y) return y / 1000 * 162 - 150 end
  r.DB2SLIDER = function(db) return (db + 150) / 162 * 1000 end
  r.mkvolstr = function(_, vol) return ("%.2fdB"):format(vol > 0 and 20 * math.log(vol, 10) or -150) end
  r.mkpanstr = function(_, pan) return ("%.0f%%"):format(pan * 100) end

  -- midi
  r.GetNumMIDIInputs = function() return 2 end
  r.GetNumMIDIOutputs = function() return 2 end
  r.GetMIDIInputName = function(i) local n = state.midi_inputs[i] return n ~= nil, n or "" end
  r.GetMIDIOutputName = function(i) local n = state.midi_outputs[i] return n ~= nil, n or "" end
  r.StuffMIDIMessage = function(mode, a, b, c) state.sent[#state.sent + 1] = { mode, a, b, c } end
  r.MIDI_GetRecentInputEvent = function(idx)
    local ev = state.input[#state.input - idx]
    if not ev then return 0, "", 0, 0, 0, 0 end
    return ev.seq, ev.buf, 0, ev.dev, 0, 0
  end

  _G.reaper = r
  return r
end

return M
