#!/usr/bin/perl -w

########################################################################
#                                                                      #
# rsnapshot                                                            #
# by Nathan Rosenquist                                                 #
# now maintained by David Cantrell                                     #
#                                                                      #
# The official rsnapshot website is located at                         #
# http://www.rsnapshot.org/                                            #
#                                                                      #
# Copyright (C) 2003-2005 Nathan Rosenquist                            #
#                                                                      #
# Portions Copyright (C) 2002-2006 Mike Rubel, Carl Wilhelm Soderstrom,#
# Ted Zlatanov, Carl Boe, Shane Liebling, Bharat Mediratta,            #
# Peter Palfrader, Nicolas Kaiser, David Cantrell, Chris Petersen,     #
# Robert Jackson, Justin Grote, David Keegel, Alan Batie               #
#                                                                      #
# rsnapshot comes with ABSOLUTELY NO WARRANTY.  This is free software, #
# and you may copy, distribute and/or modify it under the terms of     #
# the GNU GPL (version 2 or at your option any later version).         #
# See the GNU General Public License (in file: COPYING) for details.   #
#                                                                      #
# Based on code originally by Mike Rubel                               #
# http://www.mikerubel.org/computers/rsync_snapshots/                  #
#                                                                      #
########################################################################

# $Id: rsnapshot-program.pl,v 1.359 2006/10/21 06:09:50 djk20 Exp $

# tabstops are set to 4 spaces
# in vi, do: set ts=4 sw=4

########################################
###         STANDARD MODULES         ###
########################################

require 5.004;
use strict;
use DirHandle;			# DirHandle()
use Cwd;				# cwd()
use Getopt::Std;		# getopts()
use File::Path;			# mkpath(), rmtree()
use File::stat;			# stat(), lstat()
use POSIX qw(locale_h);	# setlocale()
use Fcntl;				# sysopen()
use IO::File;			# recursive open in parse_config_file

########################################
###           CPAN MODULES           ###
########################################

# keep track of whether we have access to the Lchown module
my $have_lchown = 0;

# use_lchown() is called later, so we can log the results

########################################
###     DECLARE GLOBAL VARIABLES     ###
########################################

# turn off buffering
$| = 1;

# version of rsnapshot
my $VERSION = '1.3.0';

# command or interval to execute (first cmd line arg)
my $cmd;

# default configuration file
my $config_file;

# hash to hold variables from the configuration file
my %config_vars;

# array of hash_refs containing the destination backup point
# and either a source dir or a script to run
my @backup_points;

# array of backup points to rollback, in the event of failure
my @rollback_points;

# "intervals" are user defined time periods (e.g., hourly, daily)
# this array holds hash_refs containing the name of the interval,
# and the number of snapshots to keep of it
my @intervals;

# store interval data (mostly info about which one we're on, what was before, etc.)
# this is a convenient reference to some of the data from and metadata about @intervals
my $interval_data_ref;

# intervals can't have these values, because they're either taken by other commands
# or reserved for future use
my @reserved_words = qw(
	archive
	check-config-version
	configtest
	diff
	delete
	du
	get-latest-snapshot
	help
	history
	list
	restore
	rollback
	sync
	upgrade-config-file
	version
	version-only
);

# global flags that change the outcome of the program,
# and are configurable by both cmd line and config flags
#
my $test			= 0; # turn verbose on, but don't execute any filesystem commands
my $do_configtest	= 0; # parse config file and exit
my $one_fs			= 0; # one file system (don't cross partitions within a backup point)
my $link_dest		= 0; # use the --link-dest option to rsync

# how much noise should we make? the default is 2
#
# please note that direct rsync output does not get written to the log file, only to STDOUT
# this is because we're not intercepting STDOUT while rsync runs
#
#	0	Absolutely quiet (reserved, but not implemented)
#	1	Don't display warnings about FIFOs and special files
#	2	Default (errors only)
#	3	Verbose (show shell commands and equivalents)
#	4	Extra verbose messages (individual actions inside some subroutines, output from rsync)
#	5	Debug
#
# define verbose and loglevel
my $verbose		= undef;
my $loglevel	= undef;

# set defaults for verbose and loglevel
my $default_verbose		= 2;
my $default_loglevel	= 3;

# assume the config file is valid until we find an error
my $config_perfect = 1;

# exit code for rsnapshot
my $exit_code = 0;

# global defaults for external programs
my $default_rsync_short_args	= '-a';
my $default_rsync_long_args		= '--delete --numeric-ids --relative --delete-excluded';
my $default_ssh_args			= undef;
my $default_du_args				= '-csh';

# set default for use_lazy_deletes
my $use_lazy_deletes = 0;	# do not delete the oldest archive until after backup

# exactly how the program was called, with all arguments
# this is set before getopts() modifies @ARGV
my $run_string = "$0 " . join(' ', @ARGV);

# if we have any errors, we print the run string once, at the top of the list
my $have_printed_run_string = 0;
	
# pre-buffer the include/exclude parameter flags
# local to parse_config_file and validate_config_file
my $rsync_include_args		= undef;
my $rsync_include_file_args	= undef;

########################################
###         SIGNAL HANDLERS          ###
########################################

# shut down gracefully if necessary
$SIG{'HUP'}		= 'IGNORE';
$SIG{'INT'}		= sub { bail('rsnapshot was sent INT signal... cleaning up');  };
$SIG{'QUIT'}	= sub { bail('rsnapshot was sent QUIT signal... cleaning up'); };
$SIG{'ABRT'}	= sub { bail('rsnapshot was sent ABRT signal... cleaning up'); };
$SIG{'TERM'}	= sub { bail('rsnapshot was sent TERM signal... cleaning up'); };

########################################
###      CORE PROGRAM STRUCTURE      ###
########################################

# what follows is a linear sequence of events.
# all of these subroutines will either succeed or terminate the program safely.

# figure out the path to the default config file (with autoconf we have to check)
# this sets $config_file to the full config file path
find_config_file();

# parse command line options
# (this can override $config_file, if the -c flag is used on the command line)
parse_cmd_line_opts();

# if we need to run a command that doesn't require fully parsing the config file, do it now (and exit)
if (!defined($cmd) or ((! $cmd) && ('0' ne $cmd))) {
	show_usage();
} elsif ($cmd eq 'help') {
	show_help();
} elsif ($cmd eq 'version') {
	show_version();
} elsif ($cmd eq 'version-only') {
	show_version_only();
} elsif ($cmd eq 'check-config-version') {
	check_config_version();
} elsif ($cmd eq 'upgrade-config-file') {
	upgrade_config_file();
}

# if we're just doing a configtest, set that flag
if ($cmd eq 'configtest') {
	$do_configtest = 1;
}

# parse config file (if it exists)
if (defined($config_file) && (-f "$config_file") && (-r "$config_file")) {
	# if there is a problem, this subroutine will exit the program and notify the user of the error
	parse_config_file();
	validate_config_file();
	
# no config file found
} else {
	# warn user and exit the program
	exit_no_config_file();
}

# attempt to load the Lchown module: http://search.cpan.org/dist/Lchown/
use_lchown();

# if we're just doing a configtest, exit here with the results
if (1 == $do_configtest) {
	exit_configtest();
}

# if we're just using "du" or "rsnapshot-diff" to check the disk space, do it now (and exit)
# these commands are down here because they needs to know the contents of the config file
if ($cmd eq 'du') {
	show_disk_usage();
} elsif ($cmd eq 'diff') {
	show_rsnapshot_diff();
} elsif ($cmd eq 'get-latest-snapshot') {
	show_latest_snapshot();
}

#
# IF WE GOT THIS FAR, PREPARE TO RUN A BACKUP
#

# log the beginning of this run
log_startup();

# this is reported to fix some semi-obscure problems with rmtree()
set_posix_locale();

# if we're using a lockfile, try to add it
# (the program will bail if one exists and it's not stale)
add_lockfile();

# create snapshot_root if it doesn't exist (and no_create_root != 1)
create_snapshot_root();

# actually run the backup job
# $cmd should store the name of the interval we'll run against
handle_interval( $cmd );

# if we have a lockfile, remove it
remove_lockfile();

# if we got this far, the program is done running
# write to the log and syslog with the status of the outcome
#
exit_with_status();

########################################
###           SUBROUTINES            ###
########################################

# concise usage information
# runs when rsnapshot is called with no arguments
# exits with an error condition
sub show_usage {
	print<<HERE;
rsnapshot $VERSION
Usage: rsnapshot [-vtxqVD] [-c cfgfile] [command] [args]
Type \"rsnapshot help\" or \"man rsnapshot\" for more information.
HERE
	
	exit(1);
}

# extended usage information
# runs when rsnapshot is called with "help" as an argument
# exits 0
sub show_help {
	print<<HERE;
rsnapshot $VERSION
Usage: rsnapshot [-vtxqVD] [-c cfgfile] [command] [args]
Type "man rsnapshot" for more information.

rsnapshot is a filesystem snapshot utility. It can take incremental
snapshots of local and remote filesystems for any number of machines.

rsnapshot comes with ABSOLUTELY NO WARRANTY.  This is free software,
and you are welcome to redistribute it under certain conditions.
See the GNU General Public License for details.

Options:
    -v verbose       - Show equivalent shell commands being executed.
    -t test          - Show verbose output, but don't touch anything.
    -c [file]        - Specify alternate config file (-c /path/to/file)
                       This will be similar, but not always exactly the same
                       as the real output from a live run.
    -q quiet         - Suppress non-fatal warnings.
    -V extra verbose - The same as -v, but with more detail.
    -D debug         - A firehose of diagnostic information.
    -x one_fs        - Don't cross filesystems (same as -x option to rsync).

Commands:
    [interval]       - An interval as defined in rsnapshot.conf.
    configtest       - Syntax check the config file.
    sync [dest]      - Sync files, without rotating. "sync_first" must be
                       enabled for this to work. If a full backup point
                       destination is given as an optional argument, only
                       those files will be synced.
    diff             - Front-end interface to the rsnapshot-diff program.
                       Accepts two optional arguments which can be either
                       filesystem paths or interval directories within the
                       snapshot_root (e.g., /etc/ daily.0/etc/). The default
                       is to compare the two most recent snapshots.
    du               - Show disk usage in the snapshot_root.
                       Accepts an optional destination path for comparison
                       across snapshots (e.g., localhost/home/user/foo).
    version          - Show the version number for rsnapshot.
    help             - Show this help message.
HERE
	
	exit(0);
}

# prints out the name and version
# exits 0
sub show_version {
	print "rsnapshot $VERSION\n";
	exit(0);
}

# prints only the version number
# this is "undocumented", just for use with some of the makefile targets
# exits 0
sub show_version_only {
	print "$VERSION\n";
	exit(0);
}

# accepts no arguments
# sets the $config_file global variable
#
# this program works both "as-is" in the source tree, and when it has been parsed by autoconf for installation
# the variables with "@" symbols on both sides get replaced during ./configure
# this subroutine returns the correct path to the default config file
#
sub find_config_file {
	# autoconf variables (may have too many slashes)
	my $autoconf_sysconfdir	= '@sysconfdir@';
	my $autoconf_prefix		= '@prefix@';
	my $default_config_file	= '/etc/rsnapshot.conf';
	
	# consolidate multiple slashes
	$autoconf_sysconfdir	=~ s/\/+/\//g;
	$autoconf_prefix		=~ s/\/+/\//g;
	
	# remove trailing slashes
	$autoconf_sysconfdir	=~ s/\/$//g;
	$autoconf_prefix		=~ s/\/$//g;
	
	# if --sysconfdir was not set explicitly during ./configure, but we did use autoconf
	if ($autoconf_sysconfdir eq '${prefix}/etc') {
		$default_config_file = "$autoconf_prefix/etc/rsnapshot.conf";
		
	# if --sysconfdir was set explicitly at ./configure, overriding the --prefix setting
	} elsif ($autoconf_sysconfdir ne ('@' . 'sysconfdir' . '@')) {
		$default_config_file = "$autoconf_sysconfdir/rsnapshot.conf";
	}
	
	# set global variable
	$config_file = $default_config_file;
}

# accepts no args
# returns no args
# sets some global flag variables
# exits the program with an error if we were passed invalid options
sub parse_cmd_line_opts {
	my %opts;
	my $result;
	
	# get command line options
	$result = getopts('vtxqVDc:', \%opts);
	
	#
	# validate command line args
	#
	
	# make sure config file is a file
	if (defined($opts{'c'})) {
		if ( ! -r "$opts{'c'}" ) {
			print STDERR "File not found: $opts{'c'}\n";
			$result = undef;
		}
	}
	
	# die if we don't understand all the flags
	if (!defined($result) or (1 != $result)) {
		# At this point, getopts() or our @ARGV check will have printed out "Unknown option: -X"
		print STDERR "Type \"rsnapshot help\" or \"man rsnapshot\" for more information.\n";
		exit(1);
	}
	
	#
	# with that out of the way, we can go about the business of setting global variables
	#
	
	# set command
	$cmd = $ARGV[0];
	
	# check for extra bogus arguments that getopts() didn't catch
	if (defined($cmd) && ('du' ne $cmd) && ('diff' ne $cmd) && ('sync' ne $cmd)) {
		if (scalar(@ARGV) > 1) {
			for (my $i=1; $i<scalar(@ARGV); $i++) {
				print STDERR "Unknown option: $ARGV[$i]\n";
				print STDERR "Please make sure all switches come before commands\n";
				print STDERR "(e.g., 'rsnapshot -v hourly', not 'rsnapshot hourly -v')\n";
				exit(1);
			}
			
			$result = undef;
		}
	}
	
	# alternate config file?
	if (defined($opts{'c'})) {
		$config_file = $opts{'c'};
	}
	
	# test? (just show what WOULD be done)
	if (defined($opts{'t'})) {
		$test = 1;
		$verbose = 3;
	}
	
	# quiet?
	if (defined($opts{'q'}))	{ $verbose = 1; }
	
	# verbose (or extra verbose)?
	if (defined($opts{'v'}))	{ $verbose = 3; }
	if (defined($opts{'V'}))	{ $verbose = 4; }
	
	# debug
	if (defined($opts{'D'}))	{ $verbose = 5; }
	
	# one file system? (don't span partitions with rsync)
	if (defined($opts{'x'}))	{ $one_fs = 1; }
}

# accepts an optional argument - no arg means to parse the default file,
#   if an arg is present parse that file instead
# returns no value
# this subroutine parses the config file (rsnapshot.conf)
#
sub parse_config_file {
	# count the lines in the config file, so the user can pinpoint errors more precisely
	my $file_line_num = 0;
	
	# open the config file
	my $config_file = shift() || $config_file;
	my $CONFIG = IO::File->new($config_file)
		or bail("Could not open config file \"$config_file\"\nAre you sure you have permission?");
	
	# read it line by line
	while (my $line = <$CONFIG>) {
		chomp($line);
		
		# count line numbers
		$file_line_num++;
		
		# assume the line is formatted incorrectly
		my $line_syntax_ok = 0;
		
		# ignore comments
		if (is_comment($line)) { next; }
		
		# ignore blank lines
		if (is_blank($line)) { next; }
		
		# parse line
		my ($var, $value, $value2, $value3) = split(/\t+/, $line, 4);
		
		# warn about entries we don't understand, and immediately prevent the
		# program from running or parsing anything else
		if (!defined($var)) {
			config_err($file_line_num, "$line - could not find a first word on this line");
			next;
		}
		if (!defined($value) && $var eq $line) {
			# No tabs found in $line.
			if ($line =~ /\s/) {
				# User put spaces in config line instead of tabs.
				config_err($file_line_num, "$line - missing tabs to separate words - change spaces to tabs.");
				next;
			} else {
				# User put only one word
				config_err($file_line_num, "$line - could not find second word on this line");
				next;
			}
		}
		
		# INCLUDEs
		if($var eq 'include_conf') {
			if(defined($value) && -f $value && -r $value) {
				$line_syntax_ok = 1;
				parse_config_file($value);
			} else {
				config_err($file_line_num, "$line - can't find or read file '$value'");
				next;
			}
		}

		# CONFIG_VERSION
		if ($var eq 'config_version') {
			if (defined($value)) {
				# right now 1.2 is the only possible value
				if ('1.2' eq $value) {
					$config_vars{'config_version'} = $value;
					$line_syntax_ok = 1;
					next;
				} else {
					config_err($file_line_num, "$line - config_version not recognized!");
					next;
				}
			} else {
				config_err($file_line_num, "$line - config_version not defined!");
				next;
			}
		}
		
		# SNAPSHOT_ROOT
		if ($var eq 'snapshot_root') {
			# make sure this is a full path
			if (0 == is_valid_local_abs_path($value)) {
				if (is_ssh_path($value) || is_anon_rsync_path($value) || is_cwrsync_path($value)) {
					config_err($file_line_num, "$line - snapshot_root must be a local path - you cannot have a remote snapshot_root");
				} else {
					config_err($file_line_num, "$line - snapshot_root must be a full path");
				}
				next;
			# if the snapshot root already exists:
			} elsif ( -e "$value" ) {
				# if path exists already, make sure it's a directory
				if ((-e "$value") && (! -d "$value")) {
					config_err($file_line_num, "$line - snapshot_root must be a directory");
					next;
				}
				# make sure it's readable
				if ( ! -r "$value" ) {
					config_err($file_line_num, "$line - snapshot_root exists but is not readable");
					next;
				}
				# make sure it's writable
				if ( ! -w "$value" ) {
					config_err($file_line_num, "$line - snapshot_root exists but is not writable");
					next;
				}
			}
			
			# remove the trailing slash(es) if present
			$value = remove_trailing_slash($value);
			
			$config_vars{'snapshot_root'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		
		# SYNC_FIRST
		# if this is enabled, rsnapshot syncs data to a staging directory with the "rsnapshot sync" command,
		# and all "interval" runs will simply rotate files. this changes the behaviour of the lowest interval.
		# when a sync occurs, no directories are rotated. the sync directory is kind of like a staging area for data transfers.
		# the files in the sync directory will be hard linked with the others in the other snapshot directories.
		# the sync directory lives at: /<snapshot_root>/.sync/
		#
		if ($var eq 'sync_first') {
			if (defined($value)) {
				if ('1' eq $value) {
					$config_vars{'sync_first'} = 1;
					$line_syntax_ok = 1;
					next;
				} elsif ('0' eq $value) {
					$config_vars{'sync_first'} = 0;
					$line_syntax_ok = 1;
					next;
				} else {
					config_err($file_line_num, "$line - sync_first must be set to either 1 or 0");
					next;
				}
			}
		}
		
		# NO_CREATE_ROOT
		if ($var eq 'no_create_root') {
			if (defined($value)) {
				if ('1' eq $value) {
					$config_vars{'no_create_root'} = 1;
					$line_syntax_ok = 1;
					next;
				} elsif ('0' eq $value) {
					$config_vars{'no_create_root'} = 0;
					$line_syntax_ok = 1;
					next;
				} else {
					config_err($file_line_num, "$line - no_create_root must be set to either 1 or 0");
					next;
				}
			}
		}
		
		# CHECK FOR RSYNC (required)
		if ($var eq 'cmd_rsync') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_rsync'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR SSH (optional)
		if ($var eq 'cmd_ssh') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_ssh'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR GNU cp (optional)
		if ($var eq 'cmd_cp') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_cp'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR rm (optional)
		if ($var eq 'cmd_rm') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_rm'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR LOGGER (syslog program) (optional)
		if ($var eq 'cmd_logger') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_logger'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR du (optional)
		if ($var eq 'cmd_du') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_du'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR cmd_preexec (optional)
		if ($var eq 'cmd_preexec') {
			my $full_script	= $value;	# backup script to run (including args)
			my $script;					# script file (no args)
			my @script_argv;			# all script arguments
			
			# get the base name of the script, not counting any arguments to it
			@script_argv = split(/\s+/, $full_script);
			$script = $script_argv[0];
			
			# make sure script exists and is executable
			if (((! -f "$script") or (! -x "$script")) or !is_real_local_abs_path($script)) {
				config_err($file_line_num, "$line - cmd_preexec \"$script\" is not executable or does not exist");
				next;
			}
			
			$config_vars{'cmd_preexec'} = $full_script;
			
			$line_syntax_ok = 1;
			next;
		}
		
		# CHECK FOR cmd_postexec (optional)
		if ($var eq 'cmd_postexec') {
			my $full_script	= $value;	# backup script to run (including args)
			my $script;					# script file (no args)
			my @script_argv;			# all script arguments
			
			# get the base name of the script, not counting any arguments to it
			@script_argv = split(/\s+/, $full_script);
			$script = $script_argv[0];
			
			# make sure script exists and is executable
			if (((! -f "$script") or (! -x "$script")) or !is_real_local_abs_path($script)) {
				config_err($file_line_num, "$line - cmd_postexec \"$script\" is not executable or does not exist");
				next;
			}
			
			$config_vars{'cmd_postexec'} = $full_script;
			
			$line_syntax_ok = 1;
			next;
		}
		
		# CHECK FOR rsnapshot-diff (optional)
		if ($var eq 'cmd_rsnapshot_diff') {
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value))) {
				$config_vars{'cmd_rsnapshot_diff'} = $value;
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# INTERVALS
		if ($var eq 'interval') {
			# check if interval is blank
			if (!defined($value)) { config_err($file_line_num, "$line - Interval can not be blank"); }
			
			foreach my $word (@reserved_words) {
				if ($value eq $word) {
					config_err($file_line_num,
						"$line - \"$value\" is not a valid interval, reserved word conflict");
					next;
				}
			}
			
			# make sure interval is alpha-numeric
			if ($value !~ m/^[\w\d]+$/) {
				config_err($file_line_num,
					"$line - \"$value\" is not a valid interval, must be alphanumeric characters only");
				next;
			}
			
			# check if number is blank
			if (!defined($value2)) {
				config_err($file_line_num, "$line - \"$value\" number can not be blank");
				next;
			}
			
			# check if number is valid
			if ($value2 !~ m/^\d+$/) {
				config_err($file_line_num, "$line - \"$value2\" is not a legal value for an interval");
				next;
			# ok, it's a number. is it positive?
			} else {
				# make sure number is positive
				if ($value2 <= 0) {
					config_err($file_line_num, "$line - \"$value\" must be at least 1 or higher");
					next;
				}
			}
			
			my %hash;
			$hash{'interval'}	= $value;
			$hash{'number'}		= $value2;
			push(@intervals, \%hash);
			$line_syntax_ok = 1;
			next;
		}
		
		# BACKUP POINTS
		if ($var eq 'backup') {
			my $src			= $value;	# source directory
			my $dest		= $value2;	# dest directory
			my $opt_str		= $value3;	# option string from this backup point
			my $opts_ref	= undef;	# array_ref to hold parsed opts
			
			if ( !defined($config_vars{'snapshot_root'}) ) {
				config_err($file_line_num, "$line - snapshot_root needs to be defined before backup points");
				next;
			}
			
			if (!defined($src))	{
				config_err($file_line_num, "$line - no source path specified for backup point");
				next;
			}
			
			if (!defined($dest))	{
				config_err($file_line_num, "$line - no destination path specified for backup point");
				next;
			}
			
			# make sure we have a local path for the destination
			# (we do NOT want an absolute path)
			if ( is_valid_local_abs_path($dest) ) {
				config_err($file_line_num, "$line - Backup destination $dest must be a local, relative path");
				next;
			}
			
			# make sure we aren't traversing directories
			if ( is_directory_traversal($src) ) {
				config_err($file_line_num, "$line - Directory traversal attempted in $src");
				next;
			}
			if ( is_directory_traversal($dest) ) {
				config_err($file_line_num, "$line - Directory traversal attempted in $dest");
				next;
			}
			
			# validate source path
			#
			# local absolute?
			if ( is_real_local_abs_path($src) ) {
				$line_syntax_ok = 1;
				
			# syntactically valid remote ssh?
			} elsif ( is_ssh_path($src) ) {
				# if it's an absolute ssh path, make sure we have ssh
				if (!defined($config_vars{'cmd_ssh'})) {
					config_err($file_line_num, "$line - Cannot handle $src, cmd_ssh not defined in $config_file");
					next;
				}
				$line_syntax_ok = 1;
				
			# if it's anonymous rsync, we're ok
			} elsif ( is_anon_rsync_path($src) ) {
				$line_syntax_ok = 1;
				
			# check for cwrsync
			} elsif ( is_cwrsync_path($src) ) {
				$line_syntax_ok = 1;
				
			# fear the unknown
			} else {
				config_err($file_line_num, "$line - Source directory \"$src\" doesn't exist");
				next;
			}
			
			# validate destination path
			#
			if ( is_valid_local_abs_path($dest) ) {
				config_err($file_line_num, "$line - Full paths not allowed for backup destinations");
				next;
			}
			
			# if we have special options specified for this backup point, remember them
			if (defined($opt_str) && $opt_str) {
				$opts_ref = parse_backup_opts($opt_str);
				if (!defined($opts_ref)) {
					config_err(
						$file_line_num, "$line - Syntax error on line $file_line_num in extra opts: $opt_str"
					);
					next;
				}
			}
			
			# remember src/dest
			# also, first check to see that we're not backing up the snapshot directory
			#
			# there are now two methods of making sure the user doesn't accidentally backup their snapshot_root
			# recursively in a backup point: the good way, and the old way.
			#
			# in the old way, when rsnapshot detects the snapshot_root is under a backup point, the files and
			# directories under that backup point are enumerated and get turned into several distinct rsync calls.
			# for example, if you tried to back up "/", it would do a separate rsync invocation for "/bin/", "/etc/",
			# and so on. this wouldn't be so bad except that it makes certain rsync options like one_fs and the
			# include/exclude rules act funny since rsync isn't starting where the user expects (and there is no
			# really good way to provide a workaround, either automatically or manually). however, changing this
			# behaviour that users have come to rely on would not be very nice, so the old code path is left here
			# for those that specifically enable the rsync_long_args parameter but don't set the --relative option.
			#
			# the new way is much nicer, but relies on the --relative option to rsync, which only became the default
			# in rsnapshot 1.2.0 (primarily for this feature). basically, rsnapshot dynamically constructs an exclude
			# path to avoid backing up the snapshot_root. clean and simple. many thanks to bharat mediratta for coming
			# up with this solution!!!
			#
			# we only need to do any of this if the user IS trying to backup the snapshot_root
			if ((is_real_local_abs_path("$src")) && ($config_vars{'snapshot_root'} =~ m/^$src/)) {
				
				# old, less good, backward compatibility method
				if ( defined($config_vars{'rsync_long_args'}) && ($config_vars{'rsync_long_args'} !~ m/--relative/) ) {
					# remove trailing slashes from source and dest, since we will be using our own
					$src    = remove_trailing_slash($src);
					$dest   = remove_trailing_slash($dest);
					
					opendir(SRC, "$src") or bail("Could not open $src");
					
					while (my $node = readdir(SRC)) {
						next if ($node =~ m/^\.\.?$/o); # skip '.' and '..'
						
						# avoid double slashes from root filesystem
						if ($src eq '/') {
							$src = '';
						}
						
						# if this directory is in the snapshot_root, skip it
						# otherwise, back it up
						#
						if ("$config_vars{'snapshot_root'}" !~ m/^$src\/$node/) {
							my %hash;
							
							$hash{'src'}    = "$src/$node";
							$hash{'dest'}   = "$dest/$node";
							
							if (defined($opts_ref)) {
								$hash{'opts'} = $opts_ref;
							}
							push(@backup_points, \%hash);
						}
					}
					closedir(SRC);
					
				# new, shiny, preferred method. the way of the future.
				} else {
					my %hash;
					my $exclude_path;
					
					$hash{'src'}	= $src;
					$hash{'dest'}	= $dest;
					if (defined($opts_ref)) {
						$hash{'opts'} = $opts_ref;
					}
					
					# dynamically generate an exclude path to avoid backing up the snapshot root.
					# depending on the backup point and the snapshot_root location, this could be
					# almost anything. it's tempting to think that just using the snapshot_root as
					# the exclude path will work, but it doesn't. instead, this an exclude path that
					# starts relative to the backup point. for example, if snapshot_root is set to
					# /backup/private/snapshots/, and the backup point is /backup/, the exclude path
					# will be private/snapshots/. the trailing slash does not appear to matter.
					#
					# it's also worth noting that this doesn't work at all without the --relative
					# flag being passed to rsync (which is now the default).
					#
					# this method was added by bharat mediratta, and replaces my older, less elegant
					# attempt to run multiple invocations of rsync instead.
					#
					$exclude_path = $config_vars{'snapshot_root'};
					$exclude_path =~ s/^$src//;
					
					# pass it to rsync on this backup point only
					$hash{'opts'}{'extra_rsync_long_args'} .= sprintf(' --exclude=%s', $exclude_path);
					
					push(@backup_points, \%hash);
				}
				
			# the user is NOT trying to backup the snapshot_root. no workarounds required at all.
			} else {
				my %hash;
				$hash{'src'}	= $src;
				$hash{'dest'}	= $dest;
				if (defined($opts_ref)) {
					$hash{'opts'} = $opts_ref;
				}
				push(@backup_points, \%hash);
			}
			
			next;
		}
		
		# BACKUP SCRIPTS
		if ($var eq 'backup_script') {
			my $full_script	= $value;	# backup script to run (including args)
			my $dest		= $value2;	# dest directory
			my %hash;					# tmp hash to stick in the backup points array
			my $script;					# script file (no args)
			my @script_argv;			# tmp array to help us separate the script from the args
			
			if ( !defined($config_vars{'snapshot_root'}) ) {
				config_err($file_line_num, "$line - snapshot_root needs to be defined before backup scripts");
				next;
			}
			
			if (!defined($dest)) {
				config_err($file_line_num, "$line - no destination path specified");
				next;
			}
			
			# get the base name of the script, not counting any arguments to it
			@script_argv = split(/\s+/, $full_script);
			$script = $script_argv[0];
			
			# make sure the destination is a full path
			if (1 == is_valid_local_abs_path($dest)) {
				config_err($file_line_num, "$line - Backup destination $dest must be a local, relative path");
				next;
			}
			
			# make sure we aren't traversing directories (exactly 2 dots can't be next to each other)
			if (1 == is_directory_traversal($dest)) {
				config_err($file_line_num, "$line - Directory traversal attempted in $dest");
				next;
			}
			
			# make sure script exists and is executable
			if (((! -f "$script") or (! -x "$script")) or !is_real_local_abs_path($script)) {
				config_err($file_line_num, "$line - Backup script \"$script\" is not executable or does not exist");
				next;
			}
			
			$hash{'script'}	= $full_script;
			$hash{'dest'}	= $dest;
			
			$line_syntax_ok = 1;
			
			push(@backup_points, \%hash);
			
			next;
		}
		
		# GLOBAL OPTIONS from the config file
		# ALL ARE OPTIONAL
		#
		# LINK_DEST
		if ($var eq 'link_dest') {
			if (!defined($value)) {
				config_err($file_line_num, "$line - link_dest can not be blank");
				next;
			}
			if (!is_boolean($value)) {
				config_err(
					$file_line_num, "$line - \"$value\" is not a legal value for link_dest, must be 0 or 1 only"
				);
				next;
			}
			
			$link_dest = $value;
			$line_syntax_ok = 1;
			next;
		}
		# ONE_FS
		if ($var eq 'one_fs') {
			if (!defined($value)) {
				config_err($file_line_num, "$line - one_fs can not be blank");
				next;
			}
			if (!is_boolean($value)) {
				config_err(
					$file_line_num, "$line - \"$value\" is not a legal value for one_fs, must be 0 or 1 only"
				);
				next;
			}
			
			$one_fs = $value;
			$line_syntax_ok = 1;
			next;
		}
		# LOCKFILE
		if ($var eq 'lockfile') {
			if (!defined($value)) { config_err($file_line_num, "$line - lockfile can not be blank"); }
			if (0 == is_valid_local_abs_path("$value")) {
				config_err($file_line_num, "$line - lockfile must be a full path");
				next;
			}
			$config_vars{'lockfile'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# INCLUDE
		if ($var eq 'include') {
			if (!defined($rsync_include_args)) {
				$rsync_include_args = "--include=$value";
			} else {
				$rsync_include_args .= " --include=$value";
			}
			$line_syntax_ok = 1;
			next;
		}
		# EXCLUDE
		if ($var eq 'exclude') {
			if (!defined($rsync_include_args)) {
				$rsync_include_args = "--exclude=$value";
			} else {
				$rsync_include_args .= " --exclude=$value";
			}
			$line_syntax_ok = 1;
			next;
		}
		# INCLUDE FILE
		if ($var eq 'include_file') {
			if (0 == is_real_local_abs_path($value)) {
				config_err($file_line_num, "$line - include_file $value must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value)) {
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" )) {
				config_err($file_line_num, "$line - include_file $value exists, but is not a file");
				next;
			} elsif ( ! -r "$value" ) {
				config_err($file_line_num, "$line - include_file $value exists, but is not readable");
				next;
			} else {
				if (!defined($rsync_include_file_args)) {
					$rsync_include_file_args = "--include-from=$value";
				} else {
					$rsync_include_file_args .= " --include-from=$value";
				}
				$line_syntax_ok = 1;
				next;
			}
		}
		# EXCLUDE FILE
		if ($var eq 'exclude_file') {
			if (0 == is_real_local_abs_path($value)) {
				config_err($file_line_num, "$line - exclude_file $value must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value)) {
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" )) {
				config_err($file_line_num, "$line - exclude_file $value exists, but is not a file");
				next;
			} elsif ( ! -r "$value" ) {
				config_err($file_line_num, "$line - exclude_file $value exists, but is not readable");
				next;
			} else {
				if (!defined($rsync_include_file_args)) {
					$rsync_include_file_args = "--exclude-from=$value";
				} else {
					$rsync_include_file_args .= " --exclude-from=$value";
				}
				$line_syntax_ok = 1;
				next;
			}
		}
		# RSYNC SHORT ARGS
		if ($var eq 'rsync_short_args') {
			# must be in the format '-abcde'
			if (0 == is_valid_rsync_short_args($value)) {
				config_err($file_line_num, "$line - rsync_short_args \"$value\" not in correct format");
				next;
			} else {
				$config_vars{'rsync_short_args'} = $value;
				$line_syntax_ok = 1;
				next;
			}
		}
		# RSYNC LONG ARGS
		if ($var eq 'rsync_long_args') {
			$config_vars{'rsync_long_args'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# SSH ARGS
		if ($var eq 'ssh_args') {
			if (!defined($default_ssh_args) && defined($config_vars{'ssh_args'})) {
				config_err($file_line_num, "$line - global ssh_args can only be set once, but is already set.  Perhaps you wanted to use a per-backup ssh_args instead.");
				next;
			} else {
				$config_vars{'ssh_args'} = $value;
				$line_syntax_ok = 1;
				next;
			}
		}
		# DU ARGS
		if ($var eq 'du_args') {
			$config_vars{'du_args'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# LOGFILE
		if ($var eq 'logfile') {
			if (0 == is_valid_local_abs_path($value)) {
				config_err($file_line_num, "$line - logfile must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value)) {
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" )) {
				config_err($file_line_num, "$line - logfile $value exists, but is not a file");
				next;
			} else {
				$config_vars{'logfile'} = $value;
				$line_syntax_ok = 1;
				next;
			}
		}
		# VERBOSE
		if ($var eq 'verbose') {
			if (1 == is_valid_loglevel($value)) {
				if (!defined($verbose)) {
					$verbose = $value;
				}
				
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - verbose must be a value between 1 and 5");
				next;
			}
		}
		# LOGLEVEL
		if ($var eq 'loglevel') {
			if (1 == is_valid_loglevel($value)) {
				if (!defined($loglevel)) {
					$loglevel = $value;
				}
				
				$line_syntax_ok = 1;
				next;
			} else {
				config_err($file_line_num, "$line - loglevel must be a value between 1 and 5");
				next;
			}
		}
		# USE LAZY DELETES
		if ($var eq 'use_lazy_deletes') {
			if (!defined($value)) {
				config_err($file_line_num, "$line - use_lazy_deletes can not be blank");
				next;
			}
			if (!is_boolean($value)) {
				config_err(
					$file_line_num, "$line - \"$value\" is not a legal value for use_lazy_deletes, must be 0 or 1 only"
				);
				next;
			}
			
			if (1 == $value) { $use_lazy_deletes = 1; }
			$line_syntax_ok = 1;
			next;
		}
				
		# make sure we understood this line
		# if not, warn the user, and prevent the program from executing
		# however, don't bother if the user has already been notified
		if (1 == $config_perfect) {
			if (0 == $line_syntax_ok) {
				config_err($file_line_num, $line);
				next;
			}
		}
	}
}
	
sub validate_config_file {
	####################################################################
	# SET SOME SENSIBLE DEFAULTS FOR VALUES THAT MAY NOT HAVE BEEN SET #
	####################################################################
	
	# if we didn't manage to get a verbose level yet, either through the config file
	# or the command line, use the default
	if (!defined($verbose)) {
		$verbose = $default_verbose;
	}
	# same for loglevel
	if (!defined($loglevel)) {
		$loglevel = $default_loglevel;
	}
	# assemble rsync include/exclude args
	if (defined($rsync_include_args)) {
		if (!defined($config_vars{'rsync_long_args'})) {
			$config_vars{'rsync_long_args'} = $default_rsync_long_args;
		}
		$config_vars{'rsync_long_args'} .= " $rsync_include_args";
	}
	# assemble rsync include/exclude file args
	if (defined($rsync_include_file_args)) {
		if (!defined($config_vars{'rsync_long_args'})) {
			$config_vars{'rsync_long_args'} = $default_rsync_long_args;
		}
		$config_vars{'rsync_long_args'} .= " $rsync_include_file_args";
	}
	
	###############################################
	# NOW THAT THE CONFIG FILE HAS BEEN READ IN,  #
	# DO A SANITY CHECK ON THE DATA WE PULLED OUT #
	###############################################
	
	# SINS OF COMMISSION
	# (incorrect entries in config file)
	if (0 == $config_perfect) {
		print_err("---------------------------------------------------------------------", 1);
		print_err("Errors were found in $config_file,", 1);
		print_err("rsnapshot can not continue. If you think an entry looks right, make", 1);
		print_err("sure you don't have spaces where only tabs should be.", 1);
		
		# if this wasn't a test, report the error to syslog
		if (0 == $do_configtest) {
			syslog_err("Errors were found in $config_file, rsnapshot can not continue.");
		}
		
		# exit showing an error
		exit(1);
	}
	
	# SINS OF OMISSION
	# (things that should be in the config file that aren't)
	#
	# make sure config_version was set
	if (!defined($config_vars{'config_version'})) {
		print_err ("config_version was not defined. rsnapshot can not continue.", 1);
		syslog_err("config_version was not defined. rsnapshot can not continue.");
		exit(1);
	}
	# make sure rsync was defined
	if (!defined($config_vars{'cmd_rsync'})) {
		print_err ("cmd_rsync was not defined.", 1);
		syslog_err("cmd_rsync was not defined.", 1);
		exit(1);
	}
	# make sure we got a snapshot_root
	if (!defined($config_vars{'snapshot_root'})) {
		print_err ("snapshot_root was not defined. rsnapshot can not continue.", 1);
		syslog_err("snapshot_root was not defined. rsnapshot can not continue.");
		exit(1);
	}
	# make sure we have at least one interval
	if (0 == scalar(@intervals)) {
		print_err ("At least one interval must be set. rsnapshot can not continue.", 1);
		syslog_err("At least one interval must be set. rsnapshot can not continue.");
		exit(1);
	}
	# make sure we have at least one backup point
	if (0 == scalar(@backup_points)) {
		print_err ("At least one backup point must be set. rsnapshot can not continue.", 1);
		syslog_err("At least one backup point must be set. rsnapshot can not continue.");
		exit(1);
	}

	# SINS OF CONFUSION
	# (various, specific, undesirable interactions)
	#
	# make sure that we don't have only one copy of the first interval,
	# yet expect rotations on the second interval
	if (scalar(@intervals) > 1) {
		if (defined($intervals[0]->{'number'})) {
			if (1 == $intervals[0]->{'number'}) {
				print_err ("Can not have first interval set to 1, and have a second interval", 1);
				syslog_err("Can not have first interval set to 1, and have a second interval");
				exit(1);
			}
		}
	}
	# make sure that the snapshot_root exists if no_create_root is set to 1
	if (defined($config_vars{'no_create_root'})) {
		if (1 == $config_vars{'no_create_root'}) {
			if ( ! -d "$config_vars{'snapshot_root'}" ) {
				if ( -e "$config_vars{'snapshot_root'}" ) {
					print_err ("$config_vars{'snapshot_root'} is not a directory.", 1);
				} else {
					print_err ("$config_vars{'snapshot_root'} does not exist.", 1);
				}
				print_err ("rsnapshot refuses to create snapshot_root when no_create_root is enabled", 1);
				syslog_err("rsnapshot refuses to create snapshot_root when no_create_root is enabled");
				exit(1);
			}
		}
	}
	# make sure that the user didn't call "sync" if sync_first isn't enabled
	if (($cmd eq 'sync') && (! $config_vars{'sync_first'})) {
		print_err ("\"sync_first\" must be enabled for \"sync\" to work", 1);
		syslog_err("\"sync_first\" must be enabled for \"sync\" to work");
		exit(1);
	}
	# make sure that the backup_script destination paths don't nuke data copied over for backup points
	{
		my @backup_dest			= ();
		my @backup_script_dest	= ();
		
		# remember where the destination paths are...
		foreach my $bp_ref (@backup_points) {
			my $tmp_dest_path = $$bp_ref{'dest'};
			
			# normalize multiple slashes, and strip trailing slash
			$tmp_dest_path =~ s/\/+/\//g;
			$tmp_dest_path =~ s/\/$//;
			
			# backup
			if (defined($$bp_ref{'src'})) {
				push(@backup_dest, $tmp_dest_path);
				
			# backup_script
			} elsif (defined($$bp_ref{'script'})) {
				push(@backup_script_dest, $tmp_dest_path);
				
			# something else is wrong
			} else {
				print_err ("logic error in parse_config_file(): a backup point has no src and no script", 1);
				syslog_err("logic error in parse_config_file(): a backup point has no src and no script");
				exit(1);
			}
		}
		
		# loop through and check for conflicts between backup and backup_script destination paths
		foreach my $b_dest (@backup_dest) {
			foreach my $bs_dest (@backup_script_dest) {
				if (defined($b_dest) && defined($bs_dest)) {
					my $tmp_b  = $b_dest;
					my $tmp_bs = $bs_dest;
					
					# add trailing slashes back in so similarly named directories don't match
					# e.g., localhost/abc/ and localhost/ab/
					$tmp_b  .= '/';
					$tmp_bs .= '/';
					
					if ("$b_dest" =~ m/^$bs_dest/) {
						# duplicate entries, stop here
						print_err (
							"destination conflict between \"$tmp_b\" and \"$tmp_bs\" in backup / backup_script entries",
							1
						);
						syslog_err(
							"destination conflict between \"$tmp_b\" and \"$tmp_bs\" in backup / backup_script entries"
						);
						exit(1);
					}
				} else {
					print_err ("logic error in parse_config_file(): unique destination check failed unexpectedly", 1);
					syslog_err("logic error in parse_config_file(): unique destination check failed unexpectedly");
					exit(1);
				}
			}
		}
		# loop through and check for conflicts between different backup_scripts
		for (my $i=0; $i<scalar(@backup_script_dest); $i++) {
			for (my $j=0; $j<scalar(@backup_script_dest); $j++) {
				if ($i != $j) {
					my $path1 = $backup_script_dest[$i];
					my $path2 = $backup_script_dest[$j];
					
					# add trailing slashes back in so similarly named directories don't match
					# e.g., localhost/abc/ and localhost/ab/
					$path1 .= '/';
					$path2 .= '/';
					
					if (("$path1" =~ m/$path2/) or ("$path2" =~ m/$path1/)) {
						print_err (
							"destination conflict between \"$path1\" and \"$path2\" in multiple backup_script entries", 1
						);
						syslog_err(
							"destination conflict between \"$path1\" and \"$path2\" in multiple backup_script entries"
						);
						exit(1);
					}
				}
			}
		}
	}
}

# accepts a string of options
# returns an array_ref of parsed options
# returns undef if there is an invalid option
#
# this is for individual backup points only
sub parse_backup_opts {
	my $opts_str = shift(@_);
	my @pairs;
	my %parsed_opts;
	
	# pre-buffer extra rsync arguments
	my $rsync_include_args		= undef;
	my $rsync_include_file_args	= undef;
	
	# make sure we got something (it's quite likely that we didn't)
	if (!defined($opts_str))	{ return (undef); }
	if (!$opts_str)				{ return (undef); }
	
	# split on commas first
	@pairs = split(/,/, $opts_str);
	
	# then loop through and split on equals
	foreach my $pair (@pairs) {
		my $additive;
		if ($pair =~ /^\+/) {
			$additive = 1;
			$pair =~ s/^.//;
		} else {
			$additive = 0;
		}
		
		my ($name, $value) = split(/=/, $pair, 2);
		if ( !defined($name) or !defined($value) ) {
			return (undef);
		}
		
		# parameters can't have spaces in them
		$name =~ s/\s+//go;
		
		# strip whitespace from both ends
		$value =~ s/^\s{0,}//o;
		$value =~ s/\s{0,}$//o;
		
		# ok, it's a name/value pair and it's ready for more validation
		if ($additive) {
			$parsed_opts{'extra_' . $name} = $value;
		} else {
			$parsed_opts{$name} = $value;
		}
		
		# VALIDATE ARGS
		# one_fs
		if ( $name eq 'one_fs' ) {
			if (!is_boolean($parsed_opts{'one_fs'})) {
				return (undef);
			}
		# rsync_short_args
		} elsif ( $name eq 'rsync_short_args' ) {
			# must be in the format '-abcde'
			if (0 == is_valid_rsync_short_args($value)) {
				print_err("rsync_short_args \"$value\" not in correct format", 2);
				return (undef);
			}
			
		# rsync_long_args
		} elsif ( $name eq 'rsync_long_args' ) {
			# pass unchecked
			
		# ssh_args
		} elsif ( $name eq 'ssh_args' ) {
			# pass unchecked
			
		# include
		} elsif ( $name eq 'include' ) {
			# don't validate contents
			# coerce into rsync_include_args
			# then remove the "include" key/value pair
			if (!defined($rsync_include_args)) {
				$rsync_include_args = "--include=$parsed_opts{'include'}";
			} else {
				$rsync_include_args .= " --include=$parsed_opts{'include'}";
			}
			
			delete($parsed_opts{'include'});
			
		# exclude
		} elsif ( $name eq 'exclude' ) {
			# don't validate contents
			# coerce into rsync_include_args
			# then remove the "include" key/value pair
			if (!defined($rsync_include_args)) {
				$rsync_include_args = "--exclude=$parsed_opts{'exclude'}";
			} else {
				$rsync_include_args .= " --exclude=$parsed_opts{'exclude'}";
			}
			
			delete($parsed_opts{'exclude'});
			
		# include_file
		} elsif ( $name eq 'include_file' ) {
			# verify that this file exists and is readable
			if (0 == is_real_local_abs_path($value)) {
				print_err("include_file $value must be a valid absolute path", 2);
				return (undef);
			} elsif (1 == is_directory_traversal($value)) {
				print_err("Directory traversal attempted in $value", 2);
				return (undef);
			} elsif (( -e "$value" ) && ( ! -f "$value" )) {
				print_err("include_file $value exists, but is not a file", 2);
				return (undef);
			} elsif ( ! -r "$value" ) {
				print_err("include_file $value exists, but is not readable", 2);
				return (undef);
			}
			
			# coerce into rsync_include_file_args
			# then remove the "include_file" key/value pair
			if (!defined($rsync_include_file_args)) {
				$rsync_include_file_args = "--include-from=$parsed_opts{'include_file'}";
			} else {
				$rsync_include_file_args .= " --include-from=$parsed_opts{'include_file'}";
			}
			
			delete($parsed_opts{'include_file'});
			
		# exclude_file
		} elsif ( $name eq 'exclude_file' ) {
			# verify that this file exists and is readable
			if (0 == is_real_local_abs_path($value)) {
				print_err("exclude_file $value must be a valid absolute path", 2);
				return (undef);
			} elsif (1 == is_directory_traversal($value)) {
				print_err("Directory traversal attempted in $value", 2);
				return (undef);
			} elsif (( -e "$value" ) && ( ! -f "$value" )) {
				print_err("exclude_file $value exists, but is not a file", 2);
				return (undef);
			} elsif ( ! -r "$value" ) {
				print_err("exclude_file $value exists, but is not readable", 2);
				return (undef);
			}
			
			# coerce into rsync_include_file_args
			# then remove the "exclude_file" key/value pair
			if (!defined($rsync_include_file_args)) {
				$rsync_include_file_args = "--exclude-from=$parsed_opts{'exclude_file'}";
			} else {
				$rsync_include_file_args .= " --exclude-from=$parsed_opts{'exclude_file'}";
			}
			
			delete($parsed_opts{'exclude_file'});
			
		# if we don't know about it, it doesn't exist
		} else {
			return (undef);
		}
	}
	
	# merge rsync_include_args and rsync_file_include_args in with either $default_rsync_long_args
	# or $parsed_opts{'rsync_long_args'}
	if (defined($rsync_include_args) or defined($rsync_include_file_args)) {
		# if we never defined rsync_long_args, populate it with the global default
		if (!defined($parsed_opts{'rsync_long_args'})) {
			if (defined($config_vars{'rsync_long_args'})) {
				$parsed_opts{'rsync_long_args'} = $config_vars{'rsync_long_args'};
			} else {
				$parsed_opts{'rsync_long_args'} = $default_rsync_long_args;
			}
		}
		
		# now we have something in our local rsync_long_args
		# let's concatenate the include/exclude/file stuff to it
		if (defined($rsync_include_args)) {
			$parsed_opts{'rsync_long_args'} .= " $rsync_include_args";
		}
		if (defined($rsync_include_file_args)) {
			$parsed_opts{'rsync_long_args'} .= " $rsync_include_file_args";
		}
	}
	
	# if we got anything, return it as an array_ref
	if (%parsed_opts) {
		return (\%parsed_opts);
	}
	
	return (undef);
}

# accepts line number, errstr
# prints a config file error
# also sets global $config_perfect var off
sub config_err {
	my $line_num	= shift(@_);
	my $errstr		= shift(@_);
	
	if (!defined($line_num))	{ $line_num = -1; }
	if (!defined($errstr))		{ $errstr = 'config_err() called without an error string!'; }
	
	# show the user the file and line number
	print_err("$config_file on line $line_num:", 1);
	
	# print out the offending line
	# don't print past 69 columns (because they all start with 'ERROR: ')
	# similarly, indent subsequent lines 9 spaces to get past the 'ERROR: ' message
	print_err( wrap_cmd($errstr, 69, 9), 1 );
	
	# invalidate entire config file
	$config_perfect = 0;
}

# accepts an error string
# prints to STDERR and maybe syslog. removes the lockfile if it exists.
# exits the program safely and consistently
sub bail {
	my $str = shift(@_);
	
	# print out error
	if ($str) {
		print_err($str, 1);
	}
	
	# write to syslog if we're running for real (and we have a message)
	if ((0 == $do_configtest) && (0 == $test) && defined($str) && ('' ne $str)) {
		syslog_err($str);
	}
	
	# get rid of the lockfile, if it exists
	remove_lockfile();
	
	# exit showing an error
	exit(1);
}

# accepts a string (or an array)
# prints the string, but separates it across multiple lines with backslashes if necessary
# also logs the command, but on a single line
sub print_cmd {
	# take all arguments and make them into one string
	my $str = join(' ', @_);
	
	if (!defined($str)) { return (undef); }
	
	# remove newline and consolidate spaces
	chomp($str);
	$str =~ s/\s+/ /g;
	
	# write to log (level 3 is where we start showing commands)
	log_msg($str, 3);
	
	if (!defined($verbose) or ($verbose >= 3)) {
		print wrap_cmd($str), "\n";
	}
}

# accepts a string
# wraps the text to fit in 80 columns with backslashes at the end of each wrapping line
# returns the wrapped string
sub wrap_cmd {
	my $str		= shift(@_);
	my $colmax	= shift(@_);
	my $indent	= shift(@_);
	
	my @tokens;
	my $chars = 0;		# character tally
	my $outstr = '';	# string to return
	
	# max chars before wrap (default to 80 column terminal)
	if (!defined($colmax)) {
		$colmax = 76;
	}
	
	# number of spaces to indent subsequent lines
	if (!defined($indent)) {
		$indent = 4;
	}
	
	# break up string into individual pieces
	@tokens = split(/\s+/, $str);
	
	# stop here if we don't have anything
	if (0 == scalar(@tokens)) { return (''); }
	
	# print the first token as a special exception, since we should never start out by line wrapping
	if (defined($tokens[0])) {
		$chars = (length($tokens[0]) + 1);
		$outstr .= $tokens[0];
		
		# don't forget to put the space back in
		if (scalar(@tokens) > 1) {
			$outstr .= ' ';
		}
	}
	
	# loop through the rest of the tokens and print them out, wrapping when necessary
	for (my $i=1; $i<scalar(@tokens); $i++) {
		# keep track of where we are (plus a space)
		$chars += (length($tokens[$i]) + 1);
		
		# wrap if we're at the edge
		if ($chars > $colmax) {
			$outstr .= "\\\n";
			$outstr .= (' ' x $indent);
			
			# 4 spaces + string length
			$chars = $indent + length($tokens[$i]);
		}
		
		# print out this token
		$outstr .= $tokens[$i];
		
		# print out a space unless this is the last one
		if ($i < scalar(@tokens)) {
			$outstr .= ' ';
		}
	}
	
	return ($outstr);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
sub print_msg {
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	chomp($str);
	
	# print to STDOUT
	if ((!defined($verbose)) or ($verbose >= $level)) {
		print $str, "\n";
	}
	
	# write to log
	log_msg($str, $level);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
# also raises a warning for the exit code
sub print_warn {
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	# we can no longer say the execution of the program has been error free
	raise_warning();
	
	chomp($str);
	
	# print to STDERR
	if ((!defined($verbose)) or ($level <= $verbose)) {
		print STDERR 'WARNING: ', $str, "\n";
	}
	
	# write to log
	log_msg($str, $level);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
# also raises an error for the exit code
sub print_err {
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	# we can no longer say the execution of the program has been error free
	raise_error();
	
	chomp($str);
	
	# print the run string once
	# this way we know where the message came from if it's in an e-mail
	# but we can still read messages at the console
	if (0 == $have_printed_run_string) {
		if ((!defined($verbose)) or ($level <= $verbose)) {
			print STDERR "----------------------------------------------------------------------------\n";
			print STDERR "rsnapshot encountered an error! The program was invoked with these options:\n";
			print STDERR wrap_cmd($run_string), "\n";
			print STDERR "----------------------------------------------------------------------------\n";
		}
		
		$have_printed_run_string = 1;
	}
	
	# print to STDERR
	if ((!defined($verbose)) or ($level <= $verbose)) {
		#print STDERR $run_string, ": ERROR: ", $str, "\n";
		print STDERR "ERROR: ", $str, "\n";
	}
	
	# write to log
	log_err($str, $level);
}

# accepts string, and level
# logs string if level is as high as loglevel
sub log_msg {
	my $str		= shift(@_);
	my $level	= shift(@_);
	my $result	= undef;
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ return (undef); }
	
	chomp($str);
	
	# if this is just noise, don't log it
	if (defined($loglevel) && ($level > $loglevel)) {
		return (undef);
	}
	
	# open logfile, write to it, close it back up
	# if we fail, don't use the usual print_* functions, since they just call this again
	if ((0 == $test) && (0 == $do_configtest)) {
		if (defined($config_vars{'logfile'})) {
			$result = open (LOG, ">> $config_vars{'logfile'}");
			if (!defined($result)) {
				print STDERR "Could not open logfile $config_vars{'logfile'} for writing\n";
				print STDERR "Do you have write permission for this file?\n";
				exit(1);
			}
			
			print LOG '[', get_current_date(), '] ', $str, "\n";
			
			$result = close(LOG);
			if (!defined($result)) {
				print STDERR "Could not close logfile $config_vars{'logfile'}\n";
			}
		}
	}
}

# accepts string, and level
# logs string if level is as high as loglevel
# also raises a warning for the exit code
sub log_warn {
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ return (undef); }
	
	# this run is no longer perfect since we have an error
	raise_warning();
	
	chomp($str);
	
	$str = 'WARNING: ' . $str;
	log_msg($str, $level);
}

# accepts string, and level
# logs string if level is as high as loglevel
# also raises an error for the exit code
sub log_err {
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ return (undef); }
	
	# this run is no longer perfect since we have an error
	raise_error();
	
	chomp($str);
	
	$str = "$run_string: ERROR: " . $str;
	log_msg($str, $level);
}

# log messages to syslog
# accepts message, facility, level
# only message is required
# return 1 on success, undef on failure
sub syslog_msg {
	my $msg			= shift(@_);
	my $facility	= shift(@_);
	my $level		= shift(@_);
	my $result		= undef;
	
	if (!defined($msg))			{ return (undef); }
	if (!defined($facility))	{ $facility	= 'user'; }
	if (!defined($level))		{ $level	= 'info'; }
	
	if (defined($config_vars{'cmd_logger'})) {
		# print out our call to syslog
		if (defined($verbose) && ($verbose >= 4)) {
			print_cmd("$config_vars{'cmd_logger'} -i -p $facility.$level -t rsnapshot $msg");
		}
		
		# log to syslog
		if (0 == $test) {
			$result = system($config_vars{'cmd_logger'}, '-i', '-p', "$facility.$level", '-t', 'rsnapshot', $msg);
			if (0 != $result) {
				print_warn("Could not log to syslog:", 2);
				print_warn("$config_vars{'cmd_logger'} -i -p $facility.$level -t rsnapshot $msg", 2);
			}
		}
	}
	
	return (1);
}

# log warnings to syslog
# accepts warning message
# returns 1 on success, undef on failure
# also raises a warning for the exit code
sub syslog_warn {
	my $msg = shift(@_);
	
	# this run is no longer perfect since we have an error
	raise_warning();
	
	return syslog_msg("WARNING: $msg", 'user', 'err');
}

# log errors to syslog
# accepts error message
# returns 1 on success, undef on failure
# also raises an error for the exit code
sub syslog_err {
	my $msg = shift(@_);
	
	# this run is no longer perfect since we have an error
	raise_error();
	
	return syslog_msg("$run_string: ERROR: $msg", 'user', 'err');
}

# sets exit code for at least a warning
sub raise_warning {
	if ($exit_code != 1) {
		$exit_code = 2;
	}
}

# sets exit code for error
sub raise_error {
	$exit_code = 1;
}

# accepts no arguments
# returns the current date (for the logfile)
#
# there's probably a wonderful module that can do this all for me,
# but unless it comes standard with perl 5.004 and later, i'd rather do it this way :)
#
sub get_current_date {
	# localtime() gives us an array with these elements:
	# 0 = seconds
	# 1 = minutes
	# 2 = hours
	# 3 = day of month
	# 4 = month + 1
	# 5 = year + 1900
	
	# example date format (just like Apache logs)
	# 28/Feb/2004:23:45:59
	
	my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
	
	my @fields = localtime(time());
	
	my $datestr =
					# day of month
					sprintf("%02i", $fields[3]) .
					'/' .
					# name of month
					$months[$fields[4]] .
					'/' .
					# year
					($fields[5]+1900) .
					':' .
					# hours (24 hour clock)
					sprintf("%02i", $fields[2]) .
					':' .
					# minutes
					sprintf("%02i", $fields[1]) .
					':' .
					# seconds
					sprintf("%02i", $fields[0]);
	
	return ($datestr);
}

# accepts no arguments
# returns nothing
# simply prints out a startup message to the logs and STDOUT
sub log_startup {
	log_msg("$run_string: started", 2);
}

# accepts no arguments
# returns undef if lockfile isn't defined in the config file, and 1 upon success
# also, it can make the program exit with 1 as the return value if it can't create the lockfile
#
# we don't use bail() to exit on error, because that would remove the
# lockfile that may exist from another invocation
#
# if a lockfile exists, we try to read it (and stop if we can't) to get a PID,
# then see if that PID exists.  If it does, we stop, otherwise we assume it's
# a stale lock and remove it first.
sub add_lockfile {
	# if we don't have a lockfile defined, just return undef
	if (!defined($config_vars{'lockfile'})) {
		return (undef);
	}
	
	my $lockfile = $config_vars{'lockfile'};
	
	# valid?
	if (0 == is_valid_local_abs_path($lockfile)) {
		print_err ("Lockfile $lockfile is not a valid file name", 1);
		syslog_err("Lockfile $lockfile is not a valid file name");
		exit(1);
	}
	
	# does a lockfile already exist?
        if (1 == is_real_local_abs_path($lockfile)) {
            if(!open(LOCKFILE, $lockfile)) {
                print_err ("Lockfile $lockfile exists and can't be read, can not continue!", 1);
                syslog_err("Lockfile $lockfile exists and can't be read, can not continue");
                exit(1);
            }
            my $pid = <LOCKFILE>;
            chomp($pid);
            close(LOCKFILE);
            if(kill(0, $pid)) {
                print_err ("Lockfile $lockfile exists and so does its process, can not continue");
                syslog_err("Lockfile $lockfile exists and so does its process, can not continue");
                exit(1);
            } else {
                print_warn("Removing stale lockfile $lockfile", 1);
                syslog_warn("Removing stale lockfile $lockfile");
                remove_lockfile();
            }
        }

	
	# create the lockfile
	print_cmd("echo $$ > $lockfile");
	
	if (0 == $test) {
		# sysopen() can do exclusive opens, whereas perl open() can not
		my $result = sysopen(LOCKFILE, $lockfile, O_WRONLY | O_EXCL | O_CREAT, 0644);
		if (!defined($result) || 0 == $result) {
			print_err ("Could not write lockfile $lockfile: $!", 1);
			syslog_err("Could not write lockfile $lockfile");
			exit(1);
		}
		
		# print PID to lockfile
		print LOCKFILE $$;
		
		$result = close(LOCKFILE);
		if (!defined($result) || 0 == $result) {
			print_warn("Could not close lockfile $lockfile: $!", 2);
		}
	}
	
	return (1);
}

# accepts no arguments
# accepts the path to a lockfile and tries to remove it
# returns undef if lockfile isn't defined in the config file, and 1 upon success
# also, it can exit the program with a value of 1 if it can't remove the lockfile
#
# we don't use bail() to exit on error, because that would call
# this subroutine twice in the event of a failure
sub remove_lockfile {
	# if we don't have a lockfile defined, return undef
	if (!defined($config_vars{'lockfile'})) {
		return (undef);
	}
	
	my $lockfile = $config_vars{'lockfile'};
	my $result = undef;
	
	if ( -e "$lockfile" ) {
		print_cmd("rm -f $lockfile");
		if (0 == $test) {
			$result = unlink($lockfile);
			if (0 == $result) {
				print_err ("Could not remove lockfile $lockfile", 1);
				syslog_err("Error! Could not remove lockfile $lockfile");
				exit(1);
			}
		}
	}
	
	return (1);
}

# accepts no arguments
# returns nothing
# sets the locale to POSIX (C) to mitigate some problems with the rmtree() command
#
sub set_posix_locale {
	# set POSIX locale
	# this may fix some potential problems with rmtree()
	# another solution is to enable "cmd_rm" in rsnapshot.conf
	print_msg("Setting locale to POSIX \"C\"", 4);
	setlocale(POSIX::LC_ALL, 'C');
}

# accepts no arguments
# returns nothing
# creates the snapshot_root directory (chmod 0700), if it doesn't exist and no_create_root == 0
sub create_snapshot_root {
	# attempt to create the directory if it doesn't exist
	if ( ! -d "$config_vars{'snapshot_root'}" ) {
		
		# make sure no_create_root == 0
		if (defined($config_vars{'no_create_root'})) {
			if (1 == $config_vars{'no_create_root'}) {
				print_err ("rsnapshot refuses to create snapshot_root when no_create_root is enabled", 1);
				syslog_err("rsnapshot refuses to create snapshot_root when no_create_root is enabled");
				bail();
			}
		}
		
		# actually create the directory
		print_cmd("mkdir -m 0700 -p $config_vars{'snapshot_root'}/");
		if (0 == $test) {
			eval {
				# don't pass a trailing slash to mkpath
				mkpath( "$config_vars{'snapshot_root'}", 0, 0700 );
			};
			if ($@) {
				bail(
					"Unable to create $config_vars{'snapshot_root'}/,\nPlease make sure you have the right permissions."
				);
			}
		}
	}
}

# accepts current interval
# returns a hash_ref containing information about the intervals
# exits the program if we don't have good data to work with
sub get_interval_data {
	my $cur_interval = shift(@_);
	
	# make sure we were passed an interval
	if (!defined($cur_interval)) { bail("cur_interval not specified in get_interval_data()\n"); }
	
	# the hash to return
	my %hash;
	
	# which of the intervals are we operating on?
	# if we defined hourly, daily, weekly ... hourly = 0, daily = 1, weekly = 2
	my $interval_num;
	
	# the highest possible number for the current interval context
	# if we are working on hourly, and hourly is set to 6, this would be
	# equal to 5 (since we start at 0)
	my $interval_max;
	
	# this is the name of the previous interval, in relation to the one we're
	# working on. e.g., if we're operating on weekly, this should be "daily"
	my $prev_interval;
	
	# same as $interval_max, except for the previous interval.
	# this is used to determine which of the previous snapshots to pull from
	# e.g., cp -al hourly.$prev_interval_max/ daily.0/
	my $prev_interval_max;
	
	# FIGURE OUT WHICH INTERVAL WE'RE RUNNING, AND HOW IT RELATES TO THE OTHERS
	# THEN RUN THE ACTION FOR THE CHOSEN INTERVAL
	# remember, in each hashref in this loop:
	#   "interval" is something like "daily", "weekly", etc.
	#   "number" is the number of these intervals to keep on the filesystem
	
	my $i = 0;
	foreach my $i_ref (@intervals) {
		
		# this is the interval we're set to run
		if ($$i_ref{'interval'} eq $cur_interval) {
			$interval_num = $i;
			
			# how many of these intervals should we keep?
			# we start counting from 0, so subtract one
			# e.g., 6 intervals == interval.0 .. interval.5
			$interval_max = $$i_ref{'number'} - 1;
			
			# we found our interval, exit the foreach loop
			last;
		}
		
		# since the "last" command above breaks from this entire block,
		# and since we loop through the intervals in order, if we got this
		# far in the first place it means that we're looking at an interval
		# which isn't selected to run, and that there will be more intervals in the loop.
		# therefore, this WILL be the previous interval's information, the next time through.
		#
		$prev_interval = $$i_ref{'interval'};
		
		# which of the previous interval's numbered directories should we pull from
		# for the interval we're currently set to run?
		# e.g., daily.0/ might get pulled from hourly.6/
		#
		$prev_interval_max = $$i_ref{'number'} - 1;
		
		$i++;
	}
	
	# make sure we got something that makes sense
	if ($cur_interval ne 'sync') {
		if (!defined($interval_num)) { bail("Interval \"$cur_interval\" unknown, check $config_file"); }
	}
	
	# populate our hash
	$hash{'interval'}			= $cur_interval;
	$hash{'interval_num'}		= $interval_num;
	$hash{'interval_max'}		= $interval_max;
	$hash{'prev_interval'}		= $prev_interval;
	$hash{'prev_interval_max'}	= $prev_interval_max;
	
	# and return the values
	return (\%hash);
}

# accepts no arguments
# prints the most recent snapshot directory and exits
# this is for use with the get-latest-snapshot command line argument
sub show_latest_snapshot {
	# this should only be called after parse_config_file(), but just in case...
	if (! @intervals)	{ bail("Error! intervals not defined in show_latest_snapshot()"); }
	if (! %config_vars) { bail("Error! config_vars not defined in show_latest_snapshot()"); }
	
	# regardless of .sync, this is the latest "real" snapshot
	print $config_vars{'snapshot_root'} . '/' . $intervals[0]->{'interval'} . '.0/' . "\n";
	
	exit(0);
}

# accepts no args
# prints out status to the logs, then exits the program with the current exit code
sub exit_with_status {
	if (0 == $exit_code) {
		syslog_msg("$run_string: completed successfully");
		log_msg   ("$run_string: completed successfully", 2);
		exit ($exit_code);
		
	} elsif (1 == $exit_code) {
		syslog_err("$run_string: completed, but with some errors");
		log_err   ("$run_string: completed, but with some errors", 2);
		exit ($exit_code);
		
	} elsif (2 == $exit_code) {
		syslog_warn("$run_string: completed, but with some warnings");
		log_warn   ("$run_string: completed, but with some warnings", 2);
		exit ($exit_code);
		
	# this should never happen
	} else {
		syslog_err("$run_string: completed, but with no definite status");
		log_err   ("$run_string: completed, but with no definite status", 2);
		exit (1);
	}
}

# accepts no arguments
# returns nothing
#
# exits the program with the status of the config file (e.g., Syntax OK).
# the exit code is 0 for success, 1 for failure (although failure should never happen)
sub exit_configtest {
	# if we're just doing a configtest, exit here with the results
	if (1 == $do_configtest) {
		if (1 == $config_perfect) {
			print "Syntax OK\n";
			exit(0);
			
		# this should never happen, because any errors should have killed the program before now
		} else {
			print "Syntax Error\n";
			exit(1);
		}
	}
}

# accepts no arguments
# prints out error messages since we can't find the config file
# exits with a return code of 1
sub exit_no_config_file {
	# warn that the config file could not be found
	print STDERR "Config file \"$config_file\" does not exist or is not readable.\n";
	if (0 == $do_configtest) {
		syslog_err("Config file \"$config_file\" does not exist or is not readable.");
	}
	
	# if we have the default config from the install, remind the user to create the real config
	if ((-e "$config_file.default") && (! -e "$config_file")) {
		print STDERR "Did you copy $config_file.default to $config_file yet?\n";
	}
	
	# exit showing an error
	exit(1);
}

# accepts a loglevel
# returns 1 if it's valid, 0 otherwise
sub is_valid_loglevel {
	my $value	= shift(@_);
	
	if (!defined($value)) { return (0); }
	
	if ($value =~ m/^\d$/) {
		if (($value >= 1) && ($value <= 5)) {
			return (1);
		}
	}
	
	return (0);
}

# accepts one argument
# checks to see if that argument is set to 1 or 0
# returns 1 on success, 0 on failure
sub is_boolean {
	my $var = shift(@_);
	
	if (!defined($var))		{ return (0); }
	if ($var !~ m/^\d+$/)	{ return (0); }
	
	if (1 == $var)	{ return (1); }
	if (0 == $var)	{ return (1); }
	
	return (0);
}

# accepts string
# returns 1 if it is a comment line (beginning with #)
# returns 0 otherwise
sub is_comment {
	my $str = shift(@_);
	
	if (!defined($str))	{ return (undef); }
	if ($str =~ m/^#/)	{ return (1); }
	return (0);
}

# accepts string
# returns 1 if it is blank, or just pure white space
# returns 0 otherwise
sub is_blank {
	my $str = shift(@_);
	
	if (!defined($str))	{ return (undef); }
	if ($str !~ m/\S/)	{ return (1); }
	return (0);
}

# accepts path
# returns 1 if it's a valid ssh absolute path
# returns 0 otherwise
sub is_ssh_path {
	my $path = shift(@_);
	
	if (!defined($path))				{ return (undef); }
	
	# make sure we don't have leading/trailing spaces
	if ($path =~ m/^\s/)				{ return (undef); }
	if ($path =~ m/\s$/)				{ return (undef); }
	
	# must have user@host:[~]/path syntax for ssh
	if ($path =~ m/^.*?\@.*?:~?\/.*$/)	{ return (1); }
	
	return (0);
}

# accepts path
# returns 1 if it's a valid cwrsync server path (user@host::sharename)
# return 0 otherwise
sub is_cwrsync_path {
	my $path = shift(@_);
	if (!defined($path))		{ return (undef); }
	if ($path =~ m/^[^\/]+::/)	{ return (1); }
	
	return (0);
}

# accepts path
# returns 1 if it's a syntactically valid anonymous rsync path
# returns 0 otherwise
sub is_anon_rsync_path {
	my $path = shift(@_);
	
	if (!defined($path))			{ return (undef); }
	if ($path =~ m/^rsync:\/\/.*$/)	{ return (1); }
	
	return (0);
}

# accepts proposed list for rsync_short_args
# makes sure that rsync_short_args is in the format '-abcde'
# (not '-a -b' or '-ab c', etc)
# returns 1 if it's OK, or 0 otherwise
sub is_valid_rsync_short_args {
	my $rsync_short_args = shift(@_);
	
	if (!defined($rsync_short_args))			{ return (0); }
	
	# no blank space allowed
	if ($rsync_short_args =~ m/\s/)				{ return (0); }
	
	# first character must be a dash, followed by alphanumeric characters
	if ($rsync_short_args !~ m/^\-{1,1}\w+$/)	{ return (0); }
	
	return (1);
}

# accepts path
# returns 1 if it's a real absolute path that currently exists
# returns 0 otherwise
sub is_real_local_abs_path {
	my $path	= shift(@_);
	
	if (!defined($path)) { return (undef); }
	if (1 == is_valid_local_abs_path($path)) {
		# check for symlinks first, since they might not link to a real file
		if ((-l "$path") or (-e "$path")) {
			return (1);
		}
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a syntactically valid absolute path
# returns 0 otherwise
sub is_valid_local_abs_path {
	my $path	= shift(@_);
	
	if (!defined($path)) { return (undef); }
	if ($path =~ m/^\//) {
		if (0 == is_directory_traversal($path)) {
			 return (1);
		}
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a directory traversal attempt
# returns 0 if it's safe
sub is_directory_traversal {
	my $path = shift(@_);
	
	if (!defined($path)) { return (undef); }
	
	# /..
	if ($path =~ m/\/\.\./) { return (1); }
	
	# ../
	if ($path =~ m/\.\.\//) { return (1); }
	return (0);
}

# accepts path
# returns 1 if it's a file (doesn't have a trailing slash)
# returns 0 otherwise
sub is_file {
	my $path = shift(@_);
	
	if (!defined($path)) { return (undef); }
	
	if ($path !~ m/\/$/o) {
		return (1);
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a directory (has a trailing slash)
# returns 0 otherwise
sub is_directory {
	my $path = shift(@_);
	
	if (!defined($path)) { return (undef); }
	
	if ($path =~ m/\/$/o) {
		return (1);
	}
	
	return (0);
}

# accepts string
# removes trailing slash, returns the string
sub remove_trailing_slash {
	my $str = shift(@_);
	
	# it's not a trailing slash if it's the root filesystem
	if ($str eq '/') { return ($str); }
	# it's not a trailing slash if it's a remote root filesystem
	if ($str =~ m%:/$% ) { return ($str); }
	
	$str =~ s/\/+$//;
	
	return ($str);
}

# accepts string
# returns /. if passed /, returns input otherwise
# this is to work around a bug in some versions of rsync
sub add_slashdot_if_root {
	my $str = shift(@_);
	
	if ($str eq '/') {
		return '/.';
	}
	
	return ($str);
}

# accepts the interval (cmd) to run against
# returns nothing
# calls the appropriate subroutine, depending on whether this is the lowest interval or a higher one
# also calls preexec/postexec scripts if we're working on the lowest interval
#
sub handle_interval {
	my $cmd = shift(@_);
	
	if (!defined($cmd)) { bail('cmd not defined in handle_interval()'); }
	
	my $id_ref = get_interval_data( $cmd );
	
	my $result = 0;
	
	# make sure we don't have any leftover interval.delete directories
	# if so, loop through and delete them
	foreach my $interval_ref (@intervals) {
		my $interval = $$interval_ref{'interval'};
		
		my $is_file = 0;
		my $exists = 0;
		
		# double check that the node and snapshot_root are not the same directory
		# it would be very bad to accidentally delete the snapshot root!
		# first test for symlinks (should never be here)
		if ( -l "$config_vars{'snapshot_root'}/$interval.delete" ) {
			$exists = 1;
			$is_file = 1;
			
		# file (should never be here)
		} elsif ( -f "$config_vars{'snapshot_root'}/$interval.delete" ) {
			$exists = 1;
			$is_file = 1;
			
		# directory (this is what we're expecting)
		} elsif ( -d "$config_vars{'snapshot_root'}/$interval.delete" ) {
			$exists = 1;
			$is_file = 0;
			
		# exists, but is something else
		} elsif ( -e "$config_vars{'snapshot_root'}/$interval.delete" ) {
			bail("Invalid file type for \"$config_vars{'snapshot_root'}/$interval.delete\" in handle_interval()\n");
		}
		
		# we don't use if (-e $dir), because that fails for invalid symlinks
		if (1 == $exists) {
			# if we found any leftover directories, delete them now before they pile up and cause problems
			# this is a directory
			if (0 == $is_file) {
				display_rm_rf("$config_vars{'snapshot_root'}/$interval.delete/");
				if (0 == $test) {
					$result = rm_rf( "$config_vars{'snapshot_root'}/$interval.delete/" );
					if (0 == $result) {
						bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/$interval.delete/\")");
					}		
				}		
				
			# this is a file or symlink
			} else {
				print_cmd("rm -f $config_vars{'snapshot_root'}/$interval.delete");
				if (0 == $test) {
					$result = unlink("$config_vars{'snapshot_root'}/$interval.delete");
					if (0 == $result) {
						bail("Could not remove \"$config_vars{'snapshot_root'}/$interval.delete\" in handle_interval()");
					}
				}
			}
		}
	}
	
	# handle toggling between sync_first being enabled and disabled
	
	# link_dest is enabled
	if (1 == $link_dest) {
		
		# sync_first is enabled
		if ($config_vars{'sync_first'}) {
			
			# create the sync root if it doesn't exist (and we need it right now)
			if ($cmd eq 'sync') {
				# don't create the .sync directory, it gets created later on
			}
				
		# sync_first is disabled
		} else {
			# if the sync directory is still here after sync_first is disabled, delete it
			if ( -d "$config_vars{'snapshot_root'}/.sync" ) {
				
				display_rm_rf("$config_vars{'snapshot_root'}/.sync/");
				if (0 == $test) {
					$result = rm_rf( "$config_vars{'snapshot_root'}/.sync/" );
					if (0 == $result) {
						bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/.sync/\")");
					}
				}
			}
		}
		
	# link_dest is disabled
	} else {
		
		# sync_first is enabled
		if ($config_vars{'sync_first'}) {
			# create the sync root if it doesn't exist
			if ( ! -d "$config_vars{'snapshot_root'}/.sync" ) {
				
				# cp_al() will create the directory for us
				
				# call generic cp_al() subroutine
				my $interval_0	= "$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0";
				my $sync_dir	= "$config_vars{'snapshot_root'}/.sync";
				
				display_cp_al( "$interval_0", "$sync_dir" );
				if (0 == $test) {
					$result = cp_al( "$interval_0", "$sync_dir" );
					if (! $result) {
						bail("Error! cp_al(\"$interval_0\", \"$sync_dir\")");
					}
				}
			}
			
		# sync_first is disabled
		} else {
			# if the sync directory still exists, delete it
			if ( -d "$config_vars{'snapshot_root'}/.sync" ) {
				display_rm_rf("$config_vars{'snapshot_root'}/.sync/");
				if (0 == $test) {
					$result = rm_rf( "$config_vars{'snapshot_root'}/.sync/" );
					if (0 == $result) {
						bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/.sync/\")");
					}
				}
			}
		}
	}
	
	#
	# now that the preliminaries are out of the way, the main backups happen here
	#
	
	# backup the lowest interval (or sync content to staging area)
	# we're not sure yet going in whether we'll be doing an actual backup, or just rotating snapshots for the lowest interval
	if ((defined($$id_ref{'interval_num'}) && (0 == $$id_ref{'interval_num'})) or ($cmd eq 'sync')) {
		# if we're doing a sync, run the pre/post exec scripts, and do the backup
		if ($cmd eq 'sync') {
			exec_cmd_preexec();
			backup_lowest_interval( $id_ref );
			exec_cmd_postexec();
			
		# if we're working on the lowest interval, either run the backup and rotate the snapshots, or just rotate them
		# (depending on whether sync_first is enabled
		} else {
			if ($config_vars{'sync_first'}) {
				rotate_lowest_snapshots( $$id_ref{'interval'} );
			} else {
				exec_cmd_preexec();
				rotate_lowest_snapshots( $$id_ref{'interval'} );
				backup_lowest_interval( $id_ref );
				exec_cmd_postexec();
			}
		}
		
	# just rotate the higher intervals
	} else {
		# this is not the most frequent unit, just rotate
		rotate_higher_interval( $id_ref );
	}
	
	# if use_lazy_delete is on, delete the interval.delete directory
	# we just check for the directory, it will have been created or not depending on the value of use_lazy_delete
	if ( -d "$config_vars{'snapshot_root'}/$$id_ref{'interval'}.delete" ) {
		# this is the last thing to do here, and it can take quite a while.
		# we remove the lockfile here since this delete shouldn't block other rsnapshot jobs from running
		remove_lockfile();
		
		# start the delete
		display_rm_rf("$config_vars{'snapshot_root'}/$$id_ref{'interval'}.delete/");
		if (0 == $test) {
			my $result = rm_rf( "$config_vars{'snapshot_root'}/$$id_ref{'interval'}.delete/" );
			if (0 == $result) {
				bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/$$id_ref{'interval'}.delete/\")\n");
			}
		}
	}
}

# accepts an interval_data_ref
# acts on the interval defined as $$id_ref{'interval'} (e.g., hourly)
# this should be the smallest interval (e.g., hourly, not daily)
#
# rotates older dirs within this interval, hard links .0 to .1,
# and rsync data over to .0
#
# does not return a value, it bails instantly if there's a problem
sub backup_lowest_interval {
	my $id_ref = shift(@_);
	
	# this should never happen
	if (!defined($id_ref))				{ bail('backup_lowest_interval() expects an argument'); }
	if (!defined($$id_ref{'interval'}))	{ bail('backup_lowest_interval() expects an interval'); }
	
	# this also should never happen
	if ($$id_ref{'interval'} ne 'sync') {
		if (!defined($$id_ref{'interval_num'}) or (0 != $$id_ref{'interval_num'})) {
			bail('backup_lowest_interval() can only operate on the lowest interval');
		}
	}
	
	my $sync_dest_matches	= 0;
	my $sync_dest_dir		= undef;
	
	# if we're trying to sync only certain directories, remember the path to match
	if ($ARGV[1]) {
		$sync_dest_dir = $ARGV[1];
	}
	
	# sync live filesystem data and backup script output to $interval.0
	# loop through each backup point and backup script
	foreach my $bp_ref (@backup_points) {
		
		# rsync the given backup point into the snapshot root
		if ( defined($$bp_ref{'dest'}) && (defined($$bp_ref{'src'}) or defined($$bp_ref{'script'})) ) {
			
			# if we're doing a sync and we specified an parameter on the command line (for the destination path),
			# only sync directories matching the destination path
			if (($$id_ref{'interval'} eq 'sync') && (defined($sync_dest_dir))) {
				my $avail_path	= remove_trailing_slash( $$bp_ref{'dest'} );
				my $req_path	= remove_trailing_slash( $sync_dest_dir );
				
				# if we have a match, sync this entry
				if ($avail_path eq $req_path) {
					# rsync
					if ($$bp_ref{'src'}) {
						rsync_backup_point( $$id_ref{'interval'}, $bp_ref );
						
					# backup_script
					} elsif ($$bp_ref{'script'}) {
						exec_backup_script( $$id_ref{'interval'}, $bp_ref );
					}
					
					# ok, we got at least one dest match
					$sync_dest_matches++;
				}
				
			# this is a normal operation, either a sync or a lowest interval sync/rotate
			} else {
				# rsync
				if ($$bp_ref{'src'}) {
					rsync_backup_point( $$id_ref{'interval'}, $bp_ref );
					
				# backup_script
				} elsif ($$bp_ref{'script'}) {
					exec_backup_script( $$id_ref{'interval'}, $bp_ref );
				}
			}
			
		# this should never happen
		} else {
			bail('invalid backup point data in backup_lowest_interval()');
		}
	}
	
	if ($$id_ref{'interval'} eq 'sync') {
		if (defined($sync_dest_dir) && (0 == $sync_dest_matches)) {
			bail ("No matches found for \"$sync_dest_dir\"");
		}
	}
	
	# rollback failed backups
	rollback_failed_backups( $$id_ref{'interval'} );
	
	# update mtime on $interval.0/ to show when the snapshot completed
	touch_interval_dir( $$id_ref{'interval'} );
}

# accepts $interval
# returns nothing
#
# operates on directories in the given interval (it should be the lowest one)
# deletes the highest numbered directory in the interval, and rotates the ones below it
# if link_dest is enabled, .0 gets moved to .1
# otherwise, we do cp -al .0 .1
#
# if we encounter an error, this script will terminate the program with an error condition
#
sub rotate_lowest_snapshots {
	my $interval = shift(@_);
	
	if (!defined($interval)) { bail('interval not defined in rotate_lowest_snapshots()'); }
	
	my $id_ref = get_interval_data($interval);
	my $interval_num = $$id_ref{'interval_num'};
	my $interval_max = $$id_ref{'interval_max'};
	my $prev_interval = $$id_ref{'prev_interval'};
	my $prev_interval_max = $$id_ref{'prev_interval_max'};
	
	my $result;
	
	# remove oldest directory
	if ( (-d "$config_vars{'snapshot_root'}/$interval.$interval_max") && ($interval_max > 0) ) {
		# if use_lazy_deletes is set move the oldest directory to interval.delete
		if (1 == $use_lazy_deletes) {
			print_cmd("mv",
				"$config_vars{'snapshot_root'}/$interval.$interval_max/",
				"$config_vars{'snapshot_root'}/$interval.delete/"
			);
			
			if (0 == $test) {
				my $result = safe_rename(
					"$config_vars{'snapshot_root'}/$interval.$interval_max",
					"$config_vars{'snapshot_root'}/$interval.delete"
				);
				if (0 == $result) {
					my $errstr = '';
					$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\", \"";
					$errstr .= "$config_vars{'snapshot_root'}/$interval.delete/\")";
					bail($errstr);
				}				
			}				
			
		# otherwise the default is to delete the oldest directory for this interval
		} else {
			display_rm_rf("$config_vars{'snapshot_root'}/$interval.$interval_max/");
			
			if (0 == $test) {
				my $result = rm_rf( "$config_vars{'snapshot_root'}/$interval.$interval_max/" );
				if (0 == $result) {
					bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\")\n");
				}
			}
		}
	}
	
	# rotate the middle ones
	if ($interval_max > 0) {
		for (my $i=($interval_max-1); $i>0; $i--) {
			if ( -d "$config_vars{'snapshot_root'}/$interval.$i" ) {
				print_cmd("mv",
					"$config_vars{'snapshot_root'}/$interval.$i/ ",
					"$config_vars{'snapshot_root'}/$interval." . ($i+1) . "/"
				);
				
				if (0 == $test) {
					my $result = safe_rename(
						"$config_vars{'snapshot_root'}/$interval.$i",
						("$config_vars{'snapshot_root'}/$interval." . ($i+1))
					);
					if (0 == $result) {
						my $errstr = '';
						$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.$i/\", \"";
						$errstr .= "$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/' . "\")";
						bail($errstr);
					}
				}
			}
		}
	}
	
	# .0 and .1 require more attention, especially now with link_dest and sync_first
	
	# sync_first enabled
	if ($config_vars{'sync_first'}) {
		# we move .0 to .1 no matter what (assuming it exists)
		
		if ( -d "$config_vars{'snapshot_root'}/$interval.0/" ) {
			print_cmd("mv",
				"$config_vars{'snapshot_root'}/$interval.0/",
				"$config_vars{'snapshot_root'}/$interval.1/"
			);
			
			if (0 == $test) {
				my $result = safe_rename(
					"$config_vars{'snapshot_root'}/$interval.0",
					"$config_vars{'snapshot_root'}/$interval.1"
				);
				if (0 == $result) {
					my $errstr = '';
					$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.0/\", \"";
					$errstr .= "$config_vars{'snapshot_root'}/$interval.1/\")";
					bail($errstr);
				}				
			}				
		}				
			
		# if we're using rsync --link-dest, we need to mv sync to .0 now
		if (1 == $link_dest) {
			# mv sync .0
			
			if ( -d "$config_vars{'snapshot_root'}/.sync" ) {
				print_cmd("mv",
					"$config_vars{'snapshot_root'}/.sync/",
					"$config_vars{'snapshot_root'}/$interval.0/"
				);
				
				if (0 == $test) {
					my $result = safe_rename(
						"$config_vars{'snapshot_root'}/.sync",
						"$config_vars{'snapshot_root'}/$interval.0"
					);
					if (0 == $result) {
						my $errstr = '';
						$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/.sync/\", \"";
						$errstr .= "$config_vars{'snapshot_root'}/$interval.0/\")";
						bail($errstr);
					}				
				}				
			}	
			
		# otherwise, we hard link (except for directories, symlinks, and special files) sync to .0
		} else {
			# cp -al .sync .0
			
			if ( -d "$config_vars{'snapshot_root'}/.sync/" ) {
				display_cp_al( "$config_vars{'snapshot_root'}/.sync/", "$config_vars{'snapshot_root'}/$interval.0/" );
				if (0 == $test) {
					$result = cp_al( "$config_vars{'snapshot_root'}/.sync", "$config_vars{'snapshot_root'}/$interval.0" );
					if (! $result) {
						bail("Error! cp_al(\"$config_vars{'snapshot_root'}/.sync\", \"$config_vars{'snapshot_root'}/$interval.0\")");
					}
				}
			}
		}
		
	# sync_first disabled (make sure we have a .0 directory and someplace to put it)
	} elsif ( (-d "$config_vars{'snapshot_root'}/$interval.0") && ($interval_max > 0) ) {
		
		# if we're using rsync --link-dest, we need to mv .0 to .1 now
		if (1 == $link_dest) {
			# move .0 to .1
			
			if ( -d "$config_vars{'snapshot_root'}/$interval.0/" ) {
				print_cmd("mv $config_vars{'snapshot_root'}/$interval.0/ $config_vars{'snapshot_root'}/$interval.1/");
				
				if (0 == $test) {
					my $result = safe_rename(
						"$config_vars{'snapshot_root'}/$interval.0",
						"$config_vars{'snapshot_root'}/$interval.1"
					);
					if (0 == $result) {
						my $errstr = '';
						$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.0/\", ";
						$errstr .= "\"$config_vars{'snapshot_root'}/$interval.1/\")";
						bail($errstr);
					}
				}
			}
		# otherwise, we hard link (except for directories, symlinks, and special files) .0 over to .1
		} else {
			# call generic cp_al() subroutine
			if ( -d "$config_vars{'snapshot_root'}/$interval.0/" ) {
				display_cp_al( "$config_vars{'snapshot_root'}/$interval.0", "$config_vars{'snapshot_root'}/$interval.1" );
				if (0 == $test) {
					$result = cp_al(
						"$config_vars{'snapshot_root'}/$interval.0/",
						"$config_vars{'snapshot_root'}/$interval.1/"
					);
					if (! $result) {
						my $errstr = '';
						$errstr .= "Error! cp_al(\"$config_vars{'snapshot_root'}/$interval.0/\", ";
						$errstr .= "\"$config_vars{'snapshot_root'}/$interval.1/\")";
						bail($errstr);
					}
				}
			}
		}
	}
}

# accepts interval, backup_point_ref, ssh_rsync_args_ref
# returns no args
# runs rsync on the given backup point
# this is only run on the lowest points, not for rotations
sub rsync_backup_point {
	my $interval	= shift(@_);
	my $bp_ref		= shift(@_);
	
	# validate subroutine args
	if (!defined($interval))		{ bail('interval not defined in rsync_backup_point()'); }
	if (!defined($bp_ref))			{ bail('bp_ref not defined in rsync_backup_point()'); }
	if (!defined($$bp_ref{'src'}))	{ bail('src not defined in rsync_backup_point()'); }
	if (!defined($$bp_ref{'dest'}))	{ bail('dest not defined in rsync_backup_point()'); }
	
	# set up default args for rsync and ssh
	my $ssh_args			= $default_ssh_args;
	my $rsync_short_args	= $default_rsync_short_args;
	my $rsync_long_args		= $default_rsync_long_args;
	
	# other misc variables
	my @cmd_stack				= undef;
	my $src						= undef;
	my $result					= undef;
	my $using_relative			= 0;
	
	if (defined($$bp_ref{'src'})) {
		$src = remove_trailing_slash( "$$bp_ref{'src'}" );
		$src = add_slashdot_if_root( "$src" );
	}
	
	# if we're using link-dest later, that target depends on whether we're doing a 'sync' or a regular interval
	# if we're doing a "sync", then look at [lowest-interval].0 instead of [cur-interval].1
	my $interval_link_dest;
	my $interval_num_link_dest;
	
	# start looking for link_dest targets at interval.$start_num
	my $start_num = 1;
	
	my $sync_dir_was_present = 0;
	
	# if we're doing a sync, we'll start looking at [lowest-interval].0 for a link_dest target
	if ($interval eq 'sync') {
		$start_num = 0;
		
		# remember now if the .sync directory exists
		if ( -d "$config_vars{'snapshot_root'}/.sync" ) {
			$sync_dir_was_present = 1;
		}
	}
	
	# look for the most recent link_dest target directory
	# loop through all snapshots until we find the first match
	foreach my $i_ref (@intervals) {
		if (defined($$i_ref{'number'})) {
			for (my $i = $start_num; $i < $$i_ref{'number'}; $i++) {
				
				# once we find a valid link_dest target, the search is over
				if ( -e "$config_vars{'snapshot_root'}/$$i_ref{'interval'}.$i/$$bp_ref{'dest'}" ) {
					if (!defined($interval_link_dest) && !defined($interval_num_link_dest)) {
						$interval_link_dest		= $$i_ref{'interval'};
						$interval_num_link_dest = $i;
					}
					
					# we'll still loop through the outer loop a few more times, but the defined() check above
					# will make sure the first match wins
					last;
				}
			}
		}
	}
	
	# check to see if this destination path has already failed
	# if it's set to be rolled back, skip out now
	foreach my $rollback_point (@rollback_points) {
		if (defined($rollback_point)) {
			my $tmp_dest			= $$bp_ref{'dest'};
			my $tmp_rollback_point	= $rollback_point;
			
			# don't compare the slashes at the end
			$tmp_dest			= remove_trailing_slash($tmp_dest);
			$tmp_rollback_point	= remove_trailing_slash($tmp_rollback_point);
			
			if ("$tmp_dest" eq "$tmp_rollback_point") {
				print_warn ("$$bp_ref{'src'} skipped due to rollback plan", 2);
				syslog_warn("$$bp_ref{'src'} skipped due to rollback plan");
				return (undef);
			}
		}
	}
	
	# if the config file specified rsync or ssh args, use those instead of the hard-coded defaults in the program
	if (defined($config_vars{'rsync_short_args'})) {
		$rsync_short_args = $config_vars{'rsync_short_args'};
	}
	if (defined($config_vars{'rsync_long_args'})) {
		$rsync_long_args = $config_vars{'rsync_long_args'};
	}
	if (defined($config_vars{'ssh_args'})) {
		$ssh_args = $config_vars{'ssh_args'};
	}
	
	# extra verbose?
	if ($verbose > 3) { $rsync_short_args .= 'v'; }
	
	# split up rsync long args into an array, paying attention to
	# quoting - ideally we'd use Text::Balanced or similar, but that's
	# only relatively recently gone into core
    my @rsync_long_args_stack = split_long_args_with_quotes('rsync_long_args', $rsync_long_args);

    # create $interval.0/$$bp_ref{'dest'} or .sync/$$bp_ref{'dest'} directory if it doesn't exist
	# (this may create the .sync dir, which is why we had to check for it above)
	#
	create_backup_point_dir($interval, $bp_ref);
	
	# check opts, first unique to this backup point, and then global
	#
	# with all these checks, we try the local option first, and if
	# that isn't specified, we attempt to use the global setting as
	# a fallback plan
	#
	# we do the rsync args first since they overwrite the rsync_* variables,
	# whereas the subsequent options append to them
	#
	# RSYNC SHORT ARGS
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'rsync_short_args'}) ) {
		$rsync_short_args = $$bp_ref{'opts'}->{'rsync_short_args'};
	}
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'extra_rsync_short_args'}) ) {
		$rsync_short_args .= ' ' if ($rsync_short_args);
		$rsync_short_args .= $$bp_ref{'opts'}->{'extra_rsync_short_args'};
	}
	# RSYNC LONG ARGS
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'rsync_long_args'}) ) {
		@rsync_long_args_stack = split_long_args_with_quotes('rsync_long_args (for a backup point)', $$bp_ref{'opts'}->{'rsync_long_args'});
	}
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'extra_rsync_long_args'}) ) {
		push(@rsync_long_args_stack, split_long_args_with_quotes('extra_rsync_long_args (for a backup point)', $$bp_ref{'opts'}->{'extra_rsync_long_args'}));
	}
	# SSH ARGS
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'ssh_args'}) ) {
		$ssh_args = $$bp_ref{'opts'}->{'ssh_args'};
	}
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'extra_ssh_args'}) ) {
		$ssh_args .= ' ' . $$bp_ref{'opts'}->{'extra_ssh_args'};
	}
	# ONE_FS
	if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'one_fs'}) ) {
		if (1 == $$bp_ref{'opts'}->{'one_fs'}) {
			$rsync_short_args .= 'x';
		}
	} elsif ($one_fs) {
		$rsync_short_args .= 'x';
	}
	
	# SEE WHAT KIND OF SOURCE WE'RE DEALING WITH
	#
	# local filesystem
	if ( is_real_local_abs_path($$bp_ref{'src'}) ) {
		# no change
		
	# if this is a user@host:/path, use ssh
	} elsif ( is_ssh_path($$bp_ref{'src'}) ) {
		
		# if we have any args for SSH, add them
		if ( defined($ssh_args) ) {
			push( @rsync_long_args_stack, "--rsh=$config_vars{'cmd_ssh'} $ssh_args" );
			
		# no arguments is the default
		} else {
			push( @rsync_long_args_stack, "--rsh=$config_vars{'cmd_ssh'}" );
		}
		
	# anonymous rsync
	} elsif ( is_anon_rsync_path($$bp_ref{'src'}) ) {
		# make rsync quiet if we're not running EXTRA verbose
		if ($verbose < 4) { $rsync_short_args .= 'q'; }
		
	# cwrsync path
	} elsif ( is_cwrsync_path($$bp_ref{'src'}) ) {
		# make rsync quiet if we're not running EXTRA verbose
		if ($verbose < 4) { $rsync_short_args .= 'q'; }
		
	# this should have already been validated once, but better safe than sorry
	} else {
		bail("Could not understand source \"$$bp_ref{'src'}\" in backup_lowest_interval()");
	}
	
	# if we're using --link-dest, we'll need to specify the link-dest directory target
	# this varies depending on whether we're operating on the lowest interval or doing a 'sync'
	if (1 == $link_dest) {
		# bp_ref{'dest'} and snapshot_root have already been validated, but these might be blank
		if (defined($interval_link_dest) && defined($interval_num_link_dest)) {
			
			# make sure the directory exists
			if ( -d "$config_vars{'snapshot_root'}/$interval_link_dest.$interval_num_link_dest/$$bp_ref{'dest'}" ) {
				
				# we don't use link_dest if we already synced once to this directory
				if ($sync_dir_was_present) {
					
					# skip --link-dest, this is the second time the sync has been run, because the .sync directory already exists
					
				# default: push link_dest arguments onto cmd stack
				} else {
					push(
						@rsync_long_args_stack,
						"--link-dest=$config_vars{'snapshot_root'}/$interval_link_dest.$interval_num_link_dest/$$bp_ref{'dest'}"
					);
				}
			}
		}
	}
	
	# SPECIAL EXCEPTION:
	#   If we're using --link-dest AND the source is a file AND we have a copy from the last time,
	#   manually link interval.1/foo to interval.0/foo
	#
	#   This is necessary because --link-dest only works on directories
	#
	if (
		(1 == $link_dest) &&
		(is_file($$bp_ref{'src'})) &&
		defined($interval_link_dest) &&
		defined($interval_num_link_dest) &&
		(-f "$config_vars{'snapshot_root'}/$interval_link_dest.$interval_num_link_dest/$$bp_ref{'dest'}")
	) {
		
		# these are both "destination" paths, but we're moving from .1 to .0
		my $srcpath;
		my $destpath;
		
		$srcpath = "$config_vars{'snapshot_root'}/$interval_link_dest.$interval_num_link_dest/$$bp_ref{'dest'}";
		
		if ($interval eq 'sync') {
			$destpath = "$config_vars{'snapshot_root'}/.sync/$$bp_ref{'dest'}";
		} else {
			$destpath = "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}";
		}
		
		print_cmd("ln $srcpath $destpath");
		
		if (0 == $test) {
			$result = link( "$srcpath", "$destpath" );
			
			if (!defined($result) or (0 == $result)) {
				print_err ("link(\"$srcpath\", \"$destpath\") failed", 2);
				syslog_err("link(\"$srcpath\", \"$destpath\") failed");
			}
		}
	}
	
	# figure out if we're using the --relative flag to rsync.
	# this influences how the source paths are constructed below.
	foreach my $rsync_long_arg (@rsync_long_args_stack) {
		if (defined($rsync_long_arg)) {
			if ('--relative' eq $rsync_long_arg) {
				$using_relative = 1;
			}
		}
	}
	
	if (defined($$bp_ref{'src'})) {
		# make sure that the source path doesn't have a trailing slash if we're using the --relative flag
		# this is to work around a bug in most versions of rsync that don't properly delete entries
		# when the --relative flag is set.
		#
		if (1 == $using_relative) {
			$src = remove_trailing_slash( "$$bp_ref{'src'}" );
			$src = add_slashdot_if_root( "$src" );
			
		# no matter what, we need a source path
		} else {
			# put a trailing slash on it if we know it's a directory and it doesn't have one
			if ((-d "$$bp_ref{'src'}") && ($$bp_ref{'src'} !~ /\/$/)) {
				$src = $$bp_ref{'src'} . '/';
				
			# just use it as-is
			} else {
				$src = $$bp_ref{'src'};
			}
		}
	}
	
	# BEGIN RSYNC COMMAND ASSEMBLY
	#   take care not to introduce blank elements into the array,
	#   since it can confuse rsync, which in turn causes strange errors
	#
	@cmd_stack = ();
	#
	# rsync command
	push(@cmd_stack, $config_vars{'cmd_rsync'});
	#
	# rsync short args
	if (defined($rsync_short_args) && ($rsync_short_args ne '')) {
		push(@cmd_stack, $rsync_short_args);
	}
	#
	# rsync long args
	if (@rsync_long_args_stack && (scalar(@rsync_long_args_stack) > 0)) {
		foreach my $tmp_long_arg (@rsync_long_args_stack) {
			if (defined($tmp_long_arg) && ($tmp_long_arg ne '')) {
				push(@cmd_stack, $tmp_long_arg);
			}
		}
	}
	#
	# src
	push(@cmd_stack, "$src");
	#
	# dest
	if ($interval eq 'sync') {
		push(@cmd_stack, "$config_vars{'snapshot_root'}/.sync/$$bp_ref{'dest'}");
	} else {
		push(@cmd_stack, "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}");
	}
	#
	# END RSYNC COMMAND ASSEMBLY
	
	
	# RUN THE RSYNC COMMAND FOR THIS BACKUP POINT BASED ON THE @cmd_stack VARS
	print_cmd(@cmd_stack);
	
	if (0 == $test) {
		$result = system(@cmd_stack);
		
		# now we see if rsync ran successfully, and what to do about it
		if ($result != 0) {
			# bitmask return value
			my $retval = get_retval($result);
			
			# print warnings, and set this backup point to rollback if we're using --link-dest
			#
			handle_rsync_error($retval, $bp_ref);
		}
	}
}

# accepts the name of the argument to split, and its value
# the name is used for spitting out error messages
#
# returns a list
sub split_long_args_with_quotes {
    my($argname, $argvalue) = @_;
    my $inquotes = '';
	my @stack = ('');
	for(my $i = 0; $i < length($argvalue); $i++) {
        my $thischar = substr($argvalue, $i, 1);
	    # got whitespace and not in quotes? end this argument, start next
	    if($thischar =~ /\s/ && !$inquotes) {
		$#stack++;
	        next;
            # not in quotes and got a quote? remember that we're in quotes
            } elsif($thischar =~ /['"]/ && !$inquotes) {
	        $inquotes = $thischar;
            # in quotes and got a different quote? no nesting allowed
            } elsif($thischar =~ /['"]/ && $inquotes ne $thischar) {
	        print_err("Nested quotes not allowed in $argname", 1);
	        syslog_err("Nested quotes not allowed in $argname");
		exit(1);
        # in quotes and got a close quote
	    } elsif($thischar eq $inquotes) {
	        $inquotes = '';
            }
	    $stack[-1] .= $thischar;
	}
	if($inquotes) {
	    print_err("Unbalanced quotes in $argname", 1);
	    syslog_err("Unbalanced quotes in $argname");
	    exit(1);
	}
	return @stack;
}

# accepts rsync exit code, backup_point_ref
# prints out an appropriate error message (and logs it)
# also adds destination path to the rollback queue if link_dest is enabled
sub handle_rsync_error {
	my $retval	= shift(@_);
	my $bp_ref	= shift(@_);
	
	# shouldn't ever happen
	if (!defined($retval)) { bail('retval undefined in warn_rsync_error()'); }
	if (!defined($bp_ref)) { bail('bp_ref undefined in warn_rsync_error()'); }
	
	# a partial list of rsync exit values (from the rsync 2.6.0 man page)
	#
	# 0		Success
	# 1		Syntax or usage error
	# 23	Partial transfer due to error
	# 24	Partial transfer due to vanished source files
	#
	# if we got error 1 and we were attempting --link-dest, there's
	# a very good chance that this version of rsync is too old.
	#
	if ((1 == $link_dest) && (1 == $retval)) {
		print_err ("$config_vars{'cmd_rsync'} syntax or usage error. Does this version of rsync support --link-dest?", 2);
		syslog_err("$config_vars{'cmd_rsync'} syntax or usage error. Does this version of rsync support --link-dest?");
		
	# 23 and 24 are treated as warnings because users might be using the filesystem during the backup
	# if you want perfect backups, don't allow the source to be modified while the backups are running :)
	} elsif (23 == $retval) {
		print_warn ("Some files and/or directories in $$bp_ref{'src'} only transferred partially during rsync operation", 4);
		syslog_warn("Some files and/or directories in $$bp_ref{'src'} only transferred partially during rsync operation");
		
	} elsif (24 == $retval) {
		print_warn ("Some files and/or directories in $$bp_ref{'src'} vanished during rsync operation", 4);
		syslog_warn("Some files and/or directories in $$bp_ref{'src'} vanished during rsync operation");
		
	# other error
	} else {
		print_err ("$config_vars{'cmd_rsync'} returned $retval while processing $$bp_ref{'src'}", 2);
		syslog_err("$config_vars{'cmd_rsync'} returned $retval while processing $$bp_ref{'src'}");
		
		# set this directory to rollback if we're using link_dest
		# (since $interval.0/ will have been moved to $interval.1/ by now)
		if (1 == $link_dest) {
			push(@rollback_points, $$bp_ref{'dest'});
		}
	}
}

# accepts interval, backup_point_ref, ssh_rsync_args_ref
# returns no args
# runs rsync on the given backup point
sub exec_backup_script {
	my $interval	= shift(@_);
	my $bp_ref		= shift(@_);
	
	# validate subroutine args
	if (!defined($interval))	{ bail('interval not defined in exec_backup_script()'); }
	if (!defined($bp_ref))		{ bail('bp_ref not defined in exec_backup_script()'); }
	
	# other misc variables
	my $script	= undef;
	my $tmpdir	= undef;
	my $result	= undef;
	
	# remember what directory we started in
	my $cwd = cwd();
	
	# create $interval.0/$$bp_ref{'dest'} directory if it doesn't exist
	#
	create_backup_point_dir($interval, $bp_ref);
	
	# work in a temp dir, and make this the source for the rsync operation later
	# not having a trailing slash is a subtle distinction. it allows us to use
	# the same path if it's NOT a directory when we try to delete it.
	$tmpdir = "$config_vars{'snapshot_root'}/tmp";
	
	# remove the tmp directory if it's still there for some reason
	# (this shouldn't happen unless the program was killed prematurely, etc)
	if ( -e "$tmpdir" ) {
		display_rm_rf("$tmpdir/");
		
		if (0 == $test) {
			$result = rm_rf("$tmpdir/");
			if (0 == $result) {
				bail("Could not rm_rf(\"$tmpdir/\");");
			}
		}
	}
	
	# create the tmp directory
	print_cmd("mkdir -m 0755 -p $tmpdir/");
	
	if (0 == $test) {
		eval {
			# don't ever pass a trailing slash to mkpath
			mkpath( "$tmpdir", 0, 0755 );
		};
		if ($@) {
			bail("Unable to create \"$tmpdir/\",\nPlease make sure you have the right permissions.");
		}
	}
	
	# no more calls to mkpath here. the tmp dir needs a trailing slash
	$tmpdir .= '/';
	
	# change to the tmp directory
	print_cmd("cd $tmpdir");
	
	if (0 == $test) {
		$result = chdir("$tmpdir");
		if (0 == $result) {
			bail("Could not change directory to \"$tmpdir\"");
		}
	}
	
	# run the backup script
	#
	# the assumption here is that the backup script is written in such a way
	# that it creates files in its current working directory.
	#
	# the backup script should return 0 on success, anything else is
	# considered a failure.
	#
	print_cmd($$bp_ref{'script'});
	
	if (0 == $test) {
		$result = system( $$bp_ref{'script'} );
		if ($result != 0) {
			# bitmask return value
			my $retval = get_retval($result);
			
			print_err ("backup_script $$bp_ref{'script'} returned $retval", 2);
			syslog_err("backup_script $$bp_ref{'script'} returned $retval");
			
			# if the backup script failed, roll back to the last good data
			push(@rollback_points, $$bp_ref{'dest'} );
		}
	}
	
	# change back to the previous directory
	# (/ is a special case)
	if ('/' eq $cwd) {
		print_cmd("cd $cwd");
	} else {
		print_cmd("cd $cwd/");
	}
	
	if (0 == $test) {
		chdir($cwd);
	}
	
	# if we're using link_dest, pull back the previous files (as links) that were moved up if any.
	# this is because in this situation, .0 will always be empty, so we'll pull select things
	# from .1 back to .0 if possible. these will be used as a baseline for diff comparisons by
	# sync_if_different() down below.
	if (1 == $link_dest) {
		my $lastdir;
		my $curdir;
		
		if ($interval eq 'sync') {
			$lastdir	= "$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0/$$bp_ref{'dest'}";
			$curdir		= "$config_vars{'snapshot_root'}/.sync/$$bp_ref{'dest'}";
		} else {
			$lastdir	= "$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}";
			$curdir		= "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}";
		}
		
		# make sure we have a slash at the end
		if ($lastdir !~ m/\/$/) {
			$lastdir .= '/';
		}
		if ($curdir !~ m/\/$/) {
			$curdir .= '/';
		}
		
		# if we even have files from last time
		if ( -e "$lastdir" ) {
			
			# and we're not somehow clobbering an existing directory (shouldn't happen)
			if ( ! -e "$curdir" ) {
				
				# call generic cp_al() subroutine
				display_cp_al( "$lastdir", "$curdir" );
				if (0 == $test) {
					$result = cp_al( "$lastdir", "$curdir" );
					if (! $result) {
						print_err("Warning! cp_al(\"$lastdir\", \"$curdir/\")", 2);
					}
				}
			}
		}
	}
	
	# sync the output of the backup script into this snapshot interval
	# this is using a native function since rsync doesn't quite do what we want
	#
	# rsync doesn't work here because it sees that the timestamps are different, and
	# insists on changing things even if the files are bit for bit identical on content.
	#
	# check to see where we're syncing to
	my $target_dir;
	if ($interval eq 'sync') {
		$target_dir = "$config_vars{'snapshot_root'}/.sync/$$bp_ref{'dest'}";
	} else {
		$target_dir = "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}";
	}
	
	print_cmd("sync_if_different(\"$tmpdir\", \"$target_dir\")");
	
	if (0 == $test) {
		$result = sync_if_different("$tmpdir", "$target_dir");
		if (!defined($result)) {
			print_err("Warning! sync_if_different(\"$tmpdir\", \"$$bp_ref{'dest'}\") returned undef", 2);
		}
	}
	
	# remove the tmp directory
	if ( -e "$tmpdir" ) {
		display_rm_rf("$tmpdir");
		
		if (0 == $test) {
			$result = rm_rf("$tmpdir");
			if (0 == $result) {
				bail("Could not rm_rf(\"$tmpdir\");");
			}
		}
	}
}

# accepts and runs an arbitrary command string
# returns the exit value of the command
sub exec_cmd {
	my $cmd = shift(@_);
	
	my $return = 0;
	my $retval = 0;
	
	if (!defined($cmd) or ('' eq $cmd)) {
		print_err("Warning! Command \"$cmd\" not found", 2);
		return (undef);
	}
	
	print_cmd($cmd);
	if (0 == $test) {
		$return = system($cmd);
		if (!defined($return)) {
			print_err("Warning! exec_cmd(\"$cmd\") returned undef", 2);
		}
		
		# bitmask to get the real return value
		$retval = get_retval($return);
	}
	
	return ($retval);
}

# accepts no arguments
# returns the exit code of the defined preexec script, or undef if the command is not found
sub exec_cmd_preexec {
	my $retval = 0;
	
	# exec_cmd will only run if we're not in test mode
	if (defined($config_vars{'cmd_preexec'})) {
		$retval = exec_cmd( "$config_vars{'cmd_preexec'}" );
	}
	
	if (!defined($retval)) {
		print_err("$config_vars{'cmd_preexec'} not found", 2);
	}
	
	if (0 != $retval) {
		print_warn("cmd_preexec \"$config_vars{'cmd_preexec'}\" returned $retval", 2);
	}
	
	return ($retval);
}

# accepts no arguments
# returns the exit code of the defined preexec script, or undef if the command is not found
sub exec_cmd_postexec {
	my $retval = 0;
	
	# exec_cmd will only run if we're not in test mode
	if (defined($config_vars{'cmd_postexec'})) {
		$retval = exec_cmd( "$config_vars{'cmd_postexec'}" );
	}
	
	if (!defined($retval)) {
		print_err("$config_vars{'cmd_postexec'} not found", 2);
	}
	
	if (0 != $retval) {
		print_warn("cmd_postexec \"$config_vars{'cmd_postexec'}\" returned $retval", 2);
	}
	
	return ($retval);
}

# accepts interval, backup_point_ref
# returns nothing
# exits the program if it encounters a fatal error
sub create_backup_point_dir {
	my $interval	= shift(@_);
	my $bp_ref		= shift(@_);
	
	# validate subroutine args
	if (!defined($interval))	{ bail('interval not defined in create_interval_0()'); }
	if (!defined($bp_ref))		{ bail('bp_ref not defined in create_interval_0()'); }
	
	# create missing parent directories inside the $interval.x directory
	my @dirs = split(/\//, $$bp_ref{'dest'});
	pop(@dirs);
	
	# don't mkdir for dest unless we have to
	my $destpath;
	if ($interval eq 'sync') {
		$destpath = "$config_vars{'snapshot_root'}/.sync/" . join('/', @dirs);
	} else {
		$destpath = "$config_vars{'snapshot_root'}/$interval.0/" . join('/', @dirs);
	}
	
	# make sure we DON'T have a trailing slash (for mkpath)
	if ($destpath =~ m/\/$/) {
		$destpath = remove_trailing_slash($destpath);
	}
	
	# create the directory if it doesn't exist
	if ( ! -e "$destpath" ) {
		print_cmd("mkdir -m 0755 -p $destpath/");
		
		if (0 == $test) {
			eval {
				mkpath( "$destpath", 0, 0755 );
			};
			if ($@) {
				bail("Could not mkpath(\"$destpath/\", 0, 0755);");
			}
		}
	}
}

# accepts interval we're operating on
# returns nothing important
# rolls back failed backups, as defined in the @rollback_points array
# this is necessary if we're using link_dest, since it moves the .0 to .1 directory,
# instead of recursively copying links to the files. it also helps with failed
# backup scripts.
#
sub rollback_failed_backups {
	my $interval = shift(@_);
	
	if (!defined($interval)) { bail('interval not defined in rollback_failed_backups()'); }
	
	my $result;
	my $rsync_short_args	= $default_rsync_short_args;
	
	# handle 'sync' case
	my $interval_src;
	my $interval_dest;
	
	if ($interval eq 'sync') {
		$interval_src	= $intervals[0]->{'interval'} . '.0';
		$interval_dest	= '.sync';
	} else {
		$interval_src	= "$interval.1";
		$interval_dest	= "$interval.0";
	}
	
	# extra verbose?
	if ($verbose > 3) { $rsync_short_args .= 'v'; }
	
	# rollback failed backups (if we're using link_dest)
	foreach my $rollback_point (@rollback_points) {
		# make sure there's something to rollback from
		if ( ! -e "$config_vars{'snapshot_root'}/$interval.1/$rollback_point" ) {
			next;
		}
	
		print_warn ("Rolling back \"$rollback_point\"", 2);
		syslog_warn("Rolling back \"$rollback_point\"");
		
		# using link_dest, this probably won't happen
		# just in case, we may have to delete the old backup point from interval.0 / .sync
		if ( -e "$config_vars{'snapshot_root'}/$interval_dest/$rollback_point" ) {
			display_rm_rf("$config_vars{'snapshot_root'}/$interval_dest/$rollback_point");
			if (0 == $test) {
				$result = rm_rf( "$config_vars{'snapshot_root'}/$interval_dest/$rollback_point" );
				if (0 == $result) {
					bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/$interval_dest/$rollback_point\")\n");
				}
			}
		}
		
		# copy hard links back from .1 to .0
		# this will re-populate the .0 directory without taking up (much) additional space
		#
		# if we're doing a 'sync', then instead of .1 and .0, it's lowest.0 and .sync
		display_cp_al(
			"$config_vars{'snapshot_root'}/$interval_src/$rollback_point",
			"$config_vars{'snapshot_root'}/$interval_dest/$rollback_point"
		);
		if (0 == $test) {
			$result = cp_al(
				"$config_vars{'snapshot_root'}/$interval_src/$rollback_point",
				"$config_vars{'snapshot_root'}/$interval_dest/$rollback_point"
			);
			if (! $result) {
				my $errstr = '';
				$errstr .= "Error! cp_al(\"$config_vars{'snapshot_root'}/$interval_src/$rollback_point\", ";
				$errstr .= "\"$config_vars{'snapshot_root'}/$interval_dest/$rollback_point\")";
				bail($errstr);
			}
		}
	}
}

# accepts interval
# returns nothing
# updates mtime on $interval.0
sub touch_interval_dir {
	my $interval = shift(@_);
	
	if (!defined($interval)) { bail('interval not defined in touch_interval()'); }
	
	my $interval_dir;
	
	if ($interval eq 'sync') {
		$interval_dir = '.sync';
	} else {
		$interval_dir = $interval . '.0';
	}
	
	# update mtime of $interval.0 to reflect the time this snapshot was taken
	print_cmd("touch $config_vars{'snapshot_root'}/$interval_dir/");
	
	if (0 == $test) {
		my $result = utime(time(), time(), "$config_vars{'snapshot_root'}/$interval_dir/");
		if (0 == $result) {
			bail("Could not utime(time(), time(), \"$config_vars{'snapshot_root'}/$interval_dir/\");");
		}
	}
}

# accepts an interval_data_ref
# looks at $$id_ref{'interval'} as the interval to act on,
# and the previous interval $$id_ref{'prev_interval'} to pull up the directory from (e.g., daily, hourly)
# the interval being acted upon should not be the lowest one.
#
# rotates older dirs within this interval, and hard links
# the previous interval's highest numbered dir to this interval's .0,
#
# does not return a value, it bails instantly if there's a problem
sub rotate_higher_interval {
	my $id_ref = shift(@_);
	
	# this should never happen
	if (!defined($id_ref)) { bail('rotate_higher_interval() expects an interval_data_ref'); }
	
	# this also should never happen
	if (!defined($$id_ref{'interval_num'}) or (0 == $$id_ref{'interval_num'})) {
		bail('rotate_higher_interval() can only operate on the higher intervals');
	}
	
	# set up variables for convenience since we refer to them extensively
	my $interval			= $$id_ref{'interval'};
	my $interval_num		= $$id_ref{'interval_num'};
	my $interval_max		= $$id_ref{'interval_max'};
	my $prev_interval		= $$id_ref{'prev_interval'};
	my $prev_interval_max	= $$id_ref{'prev_interval_max'};
	
	# ROTATE DIRECTORIES
	#
	# delete the oldest one (if we're keeping more than one)
	if ( -d "$config_vars{'snapshot_root'}/$interval.$interval_max" ) {
		# if use_lazy_deletes is set move the oldest directory to interval.delete
		# otherwise preform the default behavior
		if (1 == $use_lazy_deletes) {
			print_cmd("mv ",
				"$config_vars{'snapshot_root'}/$interval.$interval_max/ ",
				"$config_vars{'snapshot_root'}/$interval.delete/"
			);
			
			if (0 == $test) {
				my $result = safe_rename(
					"$config_vars{'snapshot_root'}/$interval.$interval_max",
					("$config_vars{'snapshot_root'}/$interval.delete")
				);
				if (0 == $result) {
					my $errstr = '';
					$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\", \"";
					$errstr .= "$config_vars{'snapshot_root'}/$interval.delete/\")";
					bail($errstr);
				}				
			}				
		} else {
			display_rm_rf("$config_vars{'snapshot_root'}/$interval.$interval_max/");
			
			if (0 == $test) {
				my $result = rm_rf( "$config_vars{'snapshot_root'}/$interval.$interval_max/" );
				if (0 == $result) {
					bail("Could not rm_rf(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\");");
				}
			}
		}

	} else {
		print_msg("$config_vars{'snapshot_root'}/$interval.$interval_max not present (yet), nothing to delete", 4);
	}
	
	# rotate the middle ones
	for (my $i=($interval_max-1); $i>=0; $i--) {
		if ( -d "$config_vars{'snapshot_root'}/$interval.$i" ) {
			print_cmd(
				"mv $config_vars{'snapshot_root'}/$interval.$i/ ",
				"$config_vars{'snapshot_root'}/$interval." . ($i+1) . "/"
			);
			
			if (0 == $test) {
				my $result = safe_rename(
					"$config_vars{'snapshot_root'}/$interval.$i",
					("$config_vars{'snapshot_root'}/$interval." . ($i+1))
				);
				if (0 == $result) {
					my $errstr = '';
					$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$interval.$i/\", \"";
					$errstr .= "$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/' . "\")";
					bail($errstr);
				}
			}
		} else {
			print_msg("$config_vars{'snapshot_root'}/$interval.$i not present (yet), nothing to rotate", 4);
		}
	}
	
	# prev.max and interval.0 require more attention
	if ( -d "$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max" ) {
		my $result;
		
		# if the previous interval has at least 2 snapshots,
		# or if the previous interval isn't the smallest one,
		# move the last one up a level
		if (($prev_interval_max >= 1) or ($interval_num >= 2)) {
			# mv hourly.5 to daily.0 (or whatever intervals we're using)
			print_cmd(
				"mv $config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/ ",
				"$config_vars{'snapshot_root'}/$interval.0/"
			);
			
			if (0 == $test) {
				$result = safe_rename(
					"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max",
					"$config_vars{'snapshot_root'}/$interval.0"
				);
				if (0 == $result) {
					my $errstr = '';
					$errstr .= "Error! safe_rename(\"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/\", ";
					$errstr .= "\"$config_vars{'snapshot_root'}/$interval.0/\")";
					bail($errstr);
				}
			}
		} else {
			print_err("$prev_interval must be above 1 to keep snapshots at the $interval level", 1);
			exit(1);
		}
	} else {
		print_msg("$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max not present (yet), nothing to copy", 3);
	}
}

# accepts src, dest
# prints out the cp -al command that would be run, based on config file data
sub display_cp_al {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	
	# remove trailing slashes (for newer versions of GNU cp)
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	if (!defined($src))		{ bail('src not defined in display_cp_al()'); }
	if (!defined($dest))	{ bail('dest not defined in display_cp_al()'); }
	
	if (defined($config_vars{'cmd_cp'})) {
		print_cmd("$config_vars{'cmd_cp'} -al $src $dest");
	} else {
		print_cmd("native_cp_al(\"$src\", \"$dest\")");
	}
}

# stub subroutine
# calls either gnu_cp_al() or native_cp_al()
# returns the value directly from whichever subroutine it calls
# also prints out what's happening to the screen, if appropriate
sub cp_al {
	my $src  = shift(@_);
	my $dest = shift(@_);
	my $result = 0;
	
	# use gnu cp if we have it
	if (defined($config_vars{'cmd_cp'})) {
		$result = gnu_cp_al("$src", "$dest");
		
	# fall back to the built-in native perl replacement, followed by an rsync clean-up step
	} else {
		# native cp -al
		$result = native_cp_al("$src", "$dest");
		if (1 != $result) {
			return ($result);
		}
		
		# rsync clean-up
		$result = rsync_cleanup_after_native_cp_al("$src", "$dest");
	}
	
	return ($result);
}

# this is a wrapper to call the GNU version of "cp"
# it might fail in mysterious ways if you have a different version of "cp"
#
sub gnu_cp_al {
	my $src    = shift(@_);
	my $dest   = shift(@_);
	my $result = 0;
	my $status;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# remove trailing slashes (for newer versions of GNU cp)
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	if ( ! -d "$src" ) {
		print_err("gnu_cp_al() needs a valid directory as an argument", 2);
		return (0);
	}
	
	# make the system call to GNU cp
	$result = system( $config_vars{'cmd_cp'}, '-al', "$src", "$dest" );
	if ($result != 0) {
		$status = $result >> 8;
		print_err("$config_vars{'cmd_cp'} -al $src $dest failed (result $result, exit status $status).  Perhaps your cp does not support -al options?", 2);
		return (0);
	}
	
	return (1);
}

# This is a purpose built, native perl replacement for GNU "cp -al".
# However, it is not quite as good. it does not copy "special" files:
# block, char, fifo, or sockets.
# Never the less, it does do regular files, directories, and symlinks
# which should be enough for 95% of the normal cases.
# If you absolutely have to have snapshots of FIFOs, etc, just get GNU
# cp on your system, and specify it in the config file.
#
# Please note that more recently, this subroutine is followed up by
# an rsync clean-up step. This combination effectively removes most of
# the limitations of this technique.
#
# In the great perl tradition, this returns 1 on success, 0 on failure.
#
sub native_cp_al {
	my $src    = shift(@_);
	my $dest   = shift(@_);
	my $dh     = undef;
	my $result = 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" ) {
		print_err("native_cp_al() needs a valid source directory as an argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st)) {
		print_err("Warning! Could not lstat source dir (\"$src\") : $!", 2);
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" ) {
		# print and/or log this if necessary
		if (($verbose > 4) or ($loglevel > 4)) {
			my $cmd_string = "mkdir(\"$dest\", " . get_perms($st->mode) . ")";
		
			if ($verbose > 4) {
				print_cmd($cmd_string);
			} elsif ($loglevel > 4) {
				log_msg($cmd_string, 4);
			}
		}
		
		$result = mkdir("$dest", $st->mode);
		if ( ! $result ) {
			print_err("Warning! Could not mkdir(\"$dest\", $st->mode) : $!", 2);
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<) {
		# make sure destination is not a symlink
		if ( ! -l "$dest" ) {
			# print and/or log this if necessary
			if (($verbose > 4) or ($loglevel > 4)) {
				my $cmd_string = "safe_chown(" . $st->uid . ", " . $st->gid . ", \"$dest\")";
			
				if ($verbose > 4) {
					print_cmd($cmd_string);
				} elsif ($loglevel > 4) {
					log_msg($cmd_string, 4);
				}
			}
			
			$result = safe_chown($st->uid, $st->gid, "$dest");
			if (! $result) {
				print_err("Warning! Could not safe_chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");", 2);
				return(0);
			}
		}
	}
	
	# READ DIR CONTENTS
	$dh = new DirHandle( "$src" );
	if (defined($dh)) {
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes) {
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# make sure the node we just got is valid (this is highly unlikely to fail)
			my $st = lstat("$src/$node");
			if (!defined($st)) {
				print_err("Warning! Could not lstat source node (\"$src/$node\") : $!", 2);
				next;
			}
			
			# SYMLINK (must be tested for first, because it will also pass the file and dir tests)
			if ( -l "$src/$node" ) {
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4)) {
					my $cmd_string = "copy_symlink(\"$src/$node\", \"$dest/$node\")";
				
					if ($verbose > 4) {
						print_cmd($cmd_string);
					} elsif ($loglevel > 4) {
						log_msg($cmd_string, 4);
					}
				}
				
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result) {
					print_err("Warning! copy_symlink(\"$src/$node\", \"$dest/$node\")", 2);
					next;
				}
				
			# FILE
			} elsif ( -f "$src/$node" ) {
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4)) {
					my $cmd_string = "link(\"$src/$node\", \"$dest/$node\");";
				
					if ($verbose > 4) {
						print_cmd($cmd_string);
					} elsif ($loglevel > 4) {
						log_msg($cmd_string, 4);
					}
				}
				
				# make a hard link
				$result = link("$src/$node", "$dest/$node");
				if (! $result) {
					print_err("Warning! Could not link(\"$src/$node\", \"$dest/$node\") : $!", 2);
					next;
				}
				
			# DIRECTORY
			} elsif ( -d "$src/$node" ) {
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4)) {
					my $cmd_string = "native_cp_al(\"$src/$node\", \"$dest/$node\")";
				
					if ($verbose > 4) {
						print_cmd($cmd_string);
					} elsif ($loglevel > 4) {
						log_msg($cmd_string, 4);
					}
				}
				
				# call this subroutine recursively, to create the directory
				$result = native_cp_al("$src/$node", "$dest/$node");
				if (! $result) {
					print_err("Warning! Recursion error in native_cp_al(\"$src/$node\", \"$dest/$node\")", 2);
					next;
				}
			}
			
			## rsync_cleanup_after_native_cp_al() will take care of the files we can't handle here
			#
			## FIFO
			#} elsif ( -p "$src/$node" ) {
			#	# print_err("Warning! Ignoring FIFO $src/$node", 2);
			#	
			## SOCKET
			#} elsif ( -S "$src/$node" ) {
			#	# print_err("Warning! Ignoring socket: $src/$node", 2);
			#	
			## BLOCK DEVICE
			#} elsif ( -b "$src/$node" ) {
			#	# print_err("Warning! Ignoring special block file: $src/$node", 2);
			#	
			## CHAR DEVICE
			#} elsif ( -c "$src/$node" ) {
			#	# print_err("Warning! Ignoring special character file: $src/$node", 2);
			#}
		}
		
	} else {
		print_err("Could not open \"$src\". Do you have adequate permissions?", 2);
		return(0);
	}
	
	# close open dir handle
	if (defined($dh)) { $dh->close(); }
	undef( $dh );
	
	# UTIME DEST
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4)) {
		my $cmd_string = "utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\");";
	
		if ($verbose > 4) {
			print_cmd($cmd_string);
		} elsif ($loglevel > 4) {
			log_msg($cmd_string, 4);
		}
	}
	$result = utime($st->atime, $st->mtime, "$dest");
	if (! $result) {
		print_err("Warning! Could not set utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\") : $!", 2);
		return(0);
	}
	
	return (1);
}

# If we're using native_cp_al(), it can't transfer special files.
# So, to make sure no one misses out, this subroutine gets called every time directly
# after native_cp_al(), with the same source and destinations paths.
#
# Essentially it is running between two almost identical hard linked directory trees.
# However, it will transfer over the few (if any) special files that were otherwise
# missed.
#
# This subroutine specifies its own parameters for rsync's arguments. This is to make
# sure that nothing goes wrong, since there is not much here that should be left to
# interpretation.
#
sub rsync_cleanup_after_native_cp_al {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	
	my $local_rsync_short_args = '-a';
	my @cmd_stack = ();
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure this is directory to directory
	if (($src !~ m/\/$/o) or ($dest !~ m/\/$/o)) {
		print_err("rsync_cleanup_after_native_cp_al() only works on directories", 2);
		return (0);
	}
	
	# make sure we have a source directory
	if ( ! -d "$src" ) {
		print_err("rsync_cleanup_after_native_cp_al() needs a valid source directory as an argument", 2);
		return (0);
	}
	# make sure we have a destination directory
	if ( ! -d "$dest" ) {
		print_err("rsync_cleanup_after_native_cp_al() needs a valid destination directory as an argument", 2);
		return (0);
	}
	
	# check verbose settings and modify rsync's short args accordingly
	if ($verbose > 3) { $local_rsync_short_args .= 'v'; }
	
	# setup rsync command
	#
	# rsync
	push(@cmd_stack, $config_vars{'cmd_rsync'});
	#
	# short args
	push(@cmd_stack, $local_rsync_short_args);
	#
	# long args (not the defaults)
	push(@cmd_stack, '--delete');
	push(@cmd_stack, '--numeric-ids');
	#
	# src
	push(@cmd_stack, "$src");
	#
	# dest
	push(@cmd_stack, "$dest");
	
	print_cmd(@cmd_stack);
	
	if (0 == $test) {
		my $result = system(@cmd_stack);
		
		if ($result != 0) {
			# bitmask return value
			my $retval = get_retval($result);
			
			# a partial list of rsync exit values
			# 0		Success
			# 23	Partial transfer due to error
			# 24	Partial transfer due to vanished source files
	
			if (23 == $retval) {
				print_warn ("Some files and/or directories in $src only transferred partially during rsync_cleanup_after_native_cp_al operation", 2);
				syslog_warn("Some files and/or directories in $src only transferred partially during rsync_cleanup_after_native_cp_al operation");
			} elsif (24 == $retval) {
				print_warn ("Some files and/or directories in $src vanished during rsync_cleanup_after_native_cp_al operation", 2);
				syslog_warn("Some files and/or directories in $src vanished during rsync_cleanup_after_native_cp_al operation");

			} else {
				# other error
				bail("rsync returned error $retval in rsync_cleanup_after_native_cp_al()");
			}
		}
	}
	
	return (1);
}

# accepts a path
# displays the rm command according to the config file
sub display_rm_rf {
	my $path = shift(@_);
	
	if (!defined($path)) { bail('display_rm_rf() requires an argument'); }
	
	if (defined($config_vars{'cmd_rm'})) {
		print_cmd("$config_vars{'cmd_rm'} -rf $path");
	} else {
		print_cmd("rm -rf $path");
	}
}

# stub subroutine
# calls either cmd_rm_rf() or the native perl rmtree()
# returns 1 on success, 0 on failure
sub rm_rf {
	my $path = shift(@_);
	my $result = 0;
	
	# make sure we were passed an argument
	if (!defined($path)) { return(0); }
	
	# extra bonus safety feature!
	# confirm that whatever we're deleting must be inside the snapshot_root
	if ("$path" !~ m/^$config_vars{'snapshot_root'}/o) {
		bail("rm_rf() tried to delete something outside of $config_vars{'snapshot_root'}! Quitting now!");
	}
	
	# use the rm command if we have it
	if (defined($config_vars{'cmd_rm'})) {
		$result = cmd_rm_rf("$path");
		
	# fall back on rmtree()
	} else {
		# remove trailing slash just in case
		$path =~ s/\/$//;
		$result = rmtree("$path", 0, 0);
	}
	
	return ($result);
}

# this is a wrapper to the "rm" program, called with the "-rf" flags.
sub cmd_rm_rf {
	my $path = shift(@_);
	my $result = 0;
	
	# make sure we were passed an argument
	if (!defined($path)) { return(0); }
	
	if ( ! -e "$path" ) {
		print_err("cmd_rm_rf() needs a valid file path as an argument", 2);
		return (0);
	}
	
	# make the system call to /bin/rm
	$result = system( $config_vars{'cmd_rm'}, '-rf', "$path" );
	if ($result != 0) {
		print_err("Warning! $config_vars{'cmd_rm'} failed.", 2);
		return (0);
	}
	
	return (1);
}

# accepts no arguments
# calls the 'du' command to show rsnapshot's disk usage
# exits the program with 0 for success, 1 for failure
#
# this subroutine isn't like a lot of the "real" ones that write to logfiles, etc.
# that's why the print_* subroutines aren't used here.
#
sub show_disk_usage {
	my $intervals_str = '';
	my $cmd_du	= 'du';
	my $du_args	= '-csh';
	my $dest_path = '';
	my $retval;
	
	# first, make sure we have permission to see the snapshot root
	if ( ! -r "$config_vars{'snapshot_root'}" ) {
		print STDERR ("ERROR: Permission denied\n");
		exit(1);
	}
	
	# check for 'du' program
	if ( defined($config_vars{'cmd_du'}) ) {
		# it was specified in the config file, use that version
		$cmd_du = $config_vars{'cmd_du'};
	}
	
	# check for du args
	if ( defined($config_vars{'du_args'}) ) {
		# it this was specified in the config file, use that version
		$du_args = $config_vars{'du_args'};
	}
	
	# are we looking in subdirectories or at files?
	if (defined($ARGV[1])) {
		$dest_path = $ARGV[1];
		
		# consolidate multiple slashes
		$dest_path =~ s/\/+/\//o;
		
		if (is_directory_traversal($dest_path)) {
			print STDERR "ERROR: Directory traversal is not allowed\n";
			exit(1);
		}
		if (is_valid_local_abs_path($dest_path)) {
			print STDERR "ERROR: Full paths are not allowed\n";
			exit(1);
		}
	}
	
	# find the directories to look through, in order
	# only add them to the list if we have read permissions
	if (-r "$config_vars{'snapshot_root'}/") {
		# if we have a .sync directory, that will have the most recent files, and should be first
		if (-d "$config_vars{'snapshot_root'}/.sync") {
			if (-r "$config_vars{'snapshot_root'}/.sync") {
				$intervals_str .= "$config_vars{'snapshot_root'}/.sync ";
			}
		}
		
		# loop through the intervals, most recent to oldest
		foreach my $interval_ref (@intervals) {
			my $interval			= $$interval_ref{'interval'};
			my $max_interval_num	= $$interval_ref{'number'};
			
			for (my $i=0; $i < $max_interval_num; $i++) {
				if (-r "$config_vars{'snapshot_root'}/$interval.$i/$dest_path") {
					$intervals_str .= "$config_vars{'snapshot_root'}/$interval.$i/$dest_path ";
				}
			}
		}
	}
	chop($intervals_str);
	
	# if we can see any of the intervals, find out how much space they're taking up
	# most likely we can either see all of them or none at all
	if ('' ne $intervals_str) {
		if (defined($verbose) && ($verbose >= 3)) {
			print wrap_cmd("$cmd_du $du_args $intervals_str"), "\n\n";
		}
		
		if (0 == $test) {
			$retval = system("$cmd_du $du_args $intervals_str");
			if (0 == $retval) {
				# exit showing success
				exit(0);
			} else {
				# exit showing error
				print STDERR "Error while calling $cmd_du.\n";
				print STDERR "Please make sure this version of du supports the \"$du_args\" flags.\n";
				print STDERR "GNU du is recommended.\n";
				exit(1);
			}
		} else {
			# test was successful
			exit(0);
		}
	} else {
		print STDERR ("No files or directories found\n");
		exit(1);
	}
	
	# shouldn't happen
	exit(1);
}

# accept two args from $ARGV[1] and [2], like "daily.0" "daily.1" etc.
# stick the full snapshot_root path on the beginning, and call rsnapshot-diff with these args
# NOTE: since this is a read-only operation, we're not concerned with directory traversals and relative paths
sub show_rsnapshot_diff {
	my $cmd_rsnapshot_diff = 'rsnapshot-diff';
	
	my $retval;
	
	# this will only hold two entries, no more no less
	# paths_in holds the incoming arguments
	# args will be assigned the arguments that rsnapshot-diff will use
	#
	my @paths_in	= ();
	my @cmd_args	= ();
	
	# first, make sure we have permission to see the snapshot root
	if ( ! -r "$config_vars{'snapshot_root'}" ) {
		print STDERR ("ERROR: Permission denied\n");
		exit(1);
	}
	
	# check for rsnapshot-diff program (falling back on $PATH)
	if (defined($config_vars{'cmd_rsnapshot_diff'})) {
		$cmd_rsnapshot_diff = $config_vars{'cmd_rsnapshot_diff'};
	}
	
	# see if we even got the right number of arguments (none is OK, but 1 isn't. 2 is also OK)
	if (defined($ARGV[1]) && !defined($ARGV[2])) {
		print STDERR "Usage: rsnapshot diff [interval|dir] [interval|dir]\n";
		exit(1);
	}
	
	# make this automatically pick the two lowest intervals (or .sync dir) for comparison, as the default
	# we actually want to specify the older directory first, since rsnapshot-diff will flip them around
	# anyway based on mod times. doing it this way should make both programs consistent, and cause less
	# surprises.
	if (!defined($ARGV[1]) && !defined($ARGV[2])) {
		# sync_first is enabled, and .sync exists
		if ($config_vars{'sync_first'} && (-d "$config_vars{'snapshot_root'}/.sync/")) {
			# interval.0
			if ( -d ("$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0" ) ) {
				$cmd_args[0] = "$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0";
			}
			
			# .sync
			$cmd_args[1] = "$config_vars{'snapshot_root'}/.sync";
			
		# sync_first is not enabled, or .sync doesn't exist
		} else {
			# interval.1
			if ( -d ("$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".1" ) ) {
				$cmd_args[0] = "$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".1";
			}
			# interval.0
			if ( -d ("$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0" ) ) {
				$cmd_args[1] = "$config_vars{'snapshot_root'}/" . $intervals[0]->{'interval'} . ".0";
			}
		}
			
	# if we got some command line arguments, loop through twice and figure out what they mean
	} else {
		$paths_in[0] = $ARGV[1];	# the 1st path is the 2nd cmd line argument
		$paths_in[1] = $ARGV[2];	# the 2nd path is the 3rd cmd line argument
	
		for (my $i=0; $i<2; $i++) {
			# no interval would start with ../
			if (is_directory_traversal( "$paths_in[$i]" )) {
				$cmd_args[$i] = $paths_in[$i];
				
			# if this directory exists locally, it must be local
			} elsif ( -e "$paths_in[$i]" ) {
				$cmd_args[$i] = $paths_in[$i];
				
			# absolute path
			} elsif (is_valid_local_abs_path( "$paths_in[$i]" )) {
				$cmd_args[$i] = $paths_in[$i];
				
			# we didn't find it locally, but it's in the snapshot root
			} elsif ( -e "$config_vars{'snapshot_root'}/$paths_in[$i]" ) {
				$cmd_args[$i] = "$config_vars{'snapshot_root'}/$paths_in[$i]";
			}
		}
	}
	
	# double check to make sure the directories exists (and are directories)
	if ( (!defined($cmd_args[0]) or (!defined($cmd_args[1]))) or ((! -d "$cmd_args[0]") or (! -d "$cmd_args[1]")) ) {
		print STDERR "ERROR: Arguments must be valid intervals or directories\n";
		exit(1);
	}
	
	# remove trailing slashes from directories
	$cmd_args[0] = remove_trailing_slash($cmd_args[0]);
	$cmd_args[1] = remove_trailing_slash($cmd_args[1]);
	
	# increase verbosity (by possibly sticking a verbose flag in as the first argument)
	#
	# debug
	if ($verbose >= 5) {
		unshift(@cmd_args, '-V');
		
	} elsif ($verbose >= 4) {
		unshift(@cmd_args, '-v');
		
	# verbose
	} elsif ($verbose >= 3) {
		unshift(@cmd_args, '-vi');
	}
	
	# run rsnapshot-diff
	if (defined($verbose) && ($verbose >= 3)) {
		print wrap_cmd(("$cmd_rsnapshot_diff " . join(' ', @cmd_args))), "\n\n";
	}
	if (0 == $test) {
		$retval = system($cmd_rsnapshot_diff, @cmd_args);
		if (0 == $retval) {
			exit(0);
		} else {
			# exit showing error
			print STDERR "Error while calling $cmd_rsnapshot_diff\n";
			exit(1);
		}
	} else {
		# test was successful
		exit(0);
	}
	
	# shouldn't happen
	exit(1);
}

# This subroutine works the way I hoped rsync would under certain conditions.
# This is no fault of rsync, I just had something slightly different in mind :)
#
# This subroutine accepts two arguments, a source path and a destination path.
# It traverses both recursively.
#   If a file is in the source, but not the destination, it is hard linked into dest
#   If a file is in the destination, but not the source, it is deleted
#   If a file is in both locations and is different, dest is unlinked and src is linked to dest
#   If a file is in both locations and is the same, nothing happens
#
# What makes this different than rsync is that it looks only at the file contents to
# see if the files are different, not at the metadata such as timestamps.
# I was unable to make rsync work recursively on identical files without unlinking
# at the destination and using another inode for a new file with the exact same content.
#
# If anyone knows of a better way (that doesn't add dependencies) i'd love to hear it!
#
sub sync_if_different {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $result	= 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" ) {
		print_err("sync_if_different() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# copy everything from src to dest
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4)) {
		my $cmd_string = "sync_cp_src_dest(\"$src\", \"$dest\")";
	
		if ($verbose > 4) {
			print_cmd($cmd_string);
		} elsif ($loglevel > 4) {
			log_msg($cmd_string, 4);
		}
	}
	$result = sync_cp_src_dest("$src", "$dest");
	if ( ! $result ) {
		print_err("Warning! sync_cp_src_dest(\"$src\", \"$dest\")", 2);
		return (0);
	}
	
	# delete everything from dest that isn't in src
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4)) {
		my $cmd_string = "sync_rm_dest(\"$src\", \"$dest\")";
	
		if ($verbose > 4) {
			print_cmd($cmd_string);
		} elsif ($loglevel > 4) {
			log_msg($cmd_string, 4);
		}
	}
	$result = sync_rm_dest("$src", "$dest");
	if ( ! $result ) {
		print_err("Warning! sync_rm_dest(\"$src\", \"$dest\")", 2);
		return (0);
	}
	
	return (1);
}

# accepts src, dest
# "copies" everything from src to dest, mainly using hard links
# called only from sync_if_different()
# returns 1 on success, 0 if any failures occur
sub sync_cp_src_dest {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $dh		= undef;
	my $result	= 0;
	my $retval	= 1;	# return code for this subroutine
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" ) {
		print_err("sync_if_different() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st)) {
		print_err("Could not lstat(\"$src\")", 2);
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" ) {
		# check to make sure we don't have something here that's not a directory
		if ( -e "$dest" ) {
			$result = unlink("$dest");
			if (0 == $result) {
				print_err("Warning! Could not unlink(\"$dest\")", 2);
				return(0);
			}
		}
		
		# create the directory
		$result = mkdir("$dest", $st->mode);
		if ( ! $result ) {
			print_err("Warning! Could not mkdir(\"$dest\", $st->mode);", 2);
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<) {
		# make sure destination is not a symlink (should never happen because of unlink() above)
		if ( ! -l "$dest" ) {
			$result = safe_chown($st->uid, $st->gid, "$dest");
			if (! $result) {
				print_err("Warning! Could not safe_chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");", 2);
				return(0);
			}
		}
	}
	
	# copy anything different from src into dest
	$dh = new DirHandle( "$src" );
	if (defined($dh)) {
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes) {
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# if it's a symlink, create the link
			# this check must be done before dir and file because it will
			# pretend to be a file or a directory as well as a symlink
			if ( -l "$src/$node" ) {
				# nuke whatever is in the destination, since we'd have to recreate the symlink anyway
				# and a real file or directory will be in our way
				# symlinks pretend to be directories, which is why we check it the way that we do
				if ( -e "$dest/$node" ) {
					if ((-l "$dest/$node") or (! -d "$dest/$node")) {
						$result = unlink("$dest/$node");
						if (0 == $result) {
							print_err("Warning! Could not unlink(\"$dest/$node\")", 2);
							next;
						}
						
					# nuke the destination directory
					} else {
						$result = rm_rf("$dest/$node");
						if (0 == $result) {
							print_err("Could not rm_rf(\"$dest/$node\")", 2);
							next;
						}
					}
				}
				
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result) {
					print_err("Warning! copy_symlink(\"$src/$node\", \"$dest/$node\") failed", 2);
					return(0);
				}
				
			# if it's a directory, recurse!
			} elsif ( -d "$src/$node" ) {
				# if the destination exists but isn't a directory, delete it
				if (-e "$dest/$node") {
					# a symlink might claim to be a directory, so check for that first
					if ((-l "$dest/$node") or (! -d "$dest/$node")) {
						$result = unlink("$dest/$node");
						if (0 == $result) {
							print_err("Warning! unlink(\"$dest/$node\") failed", 2);
							next;
						}
					}
				}
				
				# ok, dest is a real directory or it isn't there yet, go recurse
				$result = sync_cp_src_dest("$src/$node", "$dest/$node");
				if (! $result) {
					print_err("Warning! Recursion error in sync_cp_src_dest(\"$src/$node\", \"$dest/$node\")", 2);
				}
				
			# if it's a file...
			} elsif ( -f "$src/$node" ) {
				# if dest is a symlink, we need to remove it first
				if ( -l "$dest/$node" ) {
					$result = unlink("$dest/$node");
					if (0 == $result) {
						print_err("Warning! unlink(\"$dest/$node\") failed", 2);
						next;
					}
				}
				
				# if dest is a directory, we need to wipe it out first
				if ( -d "$dest/$node" ) {
					$result = rm_rf("$dest/$node");
					if (0 == $result) {
						print_err("Could not rm_rf(\"$dest/$node\")", 2);
						return(0);
					}
				}
				
				# if dest (still) exists, check for differences
				if ( -e "$dest/$node" ) {
					
					# if they are different, unlink dest and link src to dest
					if (1 == file_diff("$src/$node", "$dest/$node")) {
						$result = unlink("$dest/$node");
						if (0 == $result) {
							print_err("Warning! unlink(\"$dest/$node\") failed", 2);
							next;
						}
						$result = link("$src/$node", "$dest/$node");
						if (0 == $result) {
							print_err("Warning! link(\"$src/$node\", \"$dest/$node\") failed", 2);
							next;
						}
						
					# if they are the same, just leave dest alone
					} else {
						next;
					}
					
				# ok, dest doesn't exist. just link src to dest
				} else {
					$result = link("$src/$node", "$dest/$node");
					if (0 == $result) {
						print_err("Warning! link(\"$src/$node\", \"$dest/$node\") failed", 2);
					}
				}
				
			# FIFO
			} elsif ( -p "$src/$node" ) {
				print_err("Warning! Ignoring FIFO $src/$node", 2);
				
			# SOCKET
			} elsif ( -S "$src/$node" ) {
				print_err("Warning! Ignoring socket: $src/$node", 2);
				
			# BLOCK DEVICE
			} elsif ( -b "$src/$node" ) {
				print_err("Warning! Ignoring special block file: $src/$node", 2);
				
			# CHAR DEVICE
			} elsif ( -c "$src/$node" ) {
				print_err("Warning! Ignoring special character file: $src/$node", 2);
			}
		}
	}
	# close open dir handle
	if (defined($dh)) { $dh->close(); }
	undef( $dh );
	
	return (1);
}

# accepts src, dest
# deletes everything from dest that isn't in src also
# called only from sync_if_different()
sub sync_rm_dest {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $dh		= undef;
	my $result	= 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" ) {
		print_err("sync_rm_dest() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# make sure we have a destination directory
	if ( ! -d "$dest" ) {
		print_err("sync_rm_dest() needs a valid destination directory as its second argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# delete anything from dest that isn't found in src
	$dh = new DirHandle( "$dest" );
	if (defined($dh)) {
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes) {
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# if this node isn't present in src, delete it
			if ( ! -e "$src/$node" ) {
				# file or symlink
				if ((-l "$dest/$node") or (! -d "$dest/$node")) {
					$result = unlink("$dest/$node");
					if (0 == $result) {
						print_err("Warning! Could not delete \"$dest/$node\"", 2);
						next;
					}
					
				# directory
				} else {
					$result = rm_rf("$dest/$node");
					if (0 == $result) {
						print_err("Warning! Could not delete \"$dest/$node\"", 2);
					}
				}
				next;
			}
			
			# ok, this also exists in src...
			# theoretically, sync_cp_src_dest() should have caught this already, but better safe than sorry
			# also, symlinks can pretend to be directories, so we have to check for those too
			
			# if src is a file but dest is a directory, we need to recursively remove the dest dir
			if ((-l "$src/$node") or (! -d "$src/$node")) {
				if (-d "$dest/$node") {
					$result = rm_rf("$dest/$node");
					if (0 == $result) {
						print_err("Warning! Could not delete \"$dest/$node\"", 2);
					}
				}
				
			# otherwise, if src is a directory, but dest is a file, remove the file in dest
			} elsif (-d "$src/$node") {
				if ((-l "$dest/$node") or (! -d "$dest/$node")) {
					$result = unlink("$dest/$node");
					if (0 == $result) {
						print_err("Warning! Could not delete \"$dest/$node\"", 2);
						next;
					}
				}
			}
			
			# if it's a directory in src, let's recurse into it and compare files there
			if ( -d "$src/$node" ) {
				$result = sync_rm_dest("$src/$node", "$dest/$node");
				if ( ! $result ) {
					print_err("Warning! Recursion error in sync_rm_dest(\"$src/$node\", \"$dest/$node\")", 2);
				}
			}
		}
	}
	# close open dir handle
	if (defined($dh)) { $dh->close(); }
	undef( $dh );
	
	return (1);
	
}

# accepts src, dest
# "copies" a symlink from src by recreating it in dest
# returns 1 on success, 0 on failure
sub copy_symlink {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $st		= undef;
	my $result	= undef;
	
	my $link_deref_path	= undef;
	
	# make sure it's actually a symlink
	if ( ! -l "$src" ) {
		print_err("Warning! \"$src\" not a symlink in copy_symlink()", 2);
		return (0);
	}
	
	# make sure we aren't clobbering the destination
	if ( -e "$dest" ) {
		print_err("Warning! \"$dest\" exists!", 2);
		return (0);
	}
	
	# LSTAT
	$st = lstat("$src");
	if (!defined($st)) {
		print_err("Warning! lstat(\"$src\") failed", 2);
		return (0);
	}
	
	# CREATE THE SYMLINK
	# This is done in two steps:
	# Reading/dereferencing the link, and creating a new one
	#
	# Step 1: READ THE LINK
	if (($verbose > 4) or ($loglevel > 4)) {
		my $cmd_string = "readlink(\"$src\")\n";
		
		if ($verbose > 4) {
			print_cmd($cmd_string);
		} elsif ($loglevel > 4) {
			log_msg($cmd_string, 4);
		}
	}
	$link_deref_path = readlink("$src");
	if (!defined($link_deref_path)) {
		print_err("Warning! Could not readlink(\"$src\")", 2);
		return (0);
	}
	#
	# Step 2: RECREATE THE LINK
	if (($verbose > 4) or ($loglevel > 4)) {
		my $cmd_string = "symlink(\"$link_deref_path\", \"$dest\")\n";
		
		if ($verbose > 4) {
			print_cmd($cmd_string);
		} elsif ($loglevel > 4) {
			log_msg($cmd_string, 4);
		}
	}
	$result = symlink("$link_deref_path", "$dest");
	if (0 == $result) {
		print_err("Warning! Could not symlink(\"$link_deref_path\"), \"$dest\")", 2);
		return (0);
	}
	
	# CHOWN DEST (if root)
	if (0 == $<) {
		# make sure the symlink even exists
		if ( -e "$dest" ) {
			
			# print and/or log this if necessary
			if (($verbose > 4) or ($loglevel > 4)) {
				my $cmd_string = "safe_chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");";
			
				if ($verbose > 4) {
					print_cmd($cmd_string);
				} elsif ($loglevel > 4) {
					log_msg($cmd_string, 4);
				}
			}
			
			$result = safe_chown($st->uid, $st->gid, "$dest");
			
			if (0 == $result) {
				print_err("Warning! Could not safe_chown(" . $st->uid . ", " . $st->gid . ", \"$dest\")", 2);
				return (0);
			}
		}
	}
	
	return (1);
}

# accepts a file permission number from $st->mode (e.g., 33188)
# returns a "normal" file permission number (e.g., 644)
# do the appropriate bit shifting to get a "normal" UNIX file permission mode
sub get_perms {
	my $raw_mode = shift(@_);
	
	if (!defined($raw_mode)) { return (undef); }
	
	# a lot of voodoo for just one line
	# http://www.perlmonks.org/index.pl?node_id=159906
	my $mode = sprintf("%04o", ($raw_mode & 07777));
	
	return ($mode);
}

# accepts return value from the system() command
# bitmasks it, and returns the same thing "echo $?" would from the shell
sub get_retval {
	my $retval = shift(@_);
	
	if (!defined($retval)) {
		bail('get_retval() was not passed a value');
	}
	if ($retval !~ m/^\d+$/) {
		bail("get_retval() was passed $retval, a number is required");
	}
	
	return ($retval / 256);
}

# accepts two file paths
# returns 0 if they're the same, 1 if they're different
# returns undef if one or both of the files can't be found, opened, or closed
sub file_diff   {
	my $file1	= shift(@_);
	my $file2	= shift(@_);
	my $st1		= undef;
	my $st2		= undef;
	my $buf1	= undef;
	my $buf2	= undef;
	my $result	= undef;
	
	# number of bytes to read at once
	my $BUFSIZE = 16384;
	
	# boolean file comparison flag. assume they're the same.
	my $is_different = 0;
	
	if (! -r "$file1")	{ return (undef); }
	if (! -r "$file2")	{ return (undef); }
	
	# CHECK FILE SIZES FIRST
	$st1 = lstat("$file1");
	$st2 = lstat("$file2");
	
	if (!defined($st1))	{ return (undef); }
	if (!defined($st2))	{ return (undef); }
	
	# if the files aren't even the same size, they can't possibly be the same.
	# don't waste time comparing them more intensively
	if ($st1->size != $st2->size) {
		return (1);
	}
	
	# ok, we're still here.
	# that means we have to compare files one chunk at a time
	
	# open both files
	$result = open(FILE1, "$file1");
	if (!defined($result)) {
		return (undef);
	}
	$result = open(FILE2, "$file2");
	if (!defined($result)) {
		close(FILE1);
		return (undef);
	}
	
	# compare files
	while (read(FILE1, $buf1, $BUFSIZE) && read(FILE2, $buf2, $BUFSIZE)) {
		# exit this loop as soon as possible
		if ($buf1 ne $buf2)	 {
			$is_different = 1;
			last;
		}
	}
	
	# close both files
	$result = close(FILE2);
	if (!defined($result)) {
		close(FILE1);
		return (undef);
	}
	$result = close(FILE1);
	if (!defined($result)) {
		return (undef);
	}
	
	# return our findings
	return ($is_different);
}

# accepts src, dest (file paths)
# calls rename(), forcing the mtime to be correct (to work around a bug in rare versions of the Linux 2.4 kernel)
# returns 1 on success, 0 on failure, just like the real rename() command
sub safe_rename {
	my $src		= shift(@_);
	my $dest	= shift(@_);
	
	my $st;
	my $retval;
	my $result;
	
	# validate src and dest paths
	if (!defined($src)) {
		print_err("safe_rename() needs a valid source file path as an argument", 2);
		return (0);
	}
	if (!defined($dest)) {
		print_err("safe_rename() needs a valid destination file path as an argument", 2);
		return (0);
	}
	
	# stat file before rename
	$st = stat($src);
	if (!defined($st)) {
		print_err("Could not stat() \"$src\"", 2);
		return (0);
	}
	
	# rename the file
	$retval = rename( "$src", "$dest" );
	if (1 != $retval) {
		print_err("Could not rename(\"$src\", \"$dest\")", 2);
		return (0);
	}
	
	# give it back the old mtime and atime values
	$result = utime( $st->atime, $st->mtime, "$dest" );
	if (!defined($result)) {
		print_err("Could not utime( $st->atime, $st->mtime, \"$dest\")", 2);
		return (0);
	}
	
	# if we made it this far, it must have worked
	return (1);
}

# accepts no args
# checks the config file for version number
# prints the config version to stdout
# exits the program, 0 on success, 1 on failure
# this feature is "undocumented", for use with scripts, etc
sub check_config_version {
	my $version = get_config_version();
	
	if (!defined($version)) {
		print "error\n";
		exit(1);
	}
	
	print $version, "\n";
	exit(0);
}

# accepts no args
# scans the config file for the config_version parameter
# returns the config version, or undef
sub get_config_version {
	my $result;
	my $version;
	
	# make sure the config file exists and we can read it
	if (!defined($config_file)) {
		return (undef);
	}
	if (! -r "$config_file") {
		return (undef);
	}
	
	# open the config file
	$result = open(CONFIG, "$config_file");
	if (!defined($result)) {
		return (undef);
	}
	
	# scan the config file looking for the config_version parameter
	# if we find it, exit the loop
	while (my $line = <CONFIG>) {
		chomp($line);
		
		if ($line =~ m/^config_version/o) {
			if ($line =~ m/^config_version\t+([\d\.\-\w]+)$/o) {
				$version = $1;
				last;
			} else {
				$version = 'undefined';
			}
		}
	}
	
	$result = close(CONFIG);
	if (!defined($result)) {
		return (undef);
	}
	
	if (!defined($version)) {
		$version = 'unknown';
	}
	
	return ($version);
}

# accepts no args
# exits the program, 0 on success, 1 on failure
# attempts to upgrade the rsnapshot.conf file for compatibility with this version
sub upgrade_config_file {
	my $result;
	my @lines;
	my $config_version;
	
	# check if rsync_long_args is already enabled
	my $rsync_long_args_enabled	= 0;
	
	# first, see if the file isn't already up to date
	$config_version = get_config_version();
	if (!defined($config_version)) {
		print STDERR "ERROR: Could not read config file during version check.\n";
		exit(1);
	}
	# right now 1.2 is the only valid version
	if ('1.2' eq $config_version) {
		print "$config_file file is already up to date.\n";
		exit(0);
		
	# config_version is set, but not to anything we know about
	} elsif ('unknown' eq $config_version) {
		# this is good, it means the config_version was not already set to anything
		# and is a good candidate for the upgrade
		
	} else {
		print STDERR "ERROR: config_version is set to unknown version: $config_version.\n";
		exit(1);
	}
	
	# make sure config file is present and readable
	if (!defined($config_file)) {
		print STDERR "ERROR: Config file not defined.\n";
		exit(1);
	}
	if (! -r "$config_file") {
		print STDERR "ERROR: $config_file not readable.\n";
		exit(1);
	}
	
	# read in original config file
	$result = open(CONFIG, "$config_file");
	if (!defined($result)) {
		print STDERR "ERROR: Could not open $config_file for reading.\n";
		exit(1);
	}
	@lines = <CONFIG>;
	$result = close(CONFIG);
	if (!defined($result)) {
		print STDERR "ERROR: Could not close $config_file after reading.\n";
		exit(1);
	}
	
	# see if we can find rsync_long_args, either commented out or uncommented
	foreach my $line (@lines) {
		if ($line =~ m/^rsync_long_args/o) {
			$rsync_long_args_enabled = 1;
		}
	}
	
	# back up old config file
	backup_config_file(\@lines);
	
	# found rsync_long_args enabled
	if ($rsync_long_args_enabled) {
		print "Found \"rsync_long_args\" uncommented. Attempting upgrade...\n";
		write_upgraded_config_file(\@lines, 0);
		
	# did not find rsync_long_args enabled
	} else {
		print "Could not find old \"rsync_long_args\" parameter. Attempting upgrade...\n";
		write_upgraded_config_file(\@lines, 1);
	}
	
	print "\"$config_file\" was successfully upgraded.\n";
	
	exit(0);
}

# accepts array_ref of config file lines
# exits 1 on errors
# attempts to backup rsnapshot.conf to rsnapshot.conf.backup.(#)
sub backup_config_file {
	my $lines_ref = shift(@_);
	
	my $result;
	my $backup_config_file;
	my $backup_exists = 0;
	
	if (!defined($lines_ref)) {
		print STDERR "ERROR: backup_config_file() was not passed an argument.\n";
		exit(1);
	}
	
	if (!defined($config_file)) {
		print STDERR "ERROR: Could not find config file.\n";
		exit(1);
	}
	
	$backup_config_file = "$config_file.backup";
	
	print "Backing up \"$config_file\".\n";
	
	# pick a unique name for the backup file
	if ( -e "$backup_config_file" ) {
		$backup_exists = 1;
		for (my $i=0; $i<100; $i++) {
			if ( ! -e "$backup_config_file.$i" ) {
				$backup_config_file = "$backup_config_file.$i";
				$backup_exists = 0;
				last;
			}
		}
		
		# if we couldn't write a backup file, exit with an error
		if (1 == $backup_exists) {
			print STDERR "ERROR: Refusing to overwrite $backup_config_file.\n";
			print STDERR "Please move $backup_config_file out of the way and try again.\n";
			print STDERR "$config_file has NOT been upgraded!\n";
			exit(1);
		}
	}
	
	$result = open(OUTFILE, "> $backup_config_file");
	if (!defined($result) or ($result != 1)) {
	    print STDERR "Error opening $backup_config_file for writing.\n";
	    print STDERR "$config_file has NOT been upgraded!\n";
	    exit(1);
	}
	foreach my $line (@$lines_ref) {
	    print OUTFILE $line;
	}
	$result = close(OUTFILE);
	if (!defined($result) or (1 != $result)) {
	    print STDERR "could not cleanly close $backup_config_file.\n";
	    print STDERR "$config_file has NOT been upgraded!\n";
	    exit(1);
	}
	
	print "Config file was backed up to \"$backup_config_file\".\n";
}

# accepts no args
# exits 1 on errors
# attempts to write an upgraded config file to rsnapshot.conf
sub write_upgraded_config_file {
	my $lines_ref			= shift(@_);
	my $add_rsync_long_args	= shift(@_);
	
	my $result;
	
	my $upgrade_notice = '';
	
	$upgrade_notice .= "#-----------------------------------------------------------------------------\n";
	$upgrade_notice .= "# UPGRADE NOTICE:\n";
	$upgrade_notice .= "#\n";
	$upgrade_notice .= "# This file was upgraded automatically by rsnapshot.\n";
	$upgrade_notice .= "#\n";
	$upgrade_notice .= "# The \"config_version\" parameter was added, since it is now required.\n";
	$upgrade_notice .= "#\n";
	$upgrade_notice .= "# The default value for \"rsync_long_args\" has changed in this release.\n";
	$upgrade_notice .= "# By explicitly setting it to the old default values, rsnapshot will still\n";
	$upgrade_notice .= "# behave like it did in previous versions.\n";
	$upgrade_notice .= "#\n";
	
	if (defined($add_rsync_long_args) && (1 == $add_rsync_long_args)) {
		$upgrade_notice .= "# In this file, \"rsync_long_args\" was not enabled before the upgrade,\n";
		$upgrade_notice .= "# so it has been set to the old default value.\n";
	} else {
		$upgrade_notice .= "# In this file, \"rsync_long_args\" was already enabled before the upgrade,\n";
		$upgrade_notice .= "# so it was not changed.\n";
	}
	
	$upgrade_notice .= "#\n";
	$upgrade_notice .= "# New features and improvements have been added to rsnapshot that can\n";
	$upgrade_notice .= "# only be fully utilized by making some additional changes to\n";
	$upgrade_notice .= "# \"rsync_long_args\" and your \"backup\" points. If you would like to get the\n";
	$upgrade_notice .= "# most out of rsnapshot, please read the INSTALL file that came with this\n";
	$upgrade_notice .= "# program for more information.\n";
	$upgrade_notice .= "#-----------------------------------------------------------------------------\n";
	
	if (!defined($config_file)) {
		print STDERR "ERROR: Config file not found.\n";
		exit(1);
	}
	if (! -w "$config_file") {
		print STDERR "ERROR: \"$config_file\" is not writable.\n";
		exit(1);
	}
	
	$result = open(CONFIG, "> $config_file");
	if (!defined($result)) {
		print "ERROR: Could not open \"$config_file\" for writing.\n";
		exit(1);
	}
	
	print CONFIG $upgrade_notice;
	print CONFIG "\n";
	print CONFIG "config_version\t1.2\n";
	print CONFIG "\n";
	
	if (defined($add_rsync_long_args) && (1 == $add_rsync_long_args)) {
		print CONFIG "rsync_long_args\t--delete --numeric-ids\n";
		print CONFIG "\n";
	}
	
	foreach my $line (@$lines_ref) {
		print CONFIG "$line";
	}
	
	$result = close(CONFIG);
	if (!defined($result)) {
		print STDERR "ERROR: Could not close \"$config_file\" after writing\n.";
		exit(1);
	}
}

# accepts no arguments
# dynamically loads the CPAN Lchown module, if available
# sets the global variable $have_lchown
sub use_lchown {
	if ($verbose >= 5) {
		print_msg('require Lchown', 5);
	}
	eval {
		require Lchown;
	};
	if ($@) {
		$have_lchown = 0;
		
		if ($verbose >= 5) {
			print_msg('Lchown module not found', 5);
		}
		
		return(0);
	}
	
	# if it loaded, see if this OS supports the lchown() system call
	{
		no strict 'subs';
		if (defined(Lchown) && defined(Lchown::LCHOWN_AVAILABLE)) {
			if (1 == Lchown::LCHOWN_AVAILABLE()) {
				$have_lchown = 1;
				
				if ($verbose >= 5) {
					print_msg('Lchown module loaded successfully', 5);
				}
				
				return(1);
			}
		}
	}
	
	if ($verbose >= 5) {
		print_msg("Lchown module loaded, but operating system doesn't support lchown()", 5);
	}
	
	return(0);
}

# accepts uid, gid, filepath
# uses lchown() to change ownership of the file, if possible
# returns 1 upon success (or if lchown() not present)
# returns 0 on failure
sub safe_chown {
	my $uid			= shift(@_);
	my $gid			= shift(@_);
	my $filepath	= shift(@_);
	
	my $result = undef;
	
	if (!defined($uid) or !defined($gid) or !defined($filepath)) {
		print_err("safe_chown() needs uid, gid, and filepath", 2);
		return(0);
	}
	if ( ! -e "$filepath" ) {
		print_err("safe_chown() needs a valid filepath (not \"$filepath\")", 2);
		return(0);
	}
	
	# if it's a symlink, use lchown() or skip it
	if (-l "$filepath") {
		# use Lchown
		if (1 == $have_lchown) {
			$result = Lchown::lchown($uid, $gid, "$filepath");
			if (!defined($result)) {
				return (0);
			}
			
		# we can't safely do anything here, skip it
		} else {
			raise_warning();
			
			if ($verbose > 2) {
				print_warn("Could not lchown() symlink \"$filepath\"", 2);
			} elsif ($loglevel > 2) {
				log_warn("Could not lchown() symlink \"$filepath\"", 2);
			}
			
			# we'll still return 1 at the bottom, because we did as well as we could
			# the warning raised will tell the user what happened
		}
		
	# if it's not a symlink, use chown()
	} else {
		$result = chown($uid, $gid, "$filepath");
		if (! $result) {
			return (0);
		}
	}
	
	return (1);
}

########################################
###          PERLDOC / POD           ###
########################################

=pod

=head1 NAME

rsnapshot - remote filesystem snapshot utility

=head1 SYNOPSIS

B<rsnapshot> [B<-vtxqVD>] [B<-c> cfgfile] [command] [args]

=head1 DESCRIPTION

B<rsnapshot> is a filesystem snapshot utility. It can take incremental
snapshots of local and remote filesystems for any number of machines.

Local filesystem snapshots are handled with B<rsync(1)>. Secure remote
connections are handled with rsync over B<ssh(1)>, while anonymous
rsync connections simply use an rsync server. Both remote and local
transfers depend on rsync.

B<rsnapshot> saves much more disk space than you might imagine. The amount
of space required is roughly the size of one full backup, plus a copy
of each additional file that is changed. B<rsnapshot> makes extensive
use of hard links, so if the file doesn't change, the next snapshot is
simply a hard link to the exact same file.

B<rsnapshot> will typically be invoked as root by a cron job, or series
of cron jobs. It is possible, however, to run as any arbitrary user
with an alternate configuration file.

All important options are specified in a configuration file, which is
located by default at B</etc/rsnapshot.conf>. An alternate file can be
specified on the command line. There are also additional options which
can be passed on the command line.

The command line options are as follows:

=over 4

B<-v> verbose, show shell commands being executed

B<-t> test, show shell commands that would be executed

B<-c> path to alternate config file

B<-x> one filesystem, don't cross partitions within each backup point

B<-q> quiet, suppress non-fatal warnings

B<-V> same as -v, but with more detail

B<-D> a firehose of diagnostic information

=back

=head1 CONFIGURATION

B</etc/rsnapshot.conf> is the default configuration file. All parameters
in this file must be separated by tabs. B</etc/rsnapshot.conf.default>
can be used as a reference.

It is recommended that you copy B</etc/rsnapshot.conf.default> to
B</etc/rsnapshot.conf>, and then modify B</etc/rsnapshot.conf> to suit
your needs.

Here is a list of allowed parameters:

=over 4

B<config_version>     Config file version (required). Default is 1.2

B<snapshot_root>      Local filesystem path to save all snapshots

B<include_conf>       Include another file in the configuration at this point.
 
=over 4

This is recursive, but you may need to be careful about paths when specifying
which file to include.  We check to see if the file you have specified is
readable, and will yell an error if it isn't.  We recommend using a full
path.

=back

B<no_create_root>     If set to 1, rsnapshot won't create snapshot_root directory

B<cmd_rsync>          Full path to rsync (required)

B<cmd_ssh>            Full path to ssh (optional)

B<cmd_cp>             Full path to cp  (optional, but must be GNU version)

=over 4

If you are using Linux, you should uncomment cmd_cp. If you are using a
platform which does not have GNU cp, you should leave cmd_cp commented out.

With GNU cp, rsnapshot can take care of both normal files and special
files (such as FIFOs, sockets, and block/character devices) in one pass.

If cmd_cp is disabled, rsnapshot will use its own built-in function,
native_cp_al() to backup up regular files and directories. This will
then be followed up by a separate call to rsync, to move the special
files over (assuming there are any).

=back

B<cmd_rm>             Full path to rm (optional)

B<cmd_logger>         Full path to logger (optional, for syslog support)

B<cmd_du>             Full path to du (optional, for disk usage reports)

B<cmd_rsnapshot_diff> Full path to rsnapshot-diff (optional)

B<cmd_preexec>

=over 4

Full path (plus any arguments) to preexec script (optional).
This script will run immediately before each backup operation (but not any
rotations).

=back

B<cmd_postexec>

=over 4

Full path (plus any arguments) to postexec script (optional).
This script will run immediately after each backup operation (but not any
rotations).

=back

B<interval>           [name]   [number]

=over 4

"name" refers to the name of this interval (e.g., hourly, daily). "number"
is the number of snapshots for this type of interval that will be stored.
The value of "name" will be the command passed to B<rsnapshot> to perform
this type of backup.

Example: B<interval hourly 6>

[root@localhost]# B<rsnapshot hourly>

For this example, every time this is run, the following will happen:

<snapshot_root>/hourly.5/ will be deleted, if it exists.

<snapshot_root>/hourly.{1,2,3,4} will all be rotated +1, if they exist.

<snapshot_root>/hourly.0/ will be copied to <snapshot_root>/hourly.1/
using hard links.

Each backup point (explained below) will then be rsynced to the
corresponding directories in <snapshot_root>/hourly.0/

Intervals must be specified in the config file in order, from most
frequent to least frequent. The first entry is the one which will be
synced with the backup points. The subsequent intervals (e.g., daily,
weekly, etc) simply rotate, with each higher interval pulling from the
one below it for its .0 directory.

Example:

=over 4

B<interval  hourly 6>

B<interval  daily  7>

B<interval  weekly 4>

=back

daily.0/ will be copied from hourly.5/, and weekly.0/ will be copied from daily.6/

hourly.0/ will be rsynced directly from the filesystem.

=back

B<link_dest           1>

=over 4

If your version of rsync supports --link-dest (2.5.7 or newer), you can enable
this to let rsync handle some things that GNU cp or the built-in subroutines would
otherwise do. Enabling this makes rsnapshot take a slightly more complicated code
branch, but it's the best way to support special files on non-Linux systems.

=back

B<sync_first          1>

=over 4

sync_first changes the behaviour of rsnapshot. When this is enabled, all calls
to rsnapshot with various intervals simply rotate files. All backups are handled
by calling rsnapshot with the "sync" argument. The synced files are stored in
a ".sync" directory under the snapshot_root.

This allows better recovery in the event that rsnapshot is interrupted in the
middle of a sync operation, since the sync step and rotation steps are
seperated. This also means that you can easily run "rsnapshot sync" on the
command line without fear of forcing all the other directories to rotate up.
This benefit comes at the cost of one more snapshot worth of disk space.
The default is 0 (off).

=back

B<verbose             2>

=over 4

The amount of information to print out when the program is run. Allowed values
are 1 through 5. The default is 2.

    1        Quiet            Show fatal errors only
    2        Default          Show warnings and errors
    3        Verbose          Show equivalent shell commands being executed
    4        Extra Verbose    Same as verbose, but with more detail
    5        Debug            All kinds of information

=back

B<loglevel            3>

=over 4

This number means the same thing as B<verbose> above, but it determines how
much data is written to the logfile, if one is being written.

The only thing missing from this at the higher levels is the direct output
from rsync. We hope to add support for this in a future release.

=back

B<logfile             /var/log/rsnapshot>

=over 4

Full filesystem path to the rsnapshot log file. If this is defined, a log file
will be written, with the amount of data being controlled by B<loglevel>. If
this is commented out, no log file will be written.

=back

B<include             [file-name-pattern]>

=over 4

This gets passed directly to rsync using the --include directive. This
parameter can be specified as many times as needed, with one pattern defined
per line. See the rsync(1) man page for the syntax.

=back

B<exclude             [file-name-pattern]>

=over 4

This gets passed directly to rsync using the --exclude directive. This
parameter can be specified as many times as needed, with one pattern defined
per line. See the rsync(1) man page for the syntax.

=back

B<include_file        /path/to/include/file>

=over 4

This gets passed directly to rsync using the --include-from directive. See the
rsync(1) man page for the syntax.

=back

B<exclude_file        /path/to/exclude/file>

=over 4

This gets passed directly to rsync using the --exclude-from directive. See the
rsync(1) man page for the syntax.

=back

B<rsync_short_args    -a>

=over 4

List of short arguments to pass to rsync. If not specified,
"-a" is the default. Please note that these must be all next to each other.
For example, "-az" is valid, while "-a -z" is not.

=back

B<rsync_long_args     --delete --numeric-ids --relative --delete-excluded>

=over 4

List of long arguments to pass to rsync. Beginning with rsnapshot 1.2.0, this
default has changed. In previous versions, the default values were

    --delete --numeric-ids

Starting with version 1.2.0, the default values are

    --delete --numeric-ids --relative --delete-excluded

This directly affects how the destination paths in your backup points are
constructed. Depending on what behaviour you want, you can explicitly set
the values to make the program behave like the old version or the current
version. The newer settings are recommended if you're just starting. If
you are upgrading, read the upgrade guide in the INSTALL file in the
source distribution for more information.

Quotes are permitted in rsync_long_args, eg --rsync-path="sudo /usr/bin/rsync".
You may use either single (') or double (") quotes, but nested quotes (including
mixed nested quotes) are not permitted.  Similar quoting is also allowed in
per-backup-point rsync_long_args.

=back

B<ssh_args    -p 22>

=over 4

Arguments to be passed to ssh. If not specified, the default is none.

=back

B<du_args     -csh>

=over 4

Arguments to be passed to du. If not specified, the default is -csh.
GNU du supports -csh, BSD du supports -csk, Solaris du doesn't support
-c at all. The GNU version is recommended, since it offers the most
features.

=back

B<lockfile    /var/run/rsnapshot.pid>

=over 4

Lockfile to use when rsnapshot is run. This prevents a second invocation
from clobbering the first one. If not specified, no lock file is used.
Make sure to use a directory that is not world writeable for security
reasons.  Use of a lock file is strongly recommended.

If a lockfile exists when rsnapshot starts, it will try to read the file
and stop with an error if it can't.  If it *can* read the file, it sees if
a process exists with the PID noted in the file.  If it does, rsnapshot
stops with an error message.  If there is no process with that PID, then
we assume that the lockfile is stale and ignore it.

=back

B<one_fs    1>

=over 4

Prevents rsync from crossing filesystem partitions. Setting this to a value
of 1 enables this feature. 0 turns it off. This parameter is optional.
The default is 0 (off).

=back

B<use_lazy_deletes    1>

=over 4

Changes default behavior of rsnapshot and does not initially remove the 
oldest snapshot. Instead it moves that directory to "interval".delete, and 
continues as normal. Once the backup has been completed, the lockfile will
be removed before rsnapshot starts deleting the directory.

Enabling this means that snapshots get taken sooner (since the delete doesn't
come first), and any other rsnapshot processes are allowed to start while the
final delete is happening. This benefit comes at the cost of one more
snapshot worth of disk space. The default is 0 (off).

=back

B<UPGRADE NOTICE:>

=over 4

If you have used an older version of rsnapshot, you might notice that the
destination paths on the backup points have changed. Please read the INSTALL
file in the source distribution for upgrade options.

=back

B<backup>  /etc/                       localhost/

B<backup>  root@example.com:/etc/      example.com/

B<backup>  rsync://example.com/path2/  example.com/

B<backup>  /var/                       localhost/      one_fs=1

B<backup_script>   /usr/local/bin/backup_pgsql.sh    pgsql_backup/

=over 4

Examples:

B<backup   /etc/        localhost/>

=over 4

Backs up /etc/ to <snapshot_root>/<interval>.0/localhost/etc/ using rsync on
the local filesystem

=back

B<backup   /usr/local/  localhost/>

=over 4

Backs up /usr/local/ to <snapshot_root>/<interval>.0/localhost/usr/local/
using rsync on the local filesystem

=back

B<backup   root@example.com:/etc/       example.com/>

=over 4

Backs up root@example.com:/etc/ to <snapshot_root>/<interval>.0/example.com/etc/
using rsync over ssh

=back

B<backup   root@example.com:/usr/local/ example.com/>

=over 4

Backs up root@example.com:/usr/local/ to
<snapshot_root>/<interval>.0/example.com/usr/local/ using rsync over ssh

=back

B<backup   rsync://example.com/pub/      example.com/pub/>

=over 4

Backs up rsync://example.com/pub/ to <snapshot_root>/<interval>.0/example.com/pub/
using an anonymous rsync server. Please note that unlike backing up local paths
and using rsync over ssh, rsync servers have "modules", which are top level
directories that are exported. Therefore, the module should also be specified in
the destination path, as shown in the example above (the pub/ directory at the
end).

=back

B<backup   /var/     localhost/   one_fs=1>

=over 4

This is the same as the other examples, but notice how the fourth parameter
is passed. This sets this backup point to not span filesystem partitions.
If the global one_fs has been set, this will override it locally.

=back

B<backup_script      /usr/local/bin/backup_database.sh   db_backup/>

=over 4

In this example, we specify a script or program to run. This script should simply
create files and/or directories in its current working directory. rsnapshot will
then take that output and move it into the directory specified in the third column.

Please note that whatever is in the destination directory will be completely
deleted and recreated. For this reason, rsnapshot prevents you from specifying
a destination directory for a backup_script that will clobber other backups.

So in this example, say the backup_database.sh script simply runs a command like:

=over 4

#!/bin/sh

mysqldump -uusername mydatabase > mydatabase.sql

chmod u=r,go= mydatabase.sql	# r-------- (0400)

=back

rsnapshot will take the generated "mydatabase.sql" file and move it into the
<snapshot_root>/<interval>.0/db_backup/ directory. On subsequent runs,
rsnapshot checks the differences between the files created against the
previous files. If the backup script generates the same output on the next
run, the files will be hard linked against the previous ones, and no
additional disk space will be taken up.

=back

=back

Remember that tabs must separate all elements, and that
there must be a trailing slash on the end of every directory.

A hash mark (#) on the beginning of a line is treated
as a comment.

Putting it all together (an example file):

=over 4

    # THIS IS A COMMENT, REMEMBER TABS MUST SEPARATE ALL ELEMENTS

    config_version  1.2

    snapshot_root   /.snapshots/

    cmd_rsync       /usr/bin/rsync
    cmd_ssh         /usr/bin/ssh
    #cmd_cp         /bin/cp
    cmd_rm          /bin/rm
    cmd_logger      /usr/bin/logger
    cmd_du          /usr/bin/du

    interval        hourly  6
    interval        daily   7
    interval        weekly  7
    interval        monthly 3

    backup          /etc/                     localhost/
    backup          /home/                    localhost/
    backup_script   /usr/local/bin/backup_mysql.sh  mysql_backup/

    backup          root@foo.com:/etc/        foo.com/
    backup          root@foo.com:/home/       foo.com/
    backup          root@mail.foo.com:/home/  mail.foo.com/
    backup          rsync://example.com/pub/  example.com/pub/

=back

=head1 USAGE

B<rsnapshot> can be used by any user, but for system-wide backups
you will probably want to run it as root.

Since backups usually get neglected if human intervention is
required, the preferred way is to run it from cron.

When you are first setting up your backups, you will probably
also want to run it from the command line once or twice to get
a feel for what it's doing.

Here is an example crontab entry, assuming that intervals B<hourly>,
B<daily>, B<weekly> and B<monthly> have been defined in B</etc/rsnapshot.conf>

=over 4

B<0 */4 * * *         /usr/local/bin/rsnapshot hourly>

B<50 23 * * *         /usr/local/bin/rsnapshot daily>

B<40 23 * * 6         /usr/local/bin/rsnapshot weekly>

B<30 23 1 * *         /usr/local/bin/rsnapshot monthly>

=back

This example will do the following:

=over 4

6 hourly backups a day (once every 4 hours, at 0,4,8,12,16,20)

1 daily backup every day, at 11:50PM

1 weekly backup every week, at 11:40PM, on Saturdays (6th day of week)

1 monthly backup every month, at 11:30PM on the 1st day of the month

=back

It is usually a good idea to schedule the larger intervals to run a bit before the
lower ones. For example, in the crontab above, notice that "daily" runs 10 minutes
before "hourly".  The main reason for this is that the daily rotate will
pull out the oldest hourly and make that the youngest daily (which means
that the next hourly rotate will not need to delete the oldest hourly),
which is more efficient.  A secondary reason is that it is harder to
predict how long the lowest interval will take, since it needs to actually
do an rsync of the source as well as the rotate that all intervals do.

If rsnapshot takes longer than 10 minutes to do the "daily" rotate
(which usually includes deleting the oldest daily snapshot), then you
should increase the time between the intervals.
Otherwise (assuming you have set the B<lockfile> parameter, as is recommended)
your hourly snapshot will fail sometimes because the daily still has the lock.  

Remember that these are just the times that the program runs.
To set the number of backups stored, set the B<interval> numbers in
B</etc/rsnapshot.conf>

To check the disk space used by rsnapshot, you can call it with the "du" argument.

For example:

=over 4

B<rsnapshot du>

=back

This will show you exactly how much disk space is taken up in the snapshot root. This
feature requires the UNIX B<du> command to be installed on your system, for it to
support the "-csh" command line arguments, and to be in your path. You can also
override your path settings and the flags passed to du using the cmd_du and du_args
parameters.

It is also possible to pass a relative file path as a second argument, to get a report
on a particular file or subdirectory.

=over 4

B<rsnapshot du localhost/home/>

=back

The GNU version of "du" is preferred. The BSD version works well also, but does
not support the -h flag (use -k instead, to see the totals in kilobytes). Other
versions of "du", such as Solaris, may not work at all.

To check the differences between two directories, call rsnapshot with the "diff"
argument, followed by two intervals or directory paths.

For example:

=over 4

B<rsnapshot diff daily.0 daily.1>

B<rsnapshot diff daily.0/localhost/etc daily.1/localhost/etc>

B<rsnapshot diff /.snapshots/daily.0 /.snapshots/daily.1>

=back

This will call the rsnapshot-diff program, which will scan both directories
looking for differences (based on hard links).

B<rsnapshot sync>

=over 4

When B<sync_first> is enabled, rsnapshot must first be called with the B<sync>
argument, followed by the other usual cron entries. The sync should happen as
the lowest, most frequent interval, and right before. For example:

=over 4

B<0 */4 * * *         /usr/local/bin/rsnapshot sync && /usr/local/bin/rsnapshot hourly>

B<50 23 * * *         /usr/local/bin/rsnapshot daily>

B<40 23 1,8,15,22 * * /usr/local/bin/rsnapshot weekly>

B<30 23 1 * *         /usr/local/bin/rsnapshot monthly>

=back

The sync operation simply runs rsync and all backup scripts. In this scenario, all
interval calls simply rotate directories, even the lowest interval.

=back

B<rsnapshot sync [dest]>

=over 4

When B<sync_first> is enabled, all sync behaviour happens during an additional
sync step (see above). When using the sync argument, it is also possible to specify
a backup point destination as an optional parameter. If this is done, only backup
points sharing that destination path will be synced.

For example, let's say that example.com is a destination path shared by one or more
of your backup points.

=over 4

rsnapshot sync example.com

=back

This command will only sync the files that normally get backed up into example.com.
It will NOT get any other backup points with slightly different values (like
example.com/etc/, for example). In order to sync example.com/etc, you would need to
run rsnapshot again, using example.com/etc as the optional parameter.

=back

=head1 EXIT VALUES

=over 4

B<0>  All operations completed successfully

B<1>  A fatal error occurred

B<2>  Some warnings occurred, but the backup still finished

=back

=head1 FILES

/etc/rsnapshot.conf

=head1 SEE ALSO

rsync(1), ssh(1), logger(1), sshd(1), ssh-keygen(1), perl(1), cp(1), du(1), crontab(1)

=head1 DIAGNOSTICS

Use the B<-t> flag to see what commands would have been executed. This will show
you the commands rsnapshot would try to run. There are a few minor differences
(for example, not showing an attempt to remove the lockfile because it wasn't
really created in the test), but should give you a very good idea what will happen.

Using the B<-v>, B<-V>, and B<-D> flags will print increasingly more information
to STDOUT.

Make sure you don't have spaces in the config file that you think are actually tabs.

Much other weird behavior can probably be attributed to plain old file system
permissions and ssh authentication issues.

=head1 BUGS

Please report bugs (and other comments) to the rsnapshot-discuss mailing list:

B<http://lists.sourceforge.net/lists/listinfo/rsnapshot-discuss>

=head1 NOTES

Make sure your /etc/rsnapshot.conf file has all elements separated by tabs.
See /etc/rsnapshot.conf.default for a working example file.

Make sure you put a trailing slash on the end of all directory references.
If you don't, you may have extra directories created in your snapshots.
For more information on how the trailing slash is handled, see the
B<rsync(1)> manpage.

Make sure to make the snapshot directory chmod 700 and owned by root
(assuming backups are made by the root user). If the snapshot directory
is readable by other users, they will be able to modify the snapshots
containing their files, thus destroying the integrity of the snapshots.

If you would like regular users to be able to restore their own backups,
there are a number of ways this can be accomplished. One such scenario
would be:

Set B<snapshot_root> to B</.private/.snapshots> in B</etc/rsnapshot.conf>

Set the file permissions on these directories as follows:

=over 4

drwx------    /.private

drwxr-xr-x    /.private/.snapshots

=back

Export the /.private/.snapshots directory over read-only NFS, a read-only
Samba share, etc.

See the rsnapshot HOWTO for more information on making backups
accessible to non-privileged users.

For ssh to work unattended through cron, you will probably want to use
public key logins. Create an ssh key with no passphrase for root, and
install the public key on each machine you want to backup. If you are
backing up system files from remote machines, this probably means
unattended root logins. Another possibility is to create a second user
on the machine just for backups. Give the user a different name such
as "rsnapshot", but keep the UID and GID set to 0, to give root
privileges. However, make logins more restrictive, either through ssh
configuration, or using an alternate shell.

BE CAREFUL! If the private key is obtained by an attacker, they will
have free run of all the systems involved. If you are unclear on how
to do this, see B<ssh(1)>, B<sshd(1)>, and B<ssh-keygen(1)>.

Backup scripts are run as the same user that rsnapshot is running as.
Typically this is root. Make sure that all of your backup scripts are
only writable by root, and that they don't call any other programs
that aren't owned by root. If you fail to do this, anyone who can
write to the backup script or any program it calls can fully take
over the machine. Of course, this is not a situation unique to
rsnapshot.

By default, rsync transfers are done using the --numeric-ids option.
This means that user names and group names are ignored during transfers,
but the UID/GID information is kept intact. The assumption is that the
backups will be restored in the same environment they came from. Without
this option, restoring backups for multiple heterogeneous servers would
be unmanageable. If you are archiving snapshots with GNU tar, you may
want to use the --numeric-owner parameter. Also, keep a copy of the
archived system's /etc/passwd and /etc/group files handy for the UID/GID
to name mapping.

If you remove backup points in the config file, the previously archived
files under those points will permanently stay in the snapshots directory
unless you remove the files yourself. If you want to conserve disk space,
you will need to go into the <snapshot_root> directory and manually
remove the files from the smallest interval's ".0" directory.

For example, if you were previously backing up /home/ with a destination
of localhost/, and hourly is your smallest interval, you would need to do
the following to reclaim that disk space:

=over 4

rm -rf <snapshot_root>/hourly.0/localhost/home/

=back

Please note that the other snapshots previously made of /home/ will still
be using that disk space, but since the files are flushed out of hourly.0/,
they will no longer be copied to the subsequent directories, and will thus
be removed in due time as the rotations happen.

=head1 AUTHORS

Mike Rubel - B<http://www.mikerubel.org/computers/rsync_snapshots/>

=over 4

=item -
Created the original shell scripts on which this project is based

=back

Nathan Rosenquist (B<nathan@rsnapshot.org>)

=over 4

=item -
Primary author and previous maintainer of rsnapshot.

=back

David Cantrell (B<david@cantrell.org.uk>)

=over 4

=item -
Current co-maintainer of rsnapshot

=item -
Wrote the rsnapshot-diff utility

=back

David Keegel <djk@cybersource.com.au>

=over 4

=item -
Co-maintainer, with responsibility for release management since 1.2.9

=item -
Fixed race condition in lock file creation, improved error reporting

=item -
Allowed remote ssh directory paths starting with "~/" as well as "/"

=item -
Fixed a number of other bugs and buglets

=back

Carl Wilhelm Soderstrom B<(chrome@real-time.com)>

=over 4

=item -
Created the RPM .spec file which allowed the RPM package to be built, among
other things.

=back

Ted Zlatanov (B<tzz@lifelogs.com>)

=over 4

=item -
Added the one_fs feature, autoconf support, good advice, and much more.

=back

Ralf van Dooren (B<r.vdooren@snow.nl>)

=over 4

=item -
Added and maintains the rsnapshot entry in the FreeBSD ports tree.

=back

SlapAyoda

=over 4

=item -
Provided access to his computer museum for software testing.

=back

Carl Boe (B<boe@demog.berkeley.edu>)

=over 4

=item -
Found several subtle bugs and provided fixes for them.

=back

Shane Leibling (B<shane@cryptio.net>)

=over 4

=item -
Fixed a compatibility bug in utils/backup_smb_share.sh

=back

Christoph Wegscheider (B<christoph.wegscheider@wegi.net>)

=over 4

=item -
Added (and previously maintained) the Debian rsnapshot package.

=back

Bharat Mediratta (B<bharat@menalto.com>)

=over 4

=item -
Improved the exclusion rules to avoid backing up the snapshot root (among
other things).

=back

Peter Palfrader (B<weasel@debian.org>)

=over 4

=item -
Enhanced error reporting to include command line options.

=back

Nicolas Kaiser (B<nikai@nikai.net>)

=over 4

=item -
Fixed typos in program and man page

=back

Chris Petersen - (B<http://www.forevermore.net/>)

=over 4

Added cwrsync permanent-share support

=back

Robert Jackson (B<RobertJ@promedicalinc.com>)

=over 4

Added use_lazy_deletes feature

=back

Justin Grote (B<justin@grote.name>)

=over 4

Improved rsync error reporting code

=back

Anthony Ettinger (B<apwebdesign@yahoo.com>)

=over 4

Wrote the utils/mysqlbackup.pl script

=back

Sherman Boyd

=over 4

Wrote utils/random_file_verify.sh script

=back

William Bear (B<bear@umn.edu>)

=over 4

Wrote the utils/rsnapreport.pl script (pretty summary of rsync stats)

=back

Eric Anderson (B<anderson@centtech.com>)

=over 4

Improvements to utils/rsnapreport.pl.

=back

Alan Batie (B<alan@batie.org>)

=over 4

Bug fixes for include_conf

=back

=head1 COPYRIGHT

Copyright (C) 2003-2005 Nathan Rosenquist

Portions Copyright (C) 2002-2006 Mike Rubel, Carl Wilhelm Soderstrom,
Ted Zlatanov, Carl Boe, Shane Liebling, Bharat Mediratta, Peter Palfrader,
Nicolas Kaiser, David Cantrell, Chris Petersen, Robert Jackson, Justin Grote,
David Keegel, Alan Batie

This man page is distributed under the same license as rsnapshot:
the GPL (see below).

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA

=cut

