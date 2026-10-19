local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path

local Mock = require("ue4ss_mock")

local ROOT = here .. "/../.."
local ENEMY_SCALING = ROOT .. "/ue4ss/Mods/EnemyScaling/Scripts/main.lua"
local NET_OPTIMIZE = ROOT .. "/ue4ss/Mods/NetOptimize/Scripts/main.lua"

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function equal(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: esperado %s, veio %s", what, tostring(expected), tostring(actual)), 2)
    end
end

local function near(actual, expected, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
        error(string.format("%s: esperado %s, veio %s", what, tostring(expected), tostring(actual)), 2)
    end
end

local function prop(obj, key)
    return rawget(obj, "_props")[key]
end

local function set_prop(obj, key, value)
    rawget(obj, "_props")[key] = value
end

local function enemy_world(players)
    local w = Mock.world()
    w.game_state = w:spawn({ "GameStateBase", "GameState" }, { PlayerArray = w:array({}) })
    w.ai = w:spawn({ "AIController", "Controller" }, {})
    w.player_pawns = {}
    w.set_players = function(count)
        local states = {}
        for i = 1, count do
            states[i] = w:spawn({ "PlayerState" }, {})
            if not w.player_pawns[i] then
                local pc = w:spawn({ "PlayerController", "Controller" }, {})
                local pawn = w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = 500, Health = 500, Controller = pc })
                set_prop(pc, "Pawn", pawn)
                w.player_pawns[i] = pawn
            end
        end
        set_prop(w.game_state, "PlayerArray", w:array(states))
    end
    w.set_players(players)
    return w
end

local function spawn_enemy(w, health)
    return w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = health, Health = health, Controller = w.ai })
end

test("EnemyScaling: com 4 jogadores o inimigo ganha 25% de vida", function()
    local w = enemy_world(4)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth")
    near(prop(enemy, "Health"), 125, "Health")
end)

test("EnemyScaling: com 6 jogadores o inimigo ganha 75% de vida", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 175, "MaxHealth")
end)

test("EnemyScaling: com 3 jogadores nada muda (escala nativa do jogo)", function()
    local w = enemy_world(3)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(4)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
end)

test("EnemyScaling: de 6 para 4 jogadores reescala relativo e preserva a % de vida", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(2)
    set_prop(enemy, "Health", 87.5)
    w.set_players(4)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth")
    near(prop(enemy, "Health"), 62.5, "Health")
end)

test("EnemyScaling: sai e entra varias vezes sem acumular vida", function()
    local w = enemy_world(5)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(2)
    for _ = 1, 3 do
        w.set_players(4)
        w:tick(2)
        w.set_players(5)
        w:tick(2)
    end
    near(prop(enemy, "MaxHealth"), 150, "MaxHealth")
    near(prop(enemy, "Health"), 150, "Health")
end)

test("EnemyScaling: oscilacao de um scan nao muda a escala", function()
    local w = enemy_world(5)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(2)
    w.set_players(4)
    w:tick(1)
    w.set_players(5)
    w:tick(3)
    near(prop(enemy, "MaxHealth"), 150, "MaxHealth")
end)

test("EnemyScaling: inimigo morto nao e tocado", function()
    local w = enemy_world(4)
    local enemy = spawn_enemy(w, 100)
    set_prop(enemy, "Health", 0)
    w:run(ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
    near(prop(enemy, "Health"), 0, "Health")
end)

test("EnemyScaling: personagem de jogador nao recebe vida extra", function()
    local w = enemy_world(6)
    w:run(ENEMY_SCALING)
    w:tick(4)
    for i, pawn in ipairs(w.player_pawns) do
        near(prop(pawn, "MaxHealth"), 500, "MaxHealth do jogador " .. i)
    end
end)

test("EnemyScaling: no cliente (IA sem controller) nada e escalado", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    set_prop(enemy, "Controller", Mock.null)
    w:run(ENEMY_SCALING)
    w:tick(4)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
end)

test("EnemyScaling: mexe nos inimigos so dentro da game thread", function()
    local w = enemy_world(4)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick_async_only()
    w:tick_async_only()
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth antes da game thread")
    w:drain_game_thread()
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth depois da game thread")
end)

test("EnemyScaling: nao registra hook de dano (o dano escala pela DataTable do PAK)", function()
    local w = enemy_world(6)
    spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(4)
    equal(#w.hooks, 0, "hooks registrados")
end)

local function net_world(options)
    options = options or {}
    local w = Mock.world()
    w.session = w:spawn({ "GameSession" }, { MaxPlayers = 3, MaxSpectators = 2 })
    w.game_mode = w:spawn({ "GameModeBase", "GameMode" }, { GameSession = w.session })
    w.manager = w:spawn({ "GameNetworkManager" }, {
        TotalNetBandwidth = 32000, MaxDynamicBandwidth = 7000, MinDynamicBandwidth = 4000,
    })
    w.connections = {}
    for i = 1, 2 do
        w.connections[i] = w:spawn({ "SteamNetConnection", "IpConnection", "NetConnection", "Player" }, {
            CurrentNetSpeed = 10000, ConfiguredInternetSpeed = 10000, ConfiguredLanSpeed = 20000,
        })
    end
    w.driver = w:spawn({ "SteamNetDriver", "IpNetDriver", "NetDriver" }, {
        MaxClientRate = options.max_client_rate or 15000,
        MaxInternetClientRate = 10000,
        NetServerMaxTickRate = 30,
        ServerConnection = Mock.null,
        ClientConnections = w:array(w.connections),
    })
    w.local_player = w:spawn({ "LocalPlayer", "Player" }, {
        CurrentNetSpeed = 10000, ConfiguredInternetSpeed = 10000, ConfiguredLanSpeed = 20000,
    })
    w.pawns = {}
    local players = { w.local_player, w.connections[1], w.connections[2] }
    for i, player in ipairs(players) do
        local pawn = w:spawn({ "CharacterGunfire", "Character", "Pawn" }, {
            NetPriority = 3.0, MinNetUpdateFrequency = 2.0, bAlwaysRelevant = false,
        })
        w:spawn({ "PlayerController", "Controller" }, { Player = player, Pawn = pawn })
        w.pawns[i] = pawn
    end
    w.movement = w:spawn({ "CharacterMovementComponent" }, {
        NetworkSimulatedSmoothLocationTime = 0.1,
        NetworkSimulatedSmoothRotationTime = 0.05,
        ListenServerNetworkSimulatedSmoothLocationTime = 0.04,
        ListenServerNetworkSimulatedSmoothRotationTime = 0.033,
        NetworkMaxSmoothUpdateDistance = 256.0,
        NetworkNoSmoothUpdateDistance = 384.0,
    })
    return w
end

test("NetOptimize: GameSession aceita 6 jogadores", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    equal(prop(w.session, "MaxPlayers"), 6, "GameSession.MaxPlayers")
    assert(w:logged("MaxPlayers 3 %-> 6"), "log da mudanca de MaxPlayers")
end)

test("NetOptimize: o jogo voltar MaxPlayers para 3 e corrigido no proximo scan", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    set_prop(w.session, "MaxPlayers", 3)
    w:tick(1)
    equal(prop(w.session, "MaxPlayers"), 6, "GameSession.MaxPlayers")
end)

test("NetOptimize: cada cliente conectado recebe 100000 B/s", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    for i, connection in ipairs(w.connections) do
        equal(prop(connection, "CurrentNetSpeed"), 100000, "CurrentNetSpeed do cliente " .. i)
    end
end)

test("NetOptimize: o NetDriver do host deixa de limitar a 15000 B/s", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    equal(prop(w.driver, "MaxClientRate"), 100000, "MaxClientRate")
    equal(prop(w.driver, "MaxInternetClientRate"), 100000, "MaxInternetClientRate")
end)

test("NetOptimize: a banda dinamica do GameNetworkManager nao derruba os clientes", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    equal(prop(w.manager, "TotalNetBandwidth"), 600000, "TotalNetBandwidth")
    equal(prop(w.manager, "MaxDynamicBandwidth"), 100000, "MaxDynamicBandwidth")
end)

test("NetOptimize: quem reconecta volta para 100000 B/s", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    w:destroy(w.connections[2])
    local returning = w:spawn({ "SteamNetConnection", "IpConnection", "NetConnection", "Player" }, {
        CurrentNetSpeed = 10000, ConfiguredInternetSpeed = 10000, ConfiguredLanSpeed = 20000,
    })
    set_prop(w.driver, "ClientConnections", w:array({ w.connections[1], returning }))
    w:tick(1)
    equal(prop(returning, "CurrentNetSpeed"), 100000, "CurrentNetSpeed de quem reconectou")
end)

test("NetOptimize: valor ja maior que o alvo nao e reduzido", function()
    local w = net_world({ max_client_rate = 200000 })
    w:run(NET_OPTIMIZE)
    w:tick(1)
    equal(prop(w.driver, "MaxClientRate"), 200000, "MaxClientRate")
end)

test("NetOptimize: no cliente (sem GameMode) nada e alterado", function()
    local w = Mock.world()
    local server_connection = w:spawn({ "SteamNetConnection", "NetConnection", "Player" }, {
        CurrentNetSpeed = 10000, ConfiguredInternetSpeed = 10000, ConfiguredLanSpeed = 20000,
    })
    local driver = w:spawn({ "SteamNetDriver", "IpNetDriver", "NetDriver" }, {
        MaxClientRate = 15000, MaxInternetClientRate = 10000, NetServerMaxTickRate = 30,
        ServerConnection = server_connection, ClientConnections = w:array({}),
    })
    local session = w:spawn({ "GameSession" }, { MaxPlayers = 3 })
    w:run(NET_OPTIMIZE)
    w:tick(2)
    equal(prop(driver, "MaxClientRate"), 15000, "MaxClientRate do cliente")
    equal(prop(server_connection, "CurrentNetSpeed"), 10000, "CurrentNetSpeed do cliente")
    equal(prop(session, "MaxPlayers"), 3, "MaxPlayers no cliente")
end)

test("NetOptimize: mexe na engine so dentro da game thread", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick_async_only()
    equal(prop(w.session, "MaxPlayers"), 3, "MaxPlayers antes da game thread")
    equal(prop(w.connections[1], "CurrentNetSpeed"), 10000, "CurrentNetSpeed antes da game thread")
    w:drain_game_thread()
    equal(prop(w.session, "MaxPlayers"), 6, "MaxPlayers depois da game thread")
    equal(prop(w.connections[1], "CurrentNetSpeed"), 100000, "CurrentNetSpeed depois da game thread")
end)

test("NetOptimize: nao indexa TArray da engine (no UE4SS 3.0.1 isso pode inserir elementos)", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(3)
    equal(w.array_index_reads, 0, "leituras por indice em TArray")
end)

test("NetOptimize: o netcode do jogo fica como o original", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(3)
    equal(#w.console, 0, "console commands executados")
    equal(prop(w.driver, "NetServerMaxTickRate"), 30, "NetServerMaxTickRate")
    near(prop(w.movement, "NetworkSimulatedSmoothLocationTime"), 0.1, "smoothing de posicao")
    near(prop(w.movement, "NetworkSimulatedSmoothRotationTime"), 0.05, "smoothing de rotacao")
    near(prop(w.movement, "ListenServerNetworkSimulatedSmoothLocationTime"), 0.04, "smoothing do host")
    near(prop(w.movement, "NetworkMaxSmoothUpdateDistance"), 256.0, "distancia de smoothing")
    for i, pawn in ipairs(w.pawns) do
        equal(prop(pawn, "bAlwaysRelevant"), false, "bAlwaysRelevant do jogador " .. i)
        near(prop(pawn, "MinNetUpdateFrequency"), 2.0, "MinNetUpdateFrequency do jogador " .. i)
    end
    equal(prop(w.local_player, "CurrentNetSpeed"), 10000, "CurrentNetSpeed do host local")
end)

local failed = 0
for _, case in ipairs(tests) do
    local ok, err = pcall(case.fn)
    if ok then
        print("ok    " .. case.name)
    else
        failed = failed + 1
        print("FALHA " .. case.name .. "\n      " .. tostring(err))
    end
end
print(string.format("\n%d testes, %d falhas", #tests, failed))
os.exit(failed == 0 and 0 or 1)
