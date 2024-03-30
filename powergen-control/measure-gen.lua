local table = require("nuisance.table")
local lib = require("nuisance.lib")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")

local generators_information = table.parallel_map(generators, function(_, generator)
    local isWorkAllowed = generator.isWorkAllowed()

    local timeout = 20

    generator.setWorkAllowed(false)

    lib.wait_for_stable_efficiency(generator, timeout)

    generator.setWorkAllowed(true)

    local ramp_time = lib.wait_for_stable_efficiency(generator, timeout)
    local data = lib.get_generator_sensor_information(generator)

    generator.setWorkAllowed(isWorkAllowed)

    data.priority = 0
    data.ramp_time = ramp_time
    return generator.address, data
end)

local grid_information = {
    generators_information = generators_information,
}

local path = "/etc/grid_information"
local file = io.open(path, "w")
file.write(file, serialization.serialize(grid_information))
