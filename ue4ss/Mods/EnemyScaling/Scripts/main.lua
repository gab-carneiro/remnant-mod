local HEALTH_PER_EXTRA = 0.25
local BASE_PLAYERS = 3
local SCAN_INTERVAL_MS = 3000
local LOG_ENABLED = true

local STABLE_SCANS = 2
local DEFAULT_OBJECT_FLAGS = 0x30
local TRACKED_CLASSES = {
    { name = "Character", path = "/Script/Engine.Character" },
    { name = "PlayerController", path = "/Script/Engine.PlayerController" },
    { name = "GameStateBase", path = "/Script/Engine.GameStateBase" },
}
local HEALTH_PROPS = {
    { "MaxHealth", "Health" },
    { "MaxHitPoints", "HitPoints" },
    { "HealthMax", "HealthCurrent" },
}
local HEALTH_COMPONENTS = {
    "DamageableComponent",
    "StatsComponent",
    "HealthComponent",
}

local currentPlayers = 0
local pendingPlayers = -1
local pendingScans = 0
local scaledActors = {}
local tracked = {}
local latestGameState = nil
local seeded = false

local function Log(msg)
    if LOG_ENABLED then
        print("[EnemyScaling] " .. msg .. "\n")
    end
end

local function HealthMultiplier()
    return 1.0 + math.max(currentPlayers - BASE_PLAYERS, 0) * HEALTH_PER_EXTRA
end

local function Track(className, obj)
    if obj:HasAnyFlags(DEFAULT_OBJECT_FLAGS) then return end
    local address = obj:GetAddress()
    tracked[className][address] = obj
    if className == "Character" then
        scaledActors[address] = nil
    elseif className == "GameStateBase" then
        latestGameState = obj
    end
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
            callback(obj, address)
        else
            tracked[className][address] = nil
        end
    end
end

local function CurrentGameState()
    if latestGameState and latestGameState:IsValid() then return latestGameState end
    latestGameState = nil
    ForEachTracked("GameStateBase", function(state) latestGameState = state end)
    return latestGameState
end

local function UpdatePlayerCount()
    local state = CurrentGameState()
    if not state then return end

    local ok, count = pcall(function() return state.PlayerArray:GetArrayNum() end)
    if not ok or type(count) ~= "number" or count <= 0 then
        pendingScans = 0
        return
    end

    if count == currentPlayers then
        pendingScans = 0
        return
    end

    if count ~= pendingPlayers then
        pendingPlayers = count
        pendingScans = 1
    else
        pendingScans = pendingScans + 1
    end

    if pendingScans >= STABLE_SCANS then
        local old = currentPlayers
        currentPlayers = count
        pendingScans = 0
        Log(string.format("Jogadores: %d -> %d | HP x%.2f", old, count, HealthMultiplier()))
    end
end

local function GetPlayers()
    local pawns, controllers = {}, {}
    ForEachTracked("PlayerController", function(pc, address)
        controllers[address] = true
        local ok, pawn = pcall(function() return pc.Pawn end)
        if ok and pawn and pawn:IsValid() then
            pawns[pawn:GetAddress()] = true
        end
    end)
    return pawns, controllers
end

local function IsEnemy(actor, playerPawns, playerControllers)
    if playerPawns[actor:GetAddress()] then return false end

    local ok, controller = pcall(function() return actor.Controller end)
    if not ok or not controller or not controller:IsValid() then return false end

    return not playerControllers[controller:GetAddress()]
end

local function ReadNumber(obj, prop)
    local ok, value = pcall(function() return obj[prop] end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function FindHealth(actor)
    for _, props in ipairs(HEALTH_PROPS) do
        local maxHp = ReadNumber(actor, props[1])
        if maxHp and maxHp > 0 then
            return actor, props[1], props[2], "direto"
        end
    end

    for _, componentName in ipairs(HEALTH_COMPONENTS) do
        local ok, component = pcall(function() return actor[componentName] end)
        if ok and component and component:IsValid() then
            for _, props in ipairs(HEALTH_PROPS) do
                local maxHp = ReadNumber(component, props[1])
                if maxHp and maxHp > 0 then
                    return component, props[1], props[2], componentName
                end
            end
        end
    end
    return nil
end

local function ApplyRatio(actor, ratio)
    local holder, propMax, propCur, label = FindHealth(actor)
    if not holder then return false end

    local maxHp = ReadNumber(holder, propMax)
    local curHp = ReadNumber(holder, propCur)
    if not maxHp or maxHp <= 0 then return false end
    if curHp and curHp <= 0 then return true end

    local newMax = maxHp * ratio
    pcall(function() holder[propMax] = newMax end)
    if curHp then
        pcall(function() holder[propCur] = math.min(curHp * ratio, newMax) end)
    end

    Log(string.format("  HP (%s): %.0f -> %.0f (x%.2f)", label, maxHp, newMax, ratio))
    return true
end

local function Scan()
    if not seeded then
        seeded = true
        Seed()
    end

    UpdatePlayerCount()

    local playerPawns, playerControllers = GetPlayers()
    local mult = HealthMultiplier()

    if mult <= 1.0 and next(scaledActors) == nil then return end

    local seen = {}
    ForEachTracked("Character", function(actor, address)
        local entry = scaledActors[address]
        if entry then
            seen[address] = true
            if math.abs(entry.mult - mult) > 0.0001 and ApplyRatio(actor, mult / entry.mult) then
                entry.mult = mult
            end
        elseif mult > 1.0 and IsEnemy(actor, playerPawns, playerControllers) then
            if ApplyRatio(actor, mult) then
                scaledActors[address] = { mult = mult }
                seen[address] = true
            end
        end
    end)

    for address in pairs(scaledActors) do
        if not seen[address] then scaledActors[address] = nil end
    end
end

for _, class in ipairs(TRACKED_CLASSES) do
    tracked[class.name] = {}
    NotifyOnNewObject(class.path, function(obj)
        pcall(Track, class.name, obj)
    end)
end

Log("=== EnemyScaling carregado ===")
Log(string.format("Config: +%.0f%% HP por jogador acima de %d", HEALTH_PER_EXTRA * 100, BASE_PLAYERS))

LoopAsync(SCAN_INTERVAL_MS, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(Scan)
        if not ok then Log("Erro no scan: " .. tostring(err)) end
    end)
    return false
end)
