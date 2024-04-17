local lib = require("nuisance.lib")
local Control = require("fuel-control")

local shell = require("shell")
local args, opts = shell.parse(...)

local control_config = lib.read_config("fuel-control.cfg")
local control = Control.create(control_config)

if opts["regenerate-fluid-database"] or opts["r"] then
    control:regenerate_fluid_database()
end

control:stop_on("interrupted")
control:start()
control:detach()
control:wait()
