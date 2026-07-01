# AR0822 kernel driver for Raspberry Pi

[![Build](https://github.com/Kurokesu/ar0822-rpi-driver/actions/workflows/build-rpi.yml/badge.svg)](https://github.com/Kurokesu/ar0822-rpi-driver/actions/workflows/build-rpi.yml)
[![Code style](https://github.com/Kurokesu/ar0822-rpi-driver/actions/workflows/clang-format.yml/badge.svg)](https://github.com/Kurokesu/ar0822-rpi-driver/actions/workflows/clang-format.yml)
[![Raspberry Pi OS Bookworm](https://img.shields.io/badge/Raspberry_Pi_OS-Bookworm-blue?logo=raspberrypi)](https://www.debian.org/releases/bookworm/)
[![Raspberry Pi OS Trixie](https://img.shields.io/badge/Raspberry_Pi_OS-Trixie-blue?logo=raspberrypi)](https://www.debian.org/releases/trixie/)

Raspberry Pi kernel driver for Onsemi AR0822 — an 8 MP rolling shutter 1/1.8" back side illuminated CMOS sensor.

- 2-lane and 4-lane MIPI CSI-2 (up to 960 Mbps/lane)
- 10-bit and 12-bit RAW output
- 3840×2160 @ 40 fps (full resolution)
- 1920×1080 @ 120 fps (2×2 binning)

> [!NOTE]
> This driver supports an experimental eHDR mode, modeled after the IMX708
> implementation, by exposing the standard `V4L2_CID_WIDE_DYNAMIC_RANGE` control.
> Read more in [eHDR (experimental)](#ehdr-experimental).

## Setup

> [!NOTE]
> Requires Linux kernel 6.1 or newer. Verify with `uname -r`.

Install required tools:

```bash
sudo apt install -y git
sudo apt install -y --no-install-recommends dkms
```

Clone this repository:

```bash
cd ~
git clone https://github.com/Kurokesu/ar0822-rpi-driver.git
cd ar0822-rpi-driver/
```

Run setup script:

```bash
sudo ./setup.sh
```

Edit boot configuration:

```bash
sudo nano /boot/firmware/config.txt
```

Make two changes:

1. Find `camera_auto_detect` near the top and set it to `0`:

```ini
camera_auto_detect=0
```

2. Add `dtoverlay=ar0822` under the `[all]` section at the bottom of the file:

```ini
[all]
dtoverlay=ar0822
```

Save and exit. Reboot for changes to take effect.

> [!IMPORTANT]
> Stock `libcamera` does not support AR0822 — you must build a patched version for camera to function. See [Build libcamera](#build-libcamera) below.

## dtoverlay options

`ar0822` overlay supports comma-separated options to override defaults:

| option | description | default |
|--------|-------------|----------|
| `cam0` | Use cam0 port instead of cam1 | cam1 |
| `4lane` | Use 4-lane MIPI CSI-2 (if wired) | 2 lanes |

### cam0

If camera is connected to cam0 port, append `,cam0`:

```ini
dtoverlay=ar0822,cam0
```

### 4lane

To enable 4-lane MIPI CSI-2, append `,4lane`:

```ini
dtoverlay=ar0822,4lane
```

> [!WARNING]
> Before using `4lane`, confirm your camera port actually supports 4-lane MIPI CSI. Not all Raspberry Pi models and carrier boards provide 4-lane MIPI CSI on both ports.

> [!TIP]
> Options can be combined. Example — cam0, 4-lane:
> ```ini
> dtoverlay=ar0822,cam0,4lane
> ```

## Build libcamera

Main `libcamera` repository does not support AR0822. A fork with necessary modifications is available.

On Raspberry Pi, `libcamera` and `rpicam-apps` must be rebuilt together. Detailed instructions are available [here](https://www.raspberrypi.com/documentation/computers/camera_software.html#advanced-rpicam-apps), but for convenience, here is a shorter version.

Remove pre-installed `rpicam-apps`:

```bash
sudo apt remove --purge rpicam-apps
```

### libcamera

Install dependencies:

```bash
sudo apt install -y libboost-dev
sudo apt install -y libgnutls28-dev openssl libtiff5-dev pybind11-dev
sudo apt install -y qtbase5-dev libqt5core5a libqt5gui5 libqt5widgets5
sudo apt install -y meson cmake
sudo apt install -y python3-yaml python3-ply
sudo apt install -y libglib2.0-dev libgstreamer-plugins-base1.0-dev
```

Clone Kurokesu's `libcamera` fork with AR0822 support:

```bash
cd ~
git clone https://github.com/Kurokesu/libcamera.git --branch ar0822
cd libcamera/
```

Configure with `meson`:

```bash
meson setup build --buildtype=release -Dpipelines=rpi/vc4,rpi/pisp -Dipas=rpi/vc4,rpi/pisp -Dv4l2=enabled -Dgstreamer=enabled -Dtest=false -Dlc-compliance=disabled -Dcam=disabled -Dqcam=disabled -Ddocumentation=disabled -Dpycamera=enabled
```

Build:

```bash
ninja -C build
```

Install:

```bash
sudo ninja -C build install
```

> [!TIP]
> On devices with 1 GB of memory or less, build may exceed available memory. Append `-j 1` to limit to a single process.

> [!WARNING]
> `libcamera` does not yet have a stable binary interface. Always build `rpicam-apps` after building `libcamera`.

### rpicam-apps

Install dependencies:

```bash
sudo apt install -y cmake libboost-program-options-dev libdrm-dev libexif-dev
sudo apt install -y libavcodec-dev libavdevice-dev libavformat-dev libswresample-dev
sudo apt install -y libepoxy-dev libpng-dev
```

Clone Kurokesu's `rpicam-apps` fork with HDR modifications:

```bash
cd ~
git clone https://github.com/Kurokesu/rpicam-apps.git --branch hdr-ar0822
cd rpicam-apps
```

Configure with `meson` (libav enabled by default):

```bash
meson setup build -Denable_libav=enabled -Denable_drm=enabled -Denable_egl=enabled -Denable_qt=enabled -Denable_opencv=disabled -Denable_tflite=disabled -Denable_hailo=disabled
```

> [!IMPORTANT]
> On Raspberry Pi OS **Bookworm**, packaged `libav*` is **too old** for `rpicam-apps` newer than v1.9.0.

<details>
<summary>Bookworm libav workaround</summary>

Bookworm ships `libavcodec` **59.x** while newer `rpicam-apps` expects **libavcodec >= 60**, causing build errors like "libavcodec API version is too old" (see [Raspberry Pi forum thread](https://forums.raspberrypi.com/viewtopic.php?t=392649)).

- **Keep libav, without eHDR** — check out `rpicam-apps` **v1.9.0** before running `meson setup` (v1.9.0 predates eHDR patches, so eHDR will **not** be available):
  ```bash
  git checkout v1.9.0
  ```
- **Keep eHDR, disable libav** — stay on `hdr-ar0822` branch and disable libav:
  ```bash
  meson setup build -Denable_libav=disabled -Denable_drm=enabled -Denable_egl=enabled -Denable_qt=enabled -Denable_opencv=disabled -Denable_tflite=disabled -Denable_hailo=disabled
  ```

</details>

Build:

```bash
meson compile -C build
```

Install:

```bash
sudo meson install -C build
```

> [!TIP]
> This should automatically update `ldconfig` cache. If you have trouble accessing your new build, update manually:
>
> ```bash
> sudo ldconfig
> ```

### Verify rpicam-apps build

Verify `rpicam-apps` was rebuilt correctly:

```bash
rpicam-hello --version
```

Expected output (build date will differ):

```
rpicam-apps build: v1.11.1 d2836f37957f 25-02-2026 (14:43:27)
rpicam-apps capabilites: egl:1 qt:1 drm:1 libav:1
libcamera build: v0.0.0+6160-8903357b
```

### Verify that `ar0822` is detected

Do not forget to reboot!

```bash
sudo reboot
```

List available cameras:

```bash
rpicam-hello --list-cameras
```

Expected output (varies by link frequency and lane configuration):

```
Available cameras
-----------------
0 : ar0822 [3840x2160 12-bit GRBG] (/base/axi/pcie@1000120000/rp1/i2c@88000/ar0822@10)
    Modes: 'SGRBG10_CSI2P' : 1920x1080 [120.15 fps - (0, 0)/3840x2160 crop]
                             3840x2160 [40.03 fps - (0, 0)/3840x2160 crop]
           'SGRBG12_CSI2P' : 1920x1080 [120.21 fps - (0, 0)/3840x2160 crop]
                             3840x2160 [33.89 fps - (0, 0)/3840x2160 crop]
```

## eHDR (experimental)

AR0822 features an on‑sensor HDR mode that expands dynamic range up to 120 dB by combining three exposures within sensor using the MEC algorithm. To reduce bandwidth requirements, linearized 20‑bit HDR signal is companded to a 12‑bit output.

> [!IMPORTANT]
> libcamera pipeline is designed for linear image data from sensor. While Kurokesu's fork HDR implementation is experimental, companded data may show color shifts due to compression.

Due to exposure range limitations, running at maximum fps with current PIXCLK configuration reduces maximum exposure drastically.

For instance, running 4K @ 30 fps results in maximum exposure T1 ≈ 10.26 ms, while running 4K @ 28.8 fps results in T1 ≈ 30.4 ms (right at internal delay buffer limit).

Consider reducing framerate slightly when larger exposure range is desired. This will be addressed in future driver revisions.

eHDR mode is enabled by appending `--hdr` to `rpicam` commands.

### List eHDR modes

```bash
rpicam-hello --list-cameras --hdr
```

```
Available cameras
-----------------
0 : ar0822 [3840x2160 12-bit GRBG] (/base/axi/pcie@1000120000/rp1/i2c@88000/ar0822@10)
    Modes: 'SGRBG12_CSI2P' : 1920x1080 [48.04 fps - (0, 0)/3840x2160 crop]
                             3840x2160 [30.01 fps - (0, 0)/3840x2160 crop]
```

## Special thanks

- [Will Whang](https://github.com/will127534) for [imx585-v4l2-driver](https://github.com/will127534/imx585-v4l2-driver), used as basis for structuring this driver.
- Sasha Shturma's Raspberry Pi CM4 carrier with Hi-Res MIPI Display project. Install script adapted from [cm4-panel-jdi-lt070me05000](https://github.com/renetec-io/cm4-panel-jdi-lt070me05000).
