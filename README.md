# reform-debian-packages

The build sources for custom Debian packages which end up at https://mntre.com/reform-debian-repo/

You need to have the following packages installed to run all of this:

curl debhelper debian-archive-keyring debian-keyring devscripts faketime git
mmdebstrap pristine-tar python3 python3-debian python3-jinja2 quilt reprepro
rsync sbuild uidmap

You need to have sbuild set up to build packages (including linux). If you have
never set up sbuild before, the easiest way is to set it up to use unshare
mode like this (assuming you run this on the Reform):

    echo '$chroot_mode = "unshare";' > ~/.sbuildrc
    mkdir -p ~/.cache/sbuild
    mmdebstrap --variant=buildd unstable ~/.cache/sbuild/unstable-arm64.tar

If you are building this on an amd64 box, then you also need to install
binfmt-support, arch-test, qemu-user-static and create the chroots a bit
differently for both amd64 as well as for arm64.

    mmdebstrap --variant=buildd --arch=arm64 unstable ~/.cache/sbuild/unstable-arm64.tar
    mmdebstrap --variant=buildd --arch=amd64 unstable ~/.cache/sbuild/unstable-amd64.tar

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

    sh -xc '. ./setup.sh; cd linux; . ./build.sh'

You can also build the kernel of a specific suite by setting `BASESUITE` to the
suite name like `experimental` in this example:

    sh -xc 'BASESUITE=experimental; . ./setup.sh; cd linux; . ./build.sh'

## bisecting upstream linux

Also refer to:

 - https://kernel-team.pages.debian.net/kernel-handbook/ch-bugs.html#s9.2.1
 - https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation/admin-guide/README.rst
 - https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation/admin-guide/verify-bugs-and-bisect-regressions.rst

 1. apt-get install git gpg gpgv build-essential bc rsync kmod cpio bison flex libelf-dev libssl-dev
 2. git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux-upstream
 3. git checkout vX.Y # check out the good version
 4. cp /boot/config-X.Y .config # best from a kernel close to the version you are building
 5. apply relevant patches
 5. make olddefconfig # use default values for all differing options between existing .config and current git HEAD
 6. yes '' | make localmodconfig # disable all modules that are not currently loaded for faster build time
 7. make KBUILD_IMAGE=arch/arm64/boot/Image bindeb-pkg -j$(nproc) # imx8mq u-boot requires uncompressed image
 8. apt install ../linux-image-X.Y.deb
 9. test the kernel and then, if it's good: `git bisect good` -- optionally: git revert changed files
 10. repeat steps 5 to 9 with the bad version and then `git bisect bad`
 11. repeat until you find the commit that caused the regression
