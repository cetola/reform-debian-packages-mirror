#!/bin/bash

# This switch in WM8960 needs to be on for the headset mic input to work
amixer -c 0 sset 'Left Input Mixer Boost' on

# Enable wakeup from suspend on all UARTs
echo enabled > /sys/devices/platform/soc@0/30800000.bus/30860000.serial/tty/ttymxc0/power/wakeup
echo enabled > /sys/devices/platform/soc@0/30800000.bus/30890000.serial/tty/ttymxc1/power/wakeup
echo enabled > /sys/devices/platform/soc@0/30800000.bus/30880000.serial/tty/ttymxc2/power/wakeup
