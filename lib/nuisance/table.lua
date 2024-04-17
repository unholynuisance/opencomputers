local thread = require("thread")

table.parallel_map = function(t, fn)
    local result = {}

    local worker = function(k, v)
        k, v = fn(k, v)
        if k then
            result[k] = v
        end
    end

    local threads = table.values(table.map(t, function(k, v)
        return k, thread.create(worker, k, v)
    end))

    thread.waitForAll(threads)
    return result
end

table.parallel_kmap = function(t, fn)
    return table.parallel_map(t, function(k, v)
        return fn(k), v
    end)
end

table.parallel_vmap = function(t, fn)
    return table.parallel_map(t, function(k, v)
        return k, fn(v)
    end)
end

table.map = function(t, fn)
    local result = {}

    for k, v in pairs(t) do
        k, v = fn(k, v)
        if k then
            result[k] = v
        end
    end

    return result
end

table.kmap = function(t, fn)
    return table.map(t, function(k, v)
        return fn(k), v
    end)
end

table.vmap = function(t, fn)
    return table.map(t, function(k, v)
        return k, fn(v)
    end)
end

table.filter = function(t, fn)
    return table.map(t, function(k, v)
        return fn(k, v) and k, v or nil, nil
    end)
end

table.kfilter = function(t, fn)
    return table.filter(t, function(k, _)
        return fn(k)
    end)
end

table.vfilter = function(t, fn)
    return table.filter(t, function(_, v)
        return fn(v)
    end)
end

table.reduce = function(t, fn, kinit, vinit)
    local kacc = kinit
    local vacc = vinit

    for k, v in pairs(t) do
        kacc, vacc = fn(kacc, vacc, k, v)
    end

    return kacc, vacc
end

table.kreduce = function(t, fn, init)
    local acc, _ = table.reduce(t, function(acc, _, k, _)
        return fn(acc, k), nil
    end, init, nil)

    return acc
end

table.vreduce = function(t, fn, init)
    local _, acc = table.reduce(t, function(_, acc, _, v)
        return nil, fn(acc, v)
    end, nil, init)

    return acc
end

table.vsum = function(t)
    return table.vreduce(t, function(acc, v)
        return acc + v
    end, 0)
end

table.min = function(t, comp)
    return table.reduce(t, function(kacc, vacc, k, v)
        if (kacc ~= nil or vacc ~= nil) and comp(kacc, vacc, k, v) then
            return kacc, vacc
        else
            return k, v
        end
    end)
end

table.vmin = function(t, comp)
    return table.vreduce(t, function(acc, v)
        if acc ~= nil and comp(acc, v) then
            return acc
        else
            return v
        end
    end)
end

table.max = function(t, comp)
    return table.reduce(t, function(kacc, vacc, k, v)
        if (kacc ~= nil or vacc ~= nil) and comp(k, v, kacc, vacc) then
            return kacc, vacc
        else
            return k, v
        end
    end)
end

table.vmax = function(t, comp)
    return table.vreduce(t, function(acc, v)
        if acc ~= nil and comp(v, acc) then
            return acc
        else
            return v
        end
    end)
end

table.keys = function(t)
    local result = {}

    for k, _ in pairs(t) do
        result[#result + 1] = k
    end

    return result
end

table.values = function(t)
    local result = {}

    for _, v in pairs(t) do
        result[#result + 1] = v
    end

    return result
end

return table
