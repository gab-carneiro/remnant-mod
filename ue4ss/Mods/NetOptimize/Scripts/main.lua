local MAX_PLAYERS = 6
local CLIENT_NET_SPEED = 100000
local SCAN_INTERVAL_MS = 4000
local LOG_ENABLED = true

local DEFAULT_OBJECT_FLAGS = 0x30
local TRACKED_CLASSES = {
    { name = "GameModeBase", path = "/Script/Engine.GameModeBase" },
    { name = "GameNetworkManager", path = "/Script/Engine.GameNetworkManager" },
    { name = "NetDriver", path = "/Script/Engine.NetDriver" },
    { name = "NetConnection", path = "/Script/Engine.NetConnection" },
}

local tracked = {}
local seeded = false
local warned = {}

local function Log(msg)
    if LOG_ENABLED then
        print("[NetOptimize] " .. msg .. "\n")
    end
end

local function Track(className, obj)
    if obj:HasAnyFlags(DEFAULT_OBJECT_FLAGS) then return end
    tracked[className][obj:GetAddress()] = obj
end

local function Seed()
    for _, class in ipairs(TRACKED_CLASSES) do
        local ok, objects = pcall(FindAllOf, class.name)
        if ok and objects then
            for _, obj in ipairs(objects) do
                if obj:IsValid() then Track(class.name, obj) end
            end
        end
    end
end

local function ForEachTracked(className, callback)
    for address, obj in pairs(tracked[className]) do
        if obj:IsValid() then
            callback(obj)
        else
            tracked[className][address] = nil
        end
    end
end

local function ReadNumber(obj, prop)
    local ok, value = pcall(function() return obj[prop] end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function Raise(obj, prop, target, label)
    local current = ReadNumber(obj, prop)
    if current == nil or current >= target then return end
    pcall(function() obj[prop] = target end)
    if ReadNumber(obj, prop) == target then
        Log(string.format("%s.%s %d -> %d", label, prop, current, target))
    elseif not warned[label .. prop] then
        warned[label .. prop] = true
        Log(string.format("AVISO: %s.%s continua em %d", label, prop, current))
    end
end

local function RaiseLobby()
    local isServer = false
    ForEachTracked("GameModeBase", function(gameMode)
        isServer = true
        local ok, session = pcall(function() return gameMode.GameSession end)
        if ok and session and session:IsValid() then
            Raise(session, "MaxPlayers", MAX_PLAYERS, "GameSession")
        end
    end)
    return isServer
end

local function RaiseBandwidth()
    ForEachTracked("GameNetworkManager", function(manager)
        Raise(manager, "TotalNetBandwidth", CLIENT_NET_SPEED * MAX_PLAYERS, "GameNetworkManager")
        Raise(manager, "MaxDynamicBandwidth", CLIENT_NET_SPEED, "GameNetworkManager")
    end)
    ForEachTracked("NetDriver", function(driver)
        Raise(driver, "MaxClientRate", CLIENT_NET_SPEED, "NetDriver")
        Raise(driver, "MaxInternetClientRate", CLIENT_NET_SPEED, "NetDriver")
    end)
    ForEachTracked("NetConnection", function(connection)
        Raise(connection, "CurrentNetSpeed", CLIENT_NET_SPEED, "Cliente")
    end)
end

local function Scan()
    if not seeded then
        seeded = true
        Seed()
    end
    if RaiseLobby() then
        RaiseBandwidth()
    end
end

for _, class in ipairs(TRACKED_CLASSES) do
    tracked[class.name] = {}
    NotifyOnNewObject(class.path, function(obj)
        pcall(Track, class.name, obj)
    end)
end

Log("=== NetOptimize carregado ===")
Log(string.format("Config: ate %d jogadores, %d B/s por cliente", MAX_PLAYERS, CLIENT_NET_SPEED))

LoopAsync(SCAN_INTERVAL_MS, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(Scan)
        if not ok then Log("Erro no scan: " .. tostring(err)) end
    end)
    return false
end)
