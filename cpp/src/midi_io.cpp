#include "midi_io.h"

#include "bindings.h" // to_lower
#include "reaper_api.h"

#include <algorithm>

namespace faderport {

namespace {

int find_device(int count, bool (*get_name)(int, char *, int), const std::string &pattern)
{
  std::string lower = to_lower(pattern);
  char name[256];
  for (int i = 0; i < count; ++i)
  {
    name[0] = 0;
    if (get_name(i, name, sizeof(name)) && to_lower(name).find(lower) != std::string::npos)
      return i;
  }
  return -1;
}

} // namespace

bool ReaperMidiPort::open(const std::string &in_name, const std::string &out_name)
{
  close();

  int in_dev = find_device(GetNumMIDIInputs(), GetMIDIInputName, in_name);
  int out_dev = find_device(GetNumMIDIOutputs(), GetMIDIOutputName, out_name);
  if (in_dev < 0 || out_dev < 0)
    return false;

  in_ = CreateMIDIInput(in_dev);
  out_ = CreateMIDIOutput(out_dev, false, nullptr);
  if (!in_ || !out_)
  {
    close();
    return false;
  }
  in_->start();
  last_swap_ = time_precise();
  return true;
}

void ReaperMidiPort::close()
{
  if (in_)
  {
    in_->stop();
    in_->Destroy();
    in_ = nullptr;
  }
  if (out_)
  {
    out_->Destroy();
    out_ = nullptr;
  }
}

void ReaperMidiPort::send(const Message &msg)
{
  if (out_)
    out_->Send(msg[0], msg[1], msg[2], -1);
}

void ReaperMidiPort::poll(std::vector<MidiEvent> &events)
{
  if (!in_)
    return;

  double now = time_precise();
  in_->SwapBufsPrecise(static_cast<unsigned int>(now * 1000.0), now);

  MIDI_eventlist *list = in_->GetReadBuf();
  if (list)
  {
    int pos = 0;
    while (MIDI_event_t *evt = list->EnumItems(&pos))
    {
      if (evt->size < 3)
        continue;
      // frame offsets are in units of 1/1024000 s, relative to the previous swap
      double t = std::min(now, last_swap_ + evt->frame_offset / 1024000.0);
      events.push_back({{evt->midi_message[0], evt->midi_message[1], evt->midi_message[2]}, t});
    }
  }
  last_swap_ = now;
}

} // namespace faderport
