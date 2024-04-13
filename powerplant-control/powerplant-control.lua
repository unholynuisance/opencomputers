local lib = require("nuisance.lib")
local table = require("nuisance.table")

local thread = require("thread")
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

local monitor_th_f = function(context)
    local config = context.config

    local stats = {}
    stats.average_delta = 0

    while not context.should_stop do
        os.sleep(0)

        local generators_information = lib.get_generators_information(context.generators)
        local batteries_information = lib.get_batteries_information(context.batteries)

        local sum_over_field = function(t, field)
            return table.vsum(table.vmap(t, function(v)
                return v[field]
            end))
        end

        stats.batteries_input = sum_over_field(batteries_information, "average_input")
        stats.batteries_min_input = 0
        stats.batteries_output = sum_over_field(batteries_information, "average_output")
        stats.batteries_max_output = sum_over_field(batteries_information, "max_output")
        stats.batteries_energy = sum_over_field(batteries_information, "energy")
        stats.batteries_max_energy = sum_over_field(batteries_information, "max_energy")
        stats.batteries_min_energy = 0

        stats.max_energy_delta = stats.batteries_min_input - stats.batteries_max_output
        stats.time_to_empty_at_max_output = lib.ticks_to_seconds( --
            (stats.batteries_min_energy - stats.batteries_energy) / stats.max_energy_delta
        )

        stats.delta = stats.batteries_input - stats.batteries_output
        stats.average_delta = running_ema(stats.average_delta, stats.delta, config.smoothing_factor)

        stats.time_to_empty = lib.ticks_to_seconds( --
            (stats.batteries_min_energy - stats.batteries_energy) / stats.average_delta
        )

        stats.time_to_full = lib.ticks_to_seconds( --
            (stats.batteries_max_energy - stats.batteries_energy) / stats.average_delta
        )

        context.generators_information = generators_information
        context.batteries_information = batteries_information
        context.stats = stats
    end
end

local control_th_f = function(context)
    local config = context.config
    local grid_information = context.grid_information
    local generators = context.generators

    while not context.should_stop do
        os.sleep(0)

        if context.stats == nil then
            goto continue
        end

        local generators_information = context.generators_information
        local stats = context.stats

        context.control_th_message = nil

        if 0 <= stats.time_to_empty_at_max_output and stats.time_to_empty_at_max_output < config.min_time_to_empty then
            local generator = get_generator_to_enable(generators, grid_information.generators_information)
            if generator ~= nil then
                local generator_name = generators_information[generator.address].name
                context.control_th_message = string.format("Starting %s", generator_name)
                generator.setWorkAllowed(true)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        if 0 <= stats.time_to_full and stats.time_to_full < config.min_time_to_full and stats.average_delta > 0 then
            local generator = get_generator_to_disable(generators, grid_information.generators_information)
            if generator ~= nil then
                local generator_name = generators_information[generator.address].name
                context.control_th_message = string.format("Stopping %s", generator_name)
                generator.setWorkAllowed(false)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        ::continue::
    end
end

local display_th_f = function(context)
    while not context.should_stop do
        os.sleep(0)

        if context.stats == nil then
            goto continue
        end

        term.clear()

        local stats = context.stats

        print(string.format("Energy: %f", stats.batteries_energy))
        print(string.format("Delta: %f", stats.delta))
        print(string.format("Average: %f", stats.average_delta))
        print(string.format("Time to full: %f", stats.time_to_full))
        print(string.format("Time to empty: %f", stats.time_to_empty))

        if context.control_th_message ~= nil then
            print(context.control_th_message)
        end

        ::continue::
    end
end

local context = {
    should_stop = false,
}

local start = function()
    context.config = {
        smoothing_factor = 0.05,
        min_time_to_empty = 120,
        min_time_to_full = 10,
    }

    context.grid_information = get_grid_info("/etc/grid_information")
    context.grid_information.generators_information = table.vmap(
        context.grid_information.generators_information,
        function(v)
            v.ramp_rate = v.output / v.ramp_time
            return v
        end
    )

    context.generators = lib.get_proxies("gt_machine")
    context.batteries = lib.get_proxies("gt_batterybuffer")

    context.threads = {
        monitor_th = thread.create(monitor_th_f, context),
        control_th = thread.create(control_th_f, context),
        display_th = thread.create(display_th_f, context),
    }

    thread.waitForAll(table.values(context.threads))
end

local stop = function()
    context.should_stop = true
end

local main = function()
    event.listen("interrupted", stop)
    start()
end

main()
