--[[
  4irmann's FaderPort Driver: action registration (called from Scripts/__startup.lua)

  Written by the Windows installer. Registers the installed Lua scripts listed in
  register_actions.txt in REAPER's action list via the official API and starts the
  Lua driver if "autostart" is listed. Runs on every REAPER start, registering an
  already registered script keeps its command ID.
]]

local dir = reaper.GetResourcePath() .. "/Scripts/reaper-faderport-driver/"

local file = io.open(dir .. "register_actions.txt", "r")
if not file then
  return
end

local scripts, autostart = {}, false
for line in file:lines() do
  line = line:gsub("^%s+", ""):gsub("%s+$", "")
  if line == "autostart" then
    autostart = true
  elseif line ~= "" and not line:match("^#") then
    scripts[#scripts + 1] = line
  end
end
file:close()

local main_id
for _, name in ipairs(scripts) do
  local path = dir .. name
  if reaper.file_exists(path) then
    local id = reaper.AddRemoveReaScript(true, 0, path, true)
    if name == "4irmann_FaderPort.lua" then
      main_id = id
    end
  end
end

if autostart and main_id and main_id ~= 0 then
  reaper.Main_OnCommand(main_id, 0)
end
