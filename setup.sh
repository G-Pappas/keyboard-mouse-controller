#!/usr/bin/env bash
# Adds a guarded hook for keymouse.lua to ~/.config/hypr/bindings.lua once and
# reloads Hyprland so the mode works right away. Safe to run any number of
# times: it does nothing once the hook is there.
set -u

bindings="$HOME/.config/hypr/bindings.lua"
marker="-- >>> gpappas.keymouse"

[ -f "$bindings" ] || { echo "no $bindings, nothing to hook into"; exit 0; }
grep -qF "$marker" "$bindings" && { echo "already hooked up"; exit 0; }

cp "$bindings" "$bindings.bak.$(date +%s)"
cat >> "$bindings" <<'LUA'

-- >>> gpappas.keymouse: added by the Keyboard Mouse plugin (SUPER + N). Skipped once the plugin is removed.
do local p = os.getenv("HOME") .. "/.config/omarchy/plugins/gpappas.keymouse/keymouse.lua" local f = io.open(p) if f then f:close() dofile(p) end end
-- <<< gpappas.keymouse
LUA

hyprctl reload >/dev/null 2>&1
echo "hooked into bindings.lua (SUPER + N)"
