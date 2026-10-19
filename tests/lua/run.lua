local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path

local Mock = require("ue4ss_mock")

local ROOT = here .. "/../.."
local ENEMY_SCALING = ROOT .. "/ue4ss/Mods/EnemyScaling/Scripts/main.lua"
local NET_OPTIMIZE = ROOT .. "/ue4ss/Mods/NetOptimize/Scripts/main.lua"

local ENABLE_ENEMY_SCALING = { replace = { ["local ENABLED = false"] = "local ENABLED = true" } }

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

local function add_engine(w, world_object)
    w.viewport = w:spawn({ "GameViewportClient" }, { World = world_object })
    w.engine = w:spawn({ "GameEngine", "Engine" }, { GameViewport = w.viewport })
end

local function add_players(w, count)
    local states = {}
    for i = 1, count do
        if not w.player_states[i] then
            local pc = w:spawn({ "PlayerController", "Controller" }, {})
            local pawn = w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = 500, Health = 500, Controller = pc })
            set_prop(pc, "Pawn", pawn)
            w.player_pawns[i] = pawn
            w.player_states[i] = w:spawn({ "PlayerState" }, { PawnPrivate = pawn, Owner = pc })
        end
        states[i] = w.player_states[i]
    end
    set_prop(w.game_state, "PlayerArray", w:array(states))
end

local function new_enemy_level(w, players)
    w.player_pawns = {}
    w.player_states = {}
    w.ai = w:spawn({ "AIController", "Controller" }, {})
    w.game_mode = w:spawn({ "GameModeBase", "GameMode" }, {})
    w.game_state = w:spawn({ "GameStateBase", "GameState" }, { PlayerArray = w:array({}) })
    w.world_object = w:spawn({ "World" }, { AuthorityGameMode = w.game_mode, GameState = w.game_state })
    add_players(w, players)
end

local function enemy_world(players)
    local w = Mock.world()
    new_enemy_level(w, players)
    add_engine(w, w.world_object)
    w.set_players = function(count) add_players(w, count) end
    return w
end

local function spawn_enemy(w, health)
    return w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = health, Health = health, Controller = w.ai })
end

test("EnemyScaling: vem desligado no proprio script, mesmo com enabled.txt sobrando da v1.1", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING)
    w:tick(4)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
    equal(#w.loops, 0, "loops registrados")
    equal(w.find_all_calls, 0, "passadas pelo array global")
    assert(w:logged("desligado"), "log avisando que esta desligado")
end)

test("EnemyScaling: com 4 jogadores o inimigo ganha 25% de vida", function()
    local w = enemy_world(4)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth")
    near(prop(enemy, "Health"), 125, "Health")
end)

test("EnemyScaling: com 6 jogadores o inimigo ganha 75% de vida", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 175, "MaxHealth")
end)

test("EnemyScaling: com 3 jogadores nada muda e nao varre objetos", function()
    local w = enemy_world(3)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(1)
    w.find_all_calls = 0
    w:tick(4)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
    equal(w.find_all_calls, 0, "passadas pelo array global")
end)

test("EnemyScaling: uma unica passada pelo array global por scan", function()
    local w = enemy_world(5)
    spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    w.find_all_calls = 0
    w:tick(4)
    equal(w.find_all_calls, 4, "passadas pelo array global em 4 scans")
end)

test("EnemyScaling: de 6 para 4 jogadores reescala relativo e preserva a % de vida", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
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
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
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
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
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
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
    near(prop(enemy, "Health"), 0, "Health")
end)

test("EnemyScaling: personagem de jogador nao recebe vida extra", function()
    local w = enemy_world(6)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(4)
    for i, pawn in ipairs(w.player_pawns) do
        near(prop(pawn, "MaxHealth"), 500, "MaxHealth do jogador " .. i)
    end
end)

test("EnemyScaling: no cliente (sem GameMode) nada e escalado", function()
    local w = enemy_world(6)
    local enemy = spawn_enemy(w, 100)
    set_prop(w.world_object, "AuthorityGameMode", Mock.null)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(4)
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth")
end)

test("EnemyScaling: mexe nos inimigos so dentro da game thread", function()
    local w = enemy_world(4)
    local enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick_async_only()
    w:tick_async_only()
    near(prop(enemy, "MaxHealth"), 100, "MaxHealth antes da game thread")
    w:drain_game_thread()
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth depois da game thread")
end)

test("EnemyScaling: nao registra hook nem notificacao de objeto novo", function()
    local w = enemy_world(6)
    spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(4)
    equal(#w.hooks, 0, "hooks registrados")
    equal(#w.notify, 0, "NotifyOnNewObject registrados")
end)

test("EnemyScaling: inimigo que nasce depois do mod ligar tambem escala", function()
    local w = enemy_world(4)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    local enemy = spawn_enemy(w, 100)
    w:tick(1)
    near(prop(enemy, "MaxHealth"), 125, "MaxHealth")
end)

test("EnemyScaling: inimigo novo no endereco de um morto comeca do zero", function()
    local w = enemy_world(4)
    local first = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    near(prop(first, "MaxHealth"), 125, "MaxHealth do primeiro")
    local address = first:GetAddress()
    w:free(first)
    local second = w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = 200, Health = 200, Controller = w.ai }, { address = address })
    w:tick(1)
    near(prop(second, "MaxHealth"), 250, "MaxHealth do segundo")
    equal(w.use_after_free, 0, "acessos a objeto liberado")
end)

test("EnemyScaling: troca de mapa nao toca em nada do mapa antigo", function()
    local w = enemy_world(4)
    local old_enemy = spawn_enemy(w, 100)
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    local old = { old_enemy, w.ai, w.game_mode, w.game_state, w.world_object }
    for _, state in ipairs(w.player_states) do old[#old + 1] = state end
    for _, pawn in ipairs(w.player_pawns) do old[#old + 1] = pawn end
    for _, obj in ipairs(old) do w:free(obj) end
    new_enemy_level(w, 4)
    set_prop(w.viewport, "World", w.world_object)
    local new_enemy = spawn_enemy(w, 100)
    w:tick(3)
    equal(w.use_after_free, 0, "acessos a objeto liberado")
    near(prop(new_enemy, "MaxHealth"), 125, "MaxHealth no mapa novo")
end)

test("EnemyScaling: troca de mapa com inimigo no mesmo endereco e com o mesmo nome comeca do zero", function()
    local w = enemy_world(4)
    local old_enemy = w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = 100, Health = 100, Controller = w.ai }, { name = "Char_Grunt_C /Game/Map.Map:PersistentLevel.Char_Grunt_C_0" })
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(2)
    near(prop(old_enemy, "MaxHealth"), 125, "MaxHealth no mapa antigo")
    local address = old_enemy:GetAddress()
    local old = { old_enemy, w.ai, w.game_mode, w.game_state, w.world_object }
    for _, state in ipairs(w.player_states) do old[#old + 1] = state end
    for _, pawn in ipairs(w.player_pawns) do old[#old + 1] = pawn end
    for _, obj in ipairs(old) do w:free(obj) end
    new_enemy_level(w, 4)
    set_prop(w.viewport, "World", w.world_object)
    local new_enemy = w:spawn({ "CharacterGunfire", "Character" }, { MaxHealth = 100, Health = 100, Controller = w.ai }, { address = address, name = "Char_Grunt_C /Game/Map.Map:PersistentLevel.Char_Grunt_C_0" })
    w:tick(1)
    near(prop(new_enemy, "MaxHealth"), 125, "MaxHealth no mapa novo")
    equal(w.use_after_free, 0, "acessos a objeto liberado")
end)

test("EnemyScaling: jogador reconhecido so pelo pawn do PlayerState", function()
    local w = enemy_world(6)
    for _, state in ipairs(w.player_states) do set_prop(state, "Owner", Mock.null) end
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(4)
    for i, pawn in ipairs(w.player_pawns) do
        near(prop(pawn, "MaxHealth"), 500, "MaxHealth do jogador " .. i)
    end
end)

test("EnemyScaling: jogador reconhecido so pelo controller dono do PlayerState", function()
    local w = enemy_world(6)
    for _, state in ipairs(w.player_states) do set_prop(state, "PawnPrivate", Mock.null) end
    w:run(ENEMY_SCALING, ENABLE_ENEMY_SCALING)
    w:tick(4)
    for i, pawn in ipairs(w.player_pawns) do
        near(prop(pawn, "MaxHealth"), 500, "MaxHealth do jogador " .. i)
    end
end)

local function connection(w, speed)
    return w:spawn({ "SteamNetConnection", "IpConnection", "NetConnection", "Player" }, {
        CurrentNetSpeed = speed or 10000, ConfiguredInternetSpeed = 10000, ConfiguredLanSpeed = 20000,
    })
end

local function new_net_level(w, options)
    w.session = w:spawn({ "GameSession" }, { MaxPlayers = 3, MaxSpectators = 2 })
    w.game_mode = w:spawn({ "GameModeBase", "GameMode" }, { GameSession = w.session })
    w.manager = w:spawn({ "GameNetworkManager" }, {
        TotalNetBandwidth = 32000, MaxDynamicBandwidth = 7000, MinDynamicBandwidth = 4000,
    })
    w.connections = { connection(w), connection(w) }
    w.driver = w:spawn({ "SteamNetDriver", "IpNetDriver", "NetDriver" }, {
        MaxClientRate = options.max_client_rate or 10000,
        MaxInternetClientRate = 10000,
        NetServerMaxTickRate = 30,
        ServerConnection = Mock.null,
        ClientConnections = w:array(w.connections),
    })
    w.world_object = w:spawn({ "World" }, {
        AuthorityGameMode = w.game_mode, NetDriver = w.driver, NetworkManager = w.manager,
    })
end

local function net_world(options)
    options = options or {}
    local w = Mock.world()
    new_net_level(w, options)
    add_engine(w, w.world_object)
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
    for i, conn in ipairs(w.connections) do
        equal(prop(conn, "CurrentNetSpeed"), 100000, "CurrentNetSpeed do cliente " .. i)
    end
end)

test("NetOptimize: o NetDriver do host deixa de limitar a banda", function()
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
    w:free(w.connections[2])
    local returning = connection(w)
    set_prop(w.driver, "ClientConnections", w:array({ w.connections[1], returning }))
    w:tick(1)
    equal(prop(returning, "CurrentNetSpeed"), 100000, "CurrentNetSpeed de quem reconectou")
    equal(w.use_after_free, 0, "acessos a objeto liberado")
end)

test("NetOptimize: valor ja maior que o alvo nao e reduzido", function()
    local w = net_world({ max_client_rate = 200000 })
    w:run(NET_OPTIMIZE)
    w:tick(1)
    equal(prop(w.driver, "MaxClientRate"), 200000, "MaxClientRate")
end)

test("NetOptimize: no cliente (sem GameMode no mundo) nada e alterado", function()
    local w = Mock.world()
    local server_connection = connection(w)
    local driver = w:spawn({ "SteamNetDriver", "IpNetDriver", "NetDriver" }, {
        MaxClientRate = 10000, MaxInternetClientRate = 10000, NetServerMaxTickRate = 30,
        ServerConnection = server_connection, ClientConnections = w:array({}),
    })
    local world_object = w:spawn({ "World" }, { AuthorityGameMode = Mock.null, NetDriver = driver, NetworkManager = Mock.null })
    add_engine(w, world_object)
    w:run(NET_OPTIMIZE)
    w:tick(2)
    equal(prop(driver, "MaxClientRate"), 10000, "MaxClientRate do cliente")
    equal(prop(server_connection, "CurrentNetSpeed"), 10000, "CurrentNetSpeed do cliente")
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

test("NetOptimize: depois de achar o Engine nao varre mais o array global", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    w.find_all_calls = 0
    w:tick(5)
    equal(w.find_all_calls, 0, "passadas pelo array global")
end)

test("NetOptimize: troca de mapa nao toca em nada do mapa antigo", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(1)
    local old = { w.session, w.game_mode, w.manager, w.driver, w.world_object, w.connections[1], w.connections[2] }
    for _, obj in ipairs(old) do w:free(obj) end
    new_net_level(w, {})
    set_prop(w.viewport, "World", w.world_object)
    w:tick(2)
    equal(w.use_after_free, 0, "acessos a objeto liberado")
    equal(prop(w.session, "MaxPlayers"), 6, "MaxPlayers no mapa novo")
    equal(prop(w.connections[1], "CurrentNetSpeed"), 100000, "CurrentNetSpeed no mapa novo")
end)

test("NetOptimize: nao le TArray fora do tamanho (no UE4SS 3.0.1 isso le fora do buffer ou insere elementos)", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(3)
    equal(w.array_out_of_bounds_reads, 0, "leituras fora do tamanho do TArray")
end)

test("NetOptimize: nao registra hook nem notificacao de objeto novo", function()
    local w = net_world()
    w:run(NET_OPTIMIZE)
    w:tick(2)
    equal(#w.hooks, 0, "hooks registrados")
    equal(#w.notify, 0, "NotifyOnNewObject registrados")
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
