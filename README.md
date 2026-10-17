# LG TV Control

Control an LG webOS TV over the local network using its SSAP WebSocket API.

## TV

| | |
|---|---|
| Model | 55UN6800PVA (2020) |
| webOS | 5.6.0-20 (jhericurl-jimna) |

### Network findings

- Open ports: `3000` (ws), `3001` (wss, self-signed cert), `36866`.
- Closed: `1754`, `1755`, `8080`, `9998`.

## Setup

```sh
npm install
node lgtv.js            # first run shows a pairing prompt on the TV — accept it with the remote
```

The pairing key is saved to `.client-key` (gitignored), so later runs connect without a prompt.
Override the TV address with `TV_IP=x.x.x.x node lgtv.js ...`.

## Usage

```sh
node lgtv.js <ssap-uri> [json-payload]
```

| Action | Command |
|---|---|
| System info | `node lgtv.js ssap://system/getSystemInfo` |
| Get volume | `node lgtv.js ssap://audio/getVolume` |
| Set volume | `node lgtv.js ssap://audio/setVolume '{"volume":20}'` |
| Mute | `node lgtv.js ssap://audio/setMute '{"mute":true}'` |
| Current app | `node lgtv.js ssap://com.webos.applicationManager/getForegroundAppInfo` |
| Launch app | `node lgtv.js ssap://system.launcher/launch '{"id":"netflix"}'` |
| Toast message | `node lgtv.js ssap://system.notifications/createToast '{"message":"Hello"}'` |
| Turn off | `node lgtv.js ssap://system/turnOff` |

## Status (2026-10-17)

- Pairing works.
- Verified: `getSystemInfo`, `getVolume`, `getForegroundAppInfo`.
- `ssap://com.webos.service.update/getCurrentSWInformation` returns `401 insufficient permissions` because it requires an LG-signed manifest.

## Next ideas

- Friendly CLI (`lg vol 20`, `lg off`, `lg app netflix`)
- Web remote usable from a phone
- Wake-on-LAN for power on (TV can't be turned on over WebSocket once off)

## macOS app

The native Swift remote (GUI + menu bar + `lgremote` CLI) lives in [`LGRemote/`](LGRemote/README.md). The Node script above is the original prototype.
