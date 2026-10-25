# Acer Nitro 5 (AN515-57) — Gaming no CachyOS + Niri

Documentação do ajuste de desempenho feito nesta máquina: GPU híbrida Intel + NVIDIA,
compositor Niri (Wayland), CachyOS, Steam e Lutris.

Tudo aqui é reversível. Nenhum hardware foi alterado.

---

## 1. Hardware verificado

| Componente | Modelo | Observação |
|---|---|---|
| CPU | Intel Core i5-11400H (6c/12t, 4.5 GHz turbo) | `intel_pstate`, governor `powersave`, EPP `power` |
| GPU integrada | Intel UHD Graphics (TigerLake-H GT1) | **é ela que está ligada no painel interno** |
| GPU dedicada | NVIDIA GeForce GTX 1650 Mobile (TU117M, 4 GB) | TGP padrão 50 W, máx. 65 W (bloqueado), boost 1785 MHz, PCIe x8 |
| RAM | 8 GB (7.5 GiB utilizáveis) | 1 pente — gargalo principal |
| Swap | zram 7.5 GB, zstd, prioridade 100 | sem swap em disco |
| Disco | NVMe IM2P33F8ABR2-512GB (476 GB, ~237 GB livres) | DRAM-less, entrada |
| Tela | AU Optronics 0xAF90, 1920x1080 @ 144.149 Hz | VRR suportado |
| Sistema | CachyOS (Arch), kernel `7.3.0-4-cachyos`, Niri 26.04 | driver `nvidia-open` 615.78.08 (config feito em 7.2.9-2, atualizado para 7.3.0-4 no reboot) |
| BIOS | V1.22 | sem opção de MUX |

---

## 2. Diagnóstico: por que a GTX "não aparece"

- `eDP-1` (painel interno) está conectado ao **card1 = Intel i915**.
- `card0 = NVIDIA` expõe **apenas `HDMI-A-1`** (desconectado).
- Logo: **não existe MUX** neste modelo. A tela interna é soldada na Intel.

Consequência: a NVIDIA renderiza, mas cada frame é copiado para a memória da iGPU
e a Intel faz o scanout. Custo estimado: **0,5–2 ms por frame** (~5% de fps médio,
~10–15% nos 1% lows). Banda não é o problema: 1080p60 = ~500 MB/s contra ~7,9 GB/s
de PCIe 3.0 x8.

Verificação:

```bash
for s in /sys/class/drm/card*-*; do [ -e "$s/status" ] && echo "$(basename $s): $(cat $s/status)"; done
```

Único caminho para saída direta da NVIDIA: **monitor externo no HDMI**.

---

## 3. Mudanças aplicadas

### 3.1 Offload da GPU dedicada por padrão (Steam e Lutris)

Arquivos:
- `~/.local/share/applications/steam.desktop`
- `~/.local/share/applications/net.lutris.Lutris.desktop`

Linha de execução resultante:

```
env MANGOHUD=1 DRI_PRIME=1 __NV_PRIME_RENDER_OFFLOAD=1 \
    __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia \
    <binário> %U
```

Motivo: o Niri não honra `PrefersNonDefaultGPU=true` do `.desktop`, então sem isso a
Steam abre os jogos na **Intel UHD**.

Reverter: `rm ~/.local/share/applications/steam.desktop ~/.local/share/applications/net.lutris.Lutris.desktop`
e rodar `update-desktop-database ~/.local/share/applications`.

### 3.2 VRR no Niri

`~/.config/niri/cfg/display.kdl`:

```kdl
output "eDP-1" {
    mode "1920x1080@144.149"
    scale 1
    variable-refresh-rate
}
```

Atenção: nesta versão do Niri a chave é `variable-refresh-rate` **sem valor**
(`vrr` não existe; `variable-refresh-rate true` falha no parser).

Confirmar: `niri msg outputs | grep -i "Variable refresh"` → `enabled`.

### 3.3 Blur desligado nas janelas de jogo

`~/.config/niri/cfg/rules.kdl` — regras para `^steam_app_`, `(?i)\.exe$` e `^gamescope$`
com `background-effect { blur false }`.

### 3.4 Cap de fps + HUD

`~/.config/MangoHud/MangoHud.conf`: `no_display`, `fps_limit=60`.
HUD oculto por padrão; **Shift_R + F12** mostra/oculta.
O cap é térmico: menos fps = menos calor. Ajuste conforme o jogo.

### 3.5 Gamemode sem subir temperatura

`~/.config/gamemode.ini`:

```ini
[general]
desiredgov = powersave
igpu_desiredgov = powersave
[cpu]
park_cores = no
pin_cores = no
[gpu]
apply_gpu_optimisations = 0
```

Motivo: o padrão do gamemode força `performance` no governor, o que nesta máquina
dispara temperatura. Aqui ele mantém o governor como está.

Daemon: `systemctl --user enable --now gamemoded`.

### 3.6 Scheduler sched_ext (`scx_lavd`)

`/etc/scx_loader/config.toml`:

```toml
default_sched = "scx_lavd"
default_mode = "Auto"
```

Serviço: `sudo systemctl enable --now scx_loader` → `enabled` (modo `Auto`,
com `--autopilot --pinned-slice-us 500`).

Verificar: `scxctl get` e `cat /sys/kernel/sched_ext/state`.

Alternativa para testar (1% lows melhores em benchmark da comunidade):

```bash
scxctl switch --sched cake --mode gaming
scxctl switch --sched lavd --mode auto   # voltar
```

### 3.7 Mitigação do Xid 109 (regressão do driver 615.x)

`~/.config/dxvk.conf`:

```
dxvk.enableNvRawAccessChains = False
```

A branch 610/615 do driver NVIDIA tem regressão conhecida de `Xid 109 CTX SWITCH TIMEOUT`
sob Proton/DXVK (jogo congela, desktop sobrevive). A extensão `VK_NV_raw_access_chains`
é o gatilho isolado. Vale para o caminho D3D11; D3D12/vkd3d não usa essa opção.

Conferir se ocorreu: `journalctl -k -b | grep -i "NVRM: Xid"`.

### 3.8 Pacotes instalados

`gamescope 3.17.0`, `mangohud 0.8.4`, `lib32-mangohud`, `gamemode 1.8.2`, `lib32-gamemode`.

---

## 4. Uso no dia a dia

- Abrir Steam/Lutris pelo launcher do Niri — já herdam o offload NVIDIA.
- Verificar em jogo se a GPU é a correta: mostrar HUD (Shift_R+F12) ou `nvidia-smi`.
- Gamescope só quando o jogo der problema de cursor/fullscreen, com o backend correto
  para Niri:

```
gamescope -f -w 1920 -h 1080 -W 1920 -H 1080 --force-grab-cursor --backend sdl -- %command%
```

`--backend sdl` é necessário no Niri (o backend Wayland padrão não segura o cursor —
issue upstream #1711). Fora isso, jogo direto no Niri tem menos latência.

- Steam: `%command%` com `prime-run` **não é mais necessário** se o app foi aberto
  pelo atalho modificado.

---

## 5. O que NÃO funciona nesta máquina

| Tentativa | Resultado |
|---|---|
| `nvidia-smi -pl 65` (subir TGP 50 W → 65 W) | **não suportado** — vBIOS da Acer bloqueia |
| Curva de fan via LACT / NVML | `fan.speed = N/A`; nenhum nó `pwm*`/`fan*_input` no hwmon; sem `platform_profile` |
| OptiScaler | inútil aqui: TLOU2 já tem DLSS 3/4, FSR 3.1 e XeSS nativos; jogos da biblioteca não têm upscaler |
| `proton-cachyos-native` | existe no repo, mas ganho esperado 0–5% (só em jogo CPU-bound) |
| Tuning de `vm.dirty_ratio` | inócuo: a CachyOS já define `vm.dirty_bytes` (256 MB), que tem precedência |

---

## 6. Expectativa realista

| Jogo | Expectativa |
|---|---|
| Batman Arkham Knight, Dark Souls, Guilty Gear | 60 fps em 1080p (já confirmado na prática) |
| Elden Ring | 1080p low/médio, ~45–60 fps; quedas para 35–40 em áreas abertas |
| The Last of Us Part II Remastered | 720p–900p + FSR performance, texturas no mínimo, ~30 fps instável |
| AAA 2023+ em geral | limitado por 4 GB de VRAM + 8 GB de RAM, não por CPU |

Referência da comunidade: uma GTX 1050 Ti (também 4 GB) não mantém 30 fps estáveis
em 1080p no preset mais baixo do TLOU2.

---

## 7. Como medir (A/B honesto)

O `fps_limit=60` mascara diferenças. Para benchmark:

```bash
MANGOHUD_CONFIG=fps_limit=0 mangohud %command%
```

- Mesma cena, 2 execuções, olhar **1% low** e frametime — não a média.
- Teste isolado do custo do PRIME: rodar o mesmo jogo no painel interno e num monitor
  externo via HDMI. Mesma GPU, mesmos clocks — a diferença é exatamente a Intel no meio.

---

## 8. Manutenção

- O módulo NVIDIA é **pré-compilado** (`linux-cachyos-nvidia-open`). Ao atualizar kernel,
  atualize o pacote do módulo junto, senão `nvidia-smi` quebra.
- Após update de kernel, conferir: `modinfo nvidia | grep vermagic` deve bater com `uname -r`.
- `dxvk.conf` e `MangoHud.conf` são de usuário; não são sobrescritos por update.
- O override de `.desktop` pode ficar desatualizado quando o pacote `steam`/`lutris`
  atualizar o arquivo do sistema — nesse caso, refazer a cópia e reaplicar o `env`.

---

## 9. Referências

- [niri — Gaming and Steam](https://deepwiki.com/niri-wm/niri/7.2-gaming-and-steam)
- [niri — Application Issues (wiki upstream)](https://github.com/niri-wm/niri/blob/main/docs/wiki/Application-Issues.md)
- [NVIDIA Xid 109 CTX SWITCH TIMEOUT](https://theglitchfixer.blogspot.com/2026/10/nvidia-xid-109-ctx-switch-timeout-fix.html)
- [CachyOS — Gaming](https://wiki.cachyos.org/configuration/gaming/)
- [CachyOS — sched-ext](https://wiki.cachyos.org/configuration/sched-ext/)
- [CachyOS Performance Optimization Guide](https://fernbacher.github.io/cachyos-optimization/)
- [TLOU2 Remastered — PC Performance Thread](https://www.resetera.com/threads/the-last-of-us-part-ii-remastered-pc-performance-thread.1155642/)
- [TLOU2 no Proton/Linux](https://protonscr.com/game/2531310/the-last-of-us-part-ii-remastered)

---

## 10. Verificação pós-boot

Depois do reboot, `./verify.sh` roda tudo em modo somente-leitura (sem sudo) e devolve
`0` se estiver tudo certo.

Resultado em 2026-10-25, kernel `7.3.0-4-cachyos` — **19 OK, 0 falhas**:

| Checagem | Resultado |
|---|---|
| vermagic do módulo == kernel | OK (`7.3.0-4-cachyos`) |
| `nvidia_drm modeset=Y` | OK |
| `nvidia-smi` responde (GTX 1650) | OK |
| Vulkan com offload escolhe a NVIDIA | OK |
| VRR habilitado (144 Hz) | OK |
| config do Niri válida | OK |
| `sched_ext` enabled | OK |
| `scx_loader` habilitado no boot | OK |
| `gamemoded` ativo e habilitado | OK |
| gamemode não força governor `performance` | OK |
| overrides de Steam/Lutris com offload | OK |
| configs de usuário presentes | OK |
| nenhum erro `NVRM`/`Xid` no boot | OK |

Observações desse boot:

- O kernel **subiu de `7.2.9-2` para `7.3.0-4`** e o pacote `linux-cachyos-nvidia-open`
  acompanhou (`7.3.0-4`) — exatamente o cenário de risco descrito na seção 8, que passou.
  Se não tivesse acompanhado, o script falharia na primeira checagem.
- `scx_lavd` (PID 771) subiu sozinho pelo `scx_loader`, sem nenhuma ação manual.
- Apareceu um `XID 541` no log, mas é do driver `r8169` (placa de rede Realtek), não da NVIDIA.
- Perfil de energia permaneceu `power-saver` — nada reverteu a decisão sobre temperatura.

---

## 11. Jogo não-Steam (repack) — Sekiro

Instalação feita a partir de um repack FitGirl em `~/Downloads`, registrada manualmente no
Lutris 0.5.22 (a CLI dessa versão **não** tem comando de "adicionar jogo", então a entrada
foi inserida direto no SQLite `~/.local/share/lutris/pga.db` + YAML correspondente).

### Layout

| Item | Caminho |
|---|---|
| Prefix | `~/Games/Sekiro/prefix` (win64, criado com `dw-proton-x86_64`) |
| Jogo | `~/Games/Sekiro/prefix/drive_c/Games/Sekiro - Shadows Die Twice` |
| Executável | `...\drive_c\Games\Sekiro - Shadows Die Twice\sekiro.exe` |
| Tamanho | 13 GB |
| ID no Lutris | 5 (`sekiro-shadows-die-twice`) |

Config gravada em `~/.config/lutris/games/sekiro-shadows-die-twice-5.yml`:

```yaml
game:
  arch: win64
  exe: /home/.../Games/Sekiro/prefix/drive_c/Games/Sekiro - Shadows Die Twice/sekiro.exe
  path: /home/.../Games/Sekiro/prefix/drive_c/Games/Sekiro - Shadows Die Twice
  prefix: /home/wenningtonda/Games/Sekiro/prefix
system:
  gpu: card0            # Lutris injeta VK_DRIVER_FILES + offload
runner: wine
slug: sekiro-shadows-die-twice
wine:
  arch: win64
  version: dw-proton-x86_64
```

### O que acontece na execução

- O Lutris 0.5.22 identifica `dw-proton` como build baseada em Proton e executa via
  **umu-run** (container `steamrt4`), não como wine puro. Funciona, mas o log inicial é verboso.
- `system: gpu: card0` faz o Lutris setar `VK_DRIVER_FILES` e as variáveis de offload —
  o jogo abre na GTX 1650 mesmo sendo lançado pela CLI, sem depender do `.desktop`.
- **Primeiro boot compila shaders do DXVK** (`dxvk-shader-*` em 8 threads a ~90% de CPU por
  ~3 min). Depois disso estabiliza. Uso no boot: ~1,3 GB de VRAM e 25% de GPU no menu.

### Avisos conhecidos

- O instalador FitGirl reporta **"27 missing files"** ao final: são os componentes opcionais
  que foram desmarcados (packs de idioma, bonus content, credits video). Os dados do jogo
  (`Data1–5.bdt`, ~12 GB) estão completos — o jogo sobe normalmente.
- Ruído inofensivo no log: `gamemodeauto: dlopen failed - libgamemode.so`. O gamemode entra
  via `LD_PRELOAD=libgamemodeauto.so.0` e funciona; a mensagem é do `libgamemode.so` sem
  versionamento.
- `Proton: Error: unable to use parent for game drive, path /home` também é ruído — a
  execução segue e o jogo abre.
- Em jogo, manter **texturas em High** (não Max) por causa dos 4 GB de VRAM.

### Reverter / remover

```bash
python3 -c "import sqlite3;c=sqlite3.connect('$HOME/.local/share/lutris/pga.db');\
c.execute('delete from games where id=5');c.commit()"
rm ~/.config/lutris/games/sekiro-shadows-die-twice-5.yml
rm -rf ~/Games/Sekiro
```

---

## Estrutura do repo

```
.
├── README.md
├── verify.sh                                # checagem pós-boot (19 checks, sem sudo)
└── configs/
    ├── dxvk.conf                            # mitigação Xid 109
    ├── gamemode.ini                         # governor travado em powersave
    ├── MangoHud.conf                        # cap 60 fps + HUD oculto
    ├── desktop/
    │   ├── steam.desktop                    # override com offload NVIDIA
    │   └── net.lutris.Lutris.desktop        # idem
    ├── niri/
    │   ├── display.kdl                      # VRR na eDP-1
    │   └── rules.kdl                        # blur off em jogos
    └── system/
        └── scx_loader.toml                  # scx_lavd no boot
```
