local lib = require("lib")

local component = require("component")
local term = require("term")
local serialization = require("serialization")

local function parse_generator_sensor_information(sensor_information)
    local function parse_number(s)
      s = string.gsub(s, ",", "")
      return tonumber(s)
    end
  
    local name = string.match(sensor_information[1], "§9([%a]-)§r")
    local energy = parse_number(string.match(sensor_information[2], "§a([%d,]-)§r"))
    local max_energy = parse_number(string.match(sensor_information[2], "§e([%d,]-)§r"))
    local maintenance = string.match(sensor_information[3], "§a([%a]-)§r")
    local output = parse_number(string.match(sensor_information[4], "§c([%d,]-)§r"))
    local consumption = parse_number(string.match(sensor_information[5], "§e([%d,]-)§r))
    local fuel_value = parse_number(string.match(sensor_information[6], "§e([%d,]-)§r"))
    local fuel_remaining = parse_number(string.match(sensor_information[7], "§6([%d,]-)§r"))
    local efficiency = parse_number(string.match(sensor_information[8], "§e([%d,]-)§e"))
    local pollution = parse_number(string.match(sensor_information[9], "§a([%d,]-)§r"))
    
    return {
      name = name,
      energy = energy,
      max_energy = max_energy,
      maintenance = not maintenance == "No Maintanance issues",
      output = output,
      consumption = consumption,
      fuel_value = fuel_value,
      fuel_remaining = fuel_remaining,
      efficiency = efficiency,
      pollution = pollution
    }
end

local generators = get_proxies("gt_machine")

while true do
  os.sleep(1)
end
