Name: rsnapshot
Summary: Local and remote filesystem snapshot utility
Version: 1.2.0
Release: 1
BuildArch: noarch
Copyright: GPL
Group: Applications/System
Source: http://www.rsnapshot.org/downloads/rsnapshot-1.2.0.tar.gz
Patch: rsnapshot.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Requires: perl, rsync
AutoReqProv: no

%description
This is a remote backup program that uses rsync to take backup snapshots of filesystems.
It uses hard links to save space on disk.

%prep

%setup 

%patch

%build
./configure \
	--prefix=/usr \
	--bindir=/usr/bin \
	--mandir=/usr/share/man \
	--sysconfdir=/etc \
	--with-perl=/usr/bin/perl \
	--with-rsync=/usr/bin/rsync \
	--with-ssh=/usr/bin/ssh \
	--with-logger=/usr/bin/logger \
	--with-du=/usr/bin/du

%install
install -d $RPM_BUILD_ROOT/%{_bindir}
install -m 755 rsnapshot $RPM_BUILD_ROOT/usr/bin/rsnapshot

install -d $RPM_BUILD_ROOT/%{_mandir}/man1
install -m 644 rsnapshot.1 $RPM_BUILD_ROOT/usr/share/man/man1/

install -d $RPM_BUILD_ROOT/%{_sysconfdir}
install -m 644 rsnapshot.conf.default $RPM_BUILD_ROOT/etc/rsnapshot.conf.default
install -m 600 rsnapshot.conf.default $RPM_BUILD_ROOT/etc/rsnapshot.conf

%post -p /usr/bin/perl

#
# this is a modified version of utils/upgrade_rsnapshot.pl
# it upgrades the user's config file for backwards compatibility
#

$|=1;

use strict;

my $found		= 0;
my $enabled		= 0;
my $new_format	= 0;
my $result;
my $real_file	= '/etc/rsnapshot.conf';
my $backup_file	= '/etc/rsnapshot.conf.backup';	# file to back up original config file to

# file does not exist, it's not an upgrade
if ( ! -e "$real_file" ) {
	exit(0);
}

# make sure we have a file to upgrade
if ( ! -r "$real_file" ) {
	print STDERR "Could not read $real_file for upgrade\n";
	exit(1);
}

# read in original file
$result = open(FILE, "$real_file");
if (!defined($result) or (1 != $result)) {
	print STDERR "Could not open $real_file for reading.\n";
	print STDERR "$real_file has NOT been upgraded!\n";
	exit(1);
}
my @lines = <FILE>;
$result = close(FILE);
if (!defined($result) or (1 != $result)) {
	print STDERR "Could not close $real_file cleanly.\n";
	print STDERR "$real_file has NOT been upgraded!\n";
	exit(1);
}

# see if this is a new version first
foreach my $line (@lines) {
	if ($line =~ m/^#rsync_long_args\s*?\-\-delete\s*?\-\-numeric\-ids\s*?\-\-relative\s*?\-\-delete\-excluded$/o) {
		$found = 1;
		$enabled = 0;
		$new_format = 1;
	}
}

# see if we can find rsync_long_args, but commented out
foreach my $line (@lines) {
	if ($line =~ m/^#rsync_long_args\s*?\-\-delete\s*?\-\-numeric\-ids$/o) {
		$found = 1;
		$enabled = 0;
	}
}

# see if rsync_long_args is present AND enabled
foreach my $line (@lines) {
	if ($line =~ m/^rsync_long_args/o) {
		$found = 1;
		$enabled = 1;
	}
}

# now that we know what we're dealing with, upgrade the file if necessary
if (1 == $new_format) {
	#print "$real_file appears to be in the new format. No changes made.\n";
} elsif (1 == $found) {
	if (1 == $enabled) {
		#print "Found \"rsync_long_args\" uncommented. No changes made.\n";
	} else {
		#print "Found \"rsync_long_args\" commented out. Attempting upgrade...\n";
		backup_config_file();
		write_upgraded_file(1);
	}
} else {
	#print "Could not find old \"rsync_long_args\" parameter. Attempting upgrade...\n";
	backup_config_file();
	write_upgraded_file(0);
}

exit(0);

sub backup_config_file {
	my $result;
	
	print "Backing up $real_file to $backup_file\n";
	
	if ( -e "$backup_file" ) {
		print STDERR "Refusing to overwrite $backup_file.\n";
		print STDERR "Please move or delete $backup_file and try again.\n";
		print STDERR "$real_file has NOT been upgraded!\n";
		exit(1);
	}
	
	$result = open(OUTFILE, "> $backup_file");
	if (!defined($result) or ($result != 1)) {
		print STDERR "Error opening $backup_file for writing.\n";
		print STDERR "$real_file has NOT been upgraded!\n";
		exit(1);
	}
	foreach my $line (@lines) {
		print OUTFILE $line;
	}
	$result = close(OUTFILE);
	if (!defined($result) or (1 != $result)) {
		print STDERR "could not cleanly close $backup_file.\n";
		print STDERR "$real_file has NOT been upgraded!\n";
		exit(1);
	}
	
	#print "$real_file was backed up to $backup_file\n";
}

sub write_upgraded_file {
	my $scan_file = shift(@_);
	my $result;
	
	my $upgrade_message = '';
	
	my $rsync_long_args_compat = "rsync_long_args\t--delete --numeric-ids\n";
	
	$upgrade_message .= "#-----------------------------------------------------------------------------\n";
	$upgrade_message .= "# UPGRADE NOTICE:\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# The \"rsync_long_args\" parameter was added or upgraded automatically\n";
	$upgrade_message .= "# during a software upgrade.\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# In previous versions of rsnapshot, the default arguments for rsync_long_args\n";
	$upgrade_message .= "# were:\n";
	$upgrade_message .= "#   \"--delete --numeric-ids\"\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# The new defaults are:\n";
	$upgrade_message .= "#   \"--delete --numeric-ids --relative --delete-excluded\"\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# The upgrade program added an explicit entry below with the old values, which\n";
	$upgrade_message .= "# preserves the same behaviour from previous versions of rsnapshot.\n";
	$upgrade_message .= "# If you were happy with the way things were working before, you don't need\n";
	$upgrade_message .= "# to change anything. You're all done!\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# If for some reason you plan on downgrading to an earlier version of\n";
	$upgrade_message .= "# rsnapshot, the old config file was saved as \"$backup_file\"\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# Do NOT simply copy the old file back here and run the new version of\n";
	$upgrade_message .= "# rsnapshot against it. Strange things will happen, and you won't like the\n";
	$upgrade_message .= "# results!\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# Users are encouraged to upgrade to the newer settings if possible. By doing\n";
	$upgrade_message .= "# so, you will get some additional flexibility with include/exclude rules, as\n";
	$upgrade_message .= "# well as several bug fixes. However, THIS CHANGE BREAKS BACKWARDS\n";
	$upgrade_message .= "# COMPATIBILITY, so MAKE SURE YOU KNOW WHAT YOU'RE DOING before you change\n";
	$upgrade_message .= "# this setting!!!\n";
	$upgrade_message .= "#\n";
	$upgrade_message .= "# See the INSTALL file that came with the program, or visit\n";
	$upgrade_message .= "# http://www.rsnapshot.org for more information.\n";
	$upgrade_message .= "#-----------------------------------------------------------------------------\n";
	$upgrade_message .= "\n";
	
	if (!defined($scan_file)) {
		print STDERR "write_upgraded_file() needs a value. exiting.\n";
		exit(1);
	}
	
	#print "Opening $real_file for writing...\n";
	$result = open(OUTFILE, "> $real_file");
	if (!defined($result) or (1 != $result)) {
		print STDERR "Could not open $real_file for writing.\n";
		print STDERR "$real_file has NOT been upgraded!\n";
		exit(1);
	}
	
	# scan the file to uncomment rsync_long_args
	if (1 == $scan_file) {
		print OUTFILE $upgrade_message;
		
		foreach my $line (@lines) {
			if ($line =~ m/^#rsync_long_args\s*?\-\-delete\s*?\-\-numeric\-ids$/o) {
				print OUTFILE $rsync_long_args_compat;
			} else {
				print OUTFILE $line;
			}
		}
		
	# rsync_long_args isn't here, just add it to the top
	} else {
		print OUTFILE $upgrade_message;
		print OUTFILE $rsync_long_args_compat;
		print OUTFILE "\n";
		
		foreach my $line (@lines) {
			print OUTFILE $line;
		}
	}
	
	$result = close(OUTFILE);
	if (!defined($result) or (1 != $result)) {
		print STDERR "Could not cleanly close $real_file after writing.\n";
		print STDERR "Please compare $real_file and $backup_file\n.";
		print STDERR "$real_file MAY have been upgraded(?)\n";
		exit(1);
	}
	
	print "$real_file upgraded successfully.\n";
}



%clean
rm -rf $RPM_BUILD_ROOT
rm -rf $RPM_BUILD_DIR/%{name}-%{version}/

%files
%defattr(-,root,root)
%verify(user group mode md5 size mtime) %doc AUTHORS COPYING ChangeLog README INSTALL TODO
%verify(user group mode md5 size mtime) %config %{_sysconfdir}/rsnapshot.conf.default
%verify(user group mode) %config(noreplace) %{_sysconfdir}/rsnapshot.conf
%verify(user group mode md5 size mtime) %{_bindir}/rsnapshot
%verify(user group mode md5 size mtime) %{_mandir}/man1/rsnapshot.1*

%changelog
* Sun Jan 23 2005 Nathan Rosenquist <nathan@rsnapshot.org>
- Added perl upgrade script, modified from utils/upgrade_rsnapshot.pl

* Sat Jan 22 2005 Nathan Rosenquist <nathan@rsnapshot.org>
- Added --with-du option

* Thu Jan 15 2004 Nathan Rosenquist <nathan@rsnapshot.org>
- Added "AutoReqProv: no" for SuSE compatibility

* Fri Dec 26 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- Added util-linux dependency, and --with-logger= option

* Fri Dec 19 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- now fully support autoconf

* Tue Dec 16 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- changed rsnapshot.conf to rsnapshot.conf.default from the source tree

* Wed Nov 05 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- Removed fileutils dependency, added verification info

* Tue Nov 04 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- fixed anonymous rsync error

* Thu Oct 30 2003 Nathan Rosenquist <nathan@rsnapshot.org>
- update to 1.0.3

* Tue Oct 28 2003 Carl Wilhelm Soderstrom <chrome@real-time.com>
- created spec file
