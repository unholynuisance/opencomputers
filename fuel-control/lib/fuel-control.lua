local lib = require("nuisance.lib")
local table = require("nuisance.table")

local event = require("event")
local thread = require("thread")
local filesystem = require("filesystem")
local term = require("term")

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

    self._monitor_th_f = Control._monitor_th_f
    self._control_th_f = Control._control_th_f
    self._display_th_f = Control._display_th_f
    self._fluid_database_set_database_entry = Control._fluid_database_set_database_entry
    self._fluid_database_get = Control._fluid_database_get
    self._write_fluid_database = Control._write_fluid_database
    self._read_fluid_database = Control._read_fluid_database
    self._get_proxies = Control._get_proxies

    return self
end

Control.start = function(self)
    self:_read_fluid_database()
    self:_get_proxies()

    self.threads = {
        monitor_th = thread.create(self._monitor_th_f, self),
        control_th = thread.create(self._control_th_f, self),
        display_th = self.config.display and thread.create(self._display_th_f, self) or nil,
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

Control._monitor_th_f = function(self)
    while not self.should_stop do
        os.sleep(self.config.monitor_delay)

        local fluids = self.interface.getFluidsInNetwork()

        local fuels = table.map(fluids, function(_, fluid)
            local id = self.config.fuels[fluid.name] and fluid.name or self.config.fuels[fluid.label] and fluid.label
            if not id then
                return nil
            end

            local reserve = self.config.fuels[id].reserve or 0
            local stock = self.config.fuels[id].stock or 0
            local available = self.fuels and self.fuels[id]

            local value = { stock = fluid.amount - reserve, reserve = math.min(fluid.amount, reserve) }
            local key = (value.reserve >= reserve and (available or value.stock > stock)) and id or nil

            return key, value
        end)

        self.fuels = fuels
    end
end

Control._control_th_f = function(self)
    while not self.should_stop do
        os.sleep(self.config.control_delay)
        if not self.fuels then
            goto continue
        end

        if not self.current_fuel then
            local fuel, _ = table.max(self.fuels, function(_, a, _, b)
                return a.stock < b.stock
            end)

            self.current_fuel = fuel

            -- TODO: find empty slot instead of hardcoding it as 2
            self:_fluid_database_set_database_entry(fuel, "either", self.database.address, 2)
            self.interface.setFluidInterfaceConfiguration(1, self.database.address, 2)
            self.database.clear(2)
        else
            self.current_fuel = self.fuels[self.current_fuel] and self.current_fuel or nil
            self.interface.setFluidInterfaceConfiguration(1)
        end

        ::continue::
    end
end

Control._display_th_f = function(self)
    while not self.should_stop do
        os.sleep(self.config.display_delay)

        if not self.fuels then
            goto continue
        end

        term.clear()

        print("Fuels in stock:")
        table.map(self.fuels, function(k, v)
            print(string.format("%s stock: %i reserve: %i", k, v.stock, v.reserve))
        end)

        print("")
        print(string.format("Current fuel: %s", self.current_fuel))

        ::continue::
    end
end

Control._fluid_database_set_database_entry = function(self, id, how, database, entry)
    local item_id = "gregtech:gt.metaitem.01"
    local item_damage = self:_fluid_database_get(id, how) or error(string.format("Unknown liquid: %s", id))
    component.invoke(database, "set", entry, item_id, item_damage, "")
end

Control._fluid_database_get = function(self, id, how)
    assert(how == "by_label" or how == "by_name" or how == "either")

    if how == "either" then
        return self.fluid_database.by_name[id] or self.fluid_database.by_label[id]
    elseif how == "by_label" then
        return self.fluid_database.by_label[id]
    elseif how == "by_name" then
        return self.fluid_database.by_name[id]
    end
end

Control._regenerate_fluid_database = function(self)
    local result = { by_name = {}, by_label = {} }

    local item_damage_start = 30000
    local item_damage_end = 35000
    local item_id = "gregtech:gt.metaitem.01"

    for item_damage = item_damage_start, item_damage_end do
        if item_damage % 100 == 0 then
            os.sleep(0)

            if self.should_stop then
                return
            end

            print(string.format("Reached damage %i", item_damage))
        end

        -- TODO: find empty slot instead of hardcoding it as 1
        -- gregtech:gt.metaitem.01 is an IC2 fluid cell
        -- damage denotes liquid type inside of the cell
        self.database.set(1, item_id, item_damage, "")

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
