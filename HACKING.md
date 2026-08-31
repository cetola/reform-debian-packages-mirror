Rebasing Linux
--------------

The MNT patches to the Linux kernel used to be shipped as diffs, mbx files or
git-format-patch files in versioned subdirectories of the `./linux` directory.
The `./linux/build.sh` script requires changes as patch files because it uses
the Debian kernel-team packaging and Debian packages are patched using
quilt-compatible patch stacks in `./debian/patches`.

Since Linux 7.2, the aforementioned method got abandoned in favour of
generating the required patch files from a linux-stable git repository branch
containing the MNT specific commits between the last stable git tag and the tip
of the branch. Branches are named mnt-vX.Y.Z where X.Y.Z is the last stable
kernel version and the right branch will get picked automatically by
`./linux/build.sh` based on the Debian kernel package version. To force
building from a different branch, set the LINUX_BRANCH environment variable.

The linux-stable tree lives in https://source.mnt.re/josch/linux and rebasing
the patch stack onto a new linux stable tag is done with `git rebase --onto`.
Original situation:

    o---o---o---o---o  v7.1.7
         \
          o---o---o---o---o  v6.19.6
                           \
                            o---o---o  mnt-v6.19.6

In this example, a new kernel stable version `v7.1.7` got tagged and we
want to rebase our patch stack in the branch `mnt-v6.19.6` on top of it.
The patch stack are the commits between tag `v6.19.6` and the tip of
branch `mnt-v6.19.6`.

We start with creating a duplicate of the feature branch `mnt-v6.19.6`
with the correct new naming:

    $ git switch mnt-v6.19.6
    $ git switch --create mnt-v7.1.7

We can then rebase the changes between `v6.19.6` and `mnt-v6.19.6` onto
`v7.1.7` using this the following command. Note, that we used
`mnt-v7.1.7` instead of `mnt-v6.19.6` here. Both branches contain
equivalent content (for now) but `git rebase` will use the name of the
last argument as the name of the ref to update and we want to leave the
branch `mnt-v6.19.6` untouched.

    $ git rebase --onto v7.1.7 v6.19.6 mnt-v7.1.7

The new situation is:

    o---o---o---o---o  v7.1.7
         \           \
          \           o---o---o  mnt-v7.1.7
           \
            o---o---o---o---o  v6.19.6
                             \
                              o---o---o  mnt-v6.19.6
