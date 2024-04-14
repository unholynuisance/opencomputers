local lib = require("nuisance.lib")
local Controller = require("powerplant-control")
local Display = require("powerplant-display")

local shell = require("shell")

local args, opts = shell.parse(...)

local controller = Controller.create({
    data_dir = "/var/lib/powerplant-control",
    smoothing_factor = 0.05,
    min_time_to_empty = 120,
    min_time_to_full = 10,
    display_address = "localhost",
    display_port = 999,
    display_delay = 0.1,
})

local display = Display.create({
    port = 999,
})

if opts["collect-grid-information"] or opts["c"] then
    controller:collect_grid_information()
end

controller:stop_on("interrupted")
display:stop_on("interrupted")

controller:start()
display:start()

controller:wait()
display:wait()
