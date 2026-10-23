/*------------------------------------------------------------------------------------

  FaderPort parameter abstraction (see params.lua of the Lua variant)

  Track volume/pan are changed via the control surface API (CSurf_On*ChangeEx).
  REAPER asks the surface via GetTouchState() whether they are touched, which
  drives touch/latch automation. FX parameters use TrackFX_SetParamNormalized and
  TrackFX_EndParamEdit at the end of a gesture.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include "reaper_api.h"

#include <memory>
#include <string>

namespace faderport {

// surface that caused a change, excluded from CSurf_SetSurface* notifications
extern IReaperControlSurface *g_surface;

class Param
{
public:
  virtual ~Param() = default;
  virtual bool valid() = 0;
  virtual std::string key() = 0; // identity, used to detect binding changes
  virtual std::string name() = 0;
  virtual std::string value_string() = 0;
  virtual double get_norm() = 0; // 0..1 including automation playback
  virtual void set_norm(double n) = 0; // part of a gesture
  virtual void end_edit() {} // end of gesture
  virtual bool has_default() const { return false; }
  virtual double default_norm() const { return 0; }
  virtual int resolution(int def) { return def; } // number of discrete steps
  virtual bool bipolar() const { return false; } // snap to center
  virtual bool is_touch_target(MediaTrack *, int /*is_pan*/) const { return false; }
};

std::unique_ptr<Param> make_track_volume(MediaTrack *track);
std::unique_ptr<Param> make_track_pan(MediaTrack *track);
std::unique_ptr<Param> make_fx_param(MediaTrack *track, const GUID &fx_guid, int fx_index, int param);

bool track_valid(MediaTrack *track);
bool is_master(MediaTrack *track);
std::string track_name(MediaTrack *track);
std::string fx_name(MediaTrack *track, int fx);
std::string guid_string(const GUID *guid);
bool guid_equal(const GUID *a, const GUID *b);
int find_fx(MediaTrack *track, const GUID *fx_guid, int cached_index); // -1 if not found

double vol_to_norm(double vol);
double norm_to_vol(double n);

} // namespace faderport
