local lib = require("nuisance.lib")

local event = require("event")
local thread = require("thread")
local filesystem = require("filesystem")

local component = require("component")

local Control = {}
Control.create = function(config)
    local self = {}

    self.config = config or {}
    self.config.data_dir = self.config.data_dir or "/var/lib/fuel-control"

    self.start = Control.start
    self.stop = Control.stop
    self.stop_on = Control.stop_on
    self.wait = Control.wait
    self.detach = Control.detach
    self.regenerate_fluid_database = Control.regenerate_fluid_database

    self._control_th_f = Control._control_th_f
    self._regenerate_fluid_database = Control._regenerate_fluid_database
    self._write_fluid_database = Control._write_fluid_database
    self._read_fluid_database = Control._read_fluid_database
    self._get_proxies = Control._get_proxies

    return self
end

Control.start = function(self)
    self:_read_fluid_database()
    self:_get_proxies()

    self.threads = {
        control_th = thread.create(self._control_th_f, self),
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

Control.detach = function(self)
    table.vmap(self.threads, function(t)
        t:detach()
    end)
end

Control.regenerate_fluid_database = function(self)
    self:_get_proxies()
    self:_regenerate_fluid_database()
    self:_write_fluid_database()
end

Control._control_th_f = function(self)
    return
end

Control._regenerate_fluid_database = function(self)
    local result = { by_name = {}, by_label = {} }

    local damage_start = 30000
    local damage_end = 35000

    for damage = damage_start, damage_end do
        if damage % 100 == 0 then
            os.sleep(0)

            if self.should_stop then
                return
            end

            print(string.format("Reached damage %i", damage))
        end

        -- TODO: find empty slot instead of hardcoding it as 1
        -- gregtech:gt.metaitem.01 is an IC2 fluid cell
        -- damage denotes liquid type inside of the cell
        self.database.set(1, "gregtech:gt.metaitem.01", damage, "")

        local stack = self.database.get(1)
        if stack.fluid.name then
            print(string.format("%s (%s) is %i"), stack.fluid.label, stack.fluid.name, stack.damage)
            result.by_name[stack.fluid.name] = stack.damage
            result.by_label[stack.fluid.label] = stack.damage
        end
    end

    self.fluid_database = result
end

Control._write_fluid_database = function(self)
    local path = filesystem.concat(self.config.data_dir, "fluid_database")
    lib.write_table(path, self.fluid_database)
end

Control._read_fluid_database = function(self)
    local path = filesystem.concat(self.config.data_dir, "fluid_database")
    self.fluid_database = lib.read_table(path)
end

Control._get_proxies = function(self)
    local daddr = self.config.database_address
    self.database = daddr and component.proxy(daddr) or lib.get_proxy("database")

    local iaddr = self.config.interface_address
    self.interface = iaddr and component.proxy(iaddr) or lib.get_proxy("me_interface")
end

return Control
