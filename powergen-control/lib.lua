local component = require("component")

table.map = function (t, fn)
  local result = {}

  for k, v in pairs(t) do
    k, v = fn(k, v)
    result[k] = v
  end

  return result
end

table.kmap = function (t, fn)
    return table.map(t, function (k, v) return fn(k), v end)
end

table.vmap = function (t, fn)
  return table.map(t, function (k, v) return k, fn(v) end)
end

table.reduce = function (t, fn, init)
  local acc = init

  for k, v in pairs(t) do
      acc = acc + fn(acc, k, v)
  end

  return acc
end

table.kreduce = function (t, fn, init)
  return table.reduce(t, function(acc, k, _) return fn(acc, k) end, init)
end

table.vreduce = function (t, fn, init)
  return table.reduce(t, function(acc, _, v) return fn(acc, v) end, init)
end

table.vsum = function(t)
  return table.vreduce(t, function(acc, v) return acc + v end, 0)
end

table.keys = function(t)
  local result = {}

  for k, _ in pairs(t) do
    result[#result+1] = k
  end

  return result
end

table.values = function(t)
  local result = {}

  for _, v in pairs(t) do
    result[#result+1] = v
  end

  return result
end

local lib = {}

lib.get_proxies = function (filter)
  local components = table.keys(component.list(filter))
  return table.vmap(components, component.proxy)
end

lib.get_average_input = function (batteries)
  return table.vsum(table.vmap(batteries, function (v) return v.getAverageElectricInput() end))
end

lib.get_average_output = function (batteries)
  return table.vsum(table.vmap(batteries, function (v) return v.getAverageElectricOutput() end))
end

lib.parse_battery_sensor_information = function (sensor_information)
  local function parse_number(s)
    s = string.gsub(s, ",", "")
    return tonumber(s)
  end

  local name = string.match(sensor_information[1], "§9([%a]-)§r")
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

lib.get_sensor_information = function (proxies, parser)
  local raw_sensor_information = table.vmap(proxies, function(v) return v.getSensorInformation() end)
  local sensor_information = table.vmap(raw_sensor_information, parser)
  return sensor_information
end

lib.parse_generator_sensor_information = function (sensor_information)
  local function parse_number(s)
    s = string.gsub(s, ",", "")
    return tonumber(s)
  end

  local name = string.match(sensor_information[1], "§9([%a]-)§r")
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
    pollution = pollution
  }
end

return lib
