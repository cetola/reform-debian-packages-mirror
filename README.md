# reform-debian-packages

The build sources for custom Debian packages which end up at https://mntre.com/reform-debian-repo/

To run all the scripts in this repository, the following apt-get command will
install all required dependencies (on Trixie) for you:

    sudo apt --no-install-recommends install curl \
        debhelper debian-archive-keyring debian-keyring devscripts dh-python \
        faketime git kernel-wedge mmdebstrap pristine-tar python3 \
        python3-dacite python3-debian python3-jinja2 quilt reprepro rsync \
        sbuild uidmap unzip

If you are building this on an amd64 box, then you also need to install
binfmt-support, arch-test and qemu-user-static.

You need to have sbuild set up to build packages (including linux). If you have
never set up sbuild before, the easiest way is to set it up to use unshare
mode like this (assuming you run this on the Reform):

    mkdir -p ~/.config/sbuild
    cat << 'END' > ~/.config/sbuild/config.pl
    $chroot_mode = "unshare";
    $unshare_mmdebstrap_keep_tarball = 1;
    $chroot_aliases->{reform} = 'unstable';
    push @{$unshare_mmdebstrap_distro_mangle}, qr/^reform$/, 'unstable';
    1;
    END

# linux

> [!tip]
> Building the kernel will require >8GB free space on your temp directory. Please check before starting the build, especially if you are use a `tmpfs` backed `/tmp`.  
> You may use an alternate temp directory by setting the environment variable `TMPDIR`, e.g. `export TMPDIR=/var/tmp`

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

 1. apt-get install git gpg gpgv build-essential bc rsync kmod cpio bison flex libelf-dev libssl-dev debhelper libdw-dev
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
