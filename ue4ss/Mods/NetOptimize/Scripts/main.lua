local MAX_PLAYERS = 6
local CLIENT_NET_SPEED = 100000
local SCAN_INTERVAL_MS = 4000
local LOG_ENABLED = true

local engine = nil
local warned = {}

local function Log(msg)
    if LOG_ENABLED then
        print("[NetOptimize] " .. msg .. "\n")
    end
end

local function GetEngine()
    if engine then return engine end
    local ok, found = pcall(FindFirstOf, "Engine")
    if ok and found and found:IsValid() then
        engine = found
    end
    return engine
end

local function Child(obj, prop)
    if not obj then return nil end
    local ok, child = pcall(function()
        local value = obj[prop]
        if value and value:IsValid() then return value end
        return nil
    end)
    if ok then return child end
    return nil
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

local function RaiseConnections(driver)
    local ok, count = pcall(function() return driver.ClientConnections:GetArrayNum() end)
    if not ok or type(count) ~= "number" then return end
    for i = 1, count do
        local okItem, connection = pcall(function() return driver.ClientConnections[i] end)
        if okItem and connection and connection:IsValid() then
            Raise(connection, "CurrentNetSpeed", CLIENT_NET_SPEED, "Cliente")
        end
    end
end

local function Scan()
    local world = Child(Child(GetEngine(), "GameViewport"), "World")
    local gameMode = Child(world, "AuthorityGameMode")
    if not gameMode then return end

    local session = Child(gameMode, "GameSession")
    if session then
        Raise(session, "MaxPlayers", MAX_PLAYERS, "GameSession")
    end

    local manager = Child(world, "NetworkManager")
    if manager then
        Raise(manager, "TotalNetBandwidth", CLIENT_NET_SPEED * MAX_PLAYERS, "GameNetworkManager")
        Raise(manager, "MaxDynamicBandwidth", CLIENT_NET_SPEED, "GameNetworkManager")
    end

    local driver = Child(world, "NetDriver")
    if driver then
        Raise(driver, "MaxClientRate", CLIENT_NET_SPEED, "NetDriver")
        Raise(driver, "MaxInternetClientRate", CLIENT_NET_SPEED, "NetDriver")
        RaiseConnections(driver)
    end
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
