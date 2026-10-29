# HandsOff

Control your Mac without touching it. Your AirPods' head tracking moves the cursor, and you click, scroll and zoom with your voice or the AirPods stem. Built for when your hands are busy or dirty: cooking, fixing things, following along with a manual.

HandsOff lives in the menu bar and starts switched off. Say **"hands off"** to turn it on and **"stop"** to turn it off.

## Requirements

- macOS 14 or later
- AirPods with Spatial Audio head tracking (AirPods Pro, AirPods 3rd gen or later, AirPods Max)
- Xcode command line tools (`xcode-select --install`)

## Build

```sh
./build.sh
open HandsOff.app
```

The app is ad-hoc signed by default, which makes macOS ask for permissions again after every rebuild. Sign it with a stable identity to avoid that:

```sh
SIGN_ID="Apple Development: you@example.com (TEAMID)" ./build.sh
```

On first run, allow **Accessibility**, **Motion**, **Microphone** and **Speech Recognition**. For the zoom command, also turn on System Settings → Accessibility → Zoom → **Use keyboard shortcuts to zoom**.

## Controls

**Head**

| Move | Does |
|---|---|
| Turn or tilt up/down | Moves the cursor (it snaps to nearby buttons) |
| Tilt toward a shoulder | Scrolls; tilting right scrolls down |

**Voice.** Say each command on its own.

| Say | Does |
|---|---|
| "hands off" | Turn on |
| "stop" | Turn off |
| "click" / "right click" | Left or right click |
| "hold" / "unhold" | Press and release the mouse button; moving your head while holding drags |
| "recenter" | Move the cursor back to the center of the screen |
| "scroll down" / "scroll up" | Scroll |
| "next" / "back" | Right or left arrow: next or previous image |
| "zoom" | Toggle macOS Zoom around the cursor |

**AirPods stem**

| Press | Does |
|---|---|
| 1× | Left click |
| 2× | Right click |
| 3× | Recenter |

The menu bar icon also has Turn On/Off, Recenter, Open at Login and Quit.

## Tuning

The constants at the top of `main.swift` control feel:

- `yawRange`, `pitchRange`: degrees of head movement from center to screen edge
- `smoothing`: 0–1, lower is smoother but laggier
- `tiltDeadzone`, `tiltSpeed`, `tiltSign`: scroll threshold, speed and direction
- `magnetRadius`: how far the cursor reaches to snap to a button

## Known limits

- Speech recognition runs on-device and only in English.
- The microphone stays on while the app runs so it can hear "hands off". With the AirPods mic as input, that lowers AirPods audio quality; set Sound → Input to the built-in mic to avoid it.
- Pressing and holding the stem can't be detected: the AirPods use it for noise control.

## License

[MIT](LICENSE)
