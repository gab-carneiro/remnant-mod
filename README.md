# Remnant: From the Ashes — Co-op ate 6 jogadores

Mod que libera co-op de ate **6 jogadores** no **Remnant: From the Ashes**, com os inimigos escalando para nao ficar facil e a rede do host ajustada para aguentar 5 clientes.

## Quem instala o que

| Componente | Host (quem cria a sala) | Clientes (quem entra) |
|---|---|---|
| `6player_P.pak` | **Obrigatorio** | Nao precisa |
| UE4SS + NetOptimize | **Obrigatorio** | Nao precisa |
| EnemyScaling | Recomendado | Nao precisa |

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
5. **Atualizando de versao antiga?** Apague `Remnant\Content\Paks\~mods\6player.pak` (sem o `_P`). Ele nunca chegou a carregar no jogo

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
      EnemyScaling\Scripts\main.lua
```

---

## Teste de 2 minutos: o PAK carregou?

O PAK so funciona se o jogo carregar ele, e isso so da para confirmar jogando. Faca uma vez, solo:

1. Baixe `6player_TESTE_P.pak` na mesma release
2. Em `Remnant\Content\Paks\~mods\`, tire o `6player_P.pak` e coloque o `6player_TESTE_P.pak` no lugar
3. Jogue solo alguns minutos numa area com inimigos. Com o PAK de teste o solo fica com **3x mais inimigos** e os golpes deles tiram **3x mais vida**
4. Apague o `6player_TESTE_P.pak` e volte o `6player_P.pak`

| O que aconteceu | Significado |
|---|---|
| Mais inimigos e mais dano | Tudo certo |
| Mais inimigos, dano normal | O PAK carregou, mas o jogo nao usa a coluna de dano da tabela. Abra uma issue |
| Nada mudou | O PAK nao carregou. Abra uma issue |

---

## Como jogar

1. **Host** inicia o jogo normalmente
2. No console do UE4SS aparece `[NetOptimize] === NetOptimize carregado ===` e, ao entrar no mundo, `[NetOptimize] GameSession.MaxPlayers 3 -> 6`
3. Convide amigos via **Steam** (Shift+Tab > convidar) ou eles clicam "Entrar no Jogo" no perfil do host
4. A cada amigo que entra aparece algo como `[NetOptimize] Cliente.CurrentNetSpeed 10000 -> 100000` (o primeiro numero e a banda que o jogo tinha dado para ele)
5. A UI do lobby mostra so 2-3 slots, **mas jogadores extras entram normalmente**

### Console do UE4SS

O console abre automaticamente junto com o jogo. Se nao aparecer, edite `UE4SS-settings.ini`:
```ini
GuiConsoleEnabled = 1
GuiConsoleVisible = 1
```

Tambem fica tudo logado em `Win64\UE4SS.log`.

---

## Dificuldade

| Jogadores | Quantidade de inimigos | Vida dos inimigos | Dano dos inimigos |
|---|---|---|---|
| 1 | 1.00x | 1.00x | 1.00x |
| 2 | 1.33x | 1.00x | 1.00x |
| 3 | 1.66x | 1.00x | 1.00x |
| 4 | 2.00x | 1.25x | 1.10x |
| 5 | 2.33x | 1.50x | 1.20x |
| 6 | 2.66x | 1.75x | 1.30x |

- **Quantidade de inimigos:** tabela nativa do jogo (`Stats_Scaling_NumPlayers`). As linhas 1 a 4 sao do proprio Remnant; o PAK acrescenta 5 e 6 seguindo a mesma progressao
- **Dano:** coluna de dano da mesma tabela, aplicada pelo jogo em todos os tipos de inimigo (comum, elite, brute e chefe)
- **Vida:** EnemyScaling. Quando alguem sai ou entra, os inimigos vivos se ajustam ao novo valor mantendo a % de vida; inimigo morto nao e tocado

Na tabela original do jogo, vida e dano ficam em 1.0 de 1 a 4 jogadores; so a quantidade de inimigos muda. Com 6 jogadores ha o dobro de poder de fogo de 3, mas so 1.6x mais inimigos, por isso a vida e o dano extras.

### Ajustar

| O que | Onde | Padrao |
|---|---|---|
| Vida | `HEALTH_PER_EXTRA` no topo de `EnemyScaling/Scripts/main.lua` (reinicie o jogo) | `0.25` = +25% por jogador acima de 3 |
| Dano | `DAMAGE_PER_EXTRA` em `rebuild_scaling.py`, depois rode `python build_pak.py` e troque o `6player_P.pak` | `0.10` = +10% por jogador acima de 3 |

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
- **DataTable:** os nomes das linhas "5" e "6" estavam com hash 0, e com isso o jogo nao encontrava essas linhas. Tres offsets do cabecalho tinham ficado 20 bytes atras, o que faria o jogo ler lixo como dependencia ao carregar a tabela. Os dois corrigidos
- **Dano:** o hook antigo nunca rodava (`Context:IsValid()` sempre saia da funcao). O dano agora escala pela coluna nativa da tabela
- **Vida:** +25% por jogador acima de 3 (era +35%), porque com 5 e 6 jogadores agora tambem vem mais inimigos
- **NetOptimize reescrito:** a banda de 100 KB/s por cliente e aplicada onde o servidor realmente le (o fix da v1.1 gravava um campo que o servidor ignora). Sairam smoothing, prioridade de rede e as 12 CVars, 7 das quais nem existem no Unreal 4.22
- **NetOptimize e EnemyScaling** rodam na game thread
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
    EnemyScaling/      Vida extra a partir de 4 jogadores
  tests/               Testes (Python e Lua)
```

### Gerar o PAK

```bash
python build_pak.py            # 6player_P.pak
python build_pak.py --teste    # 6player_TESTE_P.pak (solo com 3x inimigos e 3x dano)
python rebuild_scaling.py      # so a DataTable, em modified/, para inspecionar
```

Requer Python 3, sem dependencias.

### Testes

```bash
python -m unittest discover -s tests
lua tests/lua/run.lua          # Lua 5.4
```

`tests/ue422.py` reproduz como o Unreal 4.22 le um PAK (rodape, indice, prioridade entre PAKs) e um pacote cozido; os testes do PAK e da DataTable passam por ele. `tests/lua/ue4ss_mock.lua` simula a API do UE4SS 3.0.1 usada pelos mods.
