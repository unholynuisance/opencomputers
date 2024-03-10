local lib = require("lib")

local os = require("os")
local component = require("component")
local term = require("term")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")

local get_gen_data = function(generator)
    return lib.parse_generator_sensor_information(generator.getSensorInformation())
end

local result = table.thread_map(generators, function(key, generator)
    local active = generator.isMachineActive()
    local prev_time = lib.get_time_seconds() + 3
    ---if not active do
    ---  generator.setWorkAllowed(true)
    ---end
    generator.setWorkAllowed(true)
    local eff_prev = get_gen_data(generator).efficiency
    os.sleep()

    while true do
        local now = lib.get_time_seconds()
        local eff_now = get_gen_data(generator).efficiency
        if prev_time + 5 >= now and eff_prev == eff_now then
            break
        end
        eff_prev = eff_now
        prev_time = now
        os.sleep()
    end

    local data = get_gen_data(generator)
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
