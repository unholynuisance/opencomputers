local lib = require("nuisance.lib")
local table = require("nuisance.table")

local thread = require("thread")
local event = require("event")
local term = require("term")
local serialization = require("serialization")
local filesystem = require("filesystem")

local Controller = {}
Controller.create = function(config)
    local self = {}

    self.config = config
    self.should_stop = false

    self.start = Controller.start
    self.stop = Controller.stop
    self.wait = Controller.wait
    self.stop_on = Controller.stop_on
    self.collect_grid_information = Controller.collect_grid_information

    self._monitor_th_f = Controller._monitor_th_f
    self._control_th_f = Controller._control_th_f
    self._display_th_f = Controller._display_th_f

    self._collect_grid_information = Controller._collect_grid_information
    self._write_grid_information = Controller._write_grid_information
    self._read_grid_information = Controller._read_grid_information
    self._get_proxies = Controller._get_proxies
    self._get_generator_to_enable = Controller._get_generator_to_enable
    self._get_generator_to_disable = Controller._get_generator_to_disable
    self._running_ema = Controller._running_ema

    return self
end

Controller.start = function(self)
    self:_read_grid_information()
    self:_get_proxies()

    self.threads = {
        monitor_th = thread.create(self._monitor_th_f, self),
        control_th = thread.create(self._control_th_f, self),
        display_th = thread.create(self._display_th_f, self),
    }
end

Controller.wait = function(self)
    thread.waitForAll(table.values(self.threads))
end

Controller.stop = function(self)
    self.should_stop = true
    self:wait()
end

Controller.stop_on = function(self, e)
    event.listen(e, function()
        self:stop()
    end)
end

Controller.collect_grid_information = function(self)
    self:_get_proxies()
    self:_collect_grid_information()
    self:_write_grid_information()
end

Controller._monitor_th_f = function(self)
    local stats = {}
    stats.average_delta = 0

    while not self.should_stop do
        os.sleep(0)

        local generators_information = lib.get_generators_information(self.generators)
        local batteries_information = lib.get_batteries_information(self.batteries)

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
        stats.average_delta = self:_running_ema(stats.average_delta, stats.delta, self.config.smoothing_factor)

        stats.time_to_empty = lib.ticks_to_seconds( --
            (stats.batteries_min_energy - stats.batteries_energy) / stats.average_delta
        )

        stats.time_to_full = lib.ticks_to_seconds( --
            (stats.batteries_max_energy - stats.batteries_energy) / stats.average_delta
        )

        self.generators_information = generators_information
        self.batteries_information = batteries_information
        self.stats = stats
    end
end

Controller._control_th_f = function(self)
    while not self.should_stop do
        os.sleep(0)

        if self.stats == nil then
            goto continue
        end

        self.control_th_message = nil

        local tte_mo, min_tte_mo = self.stats.time_to_empty_at_max_output, self.config.min_time_to_empty

        if 0 <= tte_mo and tte_mo < min_tte_mo then
            local generator = self:_get_generator_to_enable()
            if generator ~= nil then
                local generator_name = self.generators_information[generator.address].name
                self.control_th_message = string.format("Starting %s", generator_name)
                generator.setWorkAllowed(true)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        local ttf, min_ttf = self.stats.time_to_full, self.config.min_time_to_full

        if 0 <= ttf and ttf < min_ttf and self.stats.average_delta > 0 then
            local generator = self:_get_generator_to_disable()
            if generator ~= nil then
                local generator_name = self.generators_information[generator.address].name
                self.control_th_message = string.format("Stopping %s", generator_name)
                generator.setWorkAllowed(false)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        ::continue::
    end
end

Controller._display_th_f = function(self)
    while not self.should_stop do
        os.sleep(0)

        if self.stats == nil then
            goto continue
        end

        term.clear()

        print("Stats:")
        print(string.format("Energy: %f", self.stats.batteries_energy))
        print(string.format("Delta: %f", self.stats.delta))
        print(string.format("Average: %f", self.stats.average_delta))
        print(string.format("Time to full: %f", self.stats.time_to_full))
        print(string.format("Time to empty: %f", self.stats.time_to_empty))

        print("")

        print("Grid status:")
        for i, generator in ipairs(self.generators) do
            local generator_name = self.generators_information[generator.address].name
            local generator_status = generator.isWorkAllowed() and "enabled" or "disabled"
            print(string.format("%i. %s (%s)", i, generator_name, generator_status))
        end

        print("")

        print("Status:")
        print(self.control_th_message or "Idle")

        ::continue::
    end
end

Controller._collect_grid_information = function(self)
    local generators_information = table.parallel_map(self.generators, function(_, generator)
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
        data.ramp_rate = data.output / data.ramp_time
        return generator.address, data
    end)

    self.grid_information = {
        generators_information = generators_information,
    }
end

Controller._write_grid_information = function(self)
    filesystem.makeDirectory(self.config.data_dir)

    local path = filesystem.concat(self.config.data_dir, "grid_information")
    local file = io.open(path, "w")

    if file then
        file:write(serialization.serialize(self.grid_information))
    end
end

Controller._read_grid_information = function(self)
    local path = filesystem.concat(self.config.data_dir, "grid_information")
    local file = io.open(path, "r")

    if file then
        self.grid_information = serialization.unserialize(file:read("*a"))
    end
end

Controller._get_proxies = function(self)
    self.generators = lib.get_proxies("gt_machine")
    self.batteries = lib.get_proxies("gt_batterybuffer")
end

Controller._get_generator_to_enable = function(self)
    local generators = table.vfilter(self.generators, function(v)
        return not v.isWorkAllowed()
    end)

    -- return generator with max priority and max ramp_rate
    return table.max(generators, function(a, b)
        local a_info = self.grid_information.generators_information[a.address]
        local b_info = self.grid_information.generators_information[b.address]

        if a_info.priority < b_info.priority then
            return true
        end

        if a_info.ramp_rate < b_info.ramp_rate then
            return true
        end

        return false
    end)
end

Controller._get_generator_to_disable = function(self)
    local generators = table.vfilter(self.generators, function(v)
        return v.isWorkAllowed()
    end)

    -- return generator with min priority and max ramp_rate
    return table.min(generators, function(a, b)
        local a_info = self.grid_information.generators_information[a.address]
        local b_info = self.grid_information.generators_information[b.address]

        if a_info.priority < b_info.priority then
            return true
        end

        if a_info.ramp_rate > b_info.ramp_rate then
            return true
        end

        return false
    end)
end

Controller._running_ema = function(_, s, x, alpha)
    return (1 - alpha) * s + alpha * x
end

return Controller
