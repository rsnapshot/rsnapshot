# INSTALLATION

rsnapshot is a filesystem snapshot utility. It uses rsync to take
snapshots of local and remote filesystems for any number of machines,
and then rotates the snapshots according to your rsnapshot.conf.

rsnapshot comes with ABSOLUTELY NO WARRANTY.  This is free software,
and you are welcome to redistribute it under certain conditions.
See the GNU General Public Licence for details.

## QUICK START

If you are installing for the first time (and just want the defaults):

 * Run these commands for a quick installation from source code:
    (skip these commands if you have installed rpm or debian package)

        $ ./autogen.sh # Generates the configure script.
        $ ./configure --sysconfdir=/etc
        $ sudo make install
        $ sudo cp /etc/rsnapshot.conf.default /etc/rsnapshot.conf

 * Open up /etc/rsnapshot.conf with a text editor, and modify it for your system.

 * Make sure the config file syntax is valid (remember, tabs, not spaces):

        $ /usr/local/bin/rsnapshot configtest

The rsnapshot man page installed with this software covers setup and all configuration
options in detail. The [rsnapshot HOWTO](docs/HOWTOs/rsnapshot-HOWTO.en.html) may also be
useful reading for first time setups.

## UPGRADING

If you are upgrading from a previous installation of rsnapshot 1.1.x,
please read the file: `docs/Upgrading_from_1.1`

There are no special instructions for upgrading from rsnapshot 1.2.x to
1.3.x, since both use `config_version 1.2`.

If you are not sure whether you need to do anything to upgrade your
old rsnapshot.conf, you can run

        $ make upgrade

or

        $ rsnapshot upgrade-config-file

or

        $ rsnapshot -c /etc/rsnapshot.conf upgrade-config-file

## ADDITIONAL OPTIONS

If you require more precise control over the locations of files:

You can pass the following options to ./configure for more control
over where various parts of rsnapshot are installed. The example
values shown also happen to be the defaults.

 * --prefix=/usr/local

    This will install everything under /usr/local

 * --sysconfdir=/usr/local/etc

    This will install the example config file
    (rsnapshot.conf.default) under /usr/local/etc. This will also be
    the default directory where rsnapshot looks for its config file.
    It is recommended that you copy rsnapshot.conf.default and use it
    as a basis for the actual config file (rsnapshot.conf).

 * --bindir=/usr/local/bin

    This will install the rsnapshot program under /usr/local/bin

 * --mandir=/usr/local/man

    This will install the man page under /usr/local/man

 * --with-perl=/usr/bin/perl

    Specify your preferred path to perl. If you don't specify
    this, the build process will detect the first version of perl
    it finds in your path.

 * --with-rsync=/usr/bin/rsync

    Specify your preferred path to rsync. If you don't specify
    this, the build process will detect the first version of rsync
    it finds in your path. You can always change this later by
    editing the config file (rsnapshot.conf).

 * --with-cp=/bin/cp

    Specify the path to GNU cp. The traditional UNIX cp command
    is not sufficient. If you don't specify this, the build process
    will detect the first version of cp it finds in your path.
    If you don't have the GNU version of cp, leave this commented
    out in the config file (rsnapshot.conf).

 * --with-rm=/bin/rm

    Specify the path to the rm command. If you don't specify this,
    the build process will detect the first version of rm it finds
    in your path.

 * --with-ssh=/usr/bin/ssh

    Specify your preferred path to ssh. If you don't specify this,
    the build process will detect the first version of ssh it
    finds in your path. SSH is an optional feature, so it is OK if
    it isn't on your system. Either way, if you want to use ssh,
    you need to specifically enable this feature by uncommenting
    the "cmd_ssh" parameter in the config file (rsnapshot.conf).

 * --with-logger=/usr/bin/logger

    Specify your preferred path to logger. If you don't specify
    this, the build process will detect the first version of
    logger it finds in your path. If you want syslog support,
    make sure this is enabled in the config file. Syslog support
    is optional, so if you don't have it or comment it out it's OK.

 * --with-du=/usr/bin/du

    Specify your preferred path to du. If you don't specify
    this, the build process will detect the first version of
    du it finds in your path. The "du" command only gets used
    when rsnapshot is called with the "du" argument to calculate
    the amount of disk space used. This is optional, so if you
    don't have it or comment it out it's OK.
