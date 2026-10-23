/*------------------------------------------------------------------------------------

  Airmann's FaderPort Driver for REAPER (C++ extension)

  Entry point: loads the REAPER API, registers the control surface instance,
  actions and the ReaScript API used by the emulator window of the Lua variant
  ("Airmann_FaderPort - C++ emulator.lua").

  Copyright 2010-2026 Matthias Ehrmann,

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

------------------------------------------------------------------------------------*/

#include "surface.h"

#include <cstdio>
#include <memory>
#include <string>

using namespace faderport;

namespace {

reaper_plugin_info_t *g_rec = nullptr;
std::unique_ptr<Driver> g_driver;
std::unique_ptr<Surface> g_surface_instance;
bool g_dump_midi = false;

int g_cmd_toggle = 0;
int g_cmd_reset = 0;
int g_cmd_dump = 0;
int g_cmd_fx_info = 0;

// emulator bridge
int g_emu_sink = 0;
std::string g_emu_queue; // pending messages for the emulator, 6 hex chars each
std::string g_emu_out;
std::string g_status_out;
constexpr size_t EMU_QUEUE_MAX = 6 * 8192;

bool lua_driver_running()
{
  const char *running = GetExtState(Config::SECTION, "running");
  return running && std::string(running) == "1";
}

void set_enabled(bool enabled)
{
  if (enabled && lua_driver_running())
  {
    ShowConsoleMsg("FaderPort: the Lua driver is running. Stop it before enabling the C++ driver.\n");
    return;
  }
  if (!enabled && g_surface_instance->enabled())
  {
    g_driver->shutdown();
    Help_Set("", false);
  }
  g_surface_instance->set_enabled(enabled);
  if (enabled)
    SetExtState(Config::SECTION, "running_cpp", "1", false);
  else
    DeleteExtState(Config::SECTION, "running_cpp", false);
  SetExtState(Config::SECTION, "cpp_enabled", enabled ? "true" : "false", true);
}

void show_fx_info()
{
  MediaTrack *track = nullptr;
  int fx = -1;
  int track_number = -1, item_number = -1, fx_number = -1;
  if ((GetFocusedFX2(&track_number, &item_number, &fx_number) & 1) && item_number < 0 && fx_number < 0x1000000)
  {
    track = track_number == 0 ? GetMasterTrack(nullptr) : GetTrack(nullptr, track_number - 1);
    fx = fx_number;
  }
  else if ((track = GetSelectedTrack2(nullptr, 0, true)) && TrackFX_GetCount(track) > 0)
  {
    fx = 0;
  }

  ClearConsole();
  if (!track || fx < 0)
    ShowConsoleMsg("FaderPort: focus an FX window or select a track with FX.\n");
  else
    ShowConsoleMsg(g_driver->describe_fx(track, fx).c_str());
}

bool on_action(KbdSectionInfo *, int command, int, int, int, HWND)
{
  if (command == 0)
    return false;
  if (command == g_cmd_toggle)
  {
    set_enabled(!g_surface_instance->enabled());
    return true;
  }
  if (command == g_cmd_reset)
  {
    if (g_surface_instance->enabled())
      g_driver->reset();
    return true;
  }
  if (command == g_cmd_dump)
  {
    g_dump_midi = !g_dump_midi;
    g_driver->set_dump_midi(g_dump_midi);
    SetExtState(Config::SECTION, "dump_midi", g_dump_midi ? "true" : "false", true);
    return true;
  }
  if (command == g_cmd_fx_info)
  {
    show_fx_info();
    return true;
  }
  return false;
}

int toggle_state(int command)
{
  if (command == 0)
    return -1;
  if (command == g_cmd_toggle)
    return g_surface_instance->enabled() ? 1 : 0;
  if (command == g_cmd_dump)
    return g_dump_midi ? 1 : 0;
  return -1;
}

int register_action(const char *id, const char *name)
{
  custom_action_register_t action = {0, id, name, nullptr};
  return g_rec->Register("custom_action", &action);
}

//------------------------------------------------------------- emulator bridge

void AirmannFaderPort_EmuSend(int status, int data1, int data2)
{
  if (g_driver && g_surface_instance->enabled())
    g_driver->midi_callback({static_cast<uint8_t>(status), static_cast<uint8_t>(data1),
                             static_cast<uint8_t>(data2)}, time_precise());
}

const char *AirmannFaderPort_EmuReceive()
{
  g_emu_out.swap(g_emu_queue);
  g_emu_queue.clear();
  return g_emu_out.c_str();
}

void AirmannFaderPort_EmuAttach(bool attach)
{
  if (attach && !g_emu_sink)
  {
    g_emu_sink = g_driver->add_sink([](const Message &msg) {
      if (g_emu_queue.size() >= EMU_QUEUE_MAX)
        return;
      char buf[8];
      std::snprintf(buf, sizeof(buf), "%02x%02x%02x", msg[0], msg[1], msg[2]);
      g_emu_queue += buf;
    });
  }
  else if (!attach && g_emu_sink)
  {
    g_driver->remove_sink(g_emu_sink);
    g_emu_sink = 0;
    g_emu_queue.clear();
  }
  if (attach)
    g_driver->invalidate(); // resend lights and fader position
}

const char *AirmannFaderPort_GetStatus()
{
  g_status_out = g_surface_instance->enabled() ? g_driver->status() : "C++ driver disabled";
  return g_status_out.c_str();
}

bool AirmannFaderPort_IsHardwareConnected()
{
  return g_surface_instance->enabled() && g_driver->hardware_connected();
}

void *EmuSend_vararg(void **args, int)
{
  AirmannFaderPort_EmuSend(static_cast<int>(reinterpret_cast<INT_PTR>(args[0])),
                           static_cast<int>(reinterpret_cast<INT_PTR>(args[1])),
                           static_cast<int>(reinterpret_cast<INT_PTR>(args[2])));
  return nullptr;
}

void *EmuReceive_vararg(void **, int)
{
  return const_cast<char *>(AirmannFaderPort_EmuReceive());
}

void *EmuAttach_vararg(void **args, int)
{
  AirmannFaderPort_EmuAttach(reinterpret_cast<INT_PTR>(args[0]) != 0);
  return nullptr;
}

void *GetStatus_vararg(void **, int)
{
  return const_cast<char *>(AirmannFaderPort_GetStatus());
}

void *IsHardwareConnected_vararg(void **, int)
{
  return reinterpret_cast<void *>(static_cast<INT_PTR>(AirmannFaderPort_IsHardwareConnected()));
}

#define REGISTER_API(name, def)                                                        \
  g_rec->Register("API_" #name, reinterpret_cast<void *>(&name));                     \
  g_rec->Register("APIdef_" #name, const_cast<char *>(def));                           \
  g_rec->Register("APIvararg_" #name, reinterpret_cast<void *>(&name##_vararg_impl))

// vararg names expected by REGISTER_API
#define AirmannFaderPort_EmuSend_vararg_impl EmuSend_vararg
#define AirmannFaderPort_EmuReceive_vararg_impl EmuReceive_vararg
#define AirmannFaderPort_EmuAttach_vararg_impl EmuAttach_vararg
#define AirmannFaderPort_GetStatus_vararg_impl GetStatus_vararg
#define AirmannFaderPort_IsHardwareConnected_vararg_impl IsHardwareConnected_vararg

void register_api()
{
  REGISTER_API(AirmannFaderPort_EmuSend,
               "void\0int,int,int\0status,data1,data2\0FaderPort emulator: send a FaderPort MIDI message to the C++ driver.");
  REGISTER_API(AirmannFaderPort_EmuReceive,
               "const char*\0\0\0FaderPort emulator: messages the C++ driver sent since the last call, 6 hex chars each.");
  REGISTER_API(AirmannFaderPort_EmuAttach,
               "void\0bool\0attach\0FaderPort emulator: start/stop receiving messages of the C++ driver.");
  REGISTER_API(AirmannFaderPort_GetStatus,
               "const char*\0\0\0FaderPort: status line of the C++ driver.");
  REGISTER_API(AirmannFaderPort_IsHardwareConnected,
               "bool\0\0\0FaderPort: true if the C++ driver is connected to the hardware.");
}

void unload()
{
  if (!g_rec)
    return;
  if (g_surface_instance)
  {
    if (g_surface_instance->enabled())
      g_driver->shutdown();
    DeleteExtState(Config::SECTION, "running_cpp", false);
    g_rec->Register("-csurf_inst", g_surface_instance.get());
  }
  g_rec->Register("-hookcommand2", reinterpret_cast<void *>(&on_action));
  g_rec->Register("-toggleaction", reinterpret_cast<void *>(&toggle_state));
  g_surface = nullptr;
  g_surface_instance.reset();
  g_driver.reset();
  g_rec = nullptr;
}

} // namespace

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t *rec)
{
  if (!rec)
  {
    unload();
    return 0;
  }
  if (rec->caller_version != REAPER_PLUGIN_VERSION || !rec->GetFunc)
    return 0;
  if (REAPERAPI_LoadAPI(rec->GetFunc) != 0)
    return 0; // REAPER too old, some API functions are missing

  g_rec = rec;

  Config config;
  config.load();
  g_dump_midi = config.dump_midi;

  g_driver = std::make_unique<Driver>(config, Bindings::load(), std::make_unique<ReaperMidiPort>());
  g_surface_instance = std::make_unique<Surface>(*g_driver);
  g_surface = g_surface_instance.get();

  g_cmd_toggle = register_action("AIRMANN_FADERPORT_TOGGLE", "Airmann FaderPort (C++): Enable/disable driver");
  g_cmd_reset = register_action("AIRMANN_FADERPORT_RESET", "Airmann FaderPort (C++): Reset");
  g_cmd_dump = register_action("AIRMANN_FADERPORT_DUMP", "Airmann FaderPort (C++): Toggle MIDI dump");
  g_cmd_fx_info = register_action("AIRMANN_FADERPORT_FX_INFO", "Airmann FaderPort (C++): Show FX parameters");
  rec->Register("hookcommand2", reinterpret_cast<void *>(&on_action));
  rec->Register("toggleaction", reinterpret_cast<void *>(&toggle_state));

  register_api();
  rec->Register("csurf_inst", g_surface_instance.get());

  const char *enabled = GetExtState(Config::SECTION, "cpp_enabled");
  set_enabled(!HasExtState(Config::SECTION, "cpp_enabled") || (enabled && std::string(enabled) == "true"));
  return 1;
}
