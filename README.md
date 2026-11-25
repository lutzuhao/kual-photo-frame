# Kindle Photo Frame

An offline photo slideshow for jailbroken Kindles, installed as a [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) extension. Photos live on the device; it does not need a network or a cloud account. The default mode draws each photo on the Kindle sleep screen and uses the RTC alarm to change it, so one press of the power button returns you to the Kindle UI immediately.

This repository is the KUAL extension, default settings, and a photo conversion script. It does not include photos, Amazon firmware, KUAL, KOReader, or jailbreak tools.

**License:** [MIT](LICENSE) (copyright 2026 lutzuhao).

## Features

- Offline shuffle: every matching photo is shown once before any repeats
- Intervals: every 15 or 30 minutes, or 1, 6, 12, or 24 hours (aligned to the clock)
- Sleep-screen mode (default, quick exit) or full takeover mode
- Same scripts on Kindle Paperwhite 1 (758×1024) and Kindle Oasis 1st generation (1072×1448); photos are prepared per device
- Landscape photos are rotated to fill the portrait screen
- KUAL menu for interval, orientation, exit style, battery display, and quiet hours
- Optional battery percentage in the bottom-right corner (`87%`, or `87%+` while charging)
- Quiet hours: keep the current photo and sleep through the night (default 23:00–07:00 local time)
- Low-battery hold: at or below 8% and not charging, the current photo stays and no wake alarm is set
- Sleep-screen mode turns Wi-Fi off while the photo is showing and restores it when you wake the Kindle, or when you press Stop

## Supported devices (tested)

| Device | Firmware | Resolution |
|---|---|---|
| Kindle Paperwhite 1st generation (PW1) | 5.6.1.1 | 758×1024 |
| Kindle Oasis 1st generation | 5.9.7 | 1072×1448 |

Other jailbroken Kindles with KUAL, `lipc-wait-event`, and a writable RTC wake path may work, but they have not been tested. Prepare photos at that device's exact resolution.

## Requirements

- A jailbroken Kindle (jailbreaking is at your own risk; see the disclaimer below)
- [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) installed
- Photos converted to the device resolution (see [Preparing photos](#preparing-photos))
- **Recommended:** [FBInk](https://github.com/NiLuJe/FBInk) with image support, for dithered full-panel draws. The KindleModding hotfix installs it at `/mnt/us/libkh/bin/fbink`. KOReader also ships FBInk (`/mnt/us/koreader/fbink`). If FBInk is not found, the extension falls back to the built-in `eips` tool (lower quality, no dithering)

This project does not ship FBInk, KUAL, KOReader, or any Amazon firmware.

## Install

1. Convert your photos (see below) so you have a `photoframe/` folder with `images/`, `settings.sh`, and `landscape.txt`.
2. Connect the Kindle by USB. Copy these two folders onto the Kindle root (the same level as `documents/`):
   - `extensions/photoframe/` → `extensions/photoframe/`
   - `photoframe/` → `photoframe/`
3. On macOS, copy without AppleDouble `._` files, then eject:

```sh
ditto --norsrc --noextattr extensions/photoframe /Volumes/Kindle/extensions/photoframe
ditto --norsrc --noextattr photoframe /Volumes/Kindle/photoframe
find /Volumes/Kindle/extensions/photoframe /Volumes/Kindle/photoframe -name '._*' -delete
```

4. Eject the Kindle, unplug it, fully close KUAL and open it again so the menu reloads, then **Photo Frame → Stop photo frame**, then **Start photo frame**. Scripts run from a tmpfs copy, so Stop then Start is required after every update.

Re-copying `photoframe/` from a computer overwrites `settings.sh` with the defaults.

## KUAL menu

The current choice is marked with `*`.

| Menu | What it does |
|---|---|
| Start photo frame | Start the slideshow |
| Stop photo frame | Stop it completely (a reboot also stops it) |
| Change interval | 15 min, 30 min, 1 hour, 6 hours, 12 hours, 24 hours |
| Photo orientation | All photos / only vertical / only horizontal (rotated) |
| Exit style | Quick exit: sleep-screen mode (default) / Full takeover |
| Tap to toggle light | Off (default) / On while charging (stay awake, takeover) |
| Battery display | On (default): small percentage, bottom-right / Off |
| Quiet hours | Off / 22:00–07:00 / 23:00–07:00 (default) / 00:00–06:00 |
| Preview one photo now | Draw one photo immediately |
| Reset shuffle order | Reshuffle the bag |
| Show status | Settings, photo counts, battery, and running state |

## Sleep-screen mode

After **Start photo frame**, the Kindle goes to sleep and the sleep screen is your photo. At each interval it wakes, changes the photo, and sleeps again.

- One press of the **power button** returns to the Kindle UI immediately. The photo frame stays armed: sleep again and the photos come back.
- To stop it completely: KUAL → Photo Frame → **Stop photo frame**. It does not start automatically after a reboot.
- When the Kindle first sleeps you may briefly see the stock sleep screen; after a few seconds the photo is drawn over it. That is normal.
- While the sleep screen is up, Wi-Fi is turned off to save power and restored when you leave the sleep screen or press Stop.
- At or below 8% battery and not charging, the current photo is kept and no wake alarm is set, so the Kindle simply sleeps.
- The slideshow does not change photos while the Kindle is exported over USB.

**Full takeover** stops the Kindle UI while photos are showing. Exiting restarts the UI (about 30–60 seconds, looks like a reboot). Use this when you want **Tap to toggle light** while charging, or when sleep-screen mode cannot start.

If something gets stuck, hold the power button for about 20 seconds to force a reboot. The photo frame will not auto-start; you get a normal Kindle.

## Battery display

When **Battery display** is On (the default), a small inverted label is drawn in the bottom-right corner after each photo: `87%`, or `87%+` if the Kindle is charging. It uses a partial refresh so it does not flash or clear the photo. Turn it off from the KUAL menu; the setting is stored in `photoframe/settings.sh` as `SHOW_BATTERY`.

## Quiet hours

When quiet hours are on (default **23:00–07:00** local time), the current photo is kept and the Kindle is set to wake at the end of the window, so it can sleep through the night. Low-battery behaviour still wins: if the battery is at or below 8% and not charging, no wake alarm is set.

Kindle clocks are often set to UTC, even when you live in another timezone. The extension does not trust the device timezone. It uses `TZ_OFFSET` in `settings.sh` (default `+8`, Asia/Taipei) to compute local time. The KUAL menu does not change this offset; edit `TZ_OFFSET` if you need a different zone (for example `-5`). Whole-hour offsets also keep the 15-minute clock-tick alignment.

Presets in the menu: Off, 22:00–07:00, 23:00–07:00, 00:00–06:00. The window is `[start, end)` and wraps midnight when start is later than end.

## Preparing photos

The extension expects grayscale JPEGs at the exact device resolution in `photoframe/images/`, plus `photoframe/landscape.txt` listing the filenames that were rotated from landscape.

```sh
python3 -m pip install pillow
python3 tools/convert_photos.py --device pw1 --input /path/to/photos --output ./photoframe
# or:  --device oasis
```

The script applies EXIF orientation, converts to grayscale, rotates landscape photos, center-crops for a full-bleed fit, and writes `images/`, `manifest.csv`, and `landscape.txt`. After adding photos later you can rebuild the list with `sh tools/make_orientation_list.sh`.

To view a rotated landscape photo upright, turn the Kindle 90 degrees clockwise (so it lies to the right). If that is backwards, reconvert with `--rotate cw`.

## Troubleshooting

- **Photos do not change:** check the battery (a low charge holds the current photo), check quiet hours, and read `photoframe/log.txt` on the Kindle. After any script update, Stop then Start in KUAL.
- **Battery drains fast:** sleep-screen mode writes `photoframe/diag.txt`: one line per power event with the real time suspended (`slept`, wall clock minus the monotonic clock), the CPU-awake time, readyToSuspend/rtcWakeup counts, battery, front light, the interrupts that fired (wake source) and power-related system-log lines. Log lines carry `[mono N]` (seconds the CPU was awake since boot; `/proc/uptime` keeps counting during suspend and cannot show sleep).
- **Kindle clock vs local time:** log timestamps may be UTC (about 8 hours behind Taipei). Quiet hours use `TZ_OFFSET`, not the log clock. Adjust `TZ_OFFSET` if the night window feels wrong.
- **Wi-Fi was on and is now off:** sleep-screen mode turns it off while a photo is up; waking the Kindle or pressing Stop should restore it.
- **Stock sleep cover flashes first:** wait the few seconds set by `SS_DELAY` (default 3).
- **FBInk warnings in the log:** install the KindleModding hotfix or KOReader so dithered draws are available; `eips` still works as a fallback.
- **Front light and magnet wake (sleep-screen mode):** while the frame runs the front light is kept at `FRONTLIGHT_LEVEL` (default 0 = off) and the cover/magnet (hall) sensor is switched off (`HALL_OFF=1`, Oasis only: `hall_enable` in sysfs, the same switch KOReader uses for "ignore cover events"). **Stop** puts both back. If the Kindle wakes by itself after a failed hibernate (`suspending "disk"`, outOfScreenSaver without a real button press) the frame turns the light off and goes back to the sleep screen instead of exiting to the home screen.
- **Stuck screen:** hold the power button for about 20 seconds.

## Disclaimer

Jailbreaking a Kindle, installing third-party software, and using this extension are at your own risk. This can void a warranty, and a mistake can leave a device in an awkward state. There is no warranty of any kind; see [LICENSE](LICENSE). This project is not affiliated with Amazon.

## Credits and third-party code

This extension is original code, released under the MIT License.

Ideas and behaviour (not copied source) were informed by:

- The continuous `lipc-wait-event -m` scheduler used by [onlinescreensaver](https://www.mobileread.com/forums/showthread.php?t=185659) / [onlinescreensaverPW2](https://github.com/FalconFour/onlinescreensaverPW2), for catching `readyToSuspend` so an RTC wake can be set
- [KOReader](https://github.com/koreader/koreader), for sleep/wake event names and the “no framework” approach used in takeover mode
- [FBInk](https://github.com/NiLuJe/FBInk) by NiLuJe, used if it is already installed on the device (not bundled here)

Please respect the licenses of those projects if you use them.

---

## 繁體中文

把 Kindle 當成離線相框：照片存在本機，不需網路或雲端帳號。這是一個 [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) 擴充套件。預設用「睡眠畫面」模式，用定時喚醒換圖；按一下電源鍵就能立刻回到 Kindle 介面。

這個倉庫只包含擴充套件、預設設定和轉圖腳本，不含照片、Amazon 韌體、KUAL、KOReader 或越獄工具。

**授權：** [MIT](LICENSE)（copyright 2026 lutzuhao）。

### 功能

- 離線隨機輪播，全部播過一輪才會重複
- 間隔：15、30 分鐘，或 1、6、12、24 小時（對齊整點）
- 預設睡眠畫面模式（快速退出），或接管整個畫面
- 同一套程式支援 PW1（758×1024）和第一代 Oasis（1072×1448），照片依機種轉成滿版
- 橫式照片會旋轉以填滿直式螢幕
- KUAL 選單可改間隔、方向、退出方式、電量顯示、夜間時段
- 可在右下角顯示電量（例如 `87%`，充電中為 `87%+`）
- 夜間時段預設 23:00–07:00（本地時間）不換圖，睡到時段結束，較省電
- 電量 8% 以下且未充電時，停在目前這張，不再設定喚醒
- 睡眠畫面期間會關掉 Wi-Fi，喚醒或按 Stop 時再恢復

### 已測試的裝置

| 裝置 | 韌體 | 解析度 |
|---|---|---|
| Kindle Paperwhite 第一代（PW1） | 5.6.1.1 | 758×1024 |
| Kindle Oasis 第一代 | 5.9.7 | 1072×1448 |

其他已越獄、有 KUAL 和喚醒鬧鐘的 Kindle 也許也能用，但尚未測試。照片必須是該機種的解析度。

### 需求

- 已越獄的 Kindle（越獄需自行承擔風險，見下方聲明）
- 已安裝 KUAL
- 已轉成該機種解析度的照片
- **建議**安裝有圖片支援的 FBInk（KindleModding hotfix 會放到 `/mnt/us/libkh/bin/fbink`；KOReader 也有）。找不到時會改用內建的 eips，畫質較差

### 安裝

1. 先轉好照片，得到含 `images/`、`settings.sh`、`landscape.txt` 的 `photoframe/`。
2. USB 接上 Kindle，把兩個資料夾複製到 Kindle 根目錄（和 `documents` 同一層）：
   - `extensions/photoframe/` → `extensions/photoframe/`
   - `photoframe/` → `photoframe/`
3. 在 macOS 上用下面的指令複製，避免產生 `._` 檔，然後退出：

```sh
ditto --norsrc --noextattr extensions/photoframe /Volumes/Kindle/extensions/photoframe
ditto --norsrc --noextattr photoframe /Volumes/Kindle/photoframe
find /Volumes/Kindle/extensions/photoframe /Volumes/Kindle/photoframe -name '._*' -delete
```

4. 退出並拔線。請完全關掉 KUAL 再打開，選單才會換成新版。到 Photo Frame 先按 **Stop photo frame**，再按 **Start photo frame**。程式是從暫存複製執行的，每次更新後都要先 Stop 再 Start 才會生效。

從電腦重新複製 `photoframe/` 會把 `settings.sh` 還原成預設值。

### 選單與使用

目前的選擇前面會有 `*`。間隔、方向、退出方式、點螢幕開關前光、電量顯示、夜間時段都可以在 KUAL 裡改。

**睡眠畫面模式（預設）：** 按 Start 後 Kindle 會睡著，睡眠畫面就是你的照片，到時間自動換一張。想用 Kindle 時按一下電源鍵，立刻回到原本畫面；再睡著，照片就會回來。要完全關掉請按 Stop；重新開機後相框不會自動執行。進入睡眠時會先閃過一下原廠睡眠畫面，約 3 秒後換成照片，這是正常的。睡眠期間會關掉 Wi-Fi，喚醒或按 Stop 再打開。電量低於 8% 且沒充電時，照片會停在目前這張。接上電腦 USB 時不會換圖。

**接管模式：** 輪播時會關掉 Kindle 介面；退出時會重新載入（約 30 秒到 1 分鐘）。充電時若要「點螢幕開關前光」，會使用這個模式。

萬一卡住，長按電源鍵約 20 秒強制重新開機。相框不會在開機時自動執行。

### 電量顯示

預設開啟。每張照片畫好後，右下角會出現小小的電量，例如 `87%`，充電中則是 `87%+`。這一步只用局部刷新，不會整頁閃白。可在選單關掉，設定存在 `settings.sh` 的 `SHOW_BATTERY`。

### 夜間不換照片

預設 23:00–07:00（本地時間）不換圖，並把喚醒鬧鐘設在時段結束，讓 Kindle 整晚睡著。電量過低的保護仍然有效，不會為了等早上而設定喚醒。

Kindle 的時鐘常常是 UTC，紀錄檔的時間可能比台北時間慢約 8 小時。夜間時段不信任裝置時區，而是用 `settings.sh` 裡的 `TZ_OFFSET`（預設 `+8`，也就是台北）。選單不會改這個值，若你在別的時區，請自行修改（例如 `-5`）。

選單預設時段：關閉、22:00–07:00、23:00–07:00、00:00–06:00。時段是「含開始、不含結束」；開始比結束大時會跨過午夜。

### 準備照片

```sh
python3 -m pip install pillow
python3 tools/convert_photos.py --device pw1 --input /照片資料夾 --output ./photoframe
# 或： --device oasis
```

腳本會套用 EXIF 方向、轉灰階、把橫式照片旋轉後依螢幕比例由中心裁切成滿版，並寫出 `images/`、`manifest.csv`、`landscape.txt`。之後若要重算橫式清單：`sh tools/make_orientation_list.sh`。

看橫式照片時，把 Kindle 順時針轉 90 度（向右躺）就是正的。若方向反了，用 `--rotate cw` 再轉一次。

### 萬一出問題

照片不換時，先看電量是不是過低、是否在夜間時段，並查看 Kindle 上的 `photoframe/log.txt`。更新程式後記得先 Stop 再 Start。耗電太快時看 `photoframe/diag.txt`：每次睡眠／喚醒記一行，含真正睡了多久（slept）、醒著多久、電量、前光和喚醒來源。紀錄時間可能是 UTC；夜間時段看的是 `TZ_OFFSET`，不是紀錄檔上的鐘。卡住就長按電源鍵約 20 秒。

### 聲明

越獄 Kindle、安裝第三方軟體和使用這個套件，都必須自行承擔風險。這可能影響保固，操作錯誤也可能讓機器暫時無法正常使用。本專案不提供任何保證，詳見 [LICENSE](LICENSE)。本專案與 Amazon 無關。

### 第三方

本套件是原創程式，以 MIT 授權釋出。實作時參考了（但沒有直接複製原始碼）：

- onlinescreensaver / onlinescreensaverPW2 用連續 `lipc-wait-event -m` 捕捉 `readyToSuspend`、以便設定喚醒鬧鐘的做法
- KOReader 的睡眠／喚醒事件名稱，以及接管模式下停止 Kindle 介面的做法
- NiLuJe 的 FBInk（若裝置上已安裝就會使用，本倉庫不內附）

若你使用這些專案，請遵守它們自己的授權。
