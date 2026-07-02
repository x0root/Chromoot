#!/data/data/com.termux/files/usr/bin/bash

set -e

# --- Configuration Variables ---
DISTRO_NAME="alpine"
PULSE_TCP_PORT="4713"

# --- Functions ---

function show_menu() {
    echo "=================================================="
    echo "   Lightweight Chromium Mobile Setup (Alpine)      "
    echo "=================================================="
    echo "1) Install: Browser only (lightest, no audio)"
    echo "2) Install: Browser + Audio"
    echo "3) Launch Chromium (starts X11 + audio bridge in order, then Chromium)"
    echo "4) Test audio bridge only"
    echo "5) Uninstall (removes everything)"
    echo "6) Exit"
    echo "=================================================="
    read -p "Select an option [1-6]: " choice
    case $choice in
        1) install_chromium "no" ;;
        2) install_chromium "yes" ;;
        3) launch_chromium ;;
        4) test_audio_bridge ;;
        5) uninstall_all ;;
        6) exit 0 ;;
        *) echo "Invalid option. Exiting."; exit 1 ;;
    esac
}

function install_chromium() {
    local WITH_AUDIO="$1"

    echo -e "\n==> Installing Termux prerequisites"
    pkg update -y
    # termux-x11-nightly lives in the x11-repo add-on repo, not the main repo —
    # it must be enabled first or the install below fails with
    # "Unable to locate package termux-x11-nightly".
    pkg install -y x11-repo
    pkg update -y
    if [ "$WITH_AUDIO" = "yes" ]; then
        pkg install -y proot-distro termux-x11-nightly pulseaudio
    else
        pkg install -y proot-distro termux-x11-nightly
    fi

    echo -e "\n==> Installing minimal Alpine Linux rootfs"
    proot-distro install $DISTRO_NAME || echo "Alpine rootfs already installed, continuing."

    echo -e "\n==> Installing Chromium"
    if [ "$WITH_AUDIO" = "yes" ]; then
        proot-distro login $DISTRO_NAME -- sh -c '
            apk update
            apk add --no-cache chromium ttf-freefont pulseaudio alsa-plugins-pulse xrandr xdpyinfo
        '
        echo -e "\n==> Configuring PulseAudio client (avoids autospawn conflicts)"
        proot-distro login $DISTRO_NAME -- sh -c "
            mkdir -p /etc/pulse
            cat > /etc/pulse/client.conf << 'CONF_EOF'
autospawn = no
default-server = tcp:127.0.0.1:$PULSE_TCP_PORT
enable-shm = no
CONF_EOF
        "
        echo -e "\n==> Configuring ALSA's pulse bridge (Chromium's actual audio path"
        echo "    goes through ALSA's own pulse plugin, which has separate config"
        echo "    from PulseAudio's client.conf and wasn't picking up the server"
        echo "    address from environment variables alone)"
        proot-distro login $DISTRO_NAME -- sh -c "
            cat > /etc/asound.conf << 'ASOUND_EOF'
pcm.!default {
    type pulse
    server \"tcp:127.0.0.1:$PULSE_TCP_PORT\"
}
ctl.!default {
    type pulse
    server \"tcp:127.0.0.1:$PULSE_TCP_PORT\"
}
ASOUND_EOF
        "
    else
        proot-distro login $DISTRO_NAME -- sh -c '
            apk update
            apk add --no-cache chromium ttf-freefont xrandr xdpyinfo
        '
    fi

    echo -e "\n==> Writing launch script"
    if [ "$WITH_AUDIO" = "yes" ]; then
        AUDIO_EXPORT="export PULSE_SERVER=tcp:127.0.0.1:$PULSE_TCP_PORT"
    else
        AUDIO_EXPORT="# Audio not installed (browser-only tier); Chromium will run muted."
    fi
    proot-distro login $DISTRO_NAME -- sh -c "
cat > /usr/local/bin/chromium-launch << 'LAUNCH_EOF'
#!/bin/sh
export DISPLAY=:0
$AUDIO_EXPORT
# No window manager is installed, so there's no WM to fullscreen the window
# for us. xdpyinfo queries the X server directly for the real screen
# dimensions (more reliable than xrandr's mode list under Termux:X11).
# --force-device-scale-factor=1 fixes a known Termux:X11 DPI quirk where the
# window frame is sized correctly but Chromium's content renders shrunk
# inside it.
SCREEN_RES=\$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print \$2}')
if [ -z "\$SCREEN_RES" ]; then
    SCREEN_RES=\$(xrandr --current 2>/dev/null | grep '\*' | head -n1 | awk '{print \$1}')
fi
SCREEN_RES=\${SCREEN_RES:-1080x2280}
# --no-sandbox is MANDATORY for proot.
# --disable-gpu / --disable-software-rasterizer favor stability over speed.
# --disable-dev-shm-usage avoids crashes from a too-small /dev/shm in proot.
exec chromium \\
    --no-sandbox \\
    --disable-gpu \\
    --disable-software-rasterizer \\
    --disable-dev-shm-usage \\
    --ozone-platform=x11 \\
    --force-device-scale-factor=1 \\
    --window-size=\$SCREEN_RES \\
    --window-position=0,0 \\
    --no-first-run \\
    --disable-sync \\
    --disable-default-apps \\
    --disable-background-networking \\
    --disable-domain-reliability \\
    --disable-client-side-phishing-detection \\
    --disable-site-isolation-trials \\
    --renderer-process-limit=4 \\
    --disable-smooth-scrolling \\
    --enable-low-end-device-mode \\
    --disable-features=Translate,BackForwardCache \\
    --metrics-recording-only
LAUNCH_EOF
chmod +x /usr/local/bin/chromium-launch
"

    echo -e "\n=================================================="
    echo "Setup complete! ($([ "$WITH_AUDIO" = "yes" ] && echo "Browser + Audio" || echo "Browser only"))"
    echo "Note: no window manager is installed, so the browser opens sized"
    echo "to your screen but without draggable window decorations."
    echo "Before launching: open the Termux:X11 app once (just open it,"
    echo "nothing else needed there)."
    echo "Then use menu option 3 (Launch Chromium) — it starts termux-x11"
    echo "and the audio bridge in the right order automatically."
    echo "=================================================="
}

function launch_chromium() {
    if ! proot-distro login $DISTRO_NAME -- sh -c 'test -x /usr/local/bin/chromium-launch' 2>/dev/null; then
        echo "--> Chromium isn't installed yet. Run option 1 or 2 first."
        return
    fi

    echo -e "\n==> Checking Termux:X11"
    X11_SOCKET="$PREFIX/tmp/.X11-unix/X0"
    if ! pgrep -f "termux-x11" >/dev/null 2>&1 || [ ! -S "$X11_SOCKET" ]; then
        echo "--> Termux:X11 isn't actually serving a display right now"
        echo "    (a stale process can still match the check above even when"
        echo "    the socket is dead — this catches that case)."
        echo "    Fix: pkill -f termux-x11 && termux-x11 :0 &"
        echo "    Then re-run this option."
        return
    fi
    echo "--> Termux:X11: running and socket confirmed"

    HAS_AUDIO="no"
    if command -v pulseaudio >/dev/null 2>&1; then
        HAS_AUDIO="yes"
    fi

    if [ "$HAS_AUDIO" = "yes" ]; then
        echo -e "\n==> Starting audio bridge"

        # Always force a clean restart with an explicit --exit-idle-time=-1,
        # rather than trusting whatever daemon instance happens to already
        # be running. A pre-existing instance (started before this script
        # ever touched it) likely has PulseAudio's normal idle-timeout
        # behavior, meaning it can silently exit between our pre-launch
        # check and Chromium actually trying to play audio 20-30+ seconds
        # later — which matches the exact failure pattern observed.
        pulseaudio -k >/dev/null 2>&1 || true
        sleep 1
        pulseaudio --start --exit-idle-time=-1 || true
        for i in 1 2 3 4 5; do
            pactl info >/dev/null 2>&1 && break
            sleep 1
        done

        # Load a TCP loopback module rather than a unix socket bridged via
        # --shared-tmp. Repeated real-world failures (Connection refused,
        # then Protocol error, then Connection refused again) pointed at
        # proot's ptrace-based path translation being unreliable for unix
        # sockets specifically — TCP on 127.0.0.1 needs no path translation
        # at all, sidestepping that whole class of problem.
        if ! pactl -s "tcp:127.0.0.1:$PULSE_TCP_PORT" info >/dev/null 2>&1; then
            pactl load-module module-native-protocol-tcp port=$PULSE_TCP_PORT listen=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true
            for i in 1 2 3 4 5; do
                pactl -s "tcp:127.0.0.1:$PULSE_TCP_PORT" info >/dev/null 2>&1 && break
                sleep 1
            done
        fi

        if pactl -s "tcp:127.0.0.1:$PULSE_TCP_PORT" info >/dev/null 2>&1; then
            echo "--> Audio bridge is live."
        else
            echo "--> Audio bridge failed to start. Launching Chromium muted instead."
        fi

        # Guard against the sink sitting muted or at 0% by default — the
        # bridge can be fully connected and still be silent for this reason.
        if pactl info >/dev/null 2>&1; then
            pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true
            pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null || true
        fi
    fi

    echo -e "\n==> Launching Chromium"
    proot-distro login $DISTRO_NAME --shared-tmp -- chromium-launch
}

function test_audio_bridge() {
    echo -e "\n==> ALSA bridge config (Chromium's actual audio path)"
    proot-distro login $DISTRO_NAME -- sh -c 'cat /etc/asound.conf 2>/dev/null' || echo "    /etc/asound.conf not found — reinstall with option 2 to create it."

    echo -e "\n==> PulseAudio versions"
    echo -n "    Termux (host):  "
    pulseaudio --version 2>/dev/null || echo "not found"
    echo -n "    Alpine (guest): "
    proot-distro login $DISTRO_NAME -- sh -c 'pulseaudio --version' 2>/dev/null || echo "not found"

    echo -e "\n==> Checking host-side PulseAudio server"
    if ! pactl info >/dev/null 2>&1; then
        echo "--> Host PulseAudio server is not running. Run option 3 (Launch"
        echo "    Chromium) first — it starts the bridge automatically."
        return
    fi
    echo "--> Host PulseAudio server: OK"

    echo -e "\n==> Checking the TCP bridge (127.0.0.1:$PULSE_TCP_PORT)"
    if ! pactl -s "tcp:127.0.0.1:$PULSE_TCP_PORT" info >/dev/null 2>&1; then
        echo "--> TCP bridge is not live. Run option 3 to load it."
        return
    fi
    echo "--> TCP bridge: OK"

    echo -e "\n==> Checking Alpine's client can reach it and complete a handshake"
    if proot-distro login $DISTRO_NAME -- sh -c "PULSE_SERVER=tcp:127.0.0.1:$PULSE_TCP_PORT pactl info" 2>&1 | tail -5; then
        echo -e "\n--> Audio bridge is fully working."
    else
        echo -e "\n--> Handshake failed from inside Alpine even though the host-side"
        echo "    bridge is live. This would point at something blocking loopback"
        echo "    traffic between the proot environment and Termux, which would be"
        echo "    unusual — share this output if you hit it."
    fi
}

function uninstall_all() {
    echo -e "\n==> Forcefully uninstalling Chromium and the entire Alpine environment"
    read -p "Are you sure you want to delete the entire Alpine rootfs? [y/N]: " confirm
    if [[ $confirm == [yY] ]]; then
        proot-distro remove $DISTRO_NAME || echo "Alpine rootfs already removed."
        echo "--> Cleanup complete."
    else
        echo "--> Uninstall cancelled."
    fi
}

# --- Main ---
show_menu
