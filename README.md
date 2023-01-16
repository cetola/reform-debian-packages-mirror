# reform-debian-packages

The build sources for custom Debian packages which end up at https://mntre.com/reform-debian

We currently are building the following packages:

## ffmpeg

With the patches from [1] for hardware accelerated video playback:

[1] https://community.mnt.re/t/notes-on-building-ffmpeg-and-mpv-to-use-the-hardware-h-264-decoder/305

## flash-kernel

With a new entry for the reform to its database so that it can create u-boot compatible images.

## fontcontig

Making its installation reproducible: https://bugs.debian.org/864082

## xwayland

Adding a patch calling glFinish()

## blender

Compiling an old blender version because everything after 2.79b requires opengles 3.2.

## linux

A patched 5.12 kernel until the patches are rebased onto newer versions or upstreamed.

## neatvnc and wayvnc

Both packages are still waiting in the Debian NEW queue:
https://ftp-master.debian.org/new/neatvnc_0.4.0+dfsg-1.html
https://ftp-master.debian.org/new/wayvnc_0.4.1-1.html

## reform-tools

Scripts for running the reform.

# linux

To just rebuild the kernel and not the rest, you can run this:

    chdist --data-dir=./chdist apt-get base update
    env --chdir=./linux BUILD_ARCH=arm64 HOST_ARCH=arm64 BASESUITE=unstable OURSUITE=reform ./build.sh
