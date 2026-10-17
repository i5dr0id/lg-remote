# LG Remote (macOS)

A native SwiftUI remote for LG webOS TVs. One binary works three ways:

- **GUI**: a remote-shaped window, opened from the Dock, Launchpad or Spotlight
- **Menu bar**: a compact remote that keeps running after you close the window
- **CLI**: `lgremote <command>`, using the same binary and the same pairing

## Build & install

```sh
scripts/build-app.sh install
```

This builds `build/LG Remote.app`, copies it to `/Applications` (so it shows in Launchpad and can be kept in the Dock), and links `lgremote` into `/opt/homebrew/bin`. Run `scripts/build-app.sh` without `install` to build only.

On first launch, macOS asks to allow local network access. Click **Allow**, or the app can't reach the TV.

For development: `swift build && .build/debug/LGRemote` (GUI) or `.build/debug/LGRemote status` (CLI).

## How the modes work

| Launch | Result |
|---|---|
| `LG Remote.app` (Dock, Launchpad, `open -a "LG Remote"`) | Remote window + menu bar icon |
| `open -a "LG Remote" --args --background` | Menu bar only, no window or Dock icon |
| `lgremote <command>` | CLI. Runs the command and exits |
| `lgremote gui` | Opens the app from the terminal |

Closing the remote window keeps the app running in the menu bar. Settings (⌘,) has these options:

- **Show in Dock**: turn off to run as a menu-bar-only app
- **Open remote window on launch**
- **Launch at login**: starts hidden in the menu bar
- **TV address and MAC**, **Discover**, **Forget Pairing**, **Install `lgremote` command**

## Remote window

- Power (turns the TV off when connected; sends Wake-on-LAN when not), status light, input picker
- LCD display: current app, volume, connection state
- VOL / CH rockers, mute, number pad (123), all-apps grid
- D-pad + OK, Back, Home, TV settings, text keyboard
- Media keys, red/green/yellow/blue keys, YouTube/Netflix shortcuts, touchpad for the TV pointer

Keyboard shortcuts while the remote is focused:

| Key | Action |
|---|---|
| ← ↑ → ↓ | Navigate |
| Return / Space | OK |
| Delete / Esc | Back |
| H | Home |
| M | Mute |
| = and - | Volume up/down |
| ] and [ | Channel up/down |
| P / K | Play / Pause |
| 0–9 | Number keys |

Drag the remote's body to move the window. Hover over it to show the close button.

## CLI

```
lgremote status                 lgremote vol 20 | up | down | +5
lgremote off | on               lgremote mute [on|off]
lgremote up|down|left|right|ok|back|home
lgremote apps                   lgremote app netflix
lgremote inputs                 lgremote input hdmi 2
lgremote text "hello" --enter   lgremote toast "Dinner's ready"
lgremote url https://example.com
lgremote watch                  lgremote raw ssap://audio/getVolume
lgremote discover               lgremote config host 192.168.1.100
```

Run `lgremote help` for the full list.

## Layout

```
Sources/LGTVKit/      TV protocol library: WebSocket client, commands, discovery, Wake-on-LAN, config
Sources/LGRemote/     main.swift picks the mode; CLI.swift; App/ holds the SwiftUI app
Resources/Info.plist  App bundle metadata
scripts/              build-app.sh, make-icon.swift
```

Config and the pairing key live in `~/Library/Application Support/LGRemote/config.json`. The GUI and CLI share them.

## Notes

- **Power on** uses Wake-on-LAN. On the TV, enable *Settings › General › Devices › TV Management › Turn on via Wi-Fi* (the name varies by model).
- The registration manifest carries LG's test-signing signature (from the MIT-licensed `lgtv2` package). Without it, the TV refuses signed permissions such as listing apps.
- The app is ad-hoc signed. After each rebuild, macOS may ask for local network permission again.
