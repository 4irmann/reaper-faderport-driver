--[[-----------------------------------------------------------------------------------

  FaderPort parameter abstraction

  Replaces the Renoise DeviceParameter. Everything that can be bound to fader or
  pan control implements:

    valid()            parameter (still) exists
    key()              identity, used to detect binding changes
    name()             display name
    value_string()     formatted current value
    get_norm()         current value 0..1 including automation playback
    set_norm(n)        set value 0..1 (part of a gesture, writes automation
                       according to the track's automation mode)
    end_edit()         end of gesture (touch/latch automation release)
    default_norm()     default value 0..1 or nil
    resolution(def)    number of discrete steps, def if continuous
    bipolar            snap to center

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local util = require("util")

local params = {}

local IGNORE_GROUP_FLAGS = 0 -- respect track grouping and selection ganging

function params.track_valid(track)
  return track ~= nil and reaper.ValidatePtr2(0, track, "MediaTrack*")
end

function params.is_master(track)
  return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") == -1
end

function params.track_name(track)
  if not params.track_valid(track) then
    return "n/a"
  end
  if params.is_master(track) then
    return "MASTER"
  end
  local _, name = reaper.GetTrackName(track)
  return name
end

function params.fx_name(track, fx)
  local ok, name = reaper.TrackFX_GetNamedConfigParm(track, fx, "fx_name")
  if not ok or name == "" then
    ok, name = reaper.TrackFX_GetFXName(track, fx, "")
  end
  return name or ""
end

-- find FX index by GUID, cached index is checked first
function params.find_fx(track, fx_guid, cached_index)
  if not params.track_valid(track) or not fx_guid then
    return nil
  end
  if cached_index and reaper.TrackFX_GetFXGUID(track, cached_index) == fx_guid then
    return cached_index
  end
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    if reaper.TrackFX_GetFXGUID(track, fx) == fx_guid then
      return fx
    end
  end
  return nil
end

------------------------------------------------------------------- track volume

local TrackVolume = {}
TrackVolume.__index = TrackVolume

function params.track_volume(track)
  return setmetatable({ track = track, bipolar = false }, TrackVolume)
end

local function vol_to_norm(vol)
  local db = vol > 0 and 20 * math.log(vol, 10) or -150
  return util.clamp(reaper.DB2SLIDER(db) / 1000, 0, 1)
end

local function norm_to_vol(n)
  if n <= 0 then
    return 0
  end
  return 10 ^ (reaper.SLIDER2DB(n * 1000) / 20)
end

function TrackVolume:valid() return params.track_valid(self.track) end
function TrackVolume:key() return "vol:" .. reaper.GetTrackGUID(self.track) end
function TrackVolume:name() return "Volume" end

function TrackVolume:value_string()
  local _, vol = reaper.GetTrackUIVolPan(self.track)
  return reaper.mkvolstr("", vol)
end

function TrackVolume:get_norm()
  local _, vol = reaper.GetTrackUIVolPan(self.track)
  return vol_to_norm(vol)
end

function TrackVolume:set_norm(n)
  reaper.SetTrackUIVolume(self.track, norm_to_vol(n), false, false, IGNORE_GROUP_FLAGS)
end

function TrackVolume:end_edit()
  local _, vol = reaper.GetTrackUIVolPan(self.track)
  reaper.SetTrackUIVolume(self.track, vol, false, true, IGNORE_GROUP_FLAGS)
end

function TrackVolume:default_norm() return vol_to_norm(1.0) end
function TrackVolume:resolution(def) return def end

---------------------------------------------------------------------- track pan

local TrackPan = {}
TrackPan.__index = TrackPan

function params.track_pan(track)
  return setmetatable({ track = track, bipolar = true }, TrackPan)
end

function TrackPan:valid() return params.track_valid(self.track) end
function TrackPan:key() return "pan:" .. reaper.GetTrackGUID(self.track) end
function TrackPan:name() return "Pan" end

function TrackPan:value_string()
  local _, _, pan = reaper.GetTrackUIVolPan(self.track)
  return reaper.mkpanstr("", pan)
end

function TrackPan:get_norm()
  local _, _, pan = reaper.GetTrackUIVolPan(self.track)
  return (pan + 1) / 2
end

function TrackPan:set_norm(n)
  reaper.SetTrackUIPan(self.track, n * 2 - 1, false, false, IGNORE_GROUP_FLAGS)
end

function TrackPan:end_edit()
  local _, _, pan = reaper.GetTrackUIVolPan(self.track)
  reaper.SetTrackUIPan(self.track, pan, false, true, IGNORE_GROUP_FLAGS)
end

function TrackPan:default_norm() return 0.5 end
function TrackPan:resolution(def) return def end

---------------------------------------------------------------------- FX param

local FXParam = {}
FXParam.__index = FXParam

-- param: 0-based parameter index
function params.fx_param(track, fx_guid, fx_index, param)
  return setmetatable({ track = track, fx_guid = fx_guid, fx = fx_index,
                        param = param, bipolar = false }, FXParam)
end

function FXParam:resolve()
  self.fx = params.find_fx(self.track, self.fx_guid, self.fx)
  return self.fx
end

function FXParam:valid()
  local fx = self:resolve()
  return fx ~= nil and self.param < reaper.TrackFX_GetNumParams(self.track, fx)
end

function FXParam:key() return "fx:" .. self.fx_guid .. ":" .. self.param end

function FXParam:name()
  local fx = self:resolve()
  if not fx then return "n/a" end
  local _, name = reaper.TrackFX_GetParamName(self.track, fx, self.param, "")
  return name
end

function FXParam:value_string()
  local fx = self:resolve()
  if not fx then return "" end
  local _, str = reaper.TrackFX_GetFormattedParamValue(self.track, fx, self.param, "")
  return str
end

function FXParam:get_norm()
  local fx = self:resolve()
  if not fx then return 0 end
  return util.clamp(reaper.TrackFX_GetParamNormalized(self.track, fx, self.param), 0, 1)
end

function FXParam:set_norm(n)
  local fx = self:resolve()
  if not fx then return end
  reaper.TrackFX_SetParamNormalized(self.track, fx, self.param, n)
end

function FXParam:end_edit()
  local fx = self:resolve()
  if not fx then return end
  reaper.TrackFX_EndParamEdit(self.track, fx, self.param)
end

function FXParam:default_norm() return nil end -- not exposed by the REAPER API

function FXParam:resolution(def)
  local fx = self:resolve()
  if not fx then return def end
  local ok, step, _, _, is_toggle = reaper.TrackFX_GetParameterStepSizes(self.track, fx, self.param)
  if ok and is_toggle then
    return 2
  end
  if ok and step and step > 0 then
    local _, min_value, max_value = reaper.TrackFX_GetParam(self.track, fx, self.param)
    local steps = math.floor((max_value - min_value) / step + 0.5) + 1
    if steps >= 2 and steps < def then
      return steps
    end
  end
  return def
end

return params
