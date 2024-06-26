local table = require("nuisance.table")
local component = require("component")
local os = require("os")

local serialization = require("serialization")
local filesystem = require("filesystem")

local lib = {}

lib.write_file = function(path, contents)
    filesystem.makeDirectory(filesystem.path(path))

    local file = io.open(path, "w")
    return file and file:write(contents) or error("Could not open file for writing")
end

lib.read_file = function(path)
    local file = io.open(path, "r")
    return file and file:read("*a") or error("Could not open file for reading")
end

lib.write_table = function(path, t)
    local contents = serialization.serialize(t)
    return lib.write_file(path, contents)
end

lib.read_table = function(path)
    local contents = lib.read_file(path)
    return serialization.unserialize(contents)
end

lib.write_config = function(config, filename, dir)
    dir = dir or "/etc"

    local path = filesystem.concat(dir, filename)
    local contents = serialization.serialize(config)
    return lib.write_file(path, contents)
end

lib.read_config = function(filename, dir)
    dir = dir or "/etc"

    local path = filesystem.concat(dir, filename)
    local contents = lib.read_file(path)
    return serialization.unserialize(contents)
end

lib.get_ticks = function()
    return math.floor(os.time(os.date("!*t")) * 1000 / 60 / 60 - 6000)
end

lib.ticks_to_seconds = function(ticks)
    return ticks / 20
end

lib.ticks_to_whole_seconds = function(ticks)
    return math.floor(ticks)
end

lib.get_seconds = function()
    return lib.ticks_to_seconds(lib.get_ticks())
end

lib.get_whole_seconds = function()
    return lib.ticks_to_whole_seconds(lib.get_ticks())
end

lib.get_proxy = function(type)
    return component.getPrimary(type)
end

lib.get_proxies = function(filter)
    local components = table.keys(component.list(filter))
    return table.vmap(components, component.proxy)
end

lib.get_average_input = function(batteries)
    return table.vsum(table.vmap(batteries, function(v)
        return v.getAverageElectricInput()
    end))
end

lib.get_average_output = function(batteries)
    return table.vsum(table.vmap(batteries, function(v)
        return v.getAverageElectricOutput()
    end))
end

lib.parse_battery_sensor_information = function(sensor_information)
    local function parse_number(s)
        s = string.gsub(s, ",", "")
        return tonumber(s)
    end

    local name = string.match(sensor_information[1], "§9(.-)§r")
    local energy = parse_number(string.match(sensor_information[3], "§a([%d,]-)§r"))
    local max_energy = parse_number(string.match(sensor_information[3], "§e([%d,]-)§r"))
    local average_input = parse_number(string.match(sensor_information[5], "([%d,]-) EU/t"))
    local average_output = parse_number(string.match(sensor_information[7], "([%d,]-) EU/t"))

    return {
        name = name,
        energy = energy,
        max_energy = max_energy,
        average_input = average_input,
        average_output = average_output,
    }
end

lib.get_sensor_information = function(proxy, parser)
    return parser(proxy.getSensorInformation())
end

lib.parse_generator_sensor_information = function(sensor_information)
    local function parse_number(s)
        s = string.gsub(s, ",", "")
        return tonumber(s)
    end

    local name = string.match(sensor_information[1], "§9(.-)§r")
    local energy = parse_number(string.match(sensor_information[2], "§a([%d,]-)§r"))
    local max_energy = parse_number(string.match(sensor_information[2], "§e([%d,]-)§r"))
    local maintenance = string.match(sensor_information[3], "§a([%a]-)§r")
    local output = parse_number(string.match(sensor_information[4], "§c([%d,]-)§r"))
    local consumption = parse_number(string.match(sensor_information[5], "§e([%d,]-)§r"))
    local fuel_value = parse_number(string.match(sensor_information[6], "§e([%d,]-)§r"))
    local fuel_remaining = parse_number(string.match(sensor_information[7], "§6([%d,]-)§r"))
    local efficiency = parse_number(string.match(sensor_information[8], "§e([%d,.]-)§e"))
    local pollution = parse_number(string.match(sensor_information[9], "§a([%d,]-)§r"))

    return {
        name = name,
        energy = energy,
        max_energy = max_energy,
        maintenance = not maintenance == "No Maintenance issues",
        output = output,
        consumption = consumption,
        fuel_value = fuel_value,
        fuel_remaining = fuel_remaining,
        efficiency = efficiency,
        pollution = pollution,
    }
end

lib.get_generator_sensor_information = function(generator)
    return lib.get_sensor_information(generator, lib.parse_generator_sensor_information)
end

lib.get_battery_sensor_information = function(battery)
    return lib.get_sensor_information(battery, lib.parse_battery_sensor_information)
end

lib.wait_for_zero_efficiency = function(generator)
    local start_time = lib.get_ticks()
    local current_time = start_time

    repeat
        os.sleep(0)

        local current_efficiency = lib.get_generator_sensor_information(generator).efficiency
        local current_time = lib.get_ticks()

    until current_efficiency == 0

    return lib.ticks_to_seconds(current_time - start_time)
end

lib.wait_for_stable_efficiency = function(generator, timeout)
    local start_time = lib.get_ticks()

    local last_efficiency = lib.get_generator_sensor_information(generator).efficiency
    local last_efficiency_change_time = lib.get_ticks()

    repeat
        os.sleep(0)

        local current_efficiency = lib.get_generator_sensor_information(generator).efficiency
        local current_time = lib.get_ticks()

        if current_efficiency ~= last_efficiency then
            last_efficiency = current_efficiency
            last_efficiency_change_time = current_time
        end
    until current_time - last_efficiency_change_time > timeout

    return lib.ticks_to_seconds(last_efficiency_change_time - start_time)
end

lib.get_generator_information = function(generator)
    local information = lib.get_generator_sensor_information(generator)

    information.address = generator.address
    information.enabled = generator.isWorkAllowed()
    information.running = generator.hasWork()

    return information
end

lib.get_generators_information = function(generators)
    return table.map(generators, function(_, v)
        return v.address, lib.get_generator_information(v)
    end)
end

lib.get_battery_information = function(battery)
    local information = lib.get_battery_sensor_information(battery)

    information.address = battery.address
    information.outputAmperage = battery.getOutputAmperage()
    information.outputVoltage = battery.getOutputVoltage()
    information.max_output = information.outputAmperage * information.outputVoltage

    return information
end

lib.get_batteries_information = function(batteries)
    return table.map(batteries, function(_, v)
        return v.address, lib.get_battery_information(v)
    end)
end

return lib
