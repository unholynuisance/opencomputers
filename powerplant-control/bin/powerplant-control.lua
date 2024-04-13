Controller = require("powerplant-control")

local controller = Controller.create()
controller:stop_on("interrupted")
controller:start()
controller:wait()
