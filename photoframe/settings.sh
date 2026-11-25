# Photo Frame settings (busybox ash). Edit with a plain-text editor, keep LF line endings.
# The KUAL menu (Photo Frame) changes these for you.

# Minutes between photos. The photo changes on the clock tick (e.g. :00 :15 :30 :45).
INTERVAL_MIN=15

# Which photos to show: all | portrait (vertical) | landscape (horizontal photos, rotated 90 degrees).
# The list of rotated photos is photoframe/landscape.txt (made from manifest.csv on the Mac).
ORIENTATION=all

# How the photo frame runs:
#   sleep    = sleep-screen mode (default). The normal Kindle UI keeps running underneath;
#              the photo is drawn on the Kindle's sleep screen and changed by the RTC alarm.
#              One press of the power button returns to the Kindle immediately.
#   takeover = stops the Kindle UI while showing photos. Exiting restarts the UI (slow, looks like a reboot).
#              Used automatically if sleep-screen mode cannot start.
FRAME_MODE=sleep

# 1 = while the Kindle is charging, stay awake and let a tap on the screen switch the front light on/off.
#     This needs takeover mode (only while charging); when unplugged it goes back to sleeping between photos.
# 0 = off (always sleep between photos, lowest power).
TAP_LIGHT=0
# Front light level a tap turns on (1-24). 0 = the level used before the slideshow started (or 12).
TAP_LIGHT_LEVEL=0
# Touch input device for TAP_LIGHT. Empty = auto-detect (PW1: zforce touch panel, usually /dev/input/event0 or event1).
TOUCH_DEV=

# Takeover mode only: stop and return to the Kindle UI when battery <= this % and not charging.
# Sleep-screen mode: below this % the photo stops changing (the Kindle just sleeps) to save the battery.
LOW_BATTERY=8
# Takeover mode: 1 = switch the front light off while the slideshow runs (restored on exit). 0 = leave it.
FRONTLIGHT_OFF=1
# Sleep-screen mode: front light level kept while the frame runs: 0 = off (default), 1-24 = that level,
# -1 = do not touch the light. The level you had before is restored when you press Stop.
FRONTLIGHT_LEVEL=0
# Sleep-screen mode: 1 = switch the cover/magnet (hall) sensor off while the frame runs so a magnet or
# case cannot wake the Kindle (restored on Stop). Only if the Kindle has such a sensor (Oasis). 0 = leave it.
HALL_OFF=1
# Sleep-screen mode: seconds to wait for the Kindle to draw its own sleep screen before drawing the photo over it.
SS_DELAY=3

# 1 = draw a small battery percentage in the bottom-right corner after each photo (e.g. 87% or 87%+ if charging).
# 0 = off. The KUAL menu (Battery display) changes this.
SHOW_BATTERY=1

# Quiet hours: do not change photos in this local-time window; the current photo stays until the window ends.
# 1 = on (default), 0 = off. The KUAL menu (Quiet hours) has Off and the presets 22-07, 23-07, 00-06.
QUIET_HOURS=1
# Start and end hours in local time, 0-23. The window is [START, END) and wraps midnight when START > END.
QUIET_START=23
QUIET_END=7
# Hours to add to the Kindle clock to get local time. Kindle clocks are often UTC; +8 is Asia/Taipei.
# Accepts 8, +8, or a negative offset such as -5. The menu does not change this; edit it here if needed.
TZ_OFFSET=+8
