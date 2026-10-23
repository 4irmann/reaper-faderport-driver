#include "driver.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace faderport {

namespace {

// REAPER track automation modes
constexpr int AUTO_TRIM = 0;
constexpr int AUTO_READ = 1;
constexpr int AUTO_TOUCH = 2;
constexpr int AUTO_WRITE = 3;
constexpr int AUTO_LATCH = 4;

// REAPER actions
constexpr int CMD_TOGGLE_MIXER = 40078;
constexpr int CMD_VIEW_FX_CHAIN = 40291;
constexpr int CMD_SCROLL_TRACKS_INTO_VIEW = 40913;
constexpr int CMD_PREV_MARKER = 40172;
constexpr int CMD_NEXT_MARKER = 40173;
constexpr int CMD_PROJECT_START = 40042;
constexpr int CMD_PROJECT_END = 40043;
constexpr int CMD_RECMODE_AUTOPUNCH = 40076;
constexpr int CMD_RECMODE_NORMAL = 40252;
constexpr int CMD_ALL_NOTES_OFF = 40345;

double clamp(double v, double lo, double hi) { return std::min(hi, std::max(lo, v)); }
int clamp(int v, int lo, int hi) { return std::min(hi, std::max(lo, v)); }

// wrap integer value into [lo, hi]
int wrap(int v, int lo, int hi)
{
  int range = hi - lo + 1;
  return ((v - lo) % range + range) % range + lo;
}

// encoder speed based on the interval between two effective steps
// (Renoise ballistics: speed = 1 + 0.2 s / interval, min speed = 1, max speed = 20).
// The C++ variant has a time stamp for every MIDI event, so the real interval is used.
int compute_speed(double last_time, double time)
{
  if (last_time < 0)
    return 1;
  double interval = std::max(time - last_time, 0.001);
  return clamp(1 + static_cast<int>(std::floor(0.20 / interval + 0.5)), 1, 20);
}

bool is_playing() { return (GetPlayState() & 5) != 0; } // playing or recording

void log(const std::string &msg) { ShowConsoleMsg(("FaderPort: " + msg + "\n").c_str()); }

int resolve_binding_entry(const BindingEntry &entry, const std::vector<std::string> &names)
{
  if (entry.index > 0)
    return entry.index <= static_cast<int>(names.size()) ? entry.index - 1 : -1;
  if (!entry.name.empty())
  {
    for (size_t i = 0; i < names.size(); ++i)
    {
      if (names[i].compare(0, entry.name.size(), entry.name) == 0)
        return static_cast<int>(i);
    }
  }
  return -1;
}

} // namespace

Driver::Driver(Config config, Bindings bindings, std::unique_ptr<MidiPort> midi)
  : config_(std::move(config)), bindings_(std::move(bindings)), midi_(std::move(midi))
{
  init_members();
}

// member variable initialization (project specific state)
void Driver::init_members()
{
  project_ = EnumProjects(-1, nullptr, 0);

  track_ = nullptr;
  prev_track_ = nullptr;
  has_fx_ = false;
  fx_index_ = -1;
  fx_by_track_.clear();
  focus_pending_ = false;

  dsp_mode_ = config_.start_in_dsp_mode;
  sticky_mode_ = false;
  fader_pan_swapped_ = false;

  pairs_cache_.clear();
  binding_index_by_fx_.clear();

  bound_ = false;
  bound_key_.clear();
  fader_param_.reset();
  pan_param_.reset();

  last_msb_ = 0;
  motor_pos_ = -1;
  fader_res_ = 1024;
  fader_touched_ = false;
  fader_editing_ = false;
  last_fader_rx_ = -1;

  pan_res_ = config_.virtual_pan_resolution;
  virtual_pan_value_ = 0;
  pan_left_count_ = pan_right_count_ = 0;
  last_pan_time_ = last_pan_rx_ = -1;
  pan_editing_ = false;

  trim_left_count_ = trim_right_count_ = 0;
  last_trim_time_ = last_trim_rx_ = -1;
  trim_editing_ = false;

  shift_pressed_ = rewind_pressed_ = forward_pressed_ = false;
  momentary_.fill(false);
  light_cache_.fill(-1);
}

//--------------------------------------------------------------------- MIDI out

int Driver::add_sink(Sink sink)
{
  sinks_.emplace_back(next_sink_id_, std::move(sink));
  return next_sink_id_++;
}

void Driver::remove_sink(int id)
{
  sinks_.erase(std::remove_if(sinks_.begin(), sinks_.end(),
                              [id](const auto &s) { return s.first == id; }),
               sinks_.end());
}

void Driver::send(const Message &msg)
{
  if (config_.dump_midi)
  {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "send %02X %02X %02X", msg[0], msg[1], msg[2]);
    log(buf);
  }
  midi_->send(msg);
  for (auto &sink : sinks_)
    sink.second(msg);
}

void Driver::invalidate()
{
  light_cache_.fill(-1);
  motor_pos_ = -1;
}

void Driver::switch_off_lights()
{
  for (int nr = 0; nr <= 0x30; ++nr)
    send(light_message(nr, false));
  light_cache_.fill(-1);
}

//------------------------------------------------------------ connect / reset

bool Driver::connect_hardware()
{
  if (midi_->open(config_.midi_in_name, config_.midi_out_name))
  {
    device_notice_shown_ = false;
    midi_->send(native_mode_message());
    invalidate();
    return true;
  }
  if (!device_notice_shown_)
  {
    device_notice_shown_ = true;
    log("MIDI device '" + config_.midi_in_name + "' / '" + config_.midi_out_name +
        "' not found or already opened (disable it in REAPER's MIDI preferences). Retrying in the background.");
  }
  return false;
}

void Driver::reset()
{
  end_all_edits();
  switch_off_lights();
  midi_->close();
  device_notice_shown_ = false;
  connect_hardware();
  invalidate();
}

void Driver::shutdown()
{
  end_all_edits();
  switch_off_lights();
  midi_->close();
}

//------------------------------------------------------------------- main loop

void Driver::run()
{
  double now = time_precise();

  if (!midi_->is_open() && now >= next_device_retry_)
  {
    next_device_retry_ = now + config_.device_retry_interval;
    connect_hardware();
  }

  // project tab changed
  ReaProject *project = EnumProjects(-1, nullptr, 0);
  if (project != project_)
  {
    end_all_edits();
    init_members();
  }

  events_.clear();
  midi_->poll(events_);
  for (const MidiEvent &event : events_)
    midi_callback(event.msg, event.time);

  update_track();
  if (dsp_mode_)
    update_fx();
  update_binding();
  check_release_timeouts(now);
  update_motor(now);
  sync_virtual_pan(now);
  update_lights();
}

//------------------------------------------------------------ track / fx follow

void Driver::select_track(MediaTrack *track)
{
  if (!track_valid(track))
    return;
  SetOnlyTrackSelected(track);
  if (!is_master(track))
    SetMixerScroll(track);
  Main_OnCommand(CMD_SCROLL_TRACKS_INTO_VIEW, 0);
}

void Driver::update_track()
{
  if (sticky_mode_)
  {
    if (track_valid(track_))
      return;
    toggle_sticky_mode(); // track is no more: switch off sticky mode
  }

  if (MediaTrack *track = GetSelectedTrack2(nullptr, 0, true))
    track_ = track;
  else if (!track_valid(track_))
    track_ = GetMasterTrack(nullptr);
}

void Driver::on_focused_fx(MediaTrack *track, bool is_track_fx, int fx)
{
  // track FX only, no item/input/container FX
  if (!track || !is_track_fx || fx < 0 || fx >= 0x1000000)
    return;
  focus_pending_ = true;
  focus_track_ = track;
  focus_fx_ = fx;
}

void Driver::update_fx()
{
  MediaTrack *track = track_;

  if (sticky_mode_ && has_fx_ && find_fx(track, &fx_guid_, fx_index_) >= 0)
    return;

  if (focus_pending_ && config_.follow_focused_fx && !sticky_mode_ && track_valid(focus_track_))
  {
    if (focus_track_ != track)
    {
      select_track(focus_track_);
      track_ = track = focus_track_;
    }
    if (const GUID *guid = TrackFX_GetFXGUID(track, focus_fx_))
    {
      fx_guid_ = *guid;
      has_fx_ = true;
    }
  }
  focus_pending_ = false;

  std::string track_guid = guid_string(GetTrackGUID(track));
  int index = has_fx_ ? find_fx(track, &fx_guid_, fx_index_) : -1;
  if (index < 0)
  {
    if (sticky_mode_)
      toggle_sticky_mode(); // FX is no more: switch off sticky mode

    // last FX used on this track or first FX
    has_fx_ = false;
    auto it = fx_by_track_.find(track_guid);
    if (it != fx_by_track_.end())
    {
      index = find_fx(track, &it->second, -1);
      if (index >= 0)
      {
        fx_guid_ = it->second;
        has_fx_ = true;
      }
    }
    if (index < 0 && TrackFX_GetCount(track) > 0)
    {
      index = 0;
      fx_guid_ = *TrackFX_GetFXGUID(track, 0);
      has_fx_ = true;
    }
  }
  fx_index_ = index;
  if (has_fx_)
    fx_by_track_[track_guid] = fx_guid_;
}

void Driver::select_fx_delta(int delta)
{
  int count = TrackFX_GetCount(track_);
  if (count == 0)
    return;
  int index = wrap(std::max(fx_index_, 0) + delta, 0, count - 1);
  fx_index_ = index;
  fx_guid_ = *TrackFX_GetFXGUID(track_, index);
  has_fx_ = true;
  fx_by_track_[guid_string(GetTrackGUID(track_))] = fx_guid_;
  // keep visible FX chain in sync
  if (TrackFX_GetChainVisible(track_) != -1)
    TrackFX_Show(track_, index, 1);
}

//---------------------------------------------------------------- dsp bindings

// list of binding pairs for an FX
const std::vector<Driver::BindingPair> &Driver::binding_pairs(MediaTrack *track, int fx, const GUID &fx_guid)
{
  std::string key = guid_string(&fx_guid);
  auto cached = pairs_cache_.find(key);
  if (cached != pairs_cache_.end())
    return cached->second;

  std::vector<std::string> names;
  int count = TrackFX_GetNumParams(track, fx);
  for (int p = 0; p < count; ++p)
  {
    char buf[256] = "";
    TrackFX_GetParamName(track, fx, p, buf, sizeof(buf));
    names.push_back(to_lower(buf));
  }

  std::vector<BindingPair> pairs;
  if (const FxBinding *binding = bindings_.find(fx_name(track, fx)))
  {
    for (const auto &pair : binding->pairs)
    {
      int fader = resolve_binding_entry(pair.first, names);
      int pan = resolve_binding_entry(pair.second, names);
      if (fader >= 0 || pan >= 0)
        pairs.emplace_back(fader, pan);
    }
  }

  if (pairs.empty() && bindings_.generic_fallback)
  {
    for (int p = 0; p < count; p += 2)
      pairs.emplace_back(p, p + 1 < count ? p + 1 : -1);
  }

  return pairs_cache_[key] = std::move(pairs);
}

const std::vector<Driver::BindingPair> *Driver::current_pairs()
{
  if (!has_fx_ || fx_index_ < 0)
    return nullptr;
  return &binding_pairs(track_, fx_index_, fx_guid_);
}

std::string Driver::describe_fx(MediaTrack *track, int fx)
{
  const GUID *guid = TrackFX_GetFXGUID(track, fx);
  if (!guid)
    return "no FX";

  std::string text = track_name(track) + "  /  " + fx_name(track, fx) + "\nbindings (fader,pan):";
  pairs_cache_.erase(guid_string(guid)); // reflect edited binding files
  const auto &pairs = binding_pairs(track, fx, *guid);
  for (const auto &pair : pairs)
    text += " [" + std::to_string(pair.first + 1) + "," + std::to_string(pair.second + 1) + "]";
  if (pairs.empty())
    text += " none";
  text += "\n\n";

  int count = TrackFX_GetNumParams(track, fx);
  for (int p = 0; p < count; ++p)
  {
    char name[256] = "", value[256] = "", line[600];
    TrackFX_GetParamName(track, fx, p, name, sizeof(name));
    TrackFX_GetFormattedParamValue(track, fx, p, value, sizeof(value));
    std::snprintf(line, sizeof(line), "%3d ]  %-32s %s\n", p + 1, name, value);
    text += line;
  }
  return text;
}

void Driver::on_fx_param_info_changed()
{
  pairs_cache_.clear(); // parameter names/count may have changed
}

void Driver::select_binding_delta(int delta)
{
  const auto *pairs = current_pairs();
  if (!pairs || pairs->size() < 2)
    return;
  std::string key = guid_string(&fx_guid_);
  int index = binding_index_by_fx_.count(key) ? binding_index_by_fx_[key] : 0;
  binding_index_by_fx_[key] = wrap(index + delta, 0, static_cast<int>(pairs->size()) - 1);
}

// compute parameters that shall be bound and rebind on changes
void Driver::update_binding()
{
  std::unique_ptr<Param> fader, pan;

  if (!track_valid(track_))
  {
    // nothing
  }
  else if (!dsp_mode_)
  {
    fader = make_track_volume(track_);
    pan = make_track_pan(track_);
  }
  else if (const auto *pairs = current_pairs())
  {
    if (!pairs->empty())
    {
      std::string key = guid_string(&fx_guid_);
      int index = binding_index_by_fx_.count(key) ? binding_index_by_fx_[key] : 0;
      const BindingPair &pair = (*pairs)[clamp(index, 0, static_cast<int>(pairs->size()) - 1)];
      if (pair.first >= 0)
        fader = make_fx_param(track_, fx_guid_, fx_index_, pair.first);
      if (pair.second >= 0)
        pan = make_fx_param(track_, fx_guid_, fx_index_, pair.second);
    }
  }

  if (fader_pan_swapped_)
    std::swap(fader, pan);

  std::string key = (fader ? fader->key() : "-") + "|" + (pan ? pan->key() : "-");
  if (!bound_ || key != bound_key_)
  {
    bound_ = true;
    bound_key_ = key;
    bind(std::move(fader), std::move(pan));
  }
}

void Driver::end_all_edits()
{
  if (fader_param_ && (fader_editing_ || trim_editing_) && fader_param_->valid())
    fader_param_->end_edit();
  if (pan_param_ && pan_editing_ && pan_param_->valid())
    pan_param_->end_edit();
  fader_editing_ = trim_editing_ = pan_editing_ = false;
}

void Driver::bind(std::unique_ptr<Param> fader, std::unique_ptr<Param> pan)
{
  end_all_edits();

  fader_param_ = std::move(fader);
  pan_param_ = std::move(pan);

  // fader
  motor_pos_ = -1; // force motor update
  fader_res_ = fader_param_ ? fader_param_->resolution(1024) : 1024;
  last_trim_time_ = -1;
  trim_left_count_ = trim_right_count_ = 0;

  // pan
  pan_res_ = pan_param_ ? pan_param_->resolution(config_.virtual_pan_resolution)
                        : config_.virtual_pan_resolution;
  last_pan_time_ = last_pan_rx_ = -1;
  pan_left_count_ = pan_right_count_ = 0;
  if (pan_param_)
    virtual_pan_value_ = static_cast<int>(std::floor(pan_param_->get_norm() * (pan_res_ - 1) + 0.5));

  status_display_binding();
}

//------------------------------------------------------------------ status line

std::string Driver::status_prefix()
{
  std::string message = track_name(track_);
  if (dsp_mode_)
    message += fx_index_ >= 0 ? "  " + fx_name(track_, fx_index_) : "  (no FX)";
  if (sticky_mode_)
    message += "  [sticky]";
  return message;
}

void Driver::show_status(const std::string &message)
{
  status_ = message;
  Help_Set(("FaderPort: " + message).c_str(), false);
}

void Driver::status_display_binding()
{
  std::string message = status_prefix();
  if (fader_param_)
    message += "   ^" + fader_param_->name();
  if (pan_param_)
    message += "   >" + pan_param_->name();
  show_status(message);
}

void Driver::status_display_value(Param *param, const char *symbol)
{
  if (!param)
  {
    show_status(status_prefix() + "   n/a");
    return;
  }
  show_status(status_prefix() + "   " + symbol + param->name() + " -> " + param->value_string());
}

//------------------------------------------------------------------------ fader

// handler for received FaderPort fader values
void Driver::on_receive_fader_value(int value, double time)
{
  last_fader_rx_ = time;

  Param *param = fader_param_.get();
  if (!param || !param->valid())
    return;

  double n = static_cast<double>(value) / FADER_MAX;

  // round to exact center value (snap to center)
  if (param->bipolar() && std::fabs(n - 0.5) < 1.0 / 1024)
    n = 0.5;

  // quantize discrete parameters
  if (fader_res_ < 1024)
    n = std::floor(n * (fader_res_ - 1) + 0.5) / (fader_res_ - 1);

  param->set_norm(n);
  fader_editing_ = true;
  status_display_value(param, "^");
}

void Driver::on_fader_touch(bool touched)
{
  fader_touched_ = touched;
  if (!touched)
  {
    if (fader_editing_ && fader_param_ && fader_param_->valid())
      fader_param_->end_edit();
    fader_editing_ = false;
    last_fader_rx_ = -1;
    motor_pos_ = -1; // sync fader with REAPER
  }
}

// GetTouchState(): REAPER asks whether volume/pan of a track are touched
bool Driver::touch_state(MediaTrack *track, int is_pan) const
{
  if (fader_param_ && fader_param_->is_touch_target(track, is_pan))
    return fader_touched_ || fader_editing_ || trim_editing_;
  if (pan_param_ && pan_param_->is_touch_target(track, is_pan))
    return pan_editing_;
  return false;
}

// reset value of the parameter bound to fader to its default value
void Driver::reset_fader_param_to_default()
{
  Param *param = fader_param_.get();
  if (!param || !param->valid())
    return;
  if (!param->has_default())
  {
    show_status(status_prefix() + "   reset to default n/a for FX parameters");
    return;
  }
  param->set_norm(param->default_norm());
  param->end_edit();
  status_display_value(param, "^");
}

// motor fader follows the bound parameter (incl. automation playback)
void Driver::update_motor(double now)
{
  Param *param = fader_param_.get();
  if (!param || !param->valid() || fader_touched_)
    return;
  if (last_fader_rx_ >= 0 && now - last_fader_rx_ < config_.fader_release_timeout)
    return;
  int pos = static_cast<int>(std::floor(param->get_norm() * FADER_MAX + 0.5));
  if (motor_pos_ < 0 || std::abs(pos - motor_pos_) > 1)
  {
    motor_pos_ = pos;
    for (const Message &msg : fader_messages(pos))
      send(msg);
  }
}

// fake release detection for fader (no touch messages without power supply),
// pan and trim (encoders never send touch messages)
void Driver::check_release_timeouts(double now)
{
  if (fader_editing_ && !fader_touched_ && last_fader_rx_ >= 0 &&
      now - last_fader_rx_ > config_.fader_release_timeout)
  {
    fader_editing_ = false;
    if (fader_param_ && fader_param_->valid())
      fader_param_->end_edit();
  }

  if (pan_editing_ && last_pan_rx_ >= 0 && now - last_pan_rx_ > config_.pan_release_timeout)
  {
    pan_editing_ = false;
    if (pan_param_ && pan_param_->valid())
      pan_param_->end_edit();
  }

  if (trim_editing_ && last_trim_rx_ >= 0 && now - last_trim_rx_ > config_.pan_release_timeout)
  {
    trim_editing_ = false;
    if (fader_param_ && fader_param_->valid())
      fader_param_->end_edit();
  }
}

//-------------------------------------------------------------------- pan/trim

// evaluate encoder tick with anti suck handling, returns direction or 0
int Driver::encoder_direction(int value, int &left_count, int &right_count) const
{
  if (value < 63) // turn right
  {
    if (value != PAN_RIGHT || ++right_count < config_.anti_suck_min_turns)
      return 0;
    left_count = right_count = 0;
    return 1;
  }
  // turn left
  if (value != PAN_LEFT || ++left_count < config_.anti_suck_min_turns)
    return 0;
  left_count = right_count = 0;
  return -1;
}

void Driver::on_receive_pan_value(int value, double time)
{
  Param *param = pan_param_.get();
  if (!param || !param->valid())
    return;
  last_pan_rx_ = time;

  int direction = encoder_direction(value, pan_left_count_, pan_right_count_);
  if (direction == 0)
    return;

  // if resolution is low, don't use speed feature at all
  int speed = pan_res_ > 20 ? compute_speed(last_pan_time_, time) : 1;
  last_pan_time_ = time;

  int pan_max_value = pan_res_ - 1;
  virtual_pan_value_ = clamp(virtual_pan_value_ + direction * speed, 0, pan_max_value);

  double n = static_cast<double>(virtual_pan_value_) / pan_max_value;

  // round to exact center value (snap to center)
  if (param->bipolar() && std::fabs(n - 0.5) < 1.0 / (pan_max_value + 1))
    n = 0.5;

  param->set_norm(n);
  pan_editing_ = true;
  status_display_value(param, ">");
}

// shift + pan: fine adjustment of the parameter bound to fader
void Driver::on_receive_trim_value(int value, double time)
{
  Param *param = fader_param_.get();
  if (!param || !param->valid())
    return;
  last_trim_rx_ = time;

  int direction = encoder_direction(value, trim_left_count_, trim_right_count_);
  if (direction == 0)
    return;

  int speed = compute_speed(last_trim_time_, time);
  last_trim_time_ = time;

  param->set_norm(clamp(param->get_norm() + 0.0005 * direction * speed, 0.0, 1.0));
  trim_editing_ = true;
  status_display_value(param, "^");
}

// keep virtual pan value in sync with REAPER while the encoder isn't moved
void Driver::sync_virtual_pan(double now)
{
  Param *param = pan_param_.get();
  if (pan_editing_ || !param || !param->valid())
    return;
  if (last_pan_rx_ >= 0 && now - last_pan_rx_ < config_.pan_release_timeout)
    return;
  virtual_pan_value_ = static_cast<int>(std::floor(param->get_norm() * (pan_res_ - 1) + 0.5));
}

//----------------------------------------------------------------- automation

void Driver::toggle_automation_mode(int mode)
{
  if (!track_valid(track_))
    return;
  int current = GetTrackAutomationMode(track_);
  auto is_write = [](int m) { return m == AUTO_WRITE || m == AUTO_LATCH; };

  // if the mode was already set, toggle to trim/read (off)
  if (current == mode || (is_write(current) && is_write(mode)))
    SetTrackAutomationMode(track_, AUTO_TRIM);
  else
    SetTrackAutomationMode(track_, mode);
  motor_pos_ = -1; // force update in order to be in sync with REAPER
}

//------------------------------------------------------------------ transport

void Driver::toggle_play()
{
  if (is_playing())
    CSurf_OnStop();
  else
    CSurf_OnPlay();
}

// shift time selection by its length (replacement for Renoise loop block move)
void Driver::move_time_selection(int direction)
{
  double start = 0, end = 0;
  GetSet_LoopTimeRange(false, false, &start, &end, false);
  double length = end - start;
  if (length <= 0)
    return;
  double new_start = std::max(0.0, start + direction * length);
  double new_end = new_start + length;
  GetSet_LoopTimeRange(true, false, &new_start, &new_end, false);
}

void Driver::toggle_auto_punch()
{
  if (GetToggleCommandState(CMD_RECMODE_AUTOPUNCH) == 1)
    Main_OnCommand(CMD_RECMODE_NORMAL, 0);
  else
    Main_OnCommand(CMD_RECMODE_AUTOPUNCH, 0);
}

//--------------------------------------------------------------- window views

void Driver::toggle_fx_chain()
{
  if (!track_valid(track_))
    return;
  if (TrackFX_GetChainVisible(track_) != -1)
    TrackFX_Show(track_, 0, 0);
  else if (TrackFX_GetCount(track_) > 0)
    TrackFX_Show(track_, std::max(fx_index_, 0), 1);
  else
    Main_OnCommand(CMD_VIEW_FX_CHAIN, 0);
}

void Driver::toggle_fx_float()
{
  if (!track_valid(track_) || TrackFX_GetCount(track_) == 0)
    return;
  int fx = std::max(fx_index_, 0);
  TrackFX_Show(track_, fx, TrackFX_GetFloatingWindow(track_, fx) ? 2 : 3);
}

// switch sticky mode on/off
void Driver::toggle_sticky_mode()
{
  sticky_mode_ = !sticky_mode_;
  // if switched off, the binding follows the selection again with the next run()
  status_display_binding();
}

void Driver::toggle_master_track()
{
  if (track_valid(track_) && is_master(track_))
  {
    if (track_valid(prev_track_))
      select_track(prev_track_);
  }
  else
  {
    prev_track_ = track_;
    select_track(GetMasterTrack(nullptr));
  }
}

void Driver::navigate_track(int delta)
{
  int count = CountTracks(nullptr);
  if (count == 0)
    return;
  int index;
  if (!track_valid(track_) || is_master(track_))
    index = delta > 0 ? 0 : count - 1;
  else
  {
    int number = static_cast<int>(GetMediaTrackInfo_Value(track_, "IP_TRACKNUMBER"));
    index = wrap(number - 1 + delta, 0, count - 1);
  }
  select_track(GetTrack(nullptr, index));
}

//--------------------------------------------------------------------- lights

void Driver::update_lights()
{
  std::array<bool, LIGHT_COUNT> desired {};

  if (track_valid(track_))
  {
    desired[light::MUTE] = GetMediaTrackInfo_Value(track_, "B_MUTE") == 1;
    desired[light::SOLO] = GetMediaTrackInfo_Value(track_, "I_SOLO") > 0;
    desired[light::REC] = GetMediaTrackInfo_Value(track_, "I_RECARM") == 1;
    desired[light::OUTPUT] = is_master(track_);
    desired[light::PROJ] = TrackFX_GetChainVisible(track_) != -1;

    int mode = GetTrackAutomationMode(track_);
    desired[light::READ] = mode == AUTO_READ;
    desired[light::TOUCH] = mode == AUTO_TOUCH;
    desired[light::WRITE] = mode == AUTO_WRITE || mode == AUTO_LATCH;
  }

  desired[light::BANK] = dsp_mode_;
  desired[light::MIX] = GetToggleCommandState(CMD_TOGGLE_MIXER) == 1;
  desired[light::TRNS] = sticky_mode_;
  desired[light::SHIFT] = shift_pressed_;
  desired[light::PUNCH] = GetToggleCommandState(CMD_RECMODE_AUTOPUNCH) == 1;
  desired[light::USER] = fader_pan_swapped_;
  desired[light::LOOP] = GetSetRepeat(-1) == 1;

  int play_state = GetPlayState();
  desired[light::PLAY] = (play_state & 1) != 0;
  desired[light::STOP] = play_state == 0;
  desired[light::RECORD] = (play_state & 4) != 0;

  // HINT: the OFF light is a momentary light only. Whenever it is on,
  // the FaderPort doesn't send fader values (see handling of the off button)
  for (int nr = 0; nr < LIGHT_COUNT; ++nr)
  {
    int on = (desired[nr] || momentary_[nr]) ? 1 : 0;
    if (light_cache_[nr] != on)
    {
      light_cache_[nr] = on;
      send(light_message(nr, on != 0));
    }
  }
}

//----------------------------------------------------------------- MIDI input

// MIDI message handler, receives messages from FaderPort or emulator
void Driver::midi_callback(const Message &msg, double time)
{
  if (config_.dump_midi)
  {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "received %02X %02X %02X", msg[0], msg[1], msg[2]);
    log(buf);
  }

  int status = msg[0], data1 = msg[1], data2 = msg[2];

  if (status == 0xb0) // fader value
  {
    if (data1 == 0x00)
      last_msb_ = data2; // store msb, wait for lsb
    else if (data1 == 0x20)
      on_receive_fader_value(decode_fader(last_msb_, data2), time);
  }
  else if (status == 0xe0 && data1 == 0x00) // pan and trim value
  {
    if (shift_pressed_)
      on_receive_trim_value(data2, time); // trim parameter bound to fader
    else
      on_receive_pan_value(data2, time);
  }
  else if (status == 0xa0) // buttons
  {
    on_button(data1, data2);
  }
}

void Driver::on_button(int button, int value)
{
  bool pressed = value == 1;
  bool valid = track_valid(track_);

  switch (button)
  {
  case btn::FADER_TOUCH: // fader touch state
    on_fader_touch(pressed);
    break;

  case btn::SHIFT: // transport shift
    shift_pressed_ = pressed;
    break;

  case btn::PLAY: // transport play
    if (pressed)
    {
      if (shift_pressed_)
        CSurf_OnPause();
      else
        toggle_play();
    }
    break;

  case btn::FOOTSWITCH:
    if (value == config_.footswitch_pressed_signal)
      toggle_play();
    break;

  case btn::STOP: // transport stop
    if (pressed)
    {
      if (GetPlayState() != 0)
        CSurf_OnStop();
      else
        Main_OnCommand(CMD_ALL_NOTES_OFF, 0); // panic
    }
    break;

  case btn::RECORD: // transport record
    if (pressed)
      CSurf_OnRecord();
    break;

  case btn::LOOP: // transport loop
    if (pressed && shift_pressed_)
      status_display_binding();
    else if (pressed)
      GetSetRepeat(2); // toggle
    momentary_[light::LOOP] = pressed && shift_pressed_;
    break;

  case btn::PUNCH: // transport punch
    if (pressed)
    {
      if (shift_pressed_)
        move_time_selection(-1);
      else
        toggle_auto_punch();
    }
    break;

  case btn::USER: // transport user: swap fader and pan
    if (pressed && shift_pressed_)
      move_time_selection(1);
    else if (pressed)
      fader_pan_swapped_ = !fader_pan_swapped_;
    momentary_[light::USER] = pressed && shift_pressed_;
    break;

  case btn::REWIND: // transport rewind
    momentary_[light::REWIND] = pressed;
    if (pressed)
    {
      rewind_pressed_ = true;
      if (forward_pressed_)
        reset_fader_param_to_default();
    }
    else if (!forward_pressed_)
    {
      Main_OnCommand(shift_pressed_ ? CMD_PROJECT_START : CMD_PREV_MARKER, 0);
      rewind_pressed_ = false;
    }
    else
    {
      forward_pressed_ = false;
    }
    break;

  case btn::FORWARD: // transport fast forward
    momentary_[light::FORWARD] = pressed;
    if (pressed)
    {
      forward_pressed_ = true;
      if (rewind_pressed_)
        reset_fader_param_to_default();
    }
    else if (!rewind_pressed_)
    {
      Main_OnCommand(shift_pressed_ ? CMD_PROJECT_END : CMD_NEXT_MARKER, 0);
      forward_pressed_ = false;
    }
    else
    {
      rewind_pressed_ = false;
    }
    break;

  case btn::MUTE: // channel mute
    if (pressed && valid)
      SetTrackUIMute(track_, -1, 0);
    break;

  case btn::SOLO: // channel solo
    if (pressed && valid && !is_master(track_))
      SetTrackUISolo(track_, -1, 0);
    break;

  case btn::REC: // channel rec arm
    if (pressed && valid && !is_master(track_))
      SetTrackUIRecArm(track_, -1, 0);
    break;

  case btn::READ: // fader mode read
    if (pressed)
      toggle_automation_mode(AUTO_READ);
    break;

  case btn::TOUCH: // fader mode touch
    if (pressed)
      toggle_automation_mode(AUTO_TOUCH);
    break;

  case btn::WRITE: // fader mode write / latch
    if (pressed)
    {
      bool latch = shift_pressed_;
      if (config_.latch_is_default_write_mode)
        latch = !latch;
      toggle_automation_mode(latch ? AUTO_LATCH : AUTO_WRITE);
    }
    break;

  // fader mode: fader off
  // HINT: as long as the button is pressed the light is switched on.
  // Whenever the light is switched on, no fader values are sent
  // from FaderPort while fader is being moved !
  // This may be helpful for doing fader readjustments in write modes
  // without actually writing values.
  case btn::OFF:
    momentary_[light::OFF] = pressed;
    break;

  case btn::LEFT: // channel select left / right
  case btn::RIGHT:
  {
    int delta = button == btn::LEFT ? -1 : 1;
    momentary_[button == btn::LEFT ? light::LEFT : light::RIGHT] = pressed;
    if (pressed)
    {
      if (!dsp_mode_)
        navigate_track(delta);
      else if (shift_pressed_)
        select_fx_delta(delta); // select FX
      else
        select_binding_delta(delta); // select dsp binding
    }
    break;
  }

  case btn::BANK: // channel select bank: toggle dsp mode
    if (pressed)
    {
      dsp_mode_ = !dsp_mode_;
      int track_number = -1, item_number = -1, fx = -1;
      if (dsp_mode_ && (GetFocusedFX2(&track_number, &item_number, &fx) & 1))
      {
        // take over the currently focused FX
        MediaTrack *track = track_number == 0 ? GetMasterTrack(nullptr) : GetTrack(nullptr, track_number - 1);
        on_focused_fx(track, item_number < 0, fx);
      }
    }
    break;

  case btn::OUTPUT: // channel select output: toggle master track
    if (pressed)
      toggle_master_track();
    break;

  case btn::MIX: // window view mix
    if (pressed)
      Main_OnCommand(CMD_TOGGLE_MIXER, 0);
    break;

  case btn::PROJ: // window view proj: FX chain (shift: floating FX window)
    if (pressed)
    {
      if (shift_pressed_)
        toggle_fx_float();
      else
        toggle_fx_chain();
    }
    break;

  case btn::TRNS: // window view trns: sticky mode (shift: floating FX window)
    if (pressed)
    {
      if (config_.sticky_mode_support && !shift_pressed_)
        toggle_sticky_mode();
      else
        toggle_fx_float();
    }
    break;

  case btn::UNDO: // window view undo / redo
    momentary_[light::UNDO] = pressed;
    if (pressed)
    {
      if (shift_pressed_)
        Undo_DoRedo2(nullptr);
      else
        Undo_DoUndo2(nullptr);
    }
    break;

  default:
    break;
  }
}

} // namespace faderport
