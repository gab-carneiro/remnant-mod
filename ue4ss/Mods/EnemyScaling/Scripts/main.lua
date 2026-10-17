--[[
    EnemyScaling — Remnant: From the Ashes
    Escala vida e dano dos inimigos proporcionalmente ao numero de jogadores.

    O jogo escala nativamente ate 3 jogadores. Este mod adiciona scaling
    extra para 4+ jogadores via UE4SS.

    Requer: UE4SS v3.0.1+ (https://github.com/UE4SS-RE/RE-UE4SS)
]]

------------------------------------------------------------
-- CONFIGURACAO (edite aqui)
------------------------------------------------------------

-- Bonus POR JOGADOR acima de 3. Com 6 players:
--   HP:   1 + 3*0.35 = 2.05x
--   Dano: 1 + 3*0.15 = 1.45x
local HEALTH_PER_EXTRA = 0.35
local DAMAGE_PER_EXTRA = 0.15

-- Numero de jogadores que o jogo ja escala nativamente
local BASE_PLAYERS = 3

-- Intervalo de scan em milissegundos
local SCAN_INTERVAL_MS = 3000

-- Logs no console do UE4SS (desative para menos spam)
local LOG_ENABLED = true

------------------------------------------------------------
-- ESTADO INTERNO
------------------------------------------------------------

-- Numero de jogadores em uso no scaling (so muda depois de estabilizar)
local currentPlayers = 0

-- Debounce: durante join/leave/travel o PlayerArray oscila.
-- So aceitamos um novo valor se ele se repetir em scans seguidos.
local pendingPlayers = -1
local pendingScans = 0
local STABLE_SCANS = 2

-- Inimigos ja escalados, por endereco:
--   { name = full name do ator, mult = multiplicador aplicado nele }
-- Guardar o multiplicador aplicado permite re-escalar de forma RELATIVA
-- quando alguem sai/entra (antes o mod limpava a tabela, multiplicava de
-- novo em cima do valor ja escalado e curava o mob 100%).
local scaledActors = {}

-- Classe de inimigos descoberta (cache)
local enemyClassName = nil

-- Cache dos pawns de jogadores (atualizado a cada scan, usado no hook de dano)
local playerPawnCache = {}

-- Nomes de classes para tentar (GunfireRuntime / Remnant / generico)
local CHARACTER_CLASSES = {
    "CharacterGunfire",
    "RemnantCharacter",
    "AICharacterGunfire",
    "Character",
}

-- Nomes de propriedades de vida para tentar
local HEALTH_PROPS = {
    -- { property_de_max, property_de_current }
    { "MaxHealth",    "Health" },
    { "MaxHitPoints", "HitPoints" },
    { "HealthMax",    "HealthCurrent" },
}

-- Componentes onde a vida pode estar
local HEALTH_COMPONENTS = {
    "DamageableComponent",
    "StatsComponent",
    "HealthComponent",
}

------------------------------------------------------------
-- UTILIDADES
------------------------------------------------------------

local function Log(msg)
    if LOG_ENABLED then
        print("[EnemyScaling] " .. msg .. "\n")
    end
end

local function ExtraPlayers()
    return math.max(currentPlayers - BASE_PLAYERS, 0)
end

local function HealthMultiplier()
    return 1.0 + ExtraPlayers() * HEALTH_PER_EXTRA
end

local function DamageMultiplier()
    return 1.0 + ExtraPlayers() * DAMAGE_PER_EXTRA
end

-- Nome completo do objeto (detecta reuso de endereco por outro ator)
local function SafeFullName(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and type(name) == "string" then return name end
    return ""
end

------------------------------------------------------------
-- PLAYER COUNT
------------------------------------------------------------

local function UpdatePlayerCount()
    local ok, state = pcall(FindFirstOf, "GameStateBase")
    if not ok or not state or not state:IsValid() then return end

    local ok2, count = pcall(function() return state.PlayerArray:GetArrayNum() end)
    if not ok2 or type(count) ~= "number" or count <= 0 then
        -- Loading/travel: PlayerArray vazio. Mantem o valor atual.
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
        Log(string.format(
            "Jogadores: %d -> %d | HP x%.2f | Dano x%.2f",
            old, count, HealthMultiplier(), DamageMultiplier()
        ))
        -- NAO limpa scaledActors: o loop re-escala os inimigos existentes
        -- de forma relativa ao multiplicador que ja foi aplicado neles.
    end
end

------------------------------------------------------------
-- IDENTIFICACAO DE INIMIGOS
------------------------------------------------------------

-- Retorna (pawns, controllers): enderecos dos pawns e PlayerControllers
local function GetPlayers()
    local pawns, pcs = {}, {}
    local ok, controllers = pcall(FindAllOf, "PlayerController")
    if not ok or not controllers then return pawns, pcs end

    for _, pc in ipairs(controllers) do
        if pc:IsValid() then
            pcs[pc:GetAddress()] = true
            local ok2, pawn = pcall(function() return pc.Pawn end)
            if ok2 and pawn and pawn:IsValid() then
                pawns[pawn:GetAddress()] = true
            end
        end
    end
    return pawns, pcs
end

-- Inimigo = controlado por um controller que NAO e PlayerController.
-- Sem controller (ex: pawn de jogador que acabou de entrar/reconectar e
-- ainda nao foi possuido) -> nao mexe agora, tenta no proximo scan.
local function IsEnemy(actor, playerPawns, playerControllers)
    if playerPawns[actor:GetAddress()] then return false end

    local ok, ctrl = pcall(function() return actor.Controller end)
    if not ok or not ctrl or not ctrl:IsValid() then return false end

    return not playerControllers[ctrl:GetAddress()]
end

-- Descobre qual classe de personagem existe no jogo
local function DiscoverEnemyClass()
    if enemyClassName then return enemyClassName end

    for _, name in ipairs(CHARACTER_CLASSES) do
        local ok, actors = pcall(FindAllOf, name)
        if ok and actors and #actors > 0 then
            enemyClassName = name
            Log("Classe de personagens encontrada: " .. name)
            return name
        end
    end
    return nil
end

------------------------------------------------------------
-- HEALTH SCALING
------------------------------------------------------------

local function ReadNumber(obj, prop)
    local ok, val = pcall(function() return obj[prop] end)
    if ok and type(val) == "number" then return val end
    return nil
end

-- Acha onde fica a vida do ator: retorna (objeto, propMax, propCur, label)
local function FindHealth(actor)
    for _, props in ipairs(HEALTH_PROPS) do
        local maxHp = ReadNumber(actor, props[1])
        if maxHp and maxHp > 0 then
            return actor, props[1], props[2], "direto"
        end
    end

    for _, compName in ipairs(HEALTH_COMPONENTS) do
        local ok, comp = pcall(function() return actor[compName] end)
        if ok and comp and comp:IsValid() then
            for _, props in ipairs(HEALTH_PROPS) do
                local maxHp = ReadNumber(comp, props[1])
                if maxHp and maxHp > 0 then
                    return comp, props[1], props[2], compName
                end
            end
        end
    end
    return nil
end

-- Multiplica vida max e atual por 'ratio', mantendo a % de vida do mob.
-- Mob morto (vida atual <= 0) nao e tocado para nao "reviver".
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

------------------------------------------------------------
-- DAMAGE SCALING
------------------------------------------------------------

-- Caminhos de funcoes de dano para tentar hookar
local DAMAGE_HOOKS = {
    "/Script/GunfireRuntime.DamageableComponent:TakeDamage",
    "/Script/GunfireRuntime.CharacterGunfire:TakeDamage",
    "/Script/Engine.Actor:ReceiveAnyDamage",
}

local damageHooked = false

local function TryHookDamage()
    if damageHooked then return end

    for _, path in ipairs(DAMAGE_HOOKS) do
        local ok, hookId = pcall(function()
            return RegisterHook(path, function(Context, Damage, ...)
                if not Context:IsValid() then return end
                if DAMAGE_PER_EXTRA <= 0 then return end

                local mult = DamageMultiplier()
                if mult <= 1.0 then return end

                -- So escala se o alvo eh um jogador (cache do ultimo scan,
                -- evita FindAllOf a cada hit)
                local targetAddr = Context:get():GetAddress()

                -- Se Context eh o componente, pega o owner
                local ok2, owner = pcall(function() return Context:get():GetOwner() end)
                if ok2 and owner and owner:IsValid() then
                    targetAddr = owner:GetAddress()
                end

                if playerPawnCache[targetAddr] then
                    -- Multiplica o dano recebido pelo jogador
                    if Damage and Damage.get then
                        local currentDmg = Damage:get()
                        if type(currentDmg) == "number" and currentDmg > 0 then
                            Damage:set(currentDmg * mult)
                        end
                    end
                end
            end)
        end)

        if ok and hookId then
            damageHooked = true
            Log("Hook de dano registrado: " .. path)
            return
        end
    end

    Log("Nenhum hook de dano encontrado (apenas HP sera escalado)")
end

------------------------------------------------------------
-- LOOP PRINCIPAL
------------------------------------------------------------

Log("=== EnemyScaling carregado ===")
Log(string.format(
    "Config: +%.0f%% HP / +%.0f%% Dano por jogador acima de %d",
    HEALTH_PER_EXTRA * 100, DAMAGE_PER_EXTRA * 100, BASE_PLAYERS
))

-- Tenta hookar funcoes de dano uma vez na inicializacao
TryHookDamage()

local function Scan()
    UpdatePlayerCount()

    local playerPawns, playerControllers = GetPlayers()
    playerPawnCache = playerPawns

    local mult = HealthMultiplier()

    -- Nada escalado e nada a escalar
    if mult <= 1.0 and next(scaledActors) == nil then return end

    if mult > 1.0 then TryHookDamage() end

    local className = DiscoverEnemyClass()
    if not className then return end

    local ok, actors = pcall(FindAllOf, className)
    if not ok or not actors then actors = {} end

    local seen = {}
    for _, actor in ipairs(actors) do
        if actor:IsValid() then
            local addr = actor:GetAddress()
            local name = SafeFullName(actor)
            local entry = scaledActors[addr]

            -- Endereco reaproveitado por outro ator: trata como novo
            if entry and entry.name ~= name then entry = nil end

            if entry then
                seen[addr] = true
                if math.abs(entry.mult - mult) > 0.0001 then
                    -- Player saiu/entrou: ajusta relativo ao que ja foi aplicado
                    if ApplyRatio(actor, mult / entry.mult) then
                        entry.mult = mult
                    end
                end
            elseif mult > 1.0 and IsEnemy(actor, playerPawns, playerControllers) then
                if ApplyRatio(actor, mult) then
                    scaledActors[addr] = { name = name, mult = mult }
                    seen[addr] = true
                end
            end
        end
    end

    -- Remove atores que nao existem mais (morreram / travel)
    for addr in pairs(scaledActors) do
        if not seen[addr] then scaledActors[addr] = nil end
    end
end

-- Scan periodico
LoopAsync(SCAN_INTERVAL_MS, function()
    local ok, err = pcall(Scan)
    if not ok then Log("Erro no scan: " .. tostring(err)) end
    return false -- continua o loop
end)
