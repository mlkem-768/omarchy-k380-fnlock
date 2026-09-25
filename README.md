<h1 align="center">⌨️ K380 FnLock</h1>

<p align="center">
  Toggle <b>FnLock</b> on the Logitech K380 — for <a href="https://omarchy.org">Omarchy</a> (Quattro)
</p>


## ✨ Why

The Logitech K380 has FnLock disabled by default, so you need to hold Fn to use F1–F12 as function keys. That is not always convenient, especially if you use the function keys often. I made this plugin to make it easy to choose how the K380’s keys behave.


## 🧰 Features

- **Bar widget**
  - Left-click: Open a panel to choose a mode or reapply the current one
  - Right-click: Toggle between F-keys and media keys

- **CLI**
  - Check the current state or set and toggle the mode from a terminal:


## ⚙️ How it works

The script uses `hidapi` to send the FnLock command to the K380 and stores the requested mode in `~/.local/state/omarchy-k380-fnlock/`. A udev rule grants your desktop user direct access to the K380's HID interface, so no root/sudo is needed at runtime.

- `on` makes F1–F12 work as standard function keys.
- `off` gives the media and special-key functions priority.
- `apply` sends the saved mode to the keyboard again.


## 🚀 CLI Usage

```sh
omarchy-k380-fnlock set on   # Use F1–F12 as standard function keys
omarchy-k380-fnlock set off  # Use media and special-key functions
omarchy-k380-fnlock toggle   # Switch between the two modes
omarchy-k380-fnlock status   # Show the saved and last-applied modes
omarchy-k380-fnlock apply    # Reapply the saved mode
```

- `Desired` is the saved mode.
- `Applied` is the mode most recently sent successfully to the keyboard. If the keyboard is unavailable, these values may differ.


## 🗑️ Uninstall

```sh
./uninstall.sh
omarchy plugin remove io.github.mlkem-768.k380-fnlock
```

The CLI script removes the installed program and system integration files. The saved state in `~/.local/state/omarchy-k380-fnlock` is left intact.


## 🔒 Privacy

The plugin works locally and communicates with the K380’s HID interface. It does not use network access or telemetry.


## 📄 License

MIT — see [LICENSE](LICENSE).