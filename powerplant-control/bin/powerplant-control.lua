local lib = require("nuisance.lib")
local Control = require("powerplant-control")
local Display = require("powerplant-display")

local shell = require("shell")
local args, opts = shell.parse(...)

local control_config = lib.read_config("powerplant-control.cfg")
local control = Control.create(control_config)

local display_config = lib.read_config("powerplant-display.cfg")
local display = Display.create(display_config)

if opts["collect-grid-information"] or opts["i"] then
    control:collect_grid_information()
end

control:stop_on("interrupted")
display:stop_on("interrupted")

control:start()
display:start()

control:wait()
display:wait()
