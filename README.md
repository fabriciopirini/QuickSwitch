# Cmd+Tab: macOS-style app switcher for Omarchy

An app switcher in the style of macOS Cmd+Tab, built as an
[Omarchy](https://omarchy.org/) shell plugin (QML hosted by the long-running
`omarchy-shell` Quickshell process).

Forked from [ewweberlin/QuickSwitch](https://github.com/ewweberlin/QuickSwitch) (MIT).
The original shows a snapshot per window. This fork shows one large icon per
app, like macOS, and the app's name under the selection.

## Features

- **SUPER+TAB** opens the switcher: one large icon per app, most recently used
  first, with the selected app highlighted and its name below.
- A **quick SUPER+TAB tap** jumps straight to the previous app without showing
  the strip; tap again to jump back. The strip appears once SUPER is held for a
  moment.
- Tap **TAB (or the arrow keys)** while holding SUPER to advance the selection.
  **SUPER+SHIFT+TAB** goes back.
- **Mouse hover** highlights an app once the pointer moves; **click** activates it.
- **SUPER+Q** quits the highlighted app (every window of it).
- **Release SUPER** to activate the selection. The app's most recent window is
  focused and raised, switching workspace if needed.
- Windows of the same app share one icon, so switching between windows of one
  app is left to your own binding.
- Windows on special workspaces (scratchpads) are not listed.
- Colors come from the Omarchy theme.

## Requirements

- Omarchy with the Quickshell shell (`omarchy-shell`)
- Hyprland 0.56 or newer (Lua config)
- `hyprctl` on PATH

## Installation

```sh
omarchy plugin add https://github.com/fabriciopirini/QuickSwitch.git --enable
```

Add this line to `~/.config/hypr/bindings.lua` to enable SUPER+TAB:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/pirini.cmd-tab/task-switch-bindings.lua")
```

If you prefer that plugin updates never change your Hyprland config, paste the
contents of `task-switch-bindings.lua` into `bindings.lua` instead of the
`dofile` line.

If your `bindings.lua` unbinds SUPER+TAB itself, put the `dofile` line after
that unbind.

Restart the shell, reload Hyprland and check the bindings:

```sh
omarchy restart shell
hyprctl reload
hyprctl configerrors   # should be clean
hyprctl globalshortcuts
```

The `SUPER + TAB` shortcut should appear in `hyprctl globalshortcuts`. After
editing the plugin, use a full `omarchy restart shell`; the hot reload can leave
stale code running.

### Removal

```sh
omarchy plugin remove pirini.cmd-tab
omarchy plugin disable pirini.cmd-tab    # disable without deleting
omarchy plugin update pirini.cmd-tab     # update
```

## Behavior details

- **SUPER+TAB was already bound** in Omarchy to **"Next workspace"**
  (`hl.dsp.focus e+1`). The bindings file unbinds it first, so SUPER+TAB now
  opens the switcher. While the plugin is disabled or not loaded, SUPER+TAB
  falls back to "Next workspace", so there is never a dead key.
- All in-switcher keys (TAB, SHIFT+TAB, arrows, Q, Esc) live in a Hyprland
  submap named `cmdtab` that is only active while the strip is open, so your
  own SUPER+arrow / SUPER+Q bindings keep working everywhere else. **Esc**
  always leaves the submap, even if the shell has crashed.
- Releasing SUPER with **no item highlighted / pointer outside** the strip
  (Esc, or clicking empty space) closes without changing focus.
- Floating windows are raised after focusing, so the chosen window is visible
  even when windows overlap.

## Credits and license

MIT. The switcher logic and Hyprland bindings come from
[ewweberlin/QuickSwitch](https://github.com/ewweberlin/QuickSwitch); see `LICENSE`.
