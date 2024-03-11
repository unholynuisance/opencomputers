local lib = require("lib")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")

local result = table.parallel_vmap(generators, function(generator)
    local isWorkAllowed = generator.isWorkAllowed()

    generator.setWorkAllowed(true)

    lib.wait_for_stable_efficiency(generator, 20)
    local data = lib.get_generator_sensor_information(generator)

    generator.setWorkAllowed(isWorkAllowed)

    data["priority"] = 0
    data["address"] = generator.address
    return data
end)

local path = "/etc/grid_info"
local file = io.open(path, "w")
file.write(file, serialization.serialize(result))
