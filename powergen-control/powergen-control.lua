local component = require("component")
local term = require("term")
local serialization = require("serialization")
local text = require("text")

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

local function get_proxies(filter)
  local components = table.keys(component.list(filter))
  return table.vmap(components, component.proxy)
end

local function get_average_input(batteries)
  return table.vsum(table.vmap(batteries, function (v) return v.getAverageElectricInput() end))
end

local function get_average_output(batteries)
  return table.vsum(table.vmap(batteries, function (v) return v.getAverageElectricOutput() end))
end

local function parse_battery_sensor_information(sensor_information)
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

local function get_sensor_information(batteries)
  local raw_sensor_information = table.vmap(batteries, function(v) return v.getSensorInformation() end)
  local sensor_information = table.vmap(raw_sensor_information, parse_battery_sensor_information)
  return sensor_information
end

local generators = get_proxies("gt_machine")
local batteries = get_proxies("gt_batterybuffer")

while true do
  os.sleep(1)

  local average_input = get_average_input(batteries)
  local average_output = get_average_output(batteries)
  local sensor_information = get_sensor_information(batteries)

  term.clear()

  term.setCursor(1, 1)
  print(string.format("Average input: %d", average_input))
  term.setCursor(1, 2)
  print(string.format("Average output: %d", average_output))
  term.setCursor(1, 3)
  print(serialization.serialize(sensor_information))
end
