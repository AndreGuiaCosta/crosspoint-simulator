# CrossPoint Simulator

A desktop simulator for [CrossPoint](https://github.com/crosspoint-reader/crosspoint-reader)-based firmware. Compiles the firmware natively and renders the e-ink display in an SDL2 window — no device required.

> **Platform support:** macOS and Linux/WSL use different native compiler and library flags. Start from `sample-platformio-macos.ini` on macOS, or `sample-platformio-linux-wsl.ini` on Linux/WSL. Native Windows is not supported; use WSL and follow the Linux instructions.

## Prerequisites

SDL2 must be installed on the host machine. Linux/WSL users also need OpenSSL development headers for MD5 support.

```bash
# macOS
brew install sdl2

# Linux — Debian/Ubuntu (including WSL)
sudo apt install libsdl2-dev libssl-dev

# Linux — Fedora/RHEL
sudo dnf install SDL2-devel openssl-devel

# Linux — Arch
sudo pacman -S sdl2 openssl
```

## Integration

Add the `run_simulator.py` script to `./scripts` in the Firmware's project root. This will add a Platformio task in the IDE to quickly run the simulator.

Add the simulator to your firmware's platformio.ini as a lib_dep and configure the [env:simulator] environment. Use the sample file for your host OS:

- `sample-platformio-macos.ini`
- `sample-platformio-linux-wsl.ini`

For local development, replace the git reference with a symlink after you've cloned the repository:

```ini
simulator=symlink://../crosspoint-simulator
```

## Setup

Place EPUB books at `./fs_/books/` relative to the project root. This maps to the `/books/` path on the physical SD card.

## Build and run

```bash
pio run -e simulator
.pio/build/simulator/program
```

Or use the custom PlatformIO target to build and run in one step:

```bash
pio run -e simulator -t run_simulator
```

## Controls

| Key    | Action                             |
| ------ | ---------------------------------- |
| ↑ / ↓  | Page back / forward (side buttons) |
| ← / →  | Left / right front buttons         |
| Return | Confirm / Select                   |
| Escape | Back                               |
| P      | Power                              |

## Notes

**Cache**: On first open of an ebook, an "Indexing..." popup will appear while the section cache is built. If you see rendering issues after a code change that affects layout, delete `./fs_/.crosspoint/` to clear stale caches.

**HAL compatibility:** The simulator implements the HAL interface defined in `lib/hal/*.h`. If your firmware adds a new method to a HAL class and calls it, the simulator will fail to link until a matching stub is added to the relevant Hal\*.cpp here. For most cases this is a one-liner no-op. Open a PR if the change is applicable to all CrossPoint-based forks.
