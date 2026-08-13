-- chunkname: core/lib/coreentry.lua

require("core/lib/system/CoreSystem")

if table.contains(Application:argv(), "-slave") then
	require("core/lib/setups/CoreSlaveSetup")
else
	require("lib/Entry")
end
