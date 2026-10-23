/*------------------------------------------------------------------------------------

  FaderPort (classic, native mode) MIDI protocol

  Buttons send  : 0xA0 <button> <0|1>      (poly aftertouch)
  Lights receive: 0xA0 <light>  <0|1>      HINT: light numbers differ from button numbers!
  Fader send    : 0xB0 0x00 <msb>, 0xB0 0x20 <lsb>   value = msb<<3 | lsb>>4 (10 bit)
  Fader receive : 0xB0 0x00 <v>>7>, 0xB0 0x20 <v&127>
  Pan encoder   : 0xE0 0x00 <0x01 = right | 0x7E = left>
  Native mode   : 0x91 0x00 0x64 switches FaderPort from HUI into native mode

  HINT: the fader resolution is 10 bit in both directions. That's a limit of the
  hardware/protocol, not of the driver.

  Copyright 2010-2026 Matthias Ehrmann, Apache License 2.0

------------------------------------------------------------------------------------*/

#pragma once

#include <array>
#include <cstdint>

namespace faderport {

using Message = std::array<uint8_t, 3>;

constexpr int FADER_MAX = 1023;
constexpr int LIGHT_COUNT = 0x18;

constexpr uint8_t PAN_RIGHT = 0x01;
constexpr uint8_t PAN_LEFT = 0x7e;

// button numbers (FaderPort -> host)
namespace btn {
constexpr uint8_t USER = 0x00, PUNCH = 0x01, SHIFT = 0x02, REWIND = 0x03, FORWARD = 0x04,
                  STOP = 0x05, PLAY = 0x06, RECORD = 0x07, TOUCH = 0x08, WRITE = 0x09,
                  READ = 0x0a, MIX = 0x0b, PROJ = 0x0c, TRNS = 0x0d, UNDO = 0x0e, LOOP = 0x0f,
                  REC = 0x10, SOLO = 0x11, MUTE = 0x12, LEFT = 0x13, BANK = 0x14, RIGHT = 0x15,
                  OUTPUT = 0x16, OFF = 0x17, FOOTSWITCH = 0x7e, FADER_TOUCH = 0x7f;
}

// light numbers (host -> FaderPort)
namespace light {
constexpr uint8_t RECORD = 0x00, PLAY = 0x01, STOP = 0x02, FORWARD = 0x03, REWIND = 0x04,
                  SHIFT = 0x05, PUNCH = 0x06, USER = 0x07, LOOP = 0x08, UNDO = 0x09, TRNS = 0x0a,
                  PROJ = 0x0b, MIX = 0x0c, READ = 0x0d, WRITE = 0x0e, TOUCH = 0x0f, OFF = 0x10,
                  OUTPUT = 0x11, RIGHT = 0x12, BANK = 0x13, LEFT = 0x14, MUTE = 0x15, SOLO = 0x16,
                  REC = 0x17;
}

inline Message native_mode_message() { return {0x91, 0x00, 0x64}; }

inline Message light_message(int nr, bool on)
{
  return {0xa0, static_cast<uint8_t>(nr), static_cast<uint8_t>(on ? 1 : 0)};
}

// host -> FaderPort: motor fader position (0..1023)
inline std::array<Message, 2> fader_messages(int value)
{
  return {{{0xb0, 0x00, static_cast<uint8_t>(value >> 7)},
           {0xb0, 0x20, static_cast<uint8_t>(value & 0x7f)}}};
}

// FaderPort -> host: combine msb/lsb of received fader value (0..1023)
inline int decode_fader(int msb, int lsb) { return (msb << 3) | (lsb >> 4); }

// FaderPort -> host encoding (emulator, tests)
inline std::array<Message, 2> encode_fader(int value)
{
  return {{{0xb0, 0x00, static_cast<uint8_t>(value >> 3)},
           {0xb0, 0x20, static_cast<uint8_t>((value & 0x07) << 4)}}};
}

} // namespace faderport
