#!/usr/bin/env bash
# Verificacao pos-boot do tuning descrito neste repo.
# Somente leitura: nao altera nada e nao precisa de sudo.
set -uo pipefail

ok=0; fail=0
pass() { printf '  \033[32mOK\033[0m   %s\n' "$1"; ok=$((ok+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
info() { printf '       %s\n' "$1"; }

echo "== Sistema =="
info "kernel: $(uname -r)  |  uptime: $(uptime -p | sed 's/up //')"

echo "== Modulo NVIDIA =="
uniq_ver=$(modinfo nvidia 2>/dev/null | awk '/^version/{print $2}')
verm=$(modinfo nvidia 2>/dev/null | awk '/^vermagic/{print $2}')
[ "$verm" = "$(uname -r)" ] && pass "vermagic do modulo bate com o kernel ($verm)" \
    || bad "modulo ($verm) nao bate com kernel ($(uname -r)) - reinstale linux-cachyos-nvidia-open"
[ "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)" = "Y" ] \
    && pass "nvidia_drm modeset=Y" || bad "nvidia_drm modeset != Y"
info "driver: ${uniq_ver:-ausente}"

echo "== GPU dedicada =="
gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
[ -n "$gpu" ] && pass "nvidia-smi responde ($gpu)" || bad "nvidia-smi falhou"

vknv=$(env __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
        __GLX_VENDOR_LIBRARY_NAME=nvidia vulkaninfo --summary 2>/dev/null \
        | grep -m1 deviceName)
case "$vknv" in
    *NVIDIA*) pass "Vulkan com offload escolhe a NVIDIA" ;;
    *)        bad  "Vulkan com offload NAO escolheu a NVIDIA (${vknv:-vazio})" ;;
esac

echo "== Compositor (Niri) =="
niri msg outputs 2>/dev/null | grep -qi "Variable refresh rate: supported, enabled" \
    && pass "VRR habilitado" || bad "VRR nao esta habilitado"
niri validate -c "$HOME/.config/niri/config.kdl" 2>&1 | grep -q "config is valid" \
    && pass "config do niri valida" || bad "config do niri invalida"

echo "== Scheduler (scx_lavd) =="
[ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" = "enabled" ] \
    && pass "sched_ext enabled" || bad "sched_ext disabled (espere ~5s apos o boot e re-teste)"
[ "$(systemctl is-enabled scx_loader 2>/dev/null)" = "enabled" ] \
    && pass "scx_loader habilitado no boot" || bad "scx_loader nao esta habilitado"
info "$(scxctl get 2>&1 | head -1)"

echo "== Gamemode =="
[ "$(systemctl --user is-active gamemoded 2>/dev/null)" = "active" ] \
    && pass "gamemoded ativo" || bad "gamemoded inativo"
[ "$(systemctl --user is-enabled gamemoded 2>/dev/null)" = "enabled" ] \
    && pass "gamemoded habilitado no login" || bad "gamemoded nao habilitado"
if grep -q "desiredgov = powersave" "$HOME/.config/gamemode.ini" 2>/dev/null; then
    pass "gamemode nao forca governor performance"
else
    bad "gamemode.ini sem desiredgov=powersave (vai esquentar)"
fi

echo "== Offload padrao nos launchers =="
for f in "$HOME/.local/share/applications/steam.desktop" \
         "$HOME/.local/share/applications/net.lutris.Lutris.desktop"; do
    if grep -q "__VK_LAYER_NV_optimus=NVIDIA_only" "$f" 2>/dev/null; then
        pass "$(basename "$f") com offload"
    else
        bad "$(basename "$f") sem offload"
    fi
done

echo "== Configs de usuario =="
for f in "$HOME/.config/MangoHud/MangoHud.conf" "$HOME/.config/dxvk.conf" \
         "$HOME/.config/niri/cfg/display.kdl" "$HOME/.config/niri/cfg/rules.kdl"; do
    [ -f "$f" ] && pass "$(basename "$f") presente" || bad "$(basename "$f") ausente"
done
[ -f /etc/scx_loader/config.toml ] && pass "scx_loader config.toml presente" \
    || bad "scx_loader config.toml ausente"

echo "== Erros de driver no boot =="
nvrm=$(journalctl -b -k --no-pager 2>/dev/null | grep -i "NVRM" \
       | grep -viE "loading NVIDIA UNIX" | tail -3)
[ -z "$nvrm" ] && pass "nenhum erro NVRM/Xid" || { bad "ha linhas NVRM:"; echo "$nvrm" | sed 's/^/       /'; }

echo
printf 'Resultado: \033[32m%d OK\033[0m, \033[31m%d falha(s)\033[0m\n' "$ok" "$fail"
[ "$fail" -eq 0 ]
