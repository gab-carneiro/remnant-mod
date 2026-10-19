local ENABLED = false
local HEALTH_PER_EXTRA = 0.25
local BASE_PLAYERS = 3
local SCAN_INTERVAL_MS = 5000
local LOG_ENABLED = true

local STABLE_SCANS = 2
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

local engine = nil
local currentPlayers = 0
local pendingPlayers = -1
local pendingScans = 0
local scaledActors = {}
local currentGameState = nil

local function Log(msg)
    if LOG_ENABLED then
        print("[EnemyScaling] " .. msg .. "\n")
    end
end

local function HealthMultiplier()
    return 1.0 + math.max(currentPlayers - BASE_PLAYERS, 0) * HEALTH_PER_EXTRA
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

local function SafeFullName(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and type(name) == "string" then return name end
    return ""
end

local function ReadPlayers(gameState)
    local pawns, controllers = {}, {}
    local ok, count = pcall(function() return gameState.PlayerArray:GetArrayNum() end)
    if not ok or type(count) ~= "number" then return 0, pawns, controllers end
    for i = 1, count do
        local okItem, playerState = pcall(function() return gameState.PlayerArray[i] end)
        if okItem and playerState and playerState:IsValid() then
            local pawn = Child(playerState, "PawnPrivate")
            if pawn then pawns[pawn:GetAddress()] = true end
            local controller = Child(playerState, "Owner")
            if controller then controllers[controller:GetAddress()] = true end
        end
    end
    return count, pawns, controllers
end

local function UpdatePlayerCount(count)
    if count <= 0 then
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

local function IsEnemy(actor, playerPawns, playerControllers)
    if playerPawns[actor:GetAddress()] then return false end
    local controller = Child(actor, "Controller")
    if not controller then return false end
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
        local component = Child(actor, componentName)
        if component then
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
    local world = Child(Child(GetEngine(), "GameViewport"), "World")
    if not Child(world, "AuthorityGameMode") then return end
    local gameState = Child(world, "GameState")
    if not gameState then return end

    local gameStateId = SafeFullName(gameState) .. "@" .. tostring(gameState:GetAddress())
    if gameStateId ~= currentGameState then
        currentGameState = gameStateId
        scaledActors = {}
    end

    local count, playerPawns, playerControllers = ReadPlayers(gameState)
    UpdatePlayerCount(count)

    local mult = HealthMultiplier()
    if mult <= 1.0 and next(scaledActors) == nil then return end

    local ok, actors = pcall(FindAllOf, "Character")
    if not ok or not actors then actors = {} end

    local seen = {}
    for _, actor in ipairs(actors) do
        if actor:IsValid() then
            local address = actor:GetAddress()
            local name = SafeFullName(actor)
            local entry = scaledActors[address]
            if entry and entry.name ~= name then entry = nil end

            if entry then
                seen[address] = true
                if math.abs(entry.mult - mult) > 0.0001 and ApplyRatio(actor, mult / entry.mult) then
                    entry.mult = mult
                end
            elseif mult > 1.0 and IsEnemy(actor, playerPawns, playerControllers) then
                if ApplyRatio(actor, mult) then
                    scaledActors[address] = { name = name, mult = mult }
                    seen[address] = true
                end
            end
        end
    end

    for address in pairs(scaledActors) do
        if not seen[address] then scaledActors[address] = nil end
    end
end

if not ENABLED then
    Log("desligado: a vida ja escala pela tabela do PAK. Para ligar, ENABLED = true no topo deste main.lua")
    return
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
