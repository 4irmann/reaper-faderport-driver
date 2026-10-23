#include "mock_reaper.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace mock {

namespace {

State g_state;
unsigned long g_guid_counter = 1;

GUID new_guid()
{
  GUID g {};
  g.Data1 = g_guid_counter++;
  return g;
}

Track *tr(MediaTrack *t) { return reinterpret_cast<Track *>(t); }

bool valid_track(void *ptr)
{
  if (ptr == g_state.master.get())
    return true;
  for (auto &t : g_state.tracks)
    if (t.get() == ptr)
      return true;
  return false;
}

std::string ext_key(const char *s, const char *k) { return std::string(s) + "/" + k; }

void copy(char *buf, int sz, const std::string &s)
{
  if (sz > 0)
  {
    std::strncpy(buf, s.c_str(), sz - 1);
    buf[sz - 1] = 0;
  }
}

int toggle_or_set(int old, int v) { return v < 0 ? (old == 0 ? 1 : 0) : v; }

} // namespace

State &state() { return g_state; }

Track *add_track(const std::string &name)
{
  auto t = std::make_unique<Track>();
  t->name = name;
  t->number = static_cast<int>(g_state.tracks.size()) + 1;
  t->guid = new_guid();
  g_state.tracks.push_back(std::move(t));
  return g_state.tracks.back().get();
}

void remove_track(Track *track)
{
  auto &tracks = g_state.tracks;
  tracks.erase(std::remove_if(tracks.begin(), tracks.end(), [track](auto &t) { return t.get() == track; }),
               tracks.end());
  for (size_t i = 0; i < tracks.size(); ++i)
    tracks[i]->number = static_cast<int>(i) + 1;
  g_state.selected.clear();
}

Fx &add_fx(Track *track, const std::string &name, const std::vector<std::string> &params)
{
  Fx fx;
  fx.name = name;
  fx.guid = new_guid();
  for (auto &p : params)
    fx.params.push_back({p, 0.5});
  track->fx.push_back(fx);
  return track->fx.back();
}

void select(Track *track) { g_state.selected = {track}; }
void advance(double seconds) { g_state.now += seconds; }

void install()
{
  g_state = State();
  g_state.master = std::make_unique<Track>();
  g_state.master->name = "MASTER";
  g_state.master->number = -1;
  g_state.master->guid = new_guid();

  time_precise = [] { return g_state.now; };
  ShowConsoleMsg = [](const char *msg) { g_state.console += msg; };
  ClearConsole = [] { g_state.console.clear(); };
  Help_Set = [](const char *s, bool) { g_state.help = s; };
  GetResourcePath = [] { return "/nonexistent"; };

  HasExtState = [](const char *s, const char *k) { return g_state.ext.count(ext_key(s, k)) > 0; };
  GetExtState = [](const char *s, const char *k) -> const char * {
    auto it = g_state.ext.find(ext_key(s, k));
    return it == g_state.ext.end() ? "" : it->second.c_str();
  };
  SetExtState = [](const char *s, const char *k, const char *v, bool) { g_state.ext[ext_key(s, k)] = v; };
  DeleteExtState = [](const char *s, const char *k, bool) { g_state.ext.erase(ext_key(s, k)); };

  EnumProjects = [](int, char *, int) { return reinterpret_cast<ReaProject *>(&g_state); };
  CountTracks = [](ReaProject *) { return static_cast<int>(g_state.tracks.size()); };
  GetTrack = [](ReaProject *, int i) -> MediaTrack * {
    return i >= 0 && i < static_cast<int>(g_state.tracks.size()) ? mt(g_state.tracks[i].get()) : nullptr;
  };
  GetMasterTrack = [](ReaProject *) { return mt(g_state.master.get()); };
  ValidatePtr2 = [](ReaProject *, void *ptr, const char *) { return valid_track(ptr); };
  GetTrackGUID = [](MediaTrack *t) { return &tr(t)->guid; };
  guidToString = [](const GUID *g, char *dest) { std::snprintf(dest, 64, "{%08lx}", static_cast<unsigned long>(g->Data1)); };
  GetTrackName = [](MediaTrack *t, char *buf, int sz) { copy(buf, sz, tr(t)->name); return true; };
  GetSelectedTrack2 = [](ReaProject *, int i, bool want_master) -> MediaTrack * {
    if (i >= static_cast<int>(g_state.selected.size()))
      return nullptr;
    Track *t = g_state.selected[i];
    if (t == g_state.master.get() && !want_master)
      return nullptr;
    return mt(t);
  };
  SetOnlyTrackSelected = [](MediaTrack *t) { g_state.selected = {tr(t)}; };
  SetMixerScroll = [](MediaTrack *t) { return t; };
  GetMediaTrackInfo_Value = [](MediaTrack *t, const char *key) -> double {
    std::string k = key;
    if (k == "IP_TRACKNUMBER") return tr(t)->number;
    if (k == "B_MUTE") return tr(t)->mute;
    if (k == "I_SOLO") return tr(t)->solo;
    if (k == "I_RECARM") return tr(t)->arm;
    return 0;
  };
  GetTrackUIVolPan = [](MediaTrack *t, double *vol, double *pan) {
    *vol = tr(t)->vol;
    *pan = tr(t)->pan;
    return true;
  };
  CSurf_OnVolumeChangeEx = [](MediaTrack *t, double vol, bool, bool) {
    tr(t)->vol = vol;
    tr(t)->vol_calls.push_back(vol);
    return vol;
  };
  CSurf_OnPanChangeEx = [](MediaTrack *t, double pan, bool, bool) {
    tr(t)->pan = pan;
    tr(t)->pan_calls.push_back(pan);
    return pan;
  };
  CSurf_SetSurfaceVolume = [](MediaTrack *, double, IReaperControlSurface *) {};
  CSurf_SetSurfacePan = [](MediaTrack *, double, IReaperControlSurface *) {};
  SetTrackUIMute = [](MediaTrack *t, int v, int) { return tr(t)->mute = toggle_or_set(tr(t)->mute, v); };
  SetTrackUISolo = [](MediaTrack *t, int v, int) { return tr(t)->solo = toggle_or_set(tr(t)->solo, v); };
  SetTrackUIRecArm = [](MediaTrack *t, int v, int) { return tr(t)->arm = toggle_or_set(tr(t)->arm, v); };
  GetTrackAutomationMode = [](MediaTrack *t) { return tr(t)->automode; };
  SetTrackAutomationMode = [](MediaTrack *t, int m) { tr(t)->automode = m; };

  TrackFX_GetCount = [](MediaTrack *t) { return static_cast<int>(tr(t)->fx.size()); };
  TrackFX_GetFXGUID = [](MediaTrack *t, int i) -> GUID * {
    return i >= 0 && i < static_cast<int>(tr(t)->fx.size()) ? &tr(t)->fx[i].guid : nullptr;
  };
  TrackFX_GetFXName = [](MediaTrack *t, int i, char *buf, int sz) { copy(buf, sz, "VST: " + tr(t)->fx[i].name); return true; };
  TrackFX_GetNamedConfigParm = [](MediaTrack *t, int i, const char *key, char *buf, int sz) {
    if (std::string(key) != "fx_name")
      return false;
    copy(buf, sz, "VST: " + tr(t)->fx[i].name);
    return true;
  };
  TrackFX_GetNumParams = [](MediaTrack *t, int i) { return static_cast<int>(tr(t)->fx[i].params.size()); };
  TrackFX_GetParamName = [](MediaTrack *t, int i, int p, char *buf, int sz) {
    copy(buf, sz, tr(t)->fx[i].params[p].name);
    return true;
  };
  TrackFX_GetParamNormalized = [](MediaTrack *t, int i, int p) { return tr(t)->fx[i].params[p].value; };
  TrackFX_SetParamNormalized = [](MediaTrack *t, int i, int p, double v) {
    tr(t)->fx[i].params[p].value = v;
    return true;
  };
  TrackFX_EndParamEdit = [](MediaTrack *, int, int) {
    ++g_state.end_edits;
    return true;
  };
  TrackFX_GetFormattedParamValue = [](MediaTrack *t, int i, int p, char *buf, int sz) {
    char tmp[32];
    std::snprintf(tmp, sizeof(tmp), "%.2f", tr(t)->fx[i].params[p].value);
    copy(buf, sz, tmp);
    return true;
  };
  TrackFX_GetParameterStepSizes = [](MediaTrack *, int, int, double *, double *, double *, bool *) { return false; };
  TrackFX_GetParam = [](MediaTrack *t, int i, int p, double *mn, double *mx) {
    *mn = 0;
    *mx = 1;
    return tr(t)->fx[i].params[p].value;
  };
  TrackFX_GetChainVisible = [](MediaTrack *t) { return tr(t)->chain_visible; };
  TrackFX_Show = [](MediaTrack *t, int i, int flag) {
    if (flag == 1) tr(t)->chain_visible = i;
    else if (flag == 0) tr(t)->chain_visible = -1;
  };
  TrackFX_GetFloatingWindow = [](MediaTrack *, int) -> HWND { return nullptr; };
  GetFocusedFX2 = [](int *track, int *item, int *fx) {
    *track = g_state.focused_track;
    *item = g_state.focused_item;
    *fx = g_state.focused_fx;
    return g_state.focused_retval;
  };

  GetPlayState = [] { return g_state.play_state; };
  CSurf_OnPlay = [] { g_state.play_state = 1; };
  CSurf_OnStop = [] { g_state.play_state = 0; };
  CSurf_OnPause = [] { g_state.play_state = 2; };
  CSurf_OnRecord = [] { g_state.play_state = g_state.play_state == 5 ? 0 : 5; };
  GetSetRepeat = [](int v) {
    if (v == 2) g_state.repeat_state = 1 - g_state.repeat_state;
    else if (v >= 0) g_state.repeat_state = v;
    return g_state.repeat_state;
  };
  GetSet_LoopTimeRange = [](bool is_set, bool, double *s, double *e, bool) {
    if (is_set)
    {
      g_state.loop_start = *s;
      g_state.loop_end = *e;
    }
    *s = g_state.loop_start;
    *e = g_state.loop_end;
  };
  GetToggleCommandState = [](int cmd) {
    auto it = g_state.toggles.find(cmd);
    return it == g_state.toggles.end() ? 0 : it->second;
  };
  Main_OnCommand = [](int cmd, int) {
    g_state.commands.push_back(cmd);
    if (cmd == 40078) g_state.toggles[cmd] = 1 - g_state.toggles[cmd];
    else if (cmd == 40076) g_state.toggles[40076] = 1;
    else if (cmd == 40252) g_state.toggles[40076] = 0;
  };
  Undo_DoUndo2 = [](ReaProject *) { return ++g_state.undo; };
  Undo_DoRedo2 = [](ReaProject *) { return ++g_state.redo; };

  // volume helpers (simplified, but invertible)
  SLIDER2DB = [](double y) { return y / 1000 * 162 - 150; };
  DB2SLIDER = [](double db) { return (db + 150) / 162 * 1000; };
  mkvolstr = [](char *buf, double vol) { std::snprintf(buf, 64, "%.2fdB", vol > 0 ? 20 * std::log10(vol) : -150.0); };
  mkpanstr = [](char *buf, double pan) { std::snprintf(buf, 64, "%.0f%%", pan * 100); };

  GetNumMIDIInputs = [] { return 0; };
  GetNumMIDIOutputs = [] { return 0; };
  GetMIDIInputName = [](int, char *, int) { return false; };
  GetMIDIOutputName = [](int, char *, int) { return false; };
  CreateMIDIInput = [](int) -> midi_Input * { return nullptr; };
  CreateMIDIOutput = [](int, bool, int *) -> midi_Output * { return nullptr; };
}

} // namespace mock
