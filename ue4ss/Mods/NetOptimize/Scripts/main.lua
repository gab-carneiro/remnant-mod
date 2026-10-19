local MAX_PLAYERS = 6
local CLIENT_NET_SPEED = 100000
local SCAN_INTERVAL_MS = 4000
local LOG_ENABLED = true

local warned = {}

local function Log(msg)
    if LOG_ENABLED then
        print("[NetOptimize] " .. msg .. "\n")
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

local function ForEachValid(className, callback)
    local ok, objects = pcall(FindAllOf, className)
    if not ok or not objects then return end
    for _, obj in ipairs(objects) do
        if obj:IsValid() then callback(obj) end
    end
end

local function IsServer()
    local found = false
    ForEachValid("GameModeBase", function() found = true end)
    return found
end

local function RaiseLobby()
    ForEachValid("GameSession", function(session)
        Raise(session, "MaxPlayers", MAX_PLAYERS, "GameSession")
    end)
    ForEachValid("GameModeBase", function(gameMode)
        local ok, session = pcall(function() return gameMode.GameSession end)
        if ok and session and session:IsValid() then
            Raise(session, "MaxPlayers", MAX_PLAYERS, "GameSession")
        end
    end)
end

local function RaiseBandwidth()
    ForEachValid("GameNetworkManager", function(manager)
        Raise(manager, "TotalNetBandwidth", CLIENT_NET_SPEED * MAX_PLAYERS, "GameNetworkManager")
        Raise(manager, "MaxDynamicBandwidth", CLIENT_NET_SPEED, "GameNetworkManager")
    end)
    ForEachValid("NetDriver", function(driver)
        Raise(driver, "MaxClientRate", CLIENT_NET_SPEED, "NetDriver")
        Raise(driver, "MaxInternetClientRate", CLIENT_NET_SPEED, "NetDriver")
    end)
    ForEachValid("NetConnection", function(connection)
        Raise(connection, "CurrentNetSpeed", CLIENT_NET_SPEED, "Cliente")
    end)
end

local function Scan()
    if not IsServer() then return end
    RaiseLobby()
    RaiseBandwidth()
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
