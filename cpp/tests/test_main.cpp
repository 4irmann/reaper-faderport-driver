// Unit tests for the C++ FaderPort driver against a mocked REAPER API
// (same scenarios as lua/tests/run_tests.lua)

#include "driver.h"
#include "mock_reaper.h"

#include <cmath>
#include <cstdio>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

using namespace faderport;

namespace {

#define CHECK(cond)                                                                    \
  do                                                                                   \
  {                                                                                    \
    if (!(cond))                                                                       \
      throw std::runtime_error(std::string(__FILE__) + ":" + std::to_string(__LINE__) + \
                               ": CHECK(" #cond ") failed");                           \
  } while (0)

struct Fixture
{
  mock::MidiPort *midi = nullptr;
  std::unique_ptr<Driver> driver;

  Fixture()
  {
    mock::install();
    Config config;
    config.load();
    auto port = std::make_unique<mock::MidiPort>();
    midi = port.get();
    driver = std::make_unique<Driver>(config, Bindings::parse(Bindings::default_text()), std::move(port));
    driver->run(); // connects
  }

  void cycle(double dt = 0.033)
  {
    mock::advance(dt);
    driver->run();
  }

  void hw(uint8_t a, uint8_t b, uint8_t c) { midi->push(a, b, c); }

  void press(uint8_t button)
  {
    hw(0xa0, button, 1);
    hw(0xa0, button, 0);
    cycle();
  }

  void fader(int value)
  {
    for (const Message &m : encode_fader(value))
      hw(m[0], m[1], m[2]);
  }

  // last state of a light sent, -1 if never sent
  int light(int nr) const
  {
    int on = -1;
    for (const Message &m : midi->sent)
      if (m[0] == 0xa0 && m[1] == nr)
        on = m[2];
    return on;
  }

  // last motor position sent, -1 if none
  int motor() const
  {
    int msb = 0, value = -1;
    for (const Message &m : midi->sent)
    {
      if (m[0] == 0xb0 && m[1] == 0x00)
        msb = m[2];
      else if (m[0] == 0xb0 && m[1] == 0x20)
        value = (msb << 7) | m[2];
    }
    return value;
  }
};

bool approx(double a, double b, double eps = 1e-6) { return std::fabs(a - b) < eps; }

std::vector<std::pair<const char *, std::function<void()>>> tests = {

  {"protocol_fader_roundtrip", [] {
     for (int v = 0; v <= FADER_MAX; ++v)
     {
       auto hw = encode_fader(v);
       CHECK(decode_fader(hw[0][2], hw[1][2]) == v);
       auto motor = fader_messages(v);
       CHECK(((motor[0][2] << 7) | motor[1][2]) == v);
     }
   }},

  {"bindings_parser", [] {
     Bindings b = Bindings::parse("generic_fallback = false\n# c\nFoo Bar: 3,Gain; Room size,0\nX:1\n");
     CHECK(!b.generic_fallback);
     CHECK(b.fx.size() == 2);
     CHECK(b.fx[0].match == "foo bar");
     CHECK(b.fx[0].pairs.size() == 2);
     CHECK(b.fx[0].pairs[0].first.index == 3 && b.fx[0].pairs[0].second.name == "gain");
     CHECK(b.fx[0].pairs[1].first.name == "room size" && b.fx[0].pairs[1].second.index == 0);
     CHECK(b.find("VST: Foo Bar (x)") == &b.fx[0]);
     CHECK(b.fx[1].pairs[0].second.index == 0 && b.fx[1].pairs[0].second.name.empty());
     CHECK(!Bindings::parse(Bindings::default_text()).fx.empty());
   }},

  {"connect_sends_native_mode", [] {
     Fixture f;
     CHECK(!f.midi->sent.empty());
     CHECK(f.midi->sent[0] == native_mode_message());
   }},

  {"fader_sets_volume_and_touch_state", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.hw(0xa0, 0x7f, 1);
     f.fader(1023);
     f.cycle();
     CHECK(approx(t1->vol, std::pow(10.0, 12.0 / 20), 1e-3));
     CHECK(f.driver->touch_state(mock::mt(t1), 0));
     CHECK(!f.driver->touch_state(mock::mt(t1), 1));
     f.hw(0xa0, 0x7f, 0);
     f.cycle();
     CHECK(!f.driver->touch_state(mock::mt(t1), 0));
     f.hw(0xa0, 0x7f, 1);
     f.fader(0);
     f.cycle();
     CHECK(t1->vol == 0);
   }},

  {"fader_release_timeout_without_touch", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.fader(500);
     f.cycle();
     CHECK(f.driver->touch_state(mock::mt(t1), 0));
     f.cycle(0.5);
     CHECK(!f.driver->touch_state(mock::mt(t1), 0));
   }},

  {"motor_follows_volume", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.midi->sent.clear();
     f.cycle();
     CHECK(f.motor() == 947); // 0 dB in the mock taper
     f.midi->sent.clear();
     f.cycle();
     CHECK(f.motor() == -1);
     t1->vol = 0.5;
     f.cycle();
     CHECK(f.motor() >= 0 && f.motor() < 947);
     f.midi->sent.clear();
     f.hw(0xa0, 0x7f, 1);
     f.cycle();
     t1->vol = 2;
     f.cycle();
     CHECK(f.motor() == -1);
   }},

  {"buttons_mute_solo_arm_and_lights", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.press(btn::MUTE);
     CHECK(t1->mute == 1);
     f.cycle();
     CHECK(f.light(light::MUTE) == 1);
     f.press(btn::SOLO);
     f.press(btn::REC);
     f.cycle();
     CHECK(t1->solo == 1 && t1->arm == 1);
     CHECK(f.light(light::SOLO) == 1 && f.light(light::REC) == 1);
     f.press(btn::MUTE);
     f.cycle();
     CHECK(t1->mute == 0 && f.light(light::MUTE) == 0);
   }},

  {"track_navigation_wraps", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     auto *t2 = mock::add_track("t2");
     auto *t3 = mock::add_track("t3");
     mock::select(t1);
     f.cycle();
     f.press(btn::RIGHT);
     CHECK(mock::state().selected[0] == t2);
     f.press(btn::LEFT);
     f.press(btn::LEFT);
     CHECK(mock::state().selected[0] == t3);
     f.press(btn::OUTPUT);
     CHECK(mock::state().selected[0] == mock::state().master.get());
     f.cycle();
     CHECK(f.light(light::OUTPUT) == 1);
     f.press(btn::OUTPUT);
     CHECK(mock::state().selected[0] == t3);
   }},

  {"automation_modes", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.press(btn::WRITE);
     CHECK(t1->automode == 4);
     f.cycle();
     CHECK(f.light(light::WRITE) == 1);
     f.press(btn::WRITE);
     CHECK(t1->automode == 0);
     f.hw(0xa0, btn::SHIFT, 1);
     f.press(btn::WRITE);
     f.hw(0xa0, btn::SHIFT, 0);
     f.cycle();
     CHECK(t1->automode == 3);
     f.press(btn::READ);
     CHECK(t1->automode == 1);
     f.press(btn::TOUCH);
     CHECK(t1->automode == 2);
     f.press(btn::TOUCH);
     CHECK(t1->automode == 0);
   }},

  {"pan_anti_suck_and_center_snap", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.hw(0xe0, 0, PAN_RIGHT);
     f.hw(0xe0, 0, PAN_RIGHT);
     f.cycle();
     CHECK(t1->pan == 0);
     f.cycle(1.0);
     f.hw(0xe0, 0, PAN_RIGHT);
     f.cycle();
     CHECK(t1->pan > 0 && t1->pan < 0.05);
     CHECK(f.driver->touch_state(mock::mt(t1), 1));
     f.cycle(1.0);
     for (int i = 0; i < 3; ++i)
       f.hw(0xe0, 0, PAN_LEFT);
     f.cycle();
     CHECK(t1->pan == 0);
     f.cycle(1.0);
     CHECK(!f.driver->touch_state(mock::mt(t1), 1));
   }},

  {"pan_ballistics_use_event_time_stamps", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     // slow: one step per second -> speed 1 per step
     for (int step = 0; step < 3; ++step)
     {
       for (int i = 0; i < 3; ++i)
         f.midi->pending.push_back({{0xe0, 0, PAN_RIGHT}, mock::state().now + step * 1.0});
     }
     f.cycle(3.0);
     double slow = t1->pan;
     CHECK(approx(slow, 2.0 * (64 + 3) / 127 - 1, 1e-9)); // virtual pan 64 (center) + 3 steps
     // fast: steps 10 ms apart within one cycle -> max speed
     double t0 = mock::state().now;
     for (int step = 1; step <= 4; ++step)
     {
       for (int i = 0; i < 3; ++i)
         f.midi->pending.push_back({{0xe0, 0, PAN_RIGHT}, t0 + step * 0.010});
     }
     f.cycle();
     CHECK(t1->pan - slow > 0.5);
   }},

  {"trim_with_shift", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     f.cycle();
     f.hw(0xa0, btn::SHIFT, 1);
     for (int i = 0; i < 3; ++i)
       f.hw(0xe0, 0, PAN_RIGHT);
     f.cycle();
     CHECK(t1->vol > 1 && t1->vol < 1.05);
     CHECK(t1->pan == 0);
   }},

  {"rewind_forward_reset_default", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     t1->vol = 0.25;
     mock::select(t1);
     f.cycle();
     f.hw(0xa0, btn::REWIND, 1);
     f.hw(0xa0, btn::FORWARD, 1);
     f.hw(0xa0, btn::REWIND, 0);
     f.hw(0xa0, btn::FORWARD, 0);
     f.cycle();
     CHECK(approx(t1->vol, 1.0));
     for (int cmd : mock::state().commands)
       CHECK(cmd != 40172 && cmd != 40173);
     f.press(btn::REWIND);
     CHECK(mock::state().commands.back() == 40172);
   }},

  {"transport", [] {
     Fixture f;
     mock::add_track("t1");
     f.cycle();
     f.press(btn::PLAY);
     CHECK(mock::state().play_state == 1);
     f.cycle();
     CHECK(f.light(light::PLAY) == 1 && f.light(light::STOP) == 0);
     f.press(btn::PLAY);
     CHECK(mock::state().play_state == 0);
     f.press(btn::STOP);
     CHECK(mock::state().commands.back() == 40345);
     f.press(btn::LOOP);
     CHECK(mock::state().repeat_state == 1);
     f.hw(0xa0, btn::FOOTSWITCH, 1);
     f.cycle();
     CHECK(mock::state().play_state == 1);
   }},

  {"dsp_mode_named_bindings_and_swap", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::add_fx(t1, "ReaComp (Cockos)", {"Thresh", "Ratio", "Attack", "Release", "Pre-comp", "Knee", "Wet", "Dry"});
     mock::select(t1);
     f.cycle();
     f.press(btn::BANK);
     f.cycle();
     CHECK(f.light(light::BANK) == 1);
     CHECK(f.driver->fader_param()->name() == "Thresh");
     CHECK(f.driver->pan_param()->name() == "Ratio");
     f.hw(0xa0, 0x7f, 1);
     f.fader(1023);
     f.hw(0xa0, 0x7f, 0);
     f.cycle();
     CHECK(t1->fx[0].params[0].value == 1.0);
     CHECK(mock::state().end_edits == 1);
     f.press(btn::RIGHT);
     CHECK(f.driver->fader_param()->name() == "Attack");
     f.press(btn::LEFT);
     f.press(btn::LEFT);
     CHECK(f.driver->fader_param()->name() == "Knee");
     f.press(btn::USER);
     CHECK(f.driver->fader_param()->name() == "Pre-comp");
     CHECK(f.driver->pan_param()->name() == "Knee");
   }},

  {"dsp_mode_generic_fallback_and_fx_select", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::add_fx(t1, "Unknown Synth", {"A", "B", "C"});
     mock::add_fx(t1, "Other", {"X", "Y"});
     mock::select(t1);
     f.cycle();
     f.press(btn::BANK);
     CHECK(f.driver->fader_param()->name() == "A" && f.driver->pan_param()->name() == "B");
     f.press(btn::RIGHT);
     CHECK(f.driver->fader_param()->name() == "C" && f.driver->pan_param() == nullptr);
     f.hw(0xa0, btn::SHIFT, 1);
     f.press(btn::RIGHT);
     f.hw(0xa0, btn::SHIFT, 0);
     f.cycle();
     CHECK(f.driver->fader_param()->name() == "X");
   }},

  {"dsp_follows_focused_fx_callback", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     auto *t2 = mock::add_track("t2");
     mock::add_fx(t1, "Alpha", {"A1", "A2"});
     mock::add_fx(t2, "Beta", {"B1", "B2"});
     mock::add_fx(t2, "Gamma", {"G1", "G2"});
     mock::select(t1);
     f.cycle();
     f.press(btn::BANK);
     CHECK(f.driver->fader_param()->name() == "A1");
     f.driver->on_focused_fx(mock::mt(t2), true, 1); // CSURF_EXT_SETFOCUSEDFX
     f.cycle();
     CHECK(mock::state().selected[0] == t2);
     CHECK(f.driver->fader_param()->name() == "G1");
   }},

  {"bank_takes_over_focused_fx", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::add_fx(t1, "Alpha", {"A1", "A2"});
     mock::add_fx(t1, "Beta", {"B1", "B2"});
     mock::select(t1);
     mock::state().focused_retval = 1;
     mock::state().focused_track = 1;
     mock::state().focused_fx = 1;
     f.cycle();
     f.press(btn::BANK);
     CHECK(f.driver->fader_param()->name() == "B1");
   }},

  {"sticky_mode", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     auto *t2 = mock::add_track("t2");
     mock::select(t1);
     f.cycle();
     f.press(btn::TRNS);
     f.cycle();
     CHECK(f.light(light::TRNS) == 1);
     mock::select(t2);
     f.cycle();
     CHECK(f.driver->track() == mock::mt(t1));
     mock::remove_track(t1);
     f.cycle();
     CHECK(!f.driver->sticky_mode());
     mock::select(t2);
     f.cycle();
     CHECK(f.driver->track() == mock::mt(t2));
   }},

  {"off_light_is_momentary", [] {
     Fixture f;
     mock::add_track("t1");
     f.cycle();
     f.hw(0xa0, btn::OFF, 1);
     f.cycle();
     CHECK(f.light(light::OFF) == 1);
     f.hw(0xa0, btn::OFF, 0);
     f.cycle();
     CHECK(f.light(light::OFF) == 0);
   }},

  {"lights_only_sent_on_change", [] {
     Fixture f;
     mock::add_track("t1");
     f.cycle();
     f.midi->sent.clear();
     f.cycle();
     CHECK(f.midi->sent.empty());
   }},

  {"sinks_receive_messages", [] {
     Fixture f;
     auto *t1 = mock::add_track("t1");
     mock::select(t1);
     std::vector<Message> received;
     int id = f.driver->add_sink([&](const Message &m) { received.push_back(m); });
     f.driver->invalidate();
     f.cycle();
     CHECK(!received.empty());
     f.driver->remove_sink(id);
     received.clear();
     f.driver->invalidate();
     f.cycle();
     CHECK(received.empty());
   }},
};

} // namespace

int main()
{
  int failed = 0;
  for (auto &test : tests)
  {
    try
    {
      test.second();
      std::printf("PASS %s\n", test.first);
    }
    catch (const std::exception &e)
    {
      ++failed;
      std::printf("FAIL %s\n  %s\n", test.first, e.what());
    }
  }
  std::printf("%d tests, %d failed\n", static_cast<int>(tests.size()), failed);
  return failed == 0 ? 0 : 1;
}
