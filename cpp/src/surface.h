/*------------------------------------------------------------------------------------

  FaderPort control surface

  Registered behind the scenes via "csurf_inst", so no entry in REAPER's control
  surface preferences is needed. REAPER calls Run() ~30 times per second and
  asks GetTouchState() for touch/latch automation.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include "driver.h"

namespace faderport {

class Surface : public IReaperControlSurface
{
public:
  explicit Surface(Driver &driver) : driver_(driver) {}

  void set_enabled(bool enabled) { enabled_ = enabled; }
  bool enabled() const { return enabled_; }

  const char *GetTypeString() override { return "FADERPORT4IRMANN"; }
  const char *GetDescString() override { return "4irmann's FaderPort Driver"; }
  const char *GetConfigString() override { return ""; }

  void Run() override
  {
    if (enabled_)
      driver_.run();
  }

  bool GetTouchState(MediaTrack *track, int is_pan) override
  {
    return enabled_ && driver_.touch_state(track, is_pan);
  }

  void ResetCachedVolPanStates() override { driver_.invalidate(); }

  int Extended(int call, void *parm1, void *parm2, void *parm3) override
  {
    switch (call)
    {
    case CSURF_EXT_SETFOCUSEDFX:
      // parm1=(MediaTrack*)track, parm2=(int*)mediaitemidx (may be NULL), parm3=(int*)fxidx
      if (parm1 && parm3)
      {
        bool is_track_fx = !parm2 || *static_cast<int *>(parm2) < 0;
        driver_.on_focused_fx(static_cast<MediaTrack *>(parm1), is_track_fx, *static_cast<int *>(parm3));
      }
      return 1;
    case CSURF_EXT_TRACKFX_PARAMINFO_CHANGED:
      driver_.on_fx_param_info_changed();
      return 1;
    case CSURF_EXT_RESET:
      driver_.invalidate();
      return 1;
    default:
      return 0;
    }
  }

private:
  Driver &driver_;
  bool enabled_ = false;
};

} // namespace faderport
