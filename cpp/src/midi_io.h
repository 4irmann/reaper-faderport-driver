/*------------------------------------------------------------------------------------

  FaderPort MIDI I/O

  The C++ variant opens the MIDI devices itself (CreateMIDIInput/CreateMIDIOutput),
  like REAPER's own control surfaces. IMPORTANT: the FaderPort must therefore NOT be
  enabled in REAPER's MIDI preferences (opposite of the Lua variant).

  Each received event carries its own time stamp, so the encoder ballistics work
  with the real interval between two ticks.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include "protocol.h"

#include <string>
#include <vector>

class midi_Input;
class midi_Output;

namespace faderport {

struct MidiEvent
{
  Message msg;
  double time; // seconds, time_precise() time base
};

class MidiPort
{
public:
  virtual ~MidiPort() = default;
  virtual bool open(const std::string &in_name, const std::string &out_name) = 0;
  virtual void close() = 0;
  virtual bool is_open() const = 0;
  virtual void send(const Message &msg) = 0;
  virtual void poll(std::vector<MidiEvent> &events) = 0; // appends new events, oldest first
};

class ReaperMidiPort : public MidiPort
{
public:
  ~ReaperMidiPort() override { close(); }

  bool open(const std::string &in_name, const std::string &out_name) override;
  void close() override;
  bool is_open() const override { return in_ && out_; }
  void send(const Message &msg) override;
  void poll(std::vector<MidiEvent> &events) override;

private:
  midi_Input *in_ = nullptr;
  midi_Output *out_ = nullptr;
  double last_swap_ = 0;
};

} // namespace faderport
