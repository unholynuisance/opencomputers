local table = require("nuisance.table")

local term = require("term")
local thread = require("thread")
local event = require("event")

local udp = require("network").udp
local serialization = require("serialization")

local Display = {}
Display.create = function(config)
    local self = {}

    self.config = config

    self.start = Display.start
    self.stop = Display.stop
    self.wait = Display.wait
    self.stop_on = Display.stop_on
    self.detach = Display.detach

    self._monitor_th_f = Display._monitor_th_f
    self._display_th_f = Display._display_th_f

    return self
end

Display.start = function(self)
    udp.open(self.config.port)

    self.threads = {
        monitor_th = thread.create(self._monitor_th_f, self),
        display_th = thread.create(self._display_th_f, self),
    }
end

Display.stop = function(self)
    udp.close(self.config.port)
    self.should_stop = true
end

Display.stop_on = function(self, e)
    event.listen(e, function()
        self:stop()
    end)
end

Display.wait = function(self)
    thread.waitForAll(table.values(self.threads))
end

Display.detach = function(self)
    table.vmap(self.threads, function(t)
        t:detach()
    end)
end

Display._monitor_th_f = function(self)
    while not self.should_stop do
        os.sleep(0)

        local e, _, _, data = event.pullFiltered(function(...)
            local name = select(1, ...)
            local port = select(3, ...)
            return name == "datagram" and port == self.config.port
        end)

        if e then
            self.state = serialization.unserialize(data)
        end
    end
end

Display._display_th_f = function(self)
    while not self.should_stop do
        os.sleep(0)

        term.clear()

        if not self.state then
            print("Waiting for data")
            goto continue
        end

        print("Stats:")
        print(string.format("Energy: %f", self.state.stats.batteries_energy))
        print(string.format("Delta: %f", self.state.stats.delta))
        print(string.format("Average: %f", self.state.stats.average_delta))
        print(string.format("Time to full: %f", self.state.stats.time_to_full))
        print(string.format("Time to empty: %f", self.state.stats.time_to_empty))

        print("")

        print("Grid status:")
        for i, generator in ipairs(self.state.generators) do
            local generator_information = self.state.generators_information[generator.address]

            local name = generator_information.name
            local enabled = generator_information.enabled and "enabled" or "disabled"
            local running = generator_information.running and ", runnning" or ""
            print(string.format("%i. %s (%s%s)", i, name, enabled, running))
        end

        print("")

        print("Status:")
        print(self.state.control_th_message or "Idle")

        ::continue::
    end
end

return Display
