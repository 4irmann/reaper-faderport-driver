--[[
  Unit tests for the FaderPort driver against a mocked REAPER API.
  Run with a plain Lua 5.4 interpreter from the repository root:

    lua tests/run_tests.lua
]]

local tests_path = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or "./"
package.path = tests_path .. "?.lua;" .. tests_path .. "../faderport/?.lua;" .. package.path

local mock = require("mock_reaper")

local IN_DEV, OUT_DEV = 1, 1
local MODULES = { "util", "protocol", "config", "params", "bindings", "midi_io", "driver", "emulator", "cpp_bridge" }

local function setup()
  for _, m in ipairs(MODULES) do
    package.loaded[m] = nil
  end
  mock.install()
  local config = require("config")
  config.load()
  local Driver = require("driver")
  local driver = Driver.new()
  driver:run() -- connects and initializes the MIDI poll
  return driver, config
end

local function cycle(driver, dt)
  mock.advance(dt or 0.033)
  driver:run()
end

local function hw(b1, b2, b3)
  mock.push_midi(IN_DEV, b1, b2, b3)
end

local function press(driver, button)
  hw(0xa0, button, 1)
  hw(0xa0, button, 0)
  cycle(driver)
end

local function hw_fader(value)
  local protocol = require("protocol")
  local msb, lsb = protocol.encode_fader(value)
  hw(table.unpack(msb))
  hw(table.unpack(lsb))
end

local function light_state(nr)
  local on = nil
  for _, m in ipairs(mock.sent_to(OUT_DEV)) do
    if m[1] == 0xa0 and m[2] == nr then
      on = m[3] == 1
    end
  end
  return on
end

local function fader_sent()
  local msb, value
  for _, m in ipairs(mock.sent_to(OUT_DEV)) do
    if m[1] == 0xb0 and m[2] == 0x00 then
      msb = m[3]
    elseif m[1] == 0xb0 and m[2] == 0x20 then
      value = (msb << 7) | m[3]
    end
  end
  return value
end

local function near(a, b, eps)
  return math.abs(a - b) < (eps or 1e-6)
end

------------------------------------------------------------------------ tests

local T = {}

function T.protocol_fader_roundtrip()
  local protocol = require("protocol")
  for v = 0, protocol.FADER_MAX do
    local msb, lsb = protocol.encode_fader(v)
    assert(protocol.decode_fader(msb[3], lsb[3]) == v, "hardware encoding " .. v)
    local mmsb, mlsb = protocol.fader_messages(v)
    assert(protocol.decode_motor(mmsb[3], mlsb[3]) == v, "motor encoding " .. v)
  end
end

function T.connect_sends_native_mode()
  setup()
  local first = mock.sent_to(OUT_DEV)[1]
  assert(first[1] == 0x91 and first[2] == 0x00 and first[3] == 0x64, "native mode message")
end

function T.ignores_other_devices_and_history()
  local t1
  for _, m in ipairs(MODULES) do package.loaded[m] = nil end
  mock.install()
  t1 = mock.add_track("t1")
  mock.select(t1)
  hw(0xa0, 0x12, 1) -- mute pressed before the driver was started
  local config = require("config")
  config.load()
  local driver = require("driver").new()
  driver:run()
  cycle(driver)
  assert(t1.mute == 0, "history must be ignored")
  mock.push_midi(0, 0xa0, 0x12, 1) -- other device
  cycle(driver)
  assert(t1.mute == 0, "other device must be ignored")
  mock.push_midi(IN_DEV | 0x10000, 0xa0, 0x12, 1) -- FaderPort enabled for control only
  cycle(driver)
  assert(t1.mute == 1, "control only flag must be masked")
  mock.push_midi(IN_DEV, 0xa0, 0x12, 1)
  cycle(driver)
  assert(t1.mute == 0, "mute toggled back")
  hw(0xa0, 0x12, 1)
  cycle(driver)
  assert(t1.mute == 1, "mute expected")
end

function T.fader_sets_volume_as_gesture()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)

  hw(0xa0, 0x7f, 1) -- touch
  hw_fader(1023)
  cycle(driver)
  assert(near(t1.vol, 10 ^ (12 / 20), 1e-3), "full scale volume " .. t1.vol)
  assert(t1.vol_calls[#t1.vol_calls].done == false, "gesture in progress")

  hw(0xa0, 0x7f, 0) -- release
  cycle(driver)
  assert(t1.vol_calls[#t1.vol_calls].done == true, "gesture end on release")

  hw(0xa0, 0x7f, 1)
  hw_fader(0)
  cycle(driver)
  assert(t1.vol == 0, "fader at bottom = -inf")
end

function T.fader_release_timeout_without_touch()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)
  hw_fader(500)
  cycle(driver)
  assert(t1.vol_calls[#t1.vol_calls].done == false)
  cycle(driver, 0.5)
  assert(t1.vol_calls[#t1.vol_calls].done == true, "fake release after timeout")
end

function T.motor_follows_volume()
  local driver = setup()
  local t1 = mock.add_track("t1")
  t1.vol = 1.0
  mock.select(t1)
  mock.sent_clear()
  cycle(driver)
  -- 0 dB -> slider 925.9 (mock) -> 947
  assert(fader_sent() == 947, "motor position " .. tostring(fader_sent()))

  mock.sent_clear()
  cycle(driver)
  assert(fader_sent() == nil, "no resend without change")

  t1.vol = 0.5
  cycle(driver)
  assert(fader_sent() ~= nil and fader_sent() < 947, "motor follows")

  -- no motor while touched
  mock.sent_clear()
  hw(0xa0, 0x7f, 1)
  cycle(driver)
  t1.vol = 2
  cycle(driver)
  assert(fader_sent() == nil, "no motor while touched")
end

function T.buttons_mute_solo_arm_and_lights()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)
  press(driver, 0x12)
  assert(t1.mute == 1)
  cycle(driver)
  assert(light_state(0x15) == true, "mute light")
  press(driver, 0x11)
  assert(t1.solo == 1)
  press(driver, 0x10)
  assert(t1.arm == 1)
  cycle(driver)
  assert(light_state(0x16) == true and light_state(0x17) == true, "solo/rec light")
  press(driver, 0x12)
  cycle(driver)
  assert(t1.mute == 0 and light_state(0x15) == false, "mute off")
end

function T.track_navigation_wraps()
  local driver = setup()
  local t1, t2, t3 = mock.add_track("t1"), mock.add_track("t2"), mock.add_track("t3")
  mock.select(t1)
  cycle(driver)
  press(driver, 0x15) -- right
  assert(mock.state().selected[1] == t2)
  press(driver, 0x13) -- left
  press(driver, 0x13) -- left (wrap)
  assert(mock.state().selected[1] == t3, "wrap to last track")
  press(driver, 0x16) -- output: master
  assert(mock.state().selected[1] == mock.state().master)
  cycle(driver)
  assert(light_state(0x11) == true, "output light on master")
  press(driver, 0x16) -- output: back
  assert(mock.state().selected[1] == t3, "back from master")
end

function T.automation_modes()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)
  press(driver, 0x09) -- write = latch (default)
  assert(t1.automode == 4, "latch " .. t1.automode)
  cycle(driver)
  assert(light_state(0x0e) == true, "write light")
  press(driver, 0x09)
  assert(t1.automode == 0, "toggle off")
  hw(0xa0, 0x02, 1) -- shift
  press(driver, 0x09)
  hw(0xa0, 0x02, 0)
  cycle(driver)
  assert(t1.automode == 3, "shift+write = write")
  press(driver, 0x0a)
  assert(t1.automode == 1, "read")
  press(driver, 0x08)
  assert(t1.automode == 2, "touch")
  press(driver, 0x08)
  assert(t1.automode == 0, "touch off")
end

function T.pan_anti_suck_and_center_snap()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)

  hw(0xe0, 0x00, 0x01)
  hw(0xe0, 0x00, 0x01)
  cycle(driver)
  assert(t1.pan == 0, "two ticks are not enough (anti suck)")

  hw(0xe0, 0x00, 0x01)
  cycle(driver, 1.0) -- slow: speed 1
  assert(t1.pan > 0 and t1.pan < 0.05, "one step right " .. t1.pan)

  for _ = 1, 3 do hw(0xe0, 0x00, 0x7e) end
  cycle(driver, 1.0)
  assert(t1.pan == 0, "snap to center " .. t1.pan)

  -- release after timeout
  cycle(driver, 1.0)
  assert(t1.pan_calls[#t1.pan_calls].done == true, "pan gesture end")
end

function T.pan_ballistics()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)
  -- first step: speed 1
  for _ = 1, 3 do hw(0xe0, 0x00, 0x01) end
  cycle(driver, 1.0)
  local slow = t1.pan
  -- 4 steps within one 33 ms cycle -> interval 8 ms -> max speed
  for _ = 1, 12 do hw(0xe0, 0x00, 0x01) end
  cycle(driver, 0.033)
  assert(t1.pan - slow > 0.5, "fast turn accelerates " .. (t1.pan - slow))
end

function T.trim_with_shift()
  local driver = setup()
  local t1 = mock.add_track("t1")
  t1.vol = 1
  mock.select(t1)
  cycle(driver)
  hw(0xa0, 0x02, 1)
  for _ = 1, 3 do hw(0xe0, 0x00, 0x01) end
  cycle(driver, 1.0)
  assert(t1.vol > 1 and t1.vol < 1.05, "fine trim " .. t1.vol)
  assert(t1.pan == 0, "pan unchanged")
end

function T.rewind_forward_reset_default()
  local driver = setup()
  local t1 = mock.add_track("t1")
  t1.vol = 0.25
  mock.select(t1)
  cycle(driver)
  hw(0xa0, 0x03, 1)
  hw(0xa0, 0x04, 1)
  hw(0xa0, 0x03, 0)
  hw(0xa0, 0x04, 0)
  cycle(driver)
  assert(near(t1.vol, 1, 1e-6), "reset to 0 dB " .. t1.vol)
  for _, cmd in ipairs(mock.state().commands) do
    assert(cmd ~= 40172 and cmd ~= 40173, "no navigation when both pressed")
  end
  press(driver, 0x03)
  local commands = mock.state().commands
  assert(commands[#commands] == 40172, "rewind = previous marker")
end

function T.transport()
  local driver = setup()
  mock.add_track("t1")
  cycle(driver)
  press(driver, 0x06)
  assert(mock.state().play_state == 1, "play")
  cycle(driver)
  assert(light_state(0x01) == true and light_state(0x02) == false, "play light")
  press(driver, 0x06)
  assert(mock.state().play_state == 0, "play again = stop")
  press(driver, 0x05)
  local commands = mock.state().commands
  assert(commands[#commands] == 40345, "stop while stopped = panic")
  press(driver, 0x0f)
  assert(mock.state().repeat_state == 1, "loop = repeat")
  hw(0xa0, 0x7e, 1)
  cycle(driver)
  assert(mock.state().play_state == 1, "footswitch")
end

function T.dsp_mode_named_bindings_and_swap()
  local driver = setup()
  local t1 = mock.add_track("t1")
  local comp = mock.add_fx(t1, "ReaComp (Cockos)", { "Thresh", "Ratio", "Attack", "Release", "Pre-comp",
                                                     "Knee", "Wet", "Dry" })
  mock.select(t1)
  cycle(driver)
  press(driver, 0x14) -- bank: dsp mode
  cycle(driver)
  assert(light_state(0x13) == true, "bank light")
  assert(driver.fader_param:name() == "Thresh" and driver.pan_param:name() == "Ratio", driver.bound_key)

  hw(0xa0, 0x7f, 1)
  hw_fader(1023)
  hw(0xa0, 0x7f, 0)
  cycle(driver)
  assert(comp.params[1].value == 1, "fader -> Thresh")
  assert(#mock.state().end_edits == 1, "end param edit on release")

  press(driver, 0x15) -- next binding
  assert(driver.fader_param:name() == "Attack", "next pair")
  press(driver, 0x13)
  press(driver, 0x13) -- wrap backwards: Wet/Dry, Knee/Pre-comp ... last pair
  assert(driver.fader_param:name() == "Knee", "wrap to last pair " .. driver.fader_param:name())

  press(driver, 0x00) -- user: swap
  assert(driver.fader_param:name() == "Pre-comp" and driver.pan_param:name() == "Knee", "swapped")
end

function T.dsp_mode_generic_fallback_and_fx_select()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.add_fx(t1, "Unknown Synth", { "A", "B", "C" })
  mock.add_fx(t1, "Other", { "X", "Y" })
  mock.select(t1)
  cycle(driver)
  press(driver, 0x14)
  assert(driver.fader_param:name() == "A" and driver.pan_param:name() == "B")
  press(driver, 0x15)
  assert(driver.fader_param:name() == "C" and driver.pan_param == nil, "odd parameter count")
  hw(0xa0, 0x02, 1)
  press(driver, 0x15) -- shift+right: next FX
  hw(0xa0, 0x02, 0)
  cycle(driver)
  assert(driver.fader_param:name() == "X", "next FX")
end

function T.dsp_follows_focused_fx()
  local driver = setup()
  local t1, t2 = mock.add_track("t1"), mock.add_track("t2")
  mock.add_fx(t1, "Alpha", { "A1", "A2" })
  mock.add_fx(t2, "Beta", { "B1", "B2" })
  mock.add_fx(t2, "Gamma", { "G1", "G2" })
  mock.select(t1)
  cycle(driver)
  press(driver, 0x14)
  assert(driver.fader_param:name() == "A1")
  mock.state().focused = { 1, 2, -1, 1 } -- Gamma on track 2 focused
  cycle(driver)
  assert(mock.state().selected[1] == t2, "track of focused FX selected")
  assert(driver.fader_param:name() == "G1", "focused FX bound")
end

function T.sticky_mode()
  local driver = setup()
  local t1, t2 = mock.add_track("t1"), mock.add_track("t2")
  mock.select(t1)
  cycle(driver)
  press(driver, 0x0d) -- trns: sticky
  cycle(driver)
  assert(light_state(0x0a) == true, "trns light")
  mock.select(t2)
  cycle(driver)
  assert(driver.track == t1, "sticky keeps track")
  mock.remove_track(t1)
  cycle(driver)
  assert(driver.sticky_mode == false, "sticky off when track deleted")
  mock.select(t2)
  cycle(driver)
  assert(driver.track == t2)
end

function T.off_light_is_momentary()
  local driver = setup()
  mock.add_track("t1")
  cycle(driver)
  hw(0xa0, 0x17, 1)
  cycle(driver)
  assert(light_state(0x10) == true, "off light while pressed")
  hw(0xa0, 0x17, 0)
  cycle(driver)
  assert(light_state(0x10) == false, "off light released")
end

function T.lights_only_sent_on_change()
  local driver = setup()
  mock.add_track("t1")
  cycle(driver)
  mock.sent_clear()
  cycle(driver)
  assert(#mock.sent_to(OUT_DEV) == 0, "nothing sent without change")
end

function T.emulator_roundtrip()
  local driver = setup()
  local t1 = mock.add_track("t1")
  mock.select(t1)
  cycle(driver)
  local Emulator = require("emulator")
  local emu = Emulator.new(driver)
  driver:add_sink(emu.sink) -- open() without gfx
  driver:invalidate()
  cycle(driver)
  assert(emu.fader_value == 947, "emulator motor " .. emu.fader_value)
  emu:send_button(0x7f, 1)
  emu:send_fader(0)
  emu:send_button(0x7f, 0)
  assert(t1.vol == 0, "emulator fader -> volume")
  emu:send_button(0x12, 1)
  emu:send_button(0x12, 0)
  cycle(driver)
  assert(t1.mute == 1 and emu.lights[0x15] == true, "emulator mute and light")
  -- off light suppresses fader values like the hardware
  emu.lights[0x10] = true
  emu:send_fader(1023)
  assert(t1.vol == 0, "off light blocks fader")
end

function T.cpp_bridge_roundtrip()
  setup()
  local sent, attached = {}, nil
  reaper.AirmannFaderPort_EmuSend = function(a, b, c) sent[#sent + 1] = { a, b, c } end
  reaper.AirmannFaderPort_EmuAttach = function(on) attached = on end
  reaper.AirmannFaderPort_EmuReceive = function() return "a01501b00007b02033" end
  reaper.AirmannFaderPort_GetStatus = function() return "t1   ^Volume" end
  reaper.AirmannFaderPort_IsHardwareConnected = function() return false end

  local Bridge = require("cpp_bridge")
  assert(Bridge.available())
  local bridge = Bridge.new()
  local emu = require("emulator").new(bridge)
  bridge:add_sink(emu.sink)
  assert(attached == true, "attach on add_sink")
  bridge:run()
  assert(emu.lights[0x15] == true, "mute light via bridge")
  assert(emu.fader_value == (7 << 7 | 0x33), "motor via bridge " .. emu.fader_value)
  assert(bridge.status == "t1   ^Volume")
  emu:send_button(0x12, 1)
  assert(sent[1][1] == 0xa0 and sent[1][2] == 0x12 and sent[1][3] == 1, "button via bridge")
  bridge:remove_sink(emu.sink)
  assert(attached == false, "detach on remove_sink")
end

------------------------------------------------------------------------- run

local names = {}
for name in pairs(T) do names[#names + 1] = name end
table.sort(names)

local failed = 0
for _, name in ipairs(names) do
  local ok, err = xpcall(T[name], debug.traceback)
  if ok then
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. "\n" .. tostring(err))
  end
end
print(("%d tests, %d failed"):format(#names, failed))
if failed > 0 then
  os.exit(1)
end
