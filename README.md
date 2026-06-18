# EyeBreak

A tiny macOS menu-bar app that nudges you to follow the **20-20-20 rule**: every
20 minutes, look at something ~20 feet away for 20 seconds to rest your eyes.

## What it does

- Lives in the menu bar as an eye icon (👁) — no Dock icon, no window
- Every 20 minutes of active screen time it shows a small floating overlay
  prompting you to look into the distance for 20 seconds, with a gentle chime at
  the start and end of the break
- The 20-second break only counts down while you're genuinely away from the
  keyboard and mouse — any input restarts it
- If you're idle for 3+ minutes, the next interval resets and you get a fresh 
  20 minutes when you return

## Requirements

- macOS 13 (Ventura) or later
- Xcode command line tools (`clang`) — `xcode-select --install`

## Compile and run

```sh
make        # builds EyeBreak.app
make run    # builds, then launches the app
make clean  # removes the build
```

`make` produces `EyeBreak.app` in the project directory; double-click it or run
`make run`. To keep it around, drag `EyeBreak.app` to `/Applications`, then enable
**Launch at login** from the menu.

## License

MIT — see [LICENSE](LICENSE).
