local lib = require("nuisance.lib")
local table = require("nuisance.table")

local event = require("event")
local term = require("term")
local serialization = require("serialization")

local get_grid_info = function(path)
    local file = io.open(path)
    local grid_info = serialization.unserialize(file.read(file, "*a"))
    return grid_info
end

local get_generator_to_enable = function(generators, generators_information)
    generators = table.vfilter(generators, function(v)
        return not v.isWorkAllowed()
    end)

    -- return generator with max priority and max ramp_rate
    return table.max(generators, function(a, b)
        local a_info = generators_information[a.address]
        local b_info = generators_information[b.address]

        if a_info.priority < b_info.priority then
            return true
        end

        if a_info.ramp_rate < b_info.ramp_rate then
            return true
        end

        return false
    end)
end

local get_generator_to_disable = function(generators, generators_information)
    generators = table.vfilter(generators, function(v)
        return v.isWorkAllowed()
    end)

    -- return generator with min priority and max ramp_rate
    return table.min(generators, function(a, b)
        local a_info = generators_information[a.address]
        local b_info = generators_information[b.address]

        if a_info.priority < b_info.priority then
            return true
        end

        if a_info.ramp_rate > b_info.ramp_rate then
            return true
        end

        return false
    end)
end

local running_ema = function(s, x, alpha)
    return (1 - alpha) * s + alpha * x
end

local main = function(config)
    local grid_information = get_grid_info("/etc/grid_information")
    grid_information.generators_information = table.vmap(grid_information.generators_information, function(v)
        v.ramp_rate = v.output / v.ramp_time
        return v
    end)

    local generators = lib.get_proxies("gt_machine")
    local batteries = lib.get_proxies("gt_batterybuffer")

    local should_stop = false

    event.listen("interrupted", function()
        should_stop = true
    end)

    local average_delta = 0

    while not should_stop do
        os.sleep(0)

        local generators_information = lib.get_generators_information(generators)
        local batteries_information = lib.get_batteries_information(batteries)

        local sum_over_field = function(t, field)
            return table.vsum(table.vmap(t, function(v)
                return v[field]
            end))
        end

        local batteries_input = sum_over_field(batteries_information, "average_input")
        local batteries_min_input = 0
        local batteries_output = sum_over_field(batteries_information, "average_output")
        local batteries_max_output = sum_over_field(batteries_information, "max_output")
        local batteries_energy = sum_over_field(batteries_information, "energy")
        local batteries_max_energy = sum_over_field(batteries_information, "max_energy")
        local batteries_min_energy = 0

        local max_energy_delta = batteries_min_input - batteries_max_output
        local time_to_empty_at_max_output = lib.ticks_to_seconds( --
            (batteries_min_energy - batteries_energy) / max_energy_delta
        )

        local delta = batteries_input - batteries_output
        average_delta = running_ema(average_delta, delta, config.smoothing_factor)

        local time_to_empty = lib.ticks_to_seconds( --
            (batteries_min_energy - batteries_energy) / average_delta
        )
        local time_to_full = lib.ticks_to_seconds( --
            (batteries_max_energy - batteries_energy) / average_delta
        )

        term.clear()

        print(string.format("Energy: %f", batteries_energy))
        print(string.format("Delta: %f", delta))
        print(string.format("Average: %f", average_delta))
        print(string.format("Time to full: %f", time_to_full))
        print(string.format("Time to empty: %f", time_to_empty))

        if 0 <= time_to_empty_at_max_output and time_to_empty_at_max_output < config.min_time_to_empty then
            local generator = get_generator_to_enable(generators, grid_information.generators_information)
            if generator ~= nil then
                local generator_name = generators_information[generator.address].name
                print(string.format("Starting %s", generator_name))
                generator.setWorkAllowed(true)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        if 0 <= time_to_full and time_to_full < config.min_time_to_full and delta > 0 then
            local generator = get_generator_to_disable(generators, grid_information.generators_information)
            if generator ~= nil then
                local generator_name = generators_information[generator.address].name
                print(string.format("Stopping %s", generator_name))
                generator.setWorkAllowed(false)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end
    end
end

local config = {
    smoothing_factor = 0.05,
    min_time_to_empty = 120,
    min_time_to_full = 10,
}

main(config)
