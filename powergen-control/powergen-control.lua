local lib = require("lib")

local component = require("component")
local term = require("term")
local serialization = require("serialization")

local generators = lib.get_proxies("gt_machine")
local batteries = lib.get_proxies("gt_batterybuffer")

while true do
  os.sleep(1)

  local average_input = lib.get_average_input(batteries)
  local average_output = lib.get_average_output(batteries)
  local sensor_information = lib.get_sensor_information(batteries)

  term.clear()

  term.setCursor(1, 1)
  print(string.format("Average input: %d", average_input))
  term.setCursor(1, 2)
  print(string.format("Average output: %d", average_output))
  term.setCursor(1, 3)
  print(serialization.serialize(sensor_information))
end
