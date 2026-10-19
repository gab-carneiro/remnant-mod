# Remnant: From the Ashes — Co-op ate 6 jogadores

Mod que libera co-op de ate **6 jogadores** no **Remnant: From the Ashes**, com os inimigos escalando para nao ficar facil e a rede do host ajustada para aguentar 5 clientes.

## Quem instala o que

| Componente | Host (quem cria a sala) | Clientes (quem entra) |
|---|---|---|
| `6player_P.pak` | **Obrigatorio** | Nao precisa |
| UE4SS + NetOptimize | **Obrigatorio** | Nao precisa |
| EnemyScaling | Vem desligado; so se o teste mandar | Nao precisa |

> **Resumo:** so o host instala. Quem entra na sala joga com o jogo original.

---

## Instalacao (host)

1. Baixe `remnant-6players.zip` na pagina de [Releases](../../releases)
2. Abra a pasta do jogo: Steam > botao direito em Remnant: From the Ashes > **Gerenciar** > **Ver arquivos locais**
   (normalmente `C:\Program Files (x86)\Steam\steamapps\common\Remnant\`)
3. Extraia o zip **dentro dessa pasta** e aceite mesclar/substituir. O zip ja vem com a pasta `Remnant\` na estrutura certa:
   ```
   Remnant\Content\Paks\~mods\6player_P.pak
   Remnant\Binaries\Win64\Mods\NetOptimize\...
   Remnant\Binaries\Win64\Mods\EnemyScaling\...
   ```
4. Baixe o [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (`UE4SS_v3.0.1.zip`, nao o "zDEV") e extraia em `Remnant\Binaries\Win64\`, a mesma pasta onde ficou a pasta `Mods` do passo 3
5. **Atualizando de versao antiga?** Apague `Remnant\Content\Paks\~mods\6player.pak` (sem o `_P`). Ele nunca chegou a carregar no jogo. Quem instalou o UE4SS como cliente na v1.1 tambem extrai o zip novo por cima, ou apaga a pasta `Mods\EnemyScaling`

### Resultado final

```
Remnant\
  Content\Paks\~mods\
    6player_P.pak
  Binaries\Win64\
    dwmapi.dll          (UE4SS)
    UE4SS.dll
    UE4SS-settings.ini
    Mods\
      NetOptimize\Scripts\main.lua
      EnemyScaling\Scripts\main.lua   (reserva, desligado)
```

---

## Teste de 2 minutos: o PAK carregou?

O PAK so funciona se o jogo carregar ele, e isso so da para confirmar jogando. Faca uma vez, solo:

1. Baixe `6player_0_TESTE_P.pak` na mesma release
2. Em `Remnant\Content\Paks\~mods\`, tire o `6player_P.pak` e coloque o `6player_0_TESTE_P.pak` no lugar
3. Jogue solo alguns minutos numa area com inimigos. Com o PAK de teste o solo fica com **3x mais inimigos**, que aguentam **3x mais tiros** e cujos golpes tiram **3x mais vida**
4. Apague o `6player_0_TESTE_P.pak` e volte o `6player_P.pak`. Se os dois ficarem juntos em `~mods`, vale o `6player_P.pak`

| O que aconteceu | Significado |
|---|---|
| Mais inimigos, mais resistentes e batendo mais forte | Tudo certo |
| Inimigos com a resistencia normal | O jogo nao usa a coluna de vida da tabela: ative o EnemyScaling (veja [Vida pelo Lua](#vida-pelo-lua-reserva)) |
| Golpes com o dano normal | O jogo nao usa a coluna de dano da tabela. Abra uma issue |
| Nada mudou | Confira se tirou o `6player_P.pak` (com os dois em `~mods`, o de teste nao vale). Se tirou, o PAK nao carregou: abra uma issue |

---

## Como jogar

1. **Host** inicia o jogo normalmente
2. No console do UE4SS aparece `[NetOptimize] === NetOptimize carregado ===` e, ao entrar no mundo, `[NetOptimize] GameSession.MaxPlayers 3 -> 6`
3. Convide amigos via **Steam** (Shift+Tab > convidar) ou eles clicam "Entrar no Jogo" no perfil do host
4. A cada amigo que entra aparece algo como `[NetOptimize] Cliente.CurrentNetSpeed 10000 -> 100000` (o primeiro numero e a banda que o jogo tinha dado para ele)
5. A UI do lobby mostra so 2-3 slots, **mas jogadores extras entram normalmente**

### Console do UE4SS

O UE4SS 3.0.1 vem com o console escondido. Para ele abrir junto com o jogo, edite `UE4SS-settings.ini`:
```ini
GuiConsoleEnabled = 1
GuiConsoleVisible = 1
```

Tambem fica tudo logado em `Win64\UE4SS.log`.

---

## Dificuldade

| Jogadores | Quantidade de inimigos | Vida (comum, elite, brute) | Vida (chefe) | Dano dos inimigos |
|---|---|---|---|---|
| 1 | 1.00x | 1.00x | 1.00x | 1.00x |
| 2 | 1.33x | 1.00x | 1.00x | 1.00x |
| 3 | 1.66x | 1.00x | 1.00x | 1.00x |
| 4 | 2.00x | 1.15x | 1.35x | 1.10x |
| 5 | 2.33x | 1.30x | 1.70x | 1.20x |
| 6 | 2.66x | 1.45x | 2.05x | 1.30x |

Tudo isso sai da tabela nativa do jogo (`Stats_Scaling_NumPlayers`), que o proprio Remnant aplica em cada tipo de inimigo. As linhas 1 a 4 sao do jogo; o PAK acrescenta 5 e 6 seguindo a mesma progressao de quantidade, e liga as colunas de vida e dano a partir de 4 jogadores.

Na tabela original, vida e dano ficam em 1.0 de 1 a 4 jogadores; so a quantidade de inimigos muda. Com 6 jogadores ha o dobro de poder de fogo de 3, mas so 1.6x mais inimigos, por isso a vida e o dano extras. O chefe escala mais porque nao vem mais chefes com mais jogadores: com 6, ele aguenta o dobro, o mesmo que os 3 jogadores a mais tiram dele.

### Ajustar

Edite no topo de `rebuild_scaling.py`, rode `python build_pak.py` e troque o `6player_P.pak`:

| Variavel | Padrao | Descricao |
|---|---|---|
| `HEALTH_PER_EXTRA` | `0.15` | +15% de vida (comum, elite, brute) por jogador acima de 3 |
| `BOSS_HEALTH_PER_EXTRA` | `0.35` | +35% de vida do chefe por jogador acima de 3 |
| `DAMAGE_PER_EXTRA` | `0.10` | +10% de dano por jogador acima de 3 |

### Vida pelo Lua (reserva)

O EnemyScaling so serve se o teste de 2 minutos mostrar que o jogo ignora a coluna de vida. Ele vem **desligado no proprio script**: no console aparece `[EnemyScaling] desligado...`. Para ligar, troque `local ENABLED = false` por `local ENABLED = true` no topo de `Mods\EnemyScaling\Scripts\main.lua` e reinicie o jogo. Nao ligue com a coluna de vida funcionando, senao a vida escala duas vezes. Cada atualizacao do mod traz o `main.lua` desligado de novo.

Ele da +25% de vida por jogador acima de 3, igual para todos os inimigos (`HEALTH_PER_EXTRA` no topo do `main.lua`). Quando alguem sai ou entra, os inimigos vivos se ajustam mantendo a % de vida. Para achar os inimigos ele percorre a lista de objetos do jogo a cada 5 s, o que pode causar uma travadinha leve no host.

---

## Rede

Pelo padrao da Unreal 4, o host manda no maximo **10 KB/s** para cada cliente. Com 6 jogadores e mais inimigos esse limite estoura e os inimigos comecam a teleportar para quem entrou.

O NetOptimize (so no host) sobe esse limite para **100 KB/s por cliente**, o padrao das versoes novas da Unreal, e nao mexe em mais nada do netcode: smoothing, tick rate e relevancia ficam como o jogo vem. O limite e um teto, nao um consumo; no pior caso, 5 clientes usariam cerca de 4 Mbps de upload do host.

| Variavel (`NetOptimize/Scripts/main.lua`) | Padrao | Descricao |
|---|---|---|
| `MAX_PLAYERS` | `6` | Limite da sala |
| `CLIENT_NET_SPEED` | `100000` | Banda maxima por cliente, em bytes/s |

---

## Desinstalacao

| Componente | Como remover |
|---|---|
| PAK | Delete `6player_P.pak` da pasta `~mods` |
| NetOptimize | Delete `Mods/NetOptimize/` ou remova `enabled.txt` |
| EnemyScaling | Delete `Mods/EnemyScaling/` ou remova `enabled.txt` |
| UE4SS | Delete `dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini` e `Mods/` |

---

## Limitacoes

| Limitacao | Detalhe |
|---|---|
| UI do lobby | Mostra 2-3 slots. Jogadores extras entram, mas nao aparecem na lista |
| Spawn points | O jogo tem 4 spawn points fixos. Jogadores 5 e 6 reutilizam posicoes existentes |
| Compatibilidade | Apenas **Remnant: From the Ashes** (Unreal 4.22). Nao funciona com Remnant 2 |
| Host obrigatorio | Quem cria a sala precisa de UE4SS + NetOptimize |

---

## Changelog

### v1.2 — PAK carregando de verdade, dano e rede funcionando

- **PAK:** desde a conversao para o formato v8 ele nunca tinha carregado. O rodape nao tinha o GUID de criptografia, e o Unreal 4.22 lia lixo no lugar, achava que o PAK era criptografado e adiava a montagem para sempre. Agora monta, e se chama `6player_P.pak` porque no Unreal 4.22 so um PAK terminado em `_P` tem prioridade sobre o PAK do proprio jogo
- **PAK:** agora so leva a DataTable de escala. O `DefaultGame.ini` saiu: ele substituia o arquivo inteiro do jogo por uma copia antiga, e as secoes de rede estavam no arquivo errado (o jogo le essas configs do `Engine.ini`, entao nunca valeram)
- **DataTable:** os nomes das linhas "5" e "6" estavam com hash 0, e com isso o jogo nao encontrava essas linhas. Dois offsets do cabecalho tinham ficado 20 bytes atras, o que faria o jogo ler lixo como dependencia ao carregar a tabela, e o `BulkDataStartOffset` nao acompanhava as linhas novas. Tudo corrigido
- **Vida e dano** agora escalam pela tabela nativa do jogo, por tipo de inimigo, com o chefe escalando mais. O hook de dano antigo nunca rodava (`Context:IsValid()` sempre saia da funcao), e a vida pelo Lua nao distinguia chefe de inimigo comum. O EnemyScaling virou reserva e vem desligado no proprio script (`ENABLED = false`), entao o `enabled.txt` que sobra de quem atualiza da v1.1 nao liga ele
- **NetOptimize reescrito:** a banda de 100 KB/s por cliente e aplicada onde o servidor realmente le (o fix da v1.1 gravava um campo que o servidor ignora). Sairam smoothing, prioridade de rede e as 12 CVars, 7 das quais nem existem no Unreal 4.22
- **NetOptimize** roda na game thread e chega na sala, na rede e nas conexoes a partir do proprio motor do jogo, sem varrer a lista de objetos e sem guardar referencia de um mapa para o outro
- **Clientes** nao precisam mais instalar nada
- Testes automatizados em `tests/`

### v1.1 — fix de mobs bugando ao sair/entrar na sala

- **EnemyScaling:** quando alguem saia ou entrava, o mod re-multiplicava a vida de todos os inimigos em cima do valor ja escalado e curava eles 100%. Agora:
  - o mod lembra o multiplicador aplicado em cada inimigo e ajusta so a diferenca, mantendo a % de vida atual
  - inimigos mortos nao sao tocados
  - a contagem de jogadores so muda depois de ficar estavel por ~6s
  - o personagem de um jogador que acabou de reconectar nao e mais confundido com inimigo

---

## Para desenvolvedores

### Estrutura do projeto

```
remnant-mod/
  6player_P.pak        PAK pronto para uso (gerado pelo build_pak.py)
  build_pak.py         Gera o PAK v8 (Unreal 4.22)
  rebuild_scaling.py   Gera a DataTable com as linhas 1 a 6 a partir da original
  original/            DataTable original do jogo (linhas 1 a 4), entrada do build
  ue4ss/Mods/
    NetOptimize/       Limite da sala + banda por cliente
    EnemyScaling/      Reserva: vida extra pelo Lua (desligado)
  tests/               Testes (Python e Lua)
```

### Gerar o PAK

```bash
python build_pak.py            # 6player_P.pak
python build_pak.py --teste    # 6player_0_TESTE_P.pak (solo com 3x inimigos, 3x vida e 3x dano)
python rebuild_scaling.py      # so a DataTable, em modified/, para inspecionar
```

Requer Python 3, sem dependencias. O PAK e gravado sem compressao, entao sai identico em qualquer maquina.

A release leva dois arquivos: `remnant-6players.zip` (o `6player_P.pak` em `Remnant/Content/Paks/~mods/` e a pasta `ue4ss/Mods` em `Remnant/Binaries/Win64/Mods/`) e o `6player_0_TESTE_P.pak`.

### Testes

```bash
python -m unittest discover -s tests
lua tests/lua/run.lua          # Lua 5.4
```

`tests/ue422.py` reproduz como o Unreal 4.22 le um PAK (rodape, indice, prioridade entre PAKs) e um pacote cozido; os testes do PAK e da DataTable passam por ele. `tests/lua/ue4ss_mock.lua` simula a API do UE4SS 3.0.1 usada pelos mods.
