# Airmann's FaderPort Driver for REAPER

A driver for the **PreSonus FaderPort (classic)** in REAPER. It is a port of the Renoise tool
*Airmann's FaderPort Driver*, and it comes in two variants with the same features and button mapping:

| Folder | Variant | When to use it |
|---|---|---|
| [lua/](lua/README.md) | ReaScript (Lua) | No build step and runs on every platform. Has the built-in emulator. |
| [cpp/](cpp/README.md) | Native C++ extension | Native control surface with exact encoder ballistics, `GetTouchState` touch automation, and no MIDI preferences setup. Needs a build. |

Only one variant can run at a time; the two lock each other out. They share their settings through
REAPER's ExtState section `AirmannFaderPort`.

## Tests

```
lua lua/tests/run_tests.lua                    # Lua 5.4
cmake -S cpp -B cpp/build && cmake --build cpp/build && ctest --test-dir cpp/build
```

## License

Apache License 2.0, see [LICENSE.txt](LICENSE.txt).
