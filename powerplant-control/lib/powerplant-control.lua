local lib = require("nuisance.lib")
local table = require("nuisance.table")

local thread = require("thread")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local udp = require("network").udp

local Control = {}
Control.create = function(config)
    local self = {}

    self.config = config
    self.should_stop = false

    self.start = Control.start
    self.stop = Control.stop
    self.wait = Control.wait
    self.stop_on = Control.stop_on
    self.collect_grid_information = Control.collect_grid_information

    self._monitor_th_f = Control._monitor_th_f
    self._control_th_f = Control._control_th_f
    self._display_th_f = Control._display_th_f

    self._collect_grid_information = Control._collect_grid_information
    self._write_grid_information = Control._write_grid_information
    self._read_grid_information = Control._read_grid_information
    self._get_proxies = Control._get_proxies
    self._get_generator_to_enable = Control._get_generator_to_enable
    self._get_generator_to_disable = Control._get_generator_to_disable
    self._running_ema = Control._running_ema

    return self
end

Control.start = function(self)
    self:_read_grid_information()
    self:_get_proxies()

    self.threads = {
        monitor_th = thread.create(self._monitor_th_f, self),
        control_th = thread.create(self._control_th_f, self),
        display_th = thread.create(self._display_th_f, self),
    }
end

Control.stop = function(self)
    self.should_stop = true
end

Control.stop_on = function(self, e)
    event.listen(e, function()
        self:stop()
    end)
end

Control.wait = function(self)
    thread.waitForAll(table.values(self.threads))
end

Control.collect_grid_information = function(self)
    self:_get_proxies()
    self:_collect_grid_information()
    self:_write_grid_information()
end

Control._monitor_th_f = function(self)
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

Control._control_th_f = function(self)
    while not self.should_stop do
        os.sleep(0)

        if not self.stats then
            goto continue
        end

        self.control_th_message = nil

        local tte_mo, min_tte_mo = self.stats.time_to_empty_at_max_output, self.config.min_time_to_empty

        if 0 <= tte_mo and tte_mo < min_tte_mo then
            local generator = self:_get_generator_to_enable()
            if generator then
                local generator_name = self.generators_information[generator.address].name
                self.control_th_message = string.format("Starting %s", generator_name)
                generator.setWorkAllowed(true)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        local ttf, min_ttf = self.stats.time_to_full, self.config.min_time_to_full

        if 0 <= ttf and ttf < min_ttf and self.stats.average_delta > 0 then
            local generator = self:_get_generator_to_disable()
            if generator then
                local generator_name = self.generators_information[generator.address].name
                self.control_th_message = string.format("Stopping %s", generator_name)
                generator.setWorkAllowed(false)
                lib.wait_for_stable_efficiency(generator, 20)
            end
        end

        ::continue::
    end
end

Control._display_th_f = function(self)
    while not self.should_stop do
        os.sleep(self.config.display_delay)

        if not self.stats then
            goto continue
        end

        local data = serialization.serialize({
            generators = self.generators,
            batteries = self.batteries,
            grid_information = self.grid_information,
            generators_information = self.generators_information,
            batteries_information = self.batteries_information,
            stats = self.stats,
            control_th_message = self.control_th_message,
        })

        udp.send(self.config.display_address, self.config.display_port, data)

        ::continue::
    end
end

Control._collect_grid_information = function(self)
    local generators_information = table.parallel_map(self.generators, function(_, generator)
        local isWorkAllowed = generator.isWorkAllowed()

        local timeout = 20

        generator.setWorkAllowed(false)

        lib.wait_for_zero_efficiency(generator)

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

Control._write_grid_information = function(self)
    filesystem.makeDirectory(self.config.data_dir)

    local path = filesystem.concat(self.config.data_dir, "grid_information")
    local file = io.open(path, "w")

    if file then
        file:write(serialization.serialize(self.grid_information))
    end
end

Control._read_grid_information = function(self)
    local path = filesystem.concat(self.config.data_dir, "grid_information")
    local file = io.open(path, "r")

    if file then
        self.grid_information = serialization.unserialize(file:read("*a"))
    end
end

Control._get_proxies = function(self)
    self.generators = lib.get_proxies("gt_machine")
    self.batteries = lib.get_proxies("gt_batterybuffer")
end

Control._get_generator_to_enable = function(self)
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

Control._get_generator_to_disable = function(self)
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

Control._running_ema = function(_, s, x, alpha)
    return (1 - alpha) * s + alpha * x
end

return Control
