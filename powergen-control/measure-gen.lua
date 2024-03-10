local lib = require("lib")

local os = require("os")
local component = require("component")
local term = require("term")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")

local result = table.thread_map(generators, function(key, generator)
    local active = generator.isMachineActive()
    ---if not active do
    ---  generator.setWorkAllowed(true)
    ---end
    generator.setWorkAllowed(true)

    lib.wait_for_stable_efficiency(generator, 20)

    local data = lib.get_generator_sensor_information(generator)
    if not active then
        generator.setWorkAllowed(false)
    end

    os.sleep()
    data["priority"] = 0
    data["address"] = generator.address
    return key, data
end)

local path = "/etc/grid_info"
local file = io.open(path, "w")
file.write(file, serialization.serialize(result))
