#include "params.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace faderport {

IReaperControlSurface *g_surface = nullptr;

namespace {

double clamp01(double v) { return std::min(1.0, std::max(0.0, v)); }

} // namespace

//--------------------------------------------------------------------- helpers

bool track_valid(MediaTrack *track)
{
  return track && ValidatePtr2(nullptr, track, "MediaTrack*");
}

bool is_master(MediaTrack *track)
{
  return GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") == -1;
}

std::string track_name(MediaTrack *track)
{
  if (!track_valid(track))
    return "n/a";
  if (is_master(track))
    return "MASTER";
  char buf[512] = "";
  GetTrackName(track, buf, sizeof(buf));
  return buf;
}

std::string fx_name(MediaTrack *track, int fx)
{
  char buf[512] = "";
  if (!TrackFX_GetNamedConfigParm(track, fx, "fx_name", buf, sizeof(buf)) || !buf[0])
    TrackFX_GetFXName(track, fx, buf, sizeof(buf));
  return buf;
}

std::string guid_string(const GUID *guid)
{
  if (!guid)
    return "-";
  char buf[64] = "";
  guidToString(guid, buf);
  return buf;
}

bool guid_equal(const GUID *a, const GUID *b)
{
  return a && b && std::memcmp(a, b, sizeof(GUID)) == 0;
}

int find_fx(MediaTrack *track, const GUID *fx_guid, int cached_index)
{
  if (!track_valid(track) || !fx_guid)
    return -1;
  if (cached_index >= 0 && guid_equal(TrackFX_GetFXGUID(track, cached_index), fx_guid))
    return cached_index;
  int count = TrackFX_GetCount(track);
  for (int fx = 0; fx < count; ++fx)
  {
    if (guid_equal(TrackFX_GetFXGUID(track, fx), fx_guid))
      return fx;
  }
  return -1;
}

double vol_to_norm(double vol)
{
  double db = vol > 0 ? 20.0 * std::log10(vol) : -150.0;
  return clamp01(DB2SLIDER(db) / 1000.0);
}

double norm_to_vol(double n)
{
  if (n <= 0)
    return 0;
  return std::pow(10.0, SLIDER2DB(n * 1000.0) / 20.0);
}

//---------------------------------------------------------------- track volume

namespace {

class TrackVolume : public Param
{
public:
  explicit TrackVolume(MediaTrack *track) : track_(track) {}

  bool valid() override { return track_valid(track_); }
  std::string key() override { return "vol:" + guid_string(GetTrackGUID(track_)); }
  std::string name() override { return "Volume"; }

  std::string value_string() override
  {
    double vol = 0, pan = 0;
    GetTrackUIVolPan(track_, &vol, &pan);
    char buf[64] = "";
    mkvolstr(buf, vol);
    return buf;
  }

  double get_norm() override
  {
    double vol = 0, pan = 0;
    GetTrackUIVolPan(track_, &vol, &pan);
    return vol_to_norm(vol);
  }

  void set_norm(double n) override
  {
    double vol = CSurf_OnVolumeChangeEx(track_, norm_to_vol(n), false, true);
    CSurf_SetSurfaceVolume(track_, vol, g_surface);
  }

  bool has_default() const override { return true; }
  double default_norm() const override { return vol_to_norm(1.0); }
  bool is_touch_target(MediaTrack *track, int is_pan) const override { return track == track_ && is_pan == 0; }

private:
  MediaTrack *track_;
};

//------------------------------------------------------------------- track pan

class TrackPan : public Param
{
public:
  explicit TrackPan(MediaTrack *track) : track_(track) {}

  bool valid() override { return track_valid(track_); }
  std::string key() override { return "pan:" + guid_string(GetTrackGUID(track_)); }
  std::string name() override { return "Pan"; }

  std::string value_string() override
  {
    double vol = 0, pan = 0;
    GetTrackUIVolPan(track_, &vol, &pan);
    char buf[64] = "";
    mkpanstr(buf, pan);
    return buf;
  }

  double get_norm() override
  {
    double vol = 0, pan = 0;
    GetTrackUIVolPan(track_, &vol, &pan);
    return clamp01((pan + 1.0) / 2.0);
  }

  void set_norm(double n) override
  {
    double pan = CSurf_OnPanChangeEx(track_, n * 2.0 - 1.0, false, true);
    CSurf_SetSurfacePan(track_, pan, g_surface);
  }

  bool has_default() const override { return true; }
  double default_norm() const override { return 0.5; }
  bool bipolar() const override { return true; }
  bool is_touch_target(MediaTrack *track, int is_pan) const override { return track == track_ && is_pan == 1; }

private:
  MediaTrack *track_;
};

//-------------------------------------------------------------------- FX param

class FxParam : public Param
{
public:
  FxParam(MediaTrack *track, const GUID &fx_guid, int fx_index, int param)
    : track_(track), fx_guid_(fx_guid), fx_(fx_index), param_(param) {}

  bool valid() override
  {
    int fx = resolve();
    return fx >= 0 && param_ < TrackFX_GetNumParams(track_, fx);
  }

  std::string key() override { return "fx:" + guid_string(&fx_guid_) + ":" + std::to_string(param_); }

  std::string name() override
  {
    int fx = resolve();
    if (fx < 0)
      return "n/a";
    char buf[256] = "";
    TrackFX_GetParamName(track_, fx, param_, buf, sizeof(buf));
    return buf;
  }

  std::string value_string() override
  {
    int fx = resolve();
    if (fx < 0)
      return "";
    char buf[256] = "";
    TrackFX_GetFormattedParamValue(track_, fx, param_, buf, sizeof(buf));
    return buf;
  }

  double get_norm() override
  {
    int fx = resolve();
    return fx < 0 ? 0 : clamp01(TrackFX_GetParamNormalized(track_, fx, param_));
  }

  void set_norm(double n) override
  {
    int fx = resolve();
    if (fx >= 0)
      TrackFX_SetParamNormalized(track_, fx, param_, n);
  }

  void end_edit() override
  {
    int fx = resolve();
    if (fx >= 0)
      TrackFX_EndParamEdit(track_, fx, param_);
  }

  int resolution(int def) override
  {
    int fx = resolve();
    if (fx < 0)
      return def;
    double step = 0, small_step = 0, large_step = 0;
    bool is_toggle = false;
    if (!TrackFX_GetParameterStepSizes(track_, fx, param_, &step, &small_step, &large_step, &is_toggle))
      return def;
    if (is_toggle)
      return 2;
    if (step > 0)
    {
      double min_value = 0, max_value = 1;
      TrackFX_GetParam(track_, fx, param_, &min_value, &max_value);
      int steps = static_cast<int>(std::floor((max_value - min_value) / step + 0.5)) + 1;
      if (steps >= 2 && steps < def)
        return steps;
    }
    return def;
  }

private:
  int resolve()
  {
    fx_ = find_fx(track_, &fx_guid_, fx_);
    return fx_;
  }

  MediaTrack *track_;
  GUID fx_guid_;
  int fx_;
  int param_;
};

} // namespace

std::unique_ptr<Param> make_track_volume(MediaTrack *track) { return std::make_unique<TrackVolume>(track); }
std::unique_ptr<Param> make_track_pan(MediaTrack *track) { return std::make_unique<TrackPan>(track); }

std::unique_ptr<Param> make_fx_param(MediaTrack *track, const GUID &fx_guid, int fx_index, int param)
{
  return std::make_unique<FxParam>(track, fx_guid, fx_index, param);
}

} // namespace faderport
