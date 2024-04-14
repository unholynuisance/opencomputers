local lib = require("nuisance.lib")
local Control = require("powerplant-control")
local shell = require("shell")

local context = {}

start = function(...)
    local args, opts = shell.parse(...)

    local config = lib.read_config("powerplant-control.cfg")
    context.control = Control.create(config)

    if opts["collect-grid-information"] or opts["i"] then
        context.control:collect_grid_information()
    end

    context.control:start()
    context.control:detach()
end

stop = function()
    context.control:stop()
    context.control:wait()
    context.control = nil
end
