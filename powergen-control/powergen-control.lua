local lib = require("nuisance.lib")
local term = require("term")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")
local batteries = lib.get_proxies("gt_batterybuffer")

local get_grid_info = function(path)
    local file = io.open(path)
    local grid_info = serialization.unserialize(file.read(file, "*a"))
    return grid_info
end

local grid_info = get_grid_info("/etc/grid_info")

while true do
    os.sleep(1)

    local average_input = lib.get_average_input(batteries)
    local average_output = lib.get_average_output(batteries)
    local sensor_information = lib.get_sensor_information(batteries)

    term.clear()

    print(string.format("Average input: %d", average_input))
    print(string.format("Average output: %d", average_output))
    print(serialization.serialize(sensor_information))
    print(serialization.serialize(grid_info))
end
