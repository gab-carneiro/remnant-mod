local Mock = {}

local DEFAULT_OBJECT_FLAGS = 0x30

local next_address = 0x10000
local next_name = 0

local function check_alive(self)
    if rawget(self, "_freed") then
        local world = rawget(self, "_world")
        world.use_after_free = world.use_after_free + 1
        error("use-after-free: " .. rawget(self, "_name"))
    end
end

local methods = {
    IsValid = function(self)
        check_alive(self)
        return rawget(self, "_valid")
    end,
    GetAddress = function(self)
        check_alive(self)
        return rawget(self, "_address")
    end,
    GetFullName = function(self)
        check_alive(self)
        return rawget(self, "_name")
    end,
    HasAnyFlags = function(self, flags)
        check_alive(self)
        return (rawget(self, "_flags") & flags) ~= 0
    end,
    ConsoleCommand = function(self, command)
        check_alive(self)
        local world = rawget(self, "_world")
        world.console[#world.console + 1] = command
    end,
}

local ObjectMeta = {}

ObjectMeta.__index = function(self, key)
    if methods[key] then return methods[key] end
    check_alive(self)
    local value = rawget(self, "_props")[key]
    if value == nil then
        return Mock.null
    end
    return value
end

ObjectMeta.__newindex = function(self, key, value)
    check_alive(self)
    local props = rawget(self, "_props")
    if props[key] == nil then
        error("propriedade inexistente: " .. tostring(key))
    end
    props[key] = value
end

Mock.null = setmetatable({ _valid = false, _address = 0, _name = "None", _flags = 0, _props = {}, _classes = {} }, ObjectMeta)

local ArrayMeta = {}

ArrayMeta.__index = function(self, key)
    local items = rawget(self, "_items")
    if key == "GetArrayNum" then
        return function() return #items end
    end
    if type(key) == "number" then
        if key < 1 or key > #items then
            local world = rawget(self, "_world")
            world.array_out_of_bounds_reads = world.array_out_of_bounds_reads + 1
            items[#items + 1] = Mock.null
            return Mock.null
        end
        return items[key]
    end
    error("membro inexistente em TArray: " .. tostring(key))
end

ArrayMeta.__len = function(self)
    return #rawget(self, "_items")
end

local World = {}
World.__index = World

function Mock.world()
    return setmetatable({
        objects = {}, loops = {}, game_thread = {}, notify = {}, hooks = {}, logs = {}, console = {},
        array_out_of_bounds_reads = 0, find_all_calls = 0, use_after_free = 0,
    }, World)
end

function World:spawn(class_names, props, options)
    options = options or {}
    local address = options.address
    if not address then
        next_address = next_address + 0x40
        address = next_address
    end
    next_name = next_name + 1
    local obj = {
        _valid = true,
        _address = address,
        _name = options.name or (class_names[1] .. " /Game/Mock." .. class_names[1] .. "_" .. next_name),
        _flags = options.flags or 0,
        _props = props or {},
        _classes = {},
        _world = self,
    }
    for _, class_name in ipairs(class_names) do
        obj._classes[class_name] = true
    end
    setmetatable(obj, ObjectMeta)
    self.objects[#self.objects + 1] = obj
    return obj
end

function World:destroy(obj)
    rawset(obj, "_valid", false)
    for i, candidate in ipairs(self.objects) do
        if candidate == obj then
            table.remove(self.objects, i)
            return
        end
    end
end

function World:free(obj)
    self:destroy(obj)
    rawset(obj, "_freed", true)
end

function World:array(items)
    return setmetatable({ _items = items, _world = self }, ArrayMeta)
end

function World:find_all(class_name)
    self.find_all_calls = self.find_all_calls + 1
    local found = {}
    for _, obj in ipairs(self.objects) do
        if rawget(obj, "_classes")[class_name] and (rawget(obj, "_flags") & DEFAULT_OBJECT_FLAGS) == 0 then
            found[#found + 1] = obj
        end
    end
    return found
end

function World:run(script_path, options)
    options = options or {}
    local world = self
    local env = setmetatable({}, { __index = _G })
    env.FindAllOf = function(class_name)
        local found = world:find_all(class_name)
        if #found == 0 then return nil end
        return found
    end
    env.FindFirstOf = function(class_name)
        return world:find_all(class_name)[1] or Mock.null
    end
    env.NotifyOnNewObject = function(class_path, callback)
        world.notify[#world.notify + 1] = class_path
    end
    env.LoopAsync = function(_, callback)
        world.loops[#world.loops + 1] = callback
    end
    env.ExecuteInGameThread = function(callback)
        world.game_thread[#world.game_thread + 1] = callback
    end
    env.RegisterHook = function(path)
        world.hooks[#world.hooks + 1] = path
        return 1, 1
    end
    env.print = function(message)
        world.logs[#world.logs + 1] = message
    end
    local file = assert(io.open(script_path, "r"))
    local source = file:read("a")
    file:close()
    for old, new in pairs(options.replace or {}) do
        local start = source:find(old, 1, true)
        assert(start, "trecho nao encontrado no script: " .. old)
        source = source:sub(1, start - 1) .. new .. source:sub(start + #old)
    end
    local chunk = assert(load(source, "@" .. script_path, "t", env))
    chunk()
end

function World:tick_async_only()
    for _, callback in ipairs(self.loops) do
        callback()
    end
end

function World:drain_game_thread()
    local pending = self.game_thread
    self.game_thread = {}
    for _, callback in ipairs(pending) do
        callback()
    end
end

function World:tick(times)
    for _ = 1, times or 1 do
        self:tick_async_only()
        self:drain_game_thread()
    end
end

function World:logged(pattern)
    for _, line in ipairs(self.logs) do
        if line:find(pattern) then return true end
    end
    return false
end

return Mock
