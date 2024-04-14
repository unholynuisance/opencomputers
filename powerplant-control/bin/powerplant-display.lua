local lib = require("nuisance.lib")
local Display = require("powerplant-display")

local display_config = lib.read_config("powerplant-display.cfg")
local display = Display.create(display_config)

display:stop_on("interrupted")
display:start()
display:wait()
