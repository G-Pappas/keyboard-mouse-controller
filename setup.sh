#!/usr/bin/env bash
# Hooks keymouse.lua into ~/.config/hypr/bindings.lua, but only with the user's
# consent.
#   setup.sh        asks through a desktop notification (once), then applies
#   setup.sh apply  applies right away (the explicit, manual way)
# Applying backs the file up first and is safe to repeat.
set -u

bindings="$HOME/.config/hypr/bindings.lua"
marker="-- >>> gpappas.keymouse"
state="${XDG_STATE_HOME:-$HOME/.local/state}/gpappas.keymouse"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apply() {
  [ -f "$bindings" ] || { echo "no $bindings, nothing to hook into"; return 0; }
  grep -qF -- "$marker" "$bindings" && { echo "already hooked up"; return 0; }
  cp "$bindings" "$bindings.bak.$(date +%s)"
  cat >> "$bindings" <<'LUA'

-- >>> gpappas.keymouse: added by the Keyboard Mouse plugin (SUPER + N). Skipped once the plugin is removed.
do local p = os.getenv("HOME") .. "/.config/omarchy/plugins/gpappas.keymouse/keymouse.lua" local f = io.open(p) if f then f:close() dofile(p) end end
-- <<< gpappas.keymouse
LUA
  hyprctl reload >/dev/null 2>&1
  echo "hooked into bindings.lua (SUPER + N)"
}

if [ "${1:-}" = "apply" ]; then apply; exit 0; fi

[ -f "$bindings" ] || exit 0
grep -qF -- "$marker" "$bindings" && exit 0   # already set up
[ -e "$state/asked" ] && exit 0            # asked before, never nag
mkdir -p "$state" && : > "$state/asked"

answer=$(notify-send --wait --app-name="Keyboard Mouse" --action=setup="Add SUPER + N" \
  "Keyboard Mouse needs one change" \
  "Add a few lines to ~/.config/hypr/bindings.lua to enable SUPER + N? A backup is saved first. To do it later, run: $here/setup.sh apply" 2>/dev/null)
[ "$answer" = "setup" ] && apply
exit 0
