--[[-----------------------------------------------------------------------------------

  FaderPort Emulator (gfx window)

  A virtual FaderPort. It receives exactly the MIDI messages the driver sends to
  the hardware (lights, motor fader) and sends FaderPort MIDI messages to the
  driver. Works with or without connected hardware.

  Mouse: click buttons, drag fader, drag pan knob horizontally or use the mouse
  wheel over fader/pan knob. "hold" emulates holding shift/rwd/fwd/off/mute.

  Copyright 2014-2026 Matthias Ehrmann, Apache License 2.0

-------------------------------------------------------------------------------------]]

local protocol = require("protocol")
local config = require("config")

local BTN = protocol.BTN
local LIGHT = protocol.LIGHT

local RED = { 1, 0.15, 0.15 }
local GREEN = { 0.2, 1, 0.2 }
local YELLOW = { 1, 0.9, 0.1 }
local BLUE = { 0.3, 0.5, 1 }

local BW, BH, GAP = 50, 24, 6 -- button width/height/gap
local X0, Y0 = 84, 16 -- button grid origin
local ROW = BH + 10

local FADER_X, FADER_Y, FADER_W, FADER_H = 22, 74, 36, 300
local CAP_H = 18
local PAN_X, PAN_Y, PAN_R = 40, 38, 18

local WIDTH, HEIGHT = 380, 470

-- label, button, light, light color, hold capable
local LAYOUT = {
  { { "mute", BTN.MUTE, LIGHT.MUTE, RED, true }, { "solo", BTN.SOLO, LIGHT.SOLO, YELLOW },
    { "rec", BTN.REC, LIGHT.REC, RED } },
  { { "< left", BTN.LEFT, LIGHT.LEFT, RED }, { "bank", BTN.BANK, LIGHT.BANK, RED },
    { "right >", BTN.RIGHT, LIGHT.RIGHT, RED }, { "output", BTN.OUTPUT, LIGHT.OUTPUT, YELLOW } },
  { { "read", BTN.READ, LIGHT.READ, GREEN }, { "write", BTN.WRITE, LIGHT.WRITE, RED },
    { "touch", BTN.TOUCH, LIGHT.TOUCH, RED }, { "off", BTN.OFF, LIGHT.OFF, RED, true } },
  { { "mix", BTN.MIX, LIGHT.MIX, RED }, { "proj", BTN.PROJ, LIGHT.PROJ, RED },
    { "trns", BTN.TRNS, LIGHT.TRNS, RED }, { "undo", BTN.UNDO, LIGHT.UNDO, RED } },
  { { "shift", BTN.SHIFT, LIGHT.SHIFT, RED, true }, { "punch", BTN.PUNCH, LIGHT.PUNCH, RED },
    { "user", BTN.USER, LIGHT.USER, RED }, { "loop", BTN.LOOP, LIGHT.LOOP, BLUE } },
  { { "<< rwd", BTN.REWIND, LIGHT.REWIND, YELLOW, true }, { "fwd >>", BTN.FORWARD, LIGHT.FORWARD, YELLOW, true },
    { "stop", BTN.STOP, LIGHT.STOP, YELLOW }, { "play", BTN.PLAY, LIGHT.PLAY, GREEN },
    { "record", BTN.RECORD, LIGHT.RECORD, RED } },
}

local Emulator = {}
Emulator.__index = Emulator

function Emulator.new(driver)
  local self = setmetatable({}, Emulator)
  self.driver = driver
  self.visible = false
  self.lights = {}
  self.fader_value = 0
  self.last_msb = 0
  self.hold = false
  self.held = {} -- button -> true (hold emulation)
  self.buttons = {}
  self.mouse_down = false
  self.drag = nil -- "fader", "pan" or button entry
  self.pan_drag_x = 0
  self.sink = function(msg) self:on_midi_receive(msg) end

  local y = Y0
  for _, row in ipairs(LAYOUT) do
    local x = X0
    for _, def in ipairs(row) do
      self.buttons[#self.buttons + 1] = { label = def[1], btn = def[2], light = def[3],
        color = def[4], hold_capable = def[5] or false, x = x, y = y }
      x = x + BW + GAP
    end
    y = y + ROW
  end
  self.hold_box = { x = X0, y = y + 2, w = 14, h = 14 }
  self.status_y = y + 30
  return self
end

function Emulator:is_open()
  return self.visible
end

function Emulator:open()
  if self.visible then
    return
  end
  local dock = tonumber(reaper.GetExtState(config.SECTION, "emu_dock")) or 0
  local x = tonumber(reaper.GetExtState(config.SECTION, "emu_x")) or 100
  local y = tonumber(reaper.GetExtState(config.SECTION, "emu_y")) or 100
  gfx.init("FaderPort Emulator", WIDTH, HEIGHT, dock, x, y)
  gfx.setfont(1, "Arial", 14)
  self.visible = true
  self.lights = {}
  self.held = {}
  self.driver:add_sink(self.sink)
  self.driver:invalidate() -- resend lights and fader position
end

function Emulator:close()
  if not self.visible then
    return
  end
  local dock, x, y = gfx.dock(-1, 0, 0, 0, 0)
  reaper.SetExtState(config.SECTION, "emu_dock", tostring(dock), true)
  reaper.SetExtState(config.SECTION, "emu_x", tostring(x), true)
  reaper.SetExtState(config.SECTION, "emu_y", tostring(y), true)
  gfx.quit()
  self.visible = false
  self.driver:remove_sink(self.sink)
end

------------------------------------------------------------- receive handlers

-- receives messages the driver sends to the FaderPort
function Emulator:on_midi_receive(msg)
  if msg[1] == 0xb0 then
    if msg[2] == 0x00 then
      self.last_msb = msg[3]
    elseif msg[2] == 0x20 and self.drag ~= "fader" then
      self.fader_value = protocol.decode_motor(self.last_msb, msg[3])
    end
  elseif msg[1] == 0xa0 then
    self.lights[msg[2]] = msg[3] == 1
  end
end

---------------------------------------------------------------- send handlers

function Emulator:send(msg)
  self.driver:midi_callback(msg)
end

function Emulator:send_button(button, state)
  self:send({ 0xa0, button, state })
end

function Emulator:send_fader(intval)
  -- off light has a special behaviour on the hardware: if it is on,
  -- no fader values are sent. We emulate this, here.
  if self.lights[LIGHT.OFF] then
    return
  end
  local msb, lsb = protocol.encode_fader(intval)
  self:send(msb)
  self:send(lsb)
end

function Emulator:send_pan_ticks(direction, count)
  local value = direction > 0 and protocol.PAN_RIGHT or protocol.PAN_LEFT
  for _ = 1, count do
    self:send({ 0xe0, 0x00, value })
  end
end

------------------------------------------------------------------------ input

local function inside(mx, my, x, y, w, h)
  return mx >= x and mx < x + w and my >= y and my < y + h
end

function Emulator:fader_from_mouse(my)
  local v = (FADER_Y + FADER_H - CAP_H / 2 - my) / (FADER_H - CAP_H)
  return math.floor(math.max(0, math.min(1, v)) * protocol.FADER_MAX + 0.5)
end

function Emulator:on_mouse_down(mx, my)
  if inside(mx, my, FADER_X - 8, FADER_Y, FADER_W + 16, FADER_H) then
    self.drag = "fader"
    self:send_button(BTN.FADER_TOUCH, 1)
    self.fader_value = self:fader_from_mouse(my)
    self:send_fader(self.fader_value)
    return
  end

  if (mx - PAN_X) ^ 2 + (my - PAN_Y) ^ 2 <= (PAN_R + 4) ^ 2 then
    self.drag = "pan"
    self.pan_drag_x = mx
    return
  end

  local box = self.hold_box
  if inside(mx, my, box.x, box.y, 200, box.h) then
    self.hold = not self.hold
    -- release all held buttons
    for button in pairs(self.held) do
      self:send_button(button, 0)
    end
    self.held = {}
    return
  end

  for _, b in ipairs(self.buttons) do
    if inside(mx, my, b.x, b.y, BW, BH) then
      if self.hold and b.hold_capable then
        if self.held[b.btn] then
          self.held[b.btn] = nil
          self:send_button(b.btn, 0)
        else
          self.held[b.btn] = true
          self:send_button(b.btn, 1)
        end
      else
        self.drag = b
        self:send_button(b.btn, 1)
      end
      return
    end
  end
end

function Emulator:on_mouse_move(mx, my)
  if self.drag == "fader" then
    local value = self:fader_from_mouse(my)
    if value ~= self.fader_value then
      self.fader_value = value
      self:send_fader(value)
    end
  elseif self.drag == "pan" then
    local dx = mx - self.pan_drag_x
    local ticks = math.floor(math.abs(dx) / 2)
    if ticks > 0 then
      self:send_pan_ticks(dx, ticks)
      self.pan_drag_x = self.pan_drag_x + (dx > 0 and 2 or -2) * ticks
    end
  end
end

function Emulator:on_mouse_up()
  if self.drag == "fader" then
    self:send_button(BTN.FADER_TOUCH, 0)
  elseif type(self.drag) == "table" then
    self:send_button(self.drag.btn, 0)
  end
  self.drag = nil
end

function Emulator:on_mouse_wheel(mx, my, notches)
  if inside(mx, my, FADER_X - 8, FADER_Y, FADER_W + 16, FADER_H) then
    self.fader_value = math.max(0, math.min(protocol.FADER_MAX, self.fader_value + notches * 8))
    self:send_button(BTN.FADER_TOUCH, 1)
    self:send_fader(self.fader_value)
    self:send_button(BTN.FADER_TOUCH, 0)
  elseif (mx - PAN_X) ^ 2 + (my - PAN_Y) ^ 2 <= (PAN_R + 8) ^ 2 then
    -- one notch must overcome the anti suck handling
    self:send_pan_ticks(notches, math.abs(notches) * config.get("anti_suck_min_turns"))
  end
end

------------------------------------------------------------------------- draw

local function set_color(c, dim)
  dim = dim or 1
  gfx.set(c[1] * dim, c[2] * dim, c[3] * dim, 1)
end

function Emulator:draw()
  gfx.set(0.16, 0.16, 0.17, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- pan knob
  gfx.set(0.3, 0.3, 0.32, 1)
  gfx.circle(PAN_X, PAN_Y, PAN_R, 1, 1)
  gfx.set(0.85, 0.85, 0.85, 1)
  gfx.circle(PAN_X, PAN_Y, PAN_R, 0, 1)
  local angle = (self.drag == "pan") and (self.pan_drag_x % 36) / 36 * 2 * math.pi or -math.pi / 2
  gfx.line(PAN_X, PAN_Y, PAN_X + math.cos(angle) * PAN_R, PAN_Y + math.sin(angle) * PAN_R, 1)

  -- fader
  local cx = FADER_X + FADER_W / 2
  gfx.set(0.05, 0.05, 0.05, 1)
  gfx.rect(cx - 3, FADER_Y, 6, FADER_H, 1)
  local cap_y = FADER_Y + (FADER_H - CAP_H) * (1 - self.fader_value / protocol.FADER_MAX)
  gfx.set(0.75, 0.75, 0.78, 1)
  gfx.rect(FADER_X, cap_y, FADER_W, CAP_H, 1)
  gfx.set(0.1, 0.1, 0.1, 1)
  gfx.line(FADER_X, cap_y + CAP_H / 2, FADER_X + FADER_W - 1, cap_y + CAP_H / 2)
  gfx.set(0.7, 0.7, 0.7, 1)
  gfx.x, gfx.y = FADER_X - 6, FADER_Y + FADER_H + 6
  gfx.drawstr(tostring(self.fader_value))

  -- buttons
  for _, b in ipairs(self.buttons) do
    local lit = self.lights[b.light]
    if lit then
      set_color(b.color)
    elseif self.held[b.btn] or self.drag == b then
      gfx.set(0.45, 0.45, 0.47, 1)
    else
      gfx.set(0.28, 0.28, 0.3, 1)
    end
    gfx.rect(b.x, b.y, BW, BH, 1)
    gfx.set(lit and 0 or 0.85, lit and 0 or 0.85, lit and 0 or 0.85, 1)
    gfx.x, gfx.y = b.x, b.y
    gfx.drawstr(b.label, 1 | 4, b.x + BW, b.y + BH)
  end

  -- hold checkbox
  local box = self.hold_box
  gfx.set(0.85, 0.85, 0.85, 1)
  gfx.rect(box.x, box.y, box.w, box.h, 0)
  if self.hold then
    gfx.rect(box.x + 3, box.y + 3, box.w - 6, box.h - 6, 1)
  end
  gfx.x, gfx.y = box.x + box.w + 8, box.y
  gfx.drawstr("hold (shift, rwd, fwd, off, mute)")

  -- status
  gfx.set(0.7, 0.7, 0.7, 1)
  local y = self.status_y
  local hw = self.driver.midi:is_open() and "hardware connected" or "hardware not connected"
  gfx.x, gfx.y = X0, y
  gfx.drawstr(hw)
  y = y + 22
  gfx.set(0.9, 0.9, 0.6, 1)
  for part in (self.driver.status .. "   "):gmatch("(.-)%s%s%s+") do
    if part ~= "" then
      gfx.x, gfx.y = X0, y
      gfx.drawstr(part)
      y = y + 17
    end
  end
end

-- returns false if the window was closed by the user
function Emulator:run()
  if not self.visible then
    return false
  end

  local char = gfx.getchar()
  if char < 0 or char == 27 then
    self:close()
    return false
  end

  local mx, my = gfx.mouse_x, gfx.mouse_y
  local down = (gfx.mouse_cap & 1) == 1
  if down and not self.mouse_down then
    self:on_mouse_down(mx, my)
  elseif down then
    self:on_mouse_move(mx, my)
  elseif self.mouse_down then
    self:on_mouse_up()
  end
  self.mouse_down = down

  if gfx.mouse_wheel ~= 0 then
    local notches = gfx.mouse_wheel / 120
    notches = notches > 0 and math.ceil(notches) or math.floor(notches)
    gfx.mouse_wheel = 0
    self:on_mouse_wheel(mx, my, notches)
  end

  self:draw()
  gfx.update()
  return true
end

return Emulator
