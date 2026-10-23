/*------------------------------------------------------------------------------------

  FaderPort driver main (port of the Lua variant / Renoise driver)

  run() is called by the control surface on every Run() (~30 Hz): MIDI input is
  processed with per-event time stamps, then lights, motor fader and bindings are
  compared with the last state sent to the FaderPort and only changes are sent.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include "bindings.h"
#include "config.h"
#include "midi_io.h"
#include "params.h"

#include <array>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace faderport {

class Driver
{
public:
  using Sink = std::function<void(const Message &)>;

  Driver(Config config, Bindings bindings, std::unique_ptr<MidiPort> midi);

  void run();
  void shutdown(); // lights off, close MIDI
  void reset(); // reopen MIDI, resend everything
  void invalidate(); // force resending lights and fader position

  // MIDI message from FaderPort or emulator, time in time_precise() seconds
  void midi_callback(const Message &msg, double time);

  // control surface callbacks
  bool touch_state(MediaTrack *track, int is_pan) const;
  void on_focused_fx(MediaTrack *track, bool is_track_fx, int fx);
  void on_fx_param_info_changed();

  // parameter list and resolved binding pairs of an FX (replaces the Renoise device info dialog)
  std::string describe_fx(MediaTrack *track, int fx);

  int add_sink(Sink sink);
  void remove_sink(int id);

  void set_dump_midi(bool dump) { config_.dump_midi = dump; }
  const std::string &status() const { return status_; }
  bool hardware_connected() const { return midi_->is_open(); }

  // state access (tests, emulator bridge)
  Param *fader_param() const { return fader_param_.get(); }
  Param *pan_param() const { return pan_param_.get(); }
  MediaTrack *track() const { return track_; }
  bool sticky_mode() const { return sticky_mode_; }
  bool dsp_mode() const { return dsp_mode_; }

private:
  using BindingPair = std::pair<int, int>; // 0-based parameter indices, -1 = nothing

  void init_members();
  void send(const Message &msg);
  void switch_off_lights();
  bool connect_hardware();

  // track / fx follow
  void select_track(MediaTrack *track);
  void update_track();
  void update_fx();
  void select_fx_delta(int delta);

  // dsp bindings
  const std::vector<BindingPair> &binding_pairs(MediaTrack *track, int fx, const GUID &fx_guid);
  const std::vector<BindingPair> *current_pairs();
  void select_binding_delta(int delta);
  void update_binding();
  void bind(std::unique_ptr<Param> fader, std::unique_ptr<Param> pan);
  void end_all_edits();

  // status line
  std::string status_prefix();
  void show_status(const std::string &message);
  void status_display_binding();
  void status_display_value(Param *param, const char *symbol);

  // fader
  void on_receive_fader_value(int value, double time);
  void on_fader_touch(bool touched);
  void reset_fader_param_to_default();
  void update_motor(double now);
  void check_release_timeouts(double now);

  // pan / trim
  int encoder_direction(int value, int &left_count, int &right_count) const;
  void on_receive_pan_value(int value, double time);
  void on_receive_trim_value(int value, double time);
  void sync_virtual_pan(double now);

  // actions
  void toggle_automation_mode(int mode);
  void toggle_play();
  void move_time_selection(int direction);
  void toggle_auto_punch();
  void toggle_fx_chain();
  void toggle_fx_float();
  void toggle_sticky_mode();
  void toggle_master_track();
  void navigate_track(int delta);

  void update_lights();
  void on_button(int button, int value);

  Config config_;
  Bindings bindings_;
  std::unique_ptr<MidiPort> midi_;
  std::vector<std::pair<int, Sink>> sinks_;
  int next_sink_id_ = 1;
  double next_device_retry_ = 0;
  bool device_notice_shown_ = false;
  std::string status_;
  std::vector<MidiEvent> events_;

  // project specific state, see init_members()
  ReaProject *project_ = nullptr;

  MediaTrack *track_ = nullptr;
  MediaTrack *prev_track_ = nullptr;
  GUID fx_guid_ {};
  bool has_fx_ = false;
  int fx_index_ = -1;
  std::map<std::string, GUID> fx_by_track_;
  bool focus_pending_ = false;
  MediaTrack *focus_track_ = nullptr;
  int focus_fx_ = -1;

  bool dsp_mode_ = false;
  bool sticky_mode_ = false;
  bool fader_pan_swapped_ = false;

  std::map<std::string, std::vector<BindingPair>> pairs_cache_;
  std::map<std::string, int> binding_index_by_fx_;

  std::string bound_key_;
  bool bound_ = false;
  std::unique_ptr<Param> fader_param_;
  std::unique_ptr<Param> pan_param_;

  // fader
  int last_msb_ = 0;
  int motor_pos_ = -1; // last fader position sent to the surfaces, -1 = unknown
  int fader_res_ = 1024;
  bool fader_touched_ = false;
  bool fader_editing_ = false;
  double last_fader_rx_ = -1;

  // pan
  int pan_res_ = 128;
  int virtual_pan_value_ = 0;
  int pan_left_count_ = 0, pan_right_count_ = 0;
  double last_pan_time_ = -1;
  double last_pan_rx_ = -1;
  bool pan_editing_ = false;

  // trim
  int trim_left_count_ = 0, trim_right_count_ = 0;
  double last_trim_time_ = -1;
  double last_trim_rx_ = -1;
  bool trim_editing_ = false;

  // buttons
  bool shift_pressed_ = false;
  bool rewind_pressed_ = false;
  bool forward_pressed_ = false;
  std::array<bool, LIGHT_COUNT> momentary_ {};
  std::array<int, LIGHT_COUNT> light_cache_ {}; // -1 unknown, 0 off, 1 on
};

} // namespace faderport
