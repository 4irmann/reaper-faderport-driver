--[[-----------------------------------------------------------------------------------

  FaderPort helper functions

  Copyright 2010-2026 Matthias Ehrmann,

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

-------------------------------------------------------------------------------------]]

local util = {}

function util.clamp(value, min_value, max_value)
  return math.min(max_value, math.max(value, min_value))
end

-- wrap integer value into [min_value, max_value]
function util.wrap(value, min_value, max_value)
  local range = max_value - min_value + 1
  assert(range > 0, "invalid range")
  return (value - min_value) % range + min_value
end

function util.quantize(value, quantum)
  if value >= 0 then
    value = value + quantum / 2
  else
    value = value - quantum / 2
  end
  return math.floor(value / quantum) * quantum
end

-- wall clock in seconds. HINT: os.clock() is CPU time and unusable for timeouts
function util.now()
  return reaper.time_precise()
end

-- debug output to the ReaScript console
util.trace_enabled = false

function util.trace(...)
  if not util.trace_enabled then
    return
  end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  reaper.ShowConsoleMsg("FaderPort: " .. table.concat(parts, " ") .. "\n")
end

function util.log(msg)
  reaper.ShowConsoleMsg("FaderPort: " .. msg .. "\n")
end

return util
