// Minimal mock of the REAPER API used by the FaderPort driver (see lua/tests/mock_reaper.lua)
#pragma once

#include "midi_io.h"
#include "reaper_api.h"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace mock {

struct Param
{
  std::string name;
  double value = 0.5;
};

struct Fx
{
  std::string name;
  GUID guid {};
  std::vector<Param> params;
};

struct VolCall
{
  double vol;
};

struct Track
{
  std::string name;
  int number = 0; // -1 = master
  GUID guid {};
  double vol = 1, pan = 0;
  int mute = 0, solo = 0, arm = 0, automode = 0;
  std::vector<Fx> fx;
  int chain_visible = -1;
  std::vector<double> vol_calls;
  std::vector<double> pan_calls;
};

struct State
{
  double now = 0;
  std::map<std::string, std::string> ext;
  std::vector<std::unique_ptr<Track>> tracks;
  std::unique_ptr<Track> master;
  std::vector<Track *> selected;
  int play_state = 0;
  int repeat_state = 0;
  std::map<int, int> toggles;
  std::vector<int> commands;
  int focused_track = 0, focused_item = -1, focused_fx = -1, focused_retval = 0;
  double loop_start = 0, loop_end = 0;
  int undo = 0, redo = 0;
  int end_edits = 0;
  std::string help;
  std::string console;
};

State &state();
void install(); // reset state and assign mock functions to the REAPER API pointers

Track *add_track(const std::string &name);
void remove_track(Track *track);
Fx &add_fx(Track *track, const std::string &name, const std::vector<std::string> &params);
void select(Track *track);
void advance(double seconds);

inline MediaTrack *mt(Track *t) { return reinterpret_cast<MediaTrack *>(t); }

class MidiPort : public faderport::MidiPort
{
public:
  bool open(const std::string &, const std::string &) override { return open_ = available; }
  void close() override { open_ = false; }
  bool is_open() const override { return open_; }
  void send(const faderport::Message &msg) override { sent.push_back(msg); }
  void poll(std::vector<faderport::MidiEvent> &events) override
  {
    for (auto &e : pending)
      events.push_back(e);
    pending.clear();
  }

  void push(uint8_t a, uint8_t b, uint8_t c) { pending.push_back({{a, b, c}, state().now}); }

  bool available = true;
  std::vector<faderport::MidiEvent> pending;
  std::vector<faderport::Message> sent;

private:
  bool open_ = false;
};

} // namespace mock
