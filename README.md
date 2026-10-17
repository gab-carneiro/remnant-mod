# Remnant: From the Ashes — 6 Player Co-op Mod

Mod que aumenta o limite de jogadores em sessoes co-op do **Remnant: From the Ashes** de 3 para **6 jogadores**, com otimizacoes de rede, scaling de inimigos e protecoes contra crash.

## Quem precisa instalar o que

| Componente | Host (quem cria a sala) | Clientes (quem entra) |
|---|---|---|
| `6player.pak` | **Obrigatorio** | **Obrigatorio** |
| UE4SS + NetOptimize | **Obrigatorio** | Opcional (melhora rede) |
| EnemyScaling | Opcional (balanceamento) | Nao precisa |

> **Resumo:** Todos precisam do PAK. O **host** precisa do UE4SS + NetOptimize para o lobby aceitar mais de 3 pessoas.

---

## Instalacao rapida (recomendado)

1. Baixe `remnant-6players.zip` na pagina de [Releases](../../releases)
2. Abra a pasta do jogo: Steam > botao direito em Remnant: From the Ashes > **Gerenciar** > **Ver arquivos locais**
   (normalmente `C:\Program Files (x86)\Steam\steamapps\common\Remnant\`)
3. Extraia o zip **dentro dessa pasta** e aceite mesclar/substituir. O zip ja vem com a pasta `Remnant\` na estrutura certa:
   ```
   Remnant\Content\Paks\~mods\6player.pak
   Remnant\Binaries\Win64\Mods\NetOptimize\...
   Remnant\Binaries\Win64\Mods\EnemyScaling\...
   ```
4. **So o host:** baixe o [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (`UE4SS_v3.0.1.zip`, nao o "zDEV") e extraia em `Remnant\Remnant\Binaries\Win64\`
5. Pronto. Quem so entra na sala precisa apenas dos passos 1-3 (na pratica, so do `6player.pak`).

> **Atualizando de uma versao antiga?** Extraia o zip novo por cima. Os scripts `main.lua` do NetOptimize e do EnemyScaling mudaram; o `6player.pak` e o mesmo.

---

## Changelog

### v1.1 — fix de mobs bugando ao sair/entrar na sala

- **EnemyScaling:** quando alguem saia ou entrava, o mod re-multiplicava a vida de todos os inimigos em cima do valor ja escalado e curava eles 100%. Depois de 2 sai/entra com 5 players um mob de 100 HP ficava com ~900 HP, e mobs mortos voltavam com milhares de HP. Agora:
  - o mod lembra o multiplicador aplicado em cada inimigo e ajusta so a diferenca, mantendo a % de vida atual (sem cura gratis)
  - inimigos mortos nao sao tocados
  - a contagem de jogadores so muda depois de ficar estavel por ~6s (durante loading/join ela oscila)
  - o personagem de um jogador que acabou de reconectar nao e mais confundido com inimigo (antes ganhava HP escalado)
- **NetOptimize:** jogador que reconectava podia ficar com banda de 10KB/s (mobs teleportando/travando pra ele); o reset de configuracoes ao trocar de zona nao funcionava. Ambos corrigidos.

---

## Instalacao (passo a passo)

### 1 — Localizar a pasta do jogo

Steam > botao direito em Remnant > **Gerenciar** > **Ver arquivos locais**

```
C:\Program Files (x86)\Steam\steamapps\common\Remnant\
```

### 2 — Instalar o PAK mod (todos os jogadores)

1. Baixe `6player.pak` da pagina de [Releases](../../releases)
2. Crie a pasta `~mods` dentro de `Remnant\Content\Paks\` (se nao existir)
3. Copie `6player.pak` para `~mods`

```
Remnant\Content\Paks\
  ~mods\
    6player.pak    <-- aqui
```

### 3 — Instalar o UE4SS (obrigatorio para o host)

1. Baixe [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (zip normal, nao "zDEV")
2. Extraia tudo em `Remnant\Binaries\Win64\`
3. Se tinha UE4SS antigo, delete o `xinput1_3.dll` (v3.0+ usa `dwmapi.dll`)

### 4 — Instalar NetOptimize (obrigatorio para o host)

Copie a pasta `ue4ss/Mods/NetOptimize/` deste repositorio para `Win64\Mods\`:

```
Win64\Mods\
  NetOptimize\
    Scripts\main.lua
    enabled.txt
```

### 5 — Instalar EnemyScaling (opcional, so host)

Copie `ue4ss/Mods/EnemyScaling/` para `Win64\Mods\EnemyScaling\`

### Resultado final

```
Remnant\
  Content\Paks\~mods\
    6player.pak
  Binaries\Win64\
    dwmapi.dll          (UE4SS)
    UE4SS.dll
    UE4SS-settings.ini
    Mods\
      NetOptimize\Scripts\main.lua
      EnemyScaling\Scripts\main.lua   (opcional)
```

---

## Como jogar

1. **Host** inicia o jogo normalmente
2. No console UE4SS, confirme: `[NetOptimize] === Lobby override aplicado! ===`
3. Convide amigos via **Steam** (Shift+Tab > convidar) ou eles clicam "Entrar no Jogo" no perfil do host
4. A UI do lobby mostra so 2-3 slots, **mas jogadores extras entram normalmente**

### Console do UE4SS

O console abre automaticamente junto com o jogo. Se nao aparecer, edite `UE4SS-settings.ini`:
```ini
GuiConsoleEnabled = 1
GuiConsoleVisible = 1
```

Tambem fica tudo logado em `Win64\UE4SS.log`.

---

## Desinstalacao

| Componente | Como remover |
|---|---|
| PAK mod | Delete `6player.pak` da pasta `~mods` |
| NetOptimize | Delete `Mods/NetOptimize/` ou remova `enabled.txt` |
| EnemyScaling | Delete `Mods/EnemyScaling/` ou remova `enabled.txt` |
| UE4SS | Delete `dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini` e `Mods/` |

---

## Configuracao avancada

### EnemyScaling

Edite os valores no topo de `EnemyScaling/Scripts/main.lua`:

| Variavel | Padrao | Descricao |
|---|---|---|
| `HEALTH_PER_EXTRA` | `0.35` | +35% HP por jogador acima de 3 |
| `DAMAGE_PER_EXTRA` | `0.15` | +15% dano por jogador acima de 3 |

| Jogadores | HP dos inimigos | Dano nos jogadores |
|---|---|---|
| 1-3 | 1.00x (scaling nativo do jogo) | 1.00x |
| 4 | 1.35x | 1.15x |
| 5 | 1.70x | 1.30x |
| 6 | 2.05x | 1.45x |

Se alguem sai ou entra, os inimigos ja vivos sao ajustados para o novo valor mantendo a % de vida.

### NetOptimize

| Variavel | Padrao | Descricao |
|---|---|---|
| `MAX_PLAYERS_FALLBACK` | `6` | Fallback se leitura do GameSession falhar |
| `SMOOTH_LOCATION_TIME` | `0.100` | Interpolacao de posicao (s) |
| `MAX_SMOOTH_DISTANCE` | `512.0` | Distancia max para suavizar |
| `PLAYER_NET_PRIORITY` | `3.0` | Prioridade de rede dos jogadores |
| `MIN_NET_UPDATE_FREQ` | `15.0` | Update minimo de rede (Hz) |

### Gerando PAK customizado

```bash
# Requer Python 3

# 1. Gerar DataTable com scaling para N players
python rebuild_scaling.py

# 2. Gerar PAK
python build_pak.py --players 8
```

| Flag | Padrao | Descricao |
|---|---|---|
| `--players` | `6` | Numero maximo de jogadores |
| `--output` | `{N}player.pak` | Nome do arquivo de saida |
| `--no-scaling` | — | Nao incluir DataTable de scaling |

---

## Limitacoes

| Limitacao | Detalhe |
|---|---|
| UI do lobby | Mostra 2-3 slots. Jogadores extras entram, mas nao aparecem na lista. |
| Spawn points | O jogo tem 4 spawn points fixos. Players 5-6 reutilizam posicoes existentes. |
| Compatibilidade | Apenas **Remnant: From the Ashes** (UE4). Nao funciona com Remnant 2. |
| Host obrigatorio | O host precisa de UE4SS + NetOptimize. |

---

## Como funciona

### Camadas do mod

```
+----------------------------------------------------------+
|  Camada 4: UE4SS Lua (runtime)                           |
|  NetOptimize: forca MaxPlayers, CVars, smoothing,        |
|  detecta zone travel, monitora death/respawn             |
|  EnemyScaling: escala HP/dano dos inimigos               |
+----------------------------------------------------------+
|  Camada 3: DataTable Stats_Scaling_NumPlayers (PAK)      |
|  Tabela de scaling nativa com rows para 5P e 6P          |
+----------------------------------------------------------+
|  Camada 2: DefaultGame.ini (PAK)                         |
|  MaxPlayers=6, bandwidth, tick rate, timeouts            |
+----------------------------------------------------------+
|  Camada 1: Jogo original (MaxPlayers=3)                  |
+----------------------------------------------------------+
```

### Protecoes contra crash

| Protecao | Descricao |
|---|---|
| DataTable 6 rows | `FindRow("5")` e `FindRow("6")` retornam dados validos em vez de nullptr |
| Lobby persistente | MaxPlayers verificado a cada 4s, re-aplicado se o jogo resetar para 3 |
| Zone travel detection | Detecta mudanca de zona e re-aplica lobby, CVars, smoothing automaticamente |
| Death monitoring | Monitora players alive/dead, loga avisos em team wipe com 5+ players |
| Spawn point fallback | Engine faz round-robin se ha mais players que spawn points |
| Bandwidth forcing | Forca 200KB/s em todos os clientes (default e 10KB/s sem mod) |

### DataTable de scaling

| Property | 1P | 2P | 3P | 4P | 5P | 6P |
|---|---|---|---|---|---|---|
| SpawnQuantity | 1.00 | 1.33 | 1.66 | 2.00 | 2.33 | 2.66 |
| SpawnWeight | 1.00 | 1.50 | 1.75 | 1.60 | 1.60 | 1.60 |

### Otimizacoes de rede (PAK)

| Config | Default | Mod | Efeito |
|---|---|---|---|
| NetServerMaxTickRate | 30 | 60 | Tick rate do servidor |
| MaxClientRate | 15,000 | 200,000 | Banda max por cliente |
| TotalNetBandwidth | 32,000 | 1,200,000 | Banda total |
| MAXPOSITIONERRORSQUARED | 3.0 | 25.0 | Tolerancia de posicao |

### CVars aplicadas em runtime

| CVar | Valor | Efeito |
|---|---|---|
| `p.NetEnableListenServerSmoothing` | `1` | Smoothing no listen server |
| `p.NetClientSmoothingMode` | `2` | Interpolacao exponencial |
| `net.DisableBandwidthThrottling` | `1` | Evita stall de bandwidth |
| `net.MaxRPCPerNetUpdate` | `4` | Limita RPCs por tick |

---

## Estrutura do projeto

```
remnant-mod/
  6player.pak          PAK pronto para uso
  4player.pak          PAK base (input do build_pak)
  build_pak.py         Gerador de PAK v8
  rebuild_scaling.py   Gerador de DataTable com N rows
  modified/            DataTable modificada (gerada pelo rebuild_scaling)
  ue4ss/Mods/
    NetOptimize/       Lobby override + rede + protecoes
    EnemyScaling/      Scaling de HP/dano extra
```
