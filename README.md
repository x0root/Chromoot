# Chromoot

*Chrom(ium) + proot* — a real, full desktop build of **Chromium** running on
Android via Termux + a minimal Alpine Linux **proot** environment. No root
required. Includes a working audio bridge and a resolution-aware launch
script, both worked out through real device testing rather than assumed to
work.

> **Note on naming:** this is Chromium (the open-source project), not Google
> Chrome — Google does not publish a Chrome build for Linux ARM, so Chromium
> is the closest real equivalent available here. The name **Chromoot** is a
> portmanteau of **Chrom**(ium) and **proot** — proot is the actual
> lightweight sandboxing tool (no root, no VM) that makes running a full
> Linux distro, and therefore a real desktop browser, possible on stock
> Android in the first place.

## What this actually is

- Termux (Android terminal app) + `proot-distro` running a minimal **Alpine
  Linux** environment (musl-based, small footprint)
- **Termux:X11** providing the display server
- Chromium installed inside Alpine via `apk`, launched with flags tuned for
  proot's constraints (no sandbox namespaces, no real GPU access)
- An audio bridge from Termux's PulseAudio server to Chromium inside the
  proot environment, over TCP loopback

## Requirements

- Android device (tested working on a Samsung Galaxy A23; likely works on
  most modern arm64 Android devices, but this is not guaranteed across all
  OEM skins/kernels — see **Known limitations** below)
- [Termux](https://f-droid.org/packages/com.termux/) (F-Droid build recommended)
- [Termux:X11](https://github.com/termux/termux-x11/releases) APK, installed
  separately as its own Android app (not something `pkg install` can get you)
- Roughly 300–350 MB free storage

## Setup

1. Install Termux and the Termux:X11 APK (see Requirements above).
2. In Android Settings → Apps → **Termux:X11** → Battery, set it to
   **Unrestricted**. Android aggressively background-kills apps it doesn't
   recognize as active, and this is the single most common cause of the
   browser silently failing to launch after the first successful run.
3. Copy `chromoot.sh` into Termux and make it executable:
   ```
   chmod +x chromoot.sh
   ```
4. Run it:
   ```
   ./chromoot.sh
   ```

## Menu

```
1) Install: Browser only (lightest, no audio)
2) Install: Browser + Audio
3) Launch Chromium (starts X11 + audio bridge in order, then Chromium)
4) Test audio bridge only
5) Uninstall (removes everything)
6) Exit
```

**First time:** run option 1 or 2 to install. Then open the Termux:X11 app
once (just open it, nothing else needed there), switch back to Termux, and
run option 3 to launch.

**Every time after:** just option 3. It handles starting the X11 bridge and
the audio bridge in the correct order automatically.

If sound isn't working, run option 4 first — it checks each layer of the
audio path individually (PulseAudio versions, the TCP bridge, and a real
handshake test from inside the proot environment) and tells you specifically
which one failed, instead of a generic "no audio."

## Known limitations

- **No sandbox.** Chromium runs with `--no-sandbox`, which is mandatory
  under proot (it can't provide the kernel namespaces the sandbox needs).
  Fine for general browsing; avoid logging into highly sensitive accounts
  (banking, etc.) in this specific browser instance.
- **No camera or microphone.** Getting a real webcam device into Chromium
  requires the `v4l2loopback` kernel module, which needs root and a kernel
  that allows loading modules — not available on stock, non-rooted Android.
  Live microphone capture has no reliable built-in bridge in Termux either.
- **Software rendering only.** `--disable-gpu` is required because Android
  doesn't expose the standard Linux GPU interface (`/dev/dri`) that Chromium
  expects. This is the real ceiling on performance — no flag fully undoes it.
- **Audio reliability may vary by device.** The TCP-loopback bridge and ALSA
  config here were arrived at after ruling out several other failure modes
  (unix socket path translation issues under proot, PulseAudio version
  mismatches, stale idle-timed-out daemons). It's been confirmed working on
  a Samsung Galaxy A23; other OEM audio stacks or Android versions may
  surface issues not covered here. Please open an issue if you hit one.
- **No window manager.** By design, to keep the footprint minimal — the
  browser opens sized to your screen but without draggable window
  decorations. `xdpyinfo` detects your actual resolution at launch and
  `--force-device-scale-factor=1` avoids a known Termux:X11 DPI-scaling
  quirk, but Termux:X11's own resolution setting (gear icon in its extra-keys
  bar) may need to be set to match your device for content to fill correctly.

## Troubleshooting

- **"Missing X server or $DISPLAY" / Chromium won't launch:** Termux:X11 has
  likely been killed in the background. Run:
  ```
  pkill -f termux-x11
  termux-x11 :0 &
  ```
  then confirm it worked before retrying:
  ```
  ls -la $PREFIX/tmp/.X11-unix/
  ```
  You should see a file named `X0`.
- **Chromium crashes with "GPU process isn't usable":** don't add
  `--use-gl=swiftshader` alongside `--disable-software-rasterizer` — they
  contradict each other and this script deliberately avoids that combination.
- **Audio silent or "Connection refused":** run option 4 and read which
  specific check failed. Common causes covered by this script already:
  stale sockets, PulseAudio module not loaded on an already-running daemon,
  and idle-timeout killing the daemon between checks — if you hit a *new*
  failure mode, please open an issue with the option 4 output attached.

## License

MIT (or your preference — add a LICENSE file before publishing).

## Disclaimer

Personal/community project, not affiliated with Google, the Chromium
Project, Termux, or Alpine Linux. Chromium runs with `--no-sandbox` as an
inherent requirement of this environment — understand the tradeoff described
above before using this for anything beyond casual browsing.
