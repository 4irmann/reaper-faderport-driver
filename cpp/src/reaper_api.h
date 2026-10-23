/*------------------------------------------------------------------------------------

  REAPER API used by the FaderPort driver

  Only the functions listed here are loaded (REAPERAPI_MINIMAL). The unit tests
  assign mock implementations to the same function pointers.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#define REAPERAPI_MINIMAL

#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_CreateMIDIInput
#define REAPERAPI_WANT_CreateMIDIOutput
#define REAPERAPI_WANT_CSurf_OnPanChangeEx
#define REAPERAPI_WANT_CSurf_OnPause
#define REAPERAPI_WANT_CSurf_OnPlay
#define REAPERAPI_WANT_CSurf_OnRecord
#define REAPERAPI_WANT_CSurf_OnStop
#define REAPERAPI_WANT_CSurf_OnVolumeChangeEx
#define REAPERAPI_WANT_CSurf_SetSurfacePan
#define REAPERAPI_WANT_CSurf_SetSurfaceVolume
#define REAPERAPI_WANT_ClearConsole
#define REAPERAPI_WANT_DB2SLIDER
#define REAPERAPI_WANT_DeleteExtState
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_guidToString
#define REAPERAPI_WANT_GetFocusedFX2
#define REAPERAPI_WANT_GetMasterTrack
#define REAPERAPI_WANT_GetMediaTrackInfo_Value
#define REAPERAPI_WANT_GetMIDIInputName
#define REAPERAPI_WANT_GetMIDIOutputName
#define REAPERAPI_WANT_GetNumMIDIInputs
#define REAPERAPI_WANT_GetNumMIDIOutputs
#define REAPERAPI_WANT_GetPlayState
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_GetSelectedTrack2
#define REAPERAPI_WANT_GetSet_LoopTimeRange
#define REAPERAPI_WANT_GetSetRepeat
#define REAPERAPI_WANT_GetToggleCommandState
#define REAPERAPI_WANT_GetTrack
#define REAPERAPI_WANT_GetTrackAutomationMode
#define REAPERAPI_WANT_GetTrackGUID
#define REAPERAPI_WANT_GetTrackName
#define REAPERAPI_WANT_GetTrackUIVolPan
#define REAPERAPI_WANT_HasExtState
#define REAPERAPI_WANT_Help_Set
#define REAPERAPI_WANT_Main_OnCommand
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_SetMixerScroll
#define REAPERAPI_WANT_SetOnlyTrackSelected
#define REAPERAPI_WANT_SetTrackAutomationMode
#define REAPERAPI_WANT_SetTrackUIMute
#define REAPERAPI_WANT_SetTrackUIRecArm
#define REAPERAPI_WANT_SetTrackUISolo
#define REAPERAPI_WANT_ShowConsoleMsg
#define REAPERAPI_WANT_SLIDER2DB
#define REAPERAPI_WANT_TrackFX_EndParamEdit
#define REAPERAPI_WANT_TrackFX_GetChainVisible
#define REAPERAPI_WANT_TrackFX_GetCount
#define REAPERAPI_WANT_TrackFX_GetFloatingWindow
#define REAPERAPI_WANT_TrackFX_GetFormattedParamValue
#define REAPERAPI_WANT_TrackFX_GetFXGUID
#define REAPERAPI_WANT_TrackFX_GetFXName
#define REAPERAPI_WANT_TrackFX_GetNamedConfigParm
#define REAPERAPI_WANT_TrackFX_GetNumParams
#define REAPERAPI_WANT_TrackFX_GetParam
#define REAPERAPI_WANT_TrackFX_GetParameterStepSizes
#define REAPERAPI_WANT_TrackFX_GetParamName
#define REAPERAPI_WANT_TrackFX_GetParamNormalized
#define REAPERAPI_WANT_TrackFX_SetParamNormalized
#define REAPERAPI_WANT_TrackFX_Show
#define REAPERAPI_WANT_Undo_DoRedo2
#define REAPERAPI_WANT_Undo_DoUndo2
#define REAPERAPI_WANT_ValidatePtr2
#define REAPERAPI_WANT_mkpanstr
#define REAPERAPI_WANT_mkvolstr
#define REAPERAPI_WANT_time_precise

#include "reaper_plugin.h"
#include "reaper_plugin_functions.h"
