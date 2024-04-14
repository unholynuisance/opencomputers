Controller = require("powerplant-control")

local config = {
    data_dir = "/var/lib/powerplant-control",
    smoothing_factor = 0.05,
    min_time_to_empty = 120,
    min_time_to_full = 10,
}

local controller = Controller.create(config)
controller:stop_on("interrupted")
controller:start()
controller:wait()
