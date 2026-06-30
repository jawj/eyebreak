# EyeBreak

A tiny macOS menu-bar app that nudges you to follow the **20-20-20 rule**:
every 20 minutes, look at something ~20 feet away for 20 seconds to rest your
eyes.

## What it does

- Lives in the menu bar as an eye icon (👁): no Dock icon, no window
- Every 20 minutes shows a small floating overlay prompting you to look into
  the distance for 20 seconds
- A gentle chime starts and ends the break (unless toggled to silent)
- The break only counts down while you're off the keyboard and mouse: any input
  restarts it
- If you're idle for 5+ minutes, the interval resets: you get a fresh 20 
  minutes when you return
- 'Postpone for webcam' option: while your webcam is in use (e.g. you're on a 
  video call), no breaks are prompted. The break appears two minutes after the
  call ends.

## Requirements

- macOS 13 (Ventura) or later
- Xcode command line tools (`clang`) — `xcode-select --install`

## Compile and run

```sh
make        # builds EyeBreak.app
make run    # builds, then launches the app
make clean  # removes the build
```

## Install

```sh
make && rm -rf /Applications/EyeBreak.app && mv EyeBreak.app /Applications/EyeBreak.app
```

Enable **Launch at login** from the menu.

## License

[MIT](LICENSE)
