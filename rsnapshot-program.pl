#!/usr/bin/perl -w

########################################################################
#                                                                      #
# rsnapshot                                                            #
# by Nathan Rosenquist                                                 #
#                                                                      #
# Based on code originally by Mike Rubel                               #
# http://www.mikerubel.org/computers/rsync_snapshots/                  #
#                                                                      #
# The official rsnapshot website is located at                         #
# http://www.rsnapshot.org/                                            #
#                                                                      #
# rsnapshot comes with ABSOLUTELY NO WARRANTY.  This is free software, #
# and you are welcome to redistribute it under certain conditions.     #
# See the GNU General Public License for details.                      #
#                                                                      #
########################################################################

# tabstops are set to 4 spaces
# in vi, do: set ts=4 sw=4

########################
### STANDARD MODULES ###
########################

require 5.004;
use strict;
use DirHandle;
use Cwd;				# cwd()
use Getopt::Std;		# getopt(), getopts()
use File::Path;			# mkpath(), rmtree()
use File::stat;			# lstat()
use POSIX qw(locale_h);	# setlocale()

################################
### DECLARE GLOBAL VARIABLES ###
################################

# version of rsnapshot
my $VERSION = '1.1.6';

# exactly how the program was called, with all arguments
my $run_string = "$0 " . join(' ', @ARGV);

# default configuration file
my $config_file;

# hash to hold variables from the configuration file
my %config_vars;

# array of hash_refs containing the destination backup point
# and either a source dir or a script to run
my @backup_points;

# array of backup points to rollback, in the event of failure
# (when using link_dest)
my @rollback_points;

# "intervals" are user defined time periods (i.e. hourly, daily)
# this array holds hash_refs containing the name of the interval,
# and the number of snapshots to keep of it
my @intervals;

# which of the intervals are we operating on?
# if we defined hourly, daily, weekly ... hourly = 0, daily = 1, weekly = 2
my $interval_num;

# the highest possible number for the current interval context
# if we are working on hourly, and hourly is set to 6, this would be
# equal to 5 (since we start at 0)
my $interval_max;

# this is the name of the previous interval, in relation to the one we're
# working on. i.e. if we're operating on weekly, this should be "daily"
my $prev_interval;

# same as $interval_max, except for the previous interval.
# this is used to determine which of the previous snapshots to pull from
# i.e. cp -al hourly.$prev_interval_max/ daily.0/
my $prev_interval_max;

# command line flags from getopt
my %opts;

# command or interval to execute (first cmd line arg)
my $cmd;

# assume we don't have any of these programs
my $have_gnu_cp	= 0;
my $have_rm		= 0;
my $have_rsync	= 0;
my $have_ssh	= 0;

# flags that change the outcome of the program, and configurable by both cmd line and config flags
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
my $verbose				= undef;
my $default_verbose		= 2;

# same as verbose above, but for logging
my $loglevel			= undef;
my $default_loglevel	= 3;

# global defaults for external programs
my $global_default_rsync_short_args	= '-a';
my $global_default_rsync_long_args	= '--delete --numeric-ids';
my $global_default_ssh_args			= undef;

# pre-buffer the include/exclude parameter flags
my $rsync_include_args		= undef;
my $rsync_include_file_args	= undef;

# exit code for rsnapshot
my $exit_code = 0;

# assume the config file is valid
my $config_perfect = 1;

# display variable for "rm". this gets set to the full path if we have the command
my $display_rm = 'rm';

# remember what directory we started in
my $cwd = cwd();

###############
### SIGNALS ###
###############

# shut down gracefully if necessary
$SIG{'HUP'}		= 'IGNORE';
$SIG{'INT'}		= sub { bail('rsnapshot was sent INT signal... cleaning up'); };
$SIG{'QUIT'}	= sub { bail('rsnapshot was sent QUIT signal... cleaning up'); };
$SIG{'ABRT'}	= sub { bail('rsnapshot was sent ABRT signal... cleaning up'); };
$SIG{'TERM'}	= sub { bail('rsnapshot was sent TERM signal... cleaning up'); };

##############################
### CORE PROGRAM STRUCTURE ###
##############################

# figure out the path to the default config file
$config_file = get_config_file();

# get command line options
# (this can override $config_file, if the -c flag is used on the command line)
get_cmd_line_opts();

# if we were called with no arguments, show the usage information
if (!defined($cmd) or ((! $cmd) && ('0' ne $cmd)) )	{
	show_usage();
	exit(1);
}

# if we need to run a command that doesn't require the config file, do it now (and exit)
if ($cmd eq 'help')	{
	show_help();
	exit(0);
}
if ($cmd eq 'version')	{
	print "rsnapshot $VERSION\n";
	exit(0);
}
if ($cmd eq 'version_only')	{
	print $VERSION;
	exit(0);
}

# if we're just doing a configtest, set that flag
if ($cmd eq 'configtest')	{
	$do_configtest = 1;
}

# parse config file (if it exists)
if (defined($config_file) && (-f "$config_file") && (-r "$config_file"))	{
	# if there is a problem, this subroutine will exit the program and notify the user of the error
	parse_config_file();
	
# no config file found
} else	{
	# warn user and exit the program
	exit_no_config_file();
}

# if we're just doing a configtest, exit here with the results
if (1 == $do_configtest)	{
	exit_configtest();
}

# if we're just using "du" to check the disk space, do it now
# this is orphaned down here because it needs to know the contents of the config file
if ($cmd eq 'du')	{
	# this will exit the program with an appropriate exit code either way
	show_disk_usage();
}

#
# IF WE GOT THIS FAR, PREPARE TO RUN A BACKUP
#

# figure out which interval we're working on
get_current_interval();

# make sure the user is requesting to run on an interval we understand
check_valid_interval($cmd);

# log the beginning of this run
log_msg("$run_string: started", 2);

# this is reported to fix some semi-obscure problems with rmtree()
set_posix_locale();

# if we're using a lockfile, try to add it (the program will bail if one exists)
add_lockfile();

# create snapshot_root if it doesn't exist (and no_create_root != 1)
create_snapshot_root();

# actually run the backup job
if (0 == $interval_num)	{
	# if this is the most frequent interval, actually do the backups here
	backup_lowest_interval($cmd);
	
} else	{
	# this is not the most frequent unit, just rotate
	rotate_higher_interval($cmd, $prev_interval);
}

# if we have a lockfile, remove it
remove_lockfile();

# if we got this far, the program is done running
# write to the log and syslog with the status of the outcome
#
exit_with_status();

###################
### SUBROUTINES ###
###################

# concise usage information
# runs when rsnapshot is called with no arguments
sub show_usage	{
	print "rsnapshot $VERSION\n";
	print "Usage: rsnapshot [-vtxqVD] [-c cfgfile] <interval>|configtest|du|help|version\n";
	print "Type \"rsnapshot help\" or \"man rsnapshot\" for more information.\n";
}

# extended usage information
# runs when rsnapshot is called with "help" as an argument
sub show_help	{
	show_usage();
	
	print<<HERE;

rsnapshot is a filesystem snapshot utility. It can take incremental
snapshots of local and remote filesystems for any number of machines.

rsnapshot comes with ABSOLUTELY NO WARRANTY.  This is free software,
and you are welcome to redistribute it under certain conditions.
See the GNU General Public License for details.

Options:
    -v verbose       - show equivalent shell commands being executed
    -t test          - show equivalent shell commands that would be executed
    -c [file]        - specify alternate config file (-c /path/to/file)
    -x one_fs        - don't cross filesystems (same as -x option to rsync)
    -q quiet         - supress non-fatal warnings
    -V extra verbose - same as -v, but show rsync output as well
    -D debug         - a firehose of diagnostic information
HERE
}

# accepts no arguments
# returns the path to the default config file
#
# this program works both "as-is" in the source tree, and when it has been parsed by autoconf for installation
# the variables with "@" symbols on both sides get replaced during ./configure
# this subroutine returns the correct path to the default config file
#
sub get_config_file	{
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
	if ($autoconf_sysconfdir eq '${prefix}/etc')	{
		$default_config_file = "$autoconf_prefix/etc/rsnapshot.conf";
		
	# if --sysconfdir was set explicitly at ./configure, overriding the --prefix setting
	} elsif ($autoconf_sysconfdir ne ('@' . 'sysconfdir' . '@'))	{
		$default_config_file = "$autoconf_sysconfdir/rsnapshot.conf";
	}
	
	return ($default_config_file);
}

# accepts no args
# returns no args
# sets some global variables
sub get_cmd_line_opts	{
	# GET COMMAND LINE OPTIONS
	getopt('c', \%opts);
	getopts('vVtqx', \%opts);
	$cmd = $ARGV[0];
	
	# alternate config file
	if (defined($opts{'c'}))	{
		$config_file = $opts{'c'};
	}
	
	# test? (just show what WOULD be done)
	if (defined($opts{'t'}))	{
		$test = 1;
		$verbose = 3;
	}
	
	# quiet?
	if (defined($opts{'q'}))	{
		$verbose = 1;
	}
	
	# verbose (or extra verbose)?
	if (defined($opts{'v'}))	{
		$verbose = 3;
	}
	if (defined($opts{'V'}))	{
		$verbose = 4;
	}
	
	# debug
	if (defined($opts{'D'}))	{
		$verbose = 5;
	}
	
	# one file system? (don't span partitions with rsync)
	if (defined($opts{'x'}))	{
		$one_fs = 1;
	}
}

# accepts no arguments
# returns no value
# this subroutine parses the config file (rsnapshot.conf)
#
# it used to be in the main program and not a subroutine, perhaps we'll make it accept/return some args later
#
sub parse_config_file	{
	# count the lines in the config file, so the user can pinpoint errors more precisely
	my $file_line_num = 0;
	
	open(CONFIG, $config_file)
		or bail("Could not open config file \"$config_file\"\nAre you sure you have permission?");
	
	while (my $line = <CONFIG>)	{
		chomp($line);
		
		# count line numbers
		$file_line_num++;
		
		# assume the line is formatted incorrectly
		my $line_syntax_ok = 0;
		
		# ignore comments
		if (is_comment($line))	{ next; }
		
		# ignore blank lines
		if (is_blank($line))	{ next; }
		
		# parse line
		my ($var, $value, $value2, $value3) = split(/\t+/, $line, 4);
		
		# warn about entries we don't understand, and immediately prevent the
		# program from running or parsing anything else
		if (!defined($var) or !defined($value))	{
			config_err($file_line_num, $line);
			next;
		}
		
		# SNAPSHOT_ROOT
		if ($var eq 'snapshot_root')	{
			# make sure this is a full path
			if (0 == is_valid_local_abs_path($value))	{
				config_err($file_line_num, "$line - snapshot_root must be a full path");
				next;
			# if the snapshot root already exists:
			} elsif ( -e "$value" )	{
				# if path exists already, make sure it's a directory
				if ((-e "$value") && (! -d "$value"))	{
					config_err($file_line_num, "$line - snapshot_root must be a directory");
					next;
				}
				# make sure it's readable
				if ( ! -r "$value" )	{
					config_err($file_line_num, "$line - snapshot_root exists but is not readable");
					next;
				}
				# make sure it's writable
				if ( ! -w "$value" )	{
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
		
		# NO_CREATE_ROOT
		if ($var eq 'no_create_root')	{
			if (defined($value))	{
				if ('1' eq $value)	{
					$config_vars{'no_create_root'} = 1;
					$line_syntax_ok = 1;
					next;
				} elsif ('0' eq $value)	{
					$config_vars{'no_create_root'} = 0;
					$line_syntax_ok = 1;
					next;
				} else	{
					config_err($file_line_num, "$line - no_create_root must be set to either 1 or 0");
					next;
				}
			}
		}
		
		# CHECK FOR RSYNC (required)
		if ($var eq 'cmd_rsync')	{
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value)))	{
				$config_vars{'cmd_rsync'} = $value;
				$have_rsync = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR SSH (optional)
		if ($var eq 'cmd_ssh')	{
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value)))	{
				$config_vars{'cmd_ssh'} = $value;
				$have_ssh = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR GNU cp (optional)
		if ($var eq 'cmd_cp')	{
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value)))	{
				$config_vars{'cmd_cp'} = $value;
				$have_gnu_cp = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR rm (optional)
		if ($var eq 'cmd_rm')	{
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value)))	{
				$config_vars{'cmd_rm'} = $value;
				$display_rm = $value;
				$have_rm = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# CHECK FOR LOGGER (syslog program) (optional)
		if ($var eq 'cmd_logger')	{
			if ((-f "$value") && (-x "$value") && (1 == is_real_local_abs_path($value)))	{
				$config_vars{'cmd_logger'} = $value;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - $value is not executable");
				next;
			}
		}
		
		# INTERVALS
		if ($var eq 'interval')	{
			# check if interval is blank
			if (!defined($value))		{ config_err($file_line_num, "$line - Interval can not be blank"); }
			
			# check if interval is actually a number
			if ($value !~ m/^[\w\d]+$/)	{
				config_err($file_line_num,
					"$line - \"$value\" is not a valid interval, must be alphanumeric characters only");
				next;
			}
			
			# check if number is blank
			if (!defined($value2))		{
				config_err($file_line_num, "$line - \"$value\" number can not be blank");
				next;
			}
			
			# check if number is valid
			if ($value2 !~ m/^\d+$/)	{
				config_err($file_line_num, "$line - \"$value2\" is not a legal value for an interval");
				next;
			# ok, it's a number. is it positive?
			} else	{
				# make sure number is positive
				if ($value2 <= 0)			{
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
		if ($var eq 'backup')	{
			my $src			= $value;	# source directory
			my $dest		= $value2;	# dest directory
			my $opt_str		= $value3;	# option string from this backup point
			my $opts_ref	= undef;	# array_ref to hold parsed opts
			
			if ( !defined($config_vars{'snapshot_root'}) )	{
				config_err($file_line_num, "$line - snapshot_root needs to be defined before backup points");
				next;
			}
			
			# make sure we have a local path for the destination
			# (we do NOT want an absolute path)
			if ( is_valid_local_abs_path($dest) )	{
				config_err($file_line_num, "$line - Backup destination $dest must be a local path");
				next;
			}
			
			# make sure we aren't traversing directories
			if ( is_directory_traversal($src) )		{
				config_err($file_line_num, "$line - Directory traversal attempted in $src");
				next;
			}
			if ( is_directory_traversal($dest) )	{
				config_err($file_line_num, "$line - Directory traversal attempted in $dest");
				next;
			}
			
			# validate source path
			#
			# local absolute?
			if ( is_real_local_abs_path($src) )	{
				$line_syntax_ok = 1;
				
			# syntactically valid remote ssh?
			} elsif ( is_ssh_path($src) )	{
				# if it's an absolute ssh path, make sure we have ssh
				if (0 == $have_ssh)	{
					config_err($file_line_num, "$line - Cannot handle $src, cmd_ssh not defined in $config_file");
					next;
				}
				$line_syntax_ok = 1;
				
			# if it's anonymous rsync, we're ok
			} elsif ( is_anon_rsync_path($src) )	{
				$line_syntax_ok = 1;
				
			# fear the unknown
			} else	{
				config_err($file_line_num, "$line - Source directory \"$src\" doesn't exist");
				next;
			}
			
			# validate destination path
			#
			if ( is_valid_local_abs_path($dest) )	{
				config_err($file_line_num, "$line - Full paths not allowed for backup destinations");
				next;
			}
			
			# if we have special options specified for this backup point, remember them
			if (defined($opt_str) && $opt_str)	{
				$opts_ref = parse_backup_opts($opt_str);
				if (!defined($opts_ref))	{
					config_err(
						$file_line_num, "$line - Syntax error on line $file_line_num in extra opts: $opt_str"
					);
					next;
				}
			}
			
			# remember src/dest
			# also, first check to see that we're not backing up the snapshot directory
			if ((is_real_local_abs_path("$src")) && ($config_vars{'snapshot_root'} =~ m/^$src/))	{
				
				# remove trailing slashes from source and dest, since we will be using our own
				$src	= remove_trailing_slash($src);
				$dest	= remove_trailing_slash($dest);
				
				opendir(SRC, "$src") or bail("Could not open $src");
				
				while (my $node = readdir(SRC))	{
					next if ($node =~ m/^\.\.?$/o);	# skip '.' and '..'
					
					if ("$src/$node" ne "$config_vars{'snapshot_root'}")	{
						my %hash;
						
						# avoid double slashes from root filesystem
						if ($src eq '/')	{
							$hash{'src'}	= "/$node";
						} else	{
							$hash{'src'}	= "$src/$node";
						}
						
						$hash{'dest'}	= "$dest/$node";
						
						if (defined($opts_ref))	{
							$hash{'opts'} = $opts_ref;
						}
						push(@backup_points, \%hash);
					}
				}
				closedir(SRC);
			} else	{
				my %hash;
				$hash{'src'}	= $src;
				$hash{'dest'}	= $dest;
				if (defined($opts_ref))	{
					$hash{'opts'} = $opts_ref;
				}
				push(@backup_points, \%hash);
			}
			
			next;
		}
		
		# BACKUP SCRIPTS
		if ($var eq 'backup_script')	{
			my $full_script	= $value;	# backup script to run (including args)
			my $dest		= $value2;	# dest directory
			my %hash;					# tmp hash to stick in the backup points array
			my $script;					# script file (no args)
			my @script_argv;			# tmp spot to help us seperate the script from the args
			
			if ( !defined($config_vars{'snapshot_root'}) )	{
				config_err($file_line_num, "$line - snapshot_root needs to be defined before backup scripts");
				next;
			}
			
			# get the base name of the script, not counting any arguments to it
			@script_argv = split(/\s+/, $full_script);
			$script = $script_argv[0];
			
			# make sure the script is a full path
			if (1 == is_valid_local_abs_path($dest))	{
				config_err($file_line_num, "$line - Backup destination $dest must be a local path");
				next;
			}
			
			# make sure we aren't traversing directories (exactly 2 dots can't be next to each other)
			if (1 == is_directory_traversal($dest))	{
				config_err($file_line_num, "$line - Directory traversal attempted in $dest");
				next;
			}
			
			# validate destination path
			if ( is_valid_local_abs_path($dest) )	{
				config_err($file_line_num, "$line - Full paths not allowed for backup destinations");
				next;
			}
			
			# make sure script exists and is executable
			if ((! -f "$script") or (! -x "$script") && is_real_local_abs_path($script))	{
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
		if ($var eq 'link_dest')	{
			if (!defined($value))	{
				config_err($file_line_num, "$line - link_dest can not be blank");
				next;
			}
			if (!is_boolean($value))	{
				config_err(
					$file_line_num, "$line - \"$value\" is not a legal value for link_dest, must be 0 or 1 only"
				);
				next;
			}
			
			if (1 == $value)	{ $link_dest = 1; }
			$line_syntax_ok = 1;
			next;
		}
		# ONE_FS
		if ($var eq 'one_fs')	{
			if (!defined($value))	{
				config_err($file_line_num, "$line - one_fs can not be blank");
				next;
			}
			if (!is_boolean($value))	{
				config_err(
					$file_line_num, "$line - \"$value\" is not a legal value for one_fs, must be 0 or 1 only"
				);
				next;
			}
			
			if (1 == $value)	{ $one_fs = 1; }
			$line_syntax_ok = 1;
			next;
		}
		# LOCKFILE
		if ($var eq 'lockfile')	{
			if (!defined($value))	{ config_err($file_line_num, "$line - lockfile can not be blank"); }
			if (0 == is_valid_local_abs_path("$value"))	{
				config_err($file_line_num, "$line - lockfile must be a full path");
				next;
			}
			$config_vars{'lockfile'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# INCLUDE
		if ($var eq 'include')	{
			if (!defined($rsync_include_args))	{
				$rsync_include_args = "--include=$value";
			} else	{
				$rsync_include_args .= " --include=$value";
			}
			$line_syntax_ok = 1;
			next;
		}
		# EXCLUDE
		if ($var eq 'exclude')	{
			if (!defined($rsync_include_args))	{
				$rsync_include_args = "--exclude=$value";
			} else	{
				$rsync_include_args .= " --exclude=$value";
			}
			$line_syntax_ok = 1;
			next;
		}
		# INCLUDE FILE
		if ($var eq 'include_file')	{
			if (0 == is_real_local_abs_path($value))	{
				config_err($file_line_num, "$line - include_file $value must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value))	{
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" ))	{
				config_err($file_line_num, "$line - include_file $value exists, but is not a file");
				next;
			} elsif ( ! -r "$value" )	{
				config_err($file_line_num, "$line - include_file $value exists, but is not readable");
				next;
			} else	{
				if (!defined($rsync_include_file_args))	{
					$rsync_include_file_args = "--include-from=$value";
				} else	{
					$rsync_include_file_args .= " --include-from=$value";
				}
				$line_syntax_ok = 1;
				next;
			}
		}
		# EXCLUDE FILE
		if ($var eq 'exclude_file')	{
			if (0 == is_real_local_abs_path($value))	{
				config_err($file_line_num, "$line - exclude_file $value must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value))	{
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" ))	{
				config_err($file_line_num, "$line - exclude_file $value exists, but is not a file");
				next;
			} elsif ( ! -r "$value" )	{
				config_err($file_line_num, "$line - exclude_file $value exists, but is not readable");
				next;
			} else	{
				if (!defined($rsync_include_file_args))	{
					$rsync_include_file_args = "--exclude-from=$value";
				} else	{
					$rsync_include_file_args .= " --exclude-from=$value";
				}
				$line_syntax_ok = 1;
				next;
			}
		}
		# RSYNC SHORT ARGS
		if ($var eq 'rsync_short_args')	{
			# must be in the format '-abcde'
			if (0 == is_valid_rsync_short_args($value))	{
				config_err($file_line_num, "$line - rsync_short_args \"$value\" not in correct format");
				next;
			} else	{
				$config_vars{'rsync_short_args'} = $value;
				$line_syntax_ok = 1;
				next;
			}
		}
		# RSYNC LONG ARGS
		if ($var eq 'rsync_long_args')	{
			$config_vars{'rsync_long_args'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# SSH ARGS
		if ($var eq 'ssh_args')	{
			$config_vars{'ssh_args'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# LOGFILE
		if ($var eq 'logfile')	{
			if (0 == is_valid_local_abs_path($value))	{
				config_err($file_line_num, "$line - logfile must be a valid absolute path");
				next;
			} elsif (1 == is_directory_traversal($value))	{
				config_err($file_line_num, "$line - Directory traversal attempted in $value");
				next;
			} elsif (( -e "$value" ) && ( ! -f "$value" ))	{
				config_err($file_line_num, "$line - logfile $value exists, but is not a file");
				next;
			} else	{
				$config_vars{'logfile'} = $value;
				$line_syntax_ok = 1;
				next;
			}
		}
		# VERBOSE
		if ($var eq 'verbose')	{
			if (1 == is_valid_loglevel($value))	{
				if (!defined($verbose))	{
					$verbose = $value;
				}
				
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - verbose must be a value between 1 and 5");
				next;
			}
		}
		# LOGLEVEL
		if ($var eq 'loglevel')	{
			if (1 == is_valid_loglevel($value))	{
				if (!defined($loglevel))	{
					$loglevel = $value;
				}
				
				$line_syntax_ok = 1;
				next;
			} else	{
				config_err($file_line_num, "$line - loglevel must be a value between 1 and 5");
				next;
			}
		}
		
		# make sure we understood this line
		# if not, warn the user, and prevent the program from executing
		# however, don't bother if the user has already been notified
		if (1 == $config_perfect)	{
			if (0 == $line_syntax_ok)	{
				config_err($file_line_num, $line);
				next;
			}
		}
	}
	close(CONFIG) or print_err("Warning! Could not close $config_file", 2);
	
	####################################################################
	# SET SOME SENSIBLE DEFAULTS FOR VALUES THAT MAY NOT HAVE BEEN SET #
	####################################################################
	
	# if we didn't manage to get a verbose level yet, either through the config file
	# or the command line, use the default
	if (!defined($verbose))	{
		$verbose = $default_verbose;
	}
	# same for loglevel
	if (!defined($loglevel))	{
		$loglevel = $default_loglevel;
	}
	# assemble rsync include/exclude args
	if (defined($rsync_include_args))	{
		if (!defined($config_vars{'rsync_long_args'}))	{
			$config_vars{'rsync_long_args'} = $global_default_rsync_long_args;
		}
		$config_vars{'rsync_long_args'} .= " $rsync_include_args";
	}
	# assemble rsync include/exclude file args
	if (defined($rsync_include_file_args))	{
		if (!defined($config_vars{'rsync_long_args'}))	{
			$config_vars{'rsync_long_args'} = $global_default_rsync_long_args;
		}
		$config_vars{'rsync_long_args'} .= " $rsync_include_file_args";
	}
	
	###############################################
	# NOW THAT THE CONFIG FILE HAS BEEN READ IN,  #
	# DO A SANITY CHECK ON THE DATA WE PULLED OUT #
	###############################################
	
	# SINS OF COMMISSION
	# (incorrect entries in config file)
	if (0 == $config_perfect)	{
		print_err("---------------------------------------------------------------------", 1);
		print_err("Errors were found in $config_file, rsnapshot can not continue.", 1);
		print_err("If you think an entry looks right, make sure you don't have", 1);
		print_err("spaces where only tabs should be.", 1);
		
		# if this wasn't a test, report the error to syslog
		if (0 == $do_configtest)	{
			syslog_err("Errors were found in $config_file, rsnapshot can not continue.");
		}
		
		# exit showing an error
		exit(1);
	}
	
	# SINS OF OMISSION
	# (things that should be in the config file that aren't)
	#
	# make sure we got rsync in there somewhere
	if (0 == $have_rsync)	{
		print_err("cmd_rsync was not defined.", 1);
	}
	# make sure we got a snapshot_root
	if (!defined($config_vars{'snapshot_root'}))	{
		print_err ("snapshot_root was not defined. rsnapshot can not continue.", 1);
		syslog_err("snapshot_root was not defined. rsnapshot can not continue.");
		exit(1);
	}
	# make sure we have at least one interval
	if (0 == scalar(@intervals))	{
		print_err ("At least one interval must be set. rsnapshot can not continue.", 1);
		syslog_err("At least one interval must be set. rsnapshot can not continue.");
		exit(1);
	}
	# make sure we have at least one backup point
	if (0 == scalar(@backup_points))	{
		print_err ("At least one backup point must be set. rsnapshot can not continue.", 1);
		syslog_err("At least one backup point must be set. rsnapshot can not continue.");
		exit(1);
	}

	# SINS OF CONFUSION
	# (various, specific, undesirable interactions)
	#
	# make sure that we don't have only one copy of the first interval,
	# yet expect rotations on the second interval
	if (scalar(@intervals) > 1)	{
		if (defined($intervals[0]->{'number'}))	{
			if (1 == $intervals[0]->{'number'})	{
				print_err ("Can not have first interval set to 1, and have a second interval", 1);
				syslog_err("Can not have first interval set to 1, and have a second interval");
				exit(1);
			}
		}
	}
	# make sure that the snapshot_root exists if no_create_root is set to 1
	if (defined($config_vars{'no_create_root'}))	{
		if (1 == $config_vars{'no_create_root'})	{
			if ( ! -d "$config_vars{'snapshot_root'}" )	{
				print_err ("rsnapshot refuses to create snapshot_root when no_create_root is enabled", 1);
				syslog_err("rsnapshot refuses to create snapshot_root when no_create_root is enabled");
				exit(1);
			}
		}
	}
}

# accepts a string of options
# returns an array_ref of parsed options
# returns undef if there is an invalid option
#
# this is for individual backup points only
sub parse_backup_opts	{
	my $opts_str = shift(@_);
	my @pairs;
	my %parsed_opts;
	
	# pre-buffer extra rsync arguments
	my $rsync_include_args		= undef;
	my $rsync_include_file_args	= undef;
	
	# make sure we got something
	if (!defined($opts_str))	{ return (undef); }
	if (!$opts_str)				{ return (undef); }
	
	# split on commas first
	@pairs = split(/,/, $opts_str);
	
	# then loop through and split on equals
	foreach my $pair (@pairs)	{
		my ($name, $value) = split(/=/, $pair, 2);
		if ( !defined($name) or !defined($value) )	{
			return (undef);
		}
		
		# parameters can't have spaces in them
		$name =~ s/\s//go;
		
		# strip whitespace from both ends
		$value =~ s/^\s{0,}//o;
		$value =~ s/\s{0,}$//o;
		
		# ok, it's a name/value pair and it's ready for more validation
		$parsed_opts{$name} = $value;
		
		# VALIDATE ARGS
		# one_fs
		if ( $name eq 'one_fs' )	{
			if (!is_boolean($parsed_opts{'one_fs'}))	{
				return (undef);
			}
		# rsync short args
		} elsif ( $name eq 'rsync_short_args' )	{
			# must be in the format '-abcde'
			if (0 == is_valid_rsync_short_args($value))	{
				print_err("rsync_short_args \"$value\" not in correct format", 2);
				return (undef);
			}
			
		# rsync long args
		} elsif ( $name eq 'rsync_long_args' )	{
			# pass unchecked
			
		# ssh args
		} elsif ( $name eq 'ssh_args' )	{
			# pass unchecked
			
		# include
		} elsif ( $name eq 'include' )	{
			# don't validate contents
			# coerce into rsync_include_args
			# then remove the "include" key/value pair
			if (!defined($rsync_include_args))	{
				$rsync_include_args = "--include=$parsed_opts{'include'}";
			} else	{
				$rsync_include_args .= " --include=$parsed_opts{'include'}";
			}
			
			delete($parsed_opts{'include'});
			
		# exclude
		} elsif ( $name eq 'exclude' )	{
			# don't validate contents
			# coerce into rsync_include_args
			# then remove the "include" key/value pair
			if (!defined($rsync_include_args))	{
				$rsync_include_args = "--exclude=$parsed_opts{'exclude'}";
			} else	{
				$rsync_include_args .= " --exclude=$parsed_opts{'exclude'}";
			}
			
			delete($parsed_opts{'exclude'});
			
		# include file
		} elsif ( $name eq 'include_file' )	{
			# verify that this file exists and is readable
			if (0 == is_real_local_abs_path($value))	{
				print_err("include_file $value must be a valid absolute path", 2);
				return (undef);
			} elsif (1 == is_directory_traversal($value))	{
				print_err("Directory traversal attempted in $value", 2);
				return (undef);
			} elsif (( -e "$value" ) && ( ! -f "$value" ))	{
				print_err("include_file $value exists, but is not a file", 2);
				return (undef);
			} elsif ( ! -r "$value" )	{
				print_err("include_file $value exists, but is not readable", 2);
				return (undef);
			}
			
			# coerce into rsync_include_file_args
			# then remove the "include_file" key/value pair
			if (!defined($rsync_include_file_args))	{
				$rsync_include_file_args = "--include-from=$parsed_opts{'include_file'}";
			} else	{
				$rsync_include_file_args .= " --include-from=$parsed_opts{'include_file'}";
			}
			
			delete($parsed_opts{'include_file'});
			
		# exclude file
		} elsif ( $name eq 'exclude_file' )	{
			# verify that this file exists and is readable
			if (0 == is_real_local_abs_path($value))	{
				print_err("exclude_file $value must be a valid absolute path", 2);
				return (undef);
			} elsif (1 == is_directory_traversal($value))	{
				print_err("Directory traversal attempted in $value", 2);
				return (undef);
			} elsif (( -e "$value" ) && ( ! -f "$value" ))	{
				print_err("exclude_file $value exists, but is not a file", 2);
				return (undef);
			} elsif ( ! -r "$value" )	{
				print_err("exclude_file $value exists, but is not readable", 2);
				return (undef);
			}
			
			# coerce into rsync_include_file_args
			# then remove the "exclude_file" key/value pair
			if (!defined($rsync_include_file_args))	{
				$rsync_include_file_args = "--exclude-from=$parsed_opts{'exclude_file'}";
			} else	{
				$rsync_include_file_args .= " --exclude-from=$parsed_opts{'exclude_file'}";
			}
			
			delete($parsed_opts{'exclude_file'});
			
		# if we don't know about it, it doesn't exist
		} else	{
			return (undef);
		}
	}
	
	# merge rsync_include_args and rsync_file_include_args in with either $global_default_rsync_long_args
	# or $parsed_opts{'rsync_long_args'}
	if (defined($rsync_include_args) or defined($rsync_include_file_args))	{
		# if we never defined rsync_long_args, populate it with the global default
		if (!defined($parsed_opts{'rsync_long_args'}))	{
			if (defined($config_vars{'rsync_long_args'}))	{
				$parsed_opts{'rsync_long_args'} = $config_vars{'rsync_long_args'};
			} else	{
				$parsed_opts{'rsync_long_args'} = $global_default_rsync_long_args;
			}
		}
		
		# now we have something in our local rsync_long_args
		# let's concatenate the include/exclude/file stuff to it
		if (defined($rsync_include_args))	{
			$parsed_opts{'rsync_long_args'} .= " $rsync_include_args";
		}
		if (defined($rsync_include_file_args))	{
			$parsed_opts{'rsync_long_args'} .= " $rsync_include_file_args";
		}
	}
	
	# if we got anything, return it as an array_ref
	if (%parsed_opts)	{
		return (\%parsed_opts);
	}
	
	return (undef);
}

# accepts line number, errstr
# prints a config file error
# also sets global $config_perfect var off
sub config_err	{
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
sub bail	{
	my $str = shift(@_);
	
	# print out error
	if ($str)	{
		print_err($str, 1);
	}
	
	# write to syslog if we're running for real (and we have a message)
	if ((0 == $do_configtest) && (0 == $test) && ('' ne $str))	{
		syslog_err($str);
	}
	
	# get rid of the lockfile, if it exists
	remove_lockfile($config_vars{'lockfile'});
	
	# exit showing an error
	exit(1);
}

# accepts a string (or an array)
# prints the string, but seperates it across multiple lines with backslashes if necessary
# also logs the command, but on a single line
sub print_cmd	{
	# take all arguments and make them into one string
	my $str = join(' ', @_);
	
	if (!defined($str))	{ return (undef); }
	
	# remove newline and consolidate spaces
	chomp($str);
	$str =~ s/\s+/ /g;
	
	# write to log (level 3 is where we start showing commands)
	log_msg($str, 3);
	
	if (!defined($verbose) or ($verbose >= 3))	{
		print wrap_cmd($str, 76, 4), "\n";
	}
}

# accepts a string
# formats it to STDOUT wrapping to fit in 80 columns
# with backslashes at the end of each wrapping line and returns it
sub wrap_cmd	{
	my $str		= shift(@_);
	my $colmax	= shift(@_);
	my $indent	= shift(@_);
	
	my @tokens;
	my $chars = 0;		# character tally
	my $outstr = '';	# string to return
	
	# max chars before wrap (default to 80 column terminal)
	if (!defined($colmax))	{
		$colmax = 76;
	}
	
	# number of spaces to indent subsequent lines
	if (!defined($indent))	{
		$indent = 4;
	}
	
	# break up string into individual pieces
	@tokens = split(/\s+/, $str);
	
	# stop here if we don't have anything
	if (0 == scalar(@tokens))	{ return (''); }
	
	# print the first token as a special exception, since we should never start out by line wrapping
	if (defined($tokens[0]))	{
		$chars = (length($tokens[0]) + 1);
		$outstr .= $tokens[0];
		
		# don't forget to put the space back in
		if (scalar(@tokens) > 1)	{
			$outstr .= ' ';
		}
	}
	
	# loop through the rest of the tokens and print them out, wrapping when necessary
	for (my $i=1; $i<scalar(@tokens); $i++)	{
		# keep track of where we are (plus a space)
		$chars += (length($tokens[$i]) + 1);
		
		# wrap if we're at the edge
		if ($chars > $colmax)	{
			$outstr .= "\\\n";
			$outstr .= (' ' x $indent);
			
			# 4 spaces + string length
			$chars = $indent + length($tokens[$i]);
		}
		
		# print out this token
		$outstr .= $tokens[$i];
		
		# print out a space unless this is the last one
		if ($i < scalar(@tokens))	{
			$outstr .= ' ';
		}
	}
	
	return ($outstr);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
sub print_msg	{
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	chomp($str);
	
	# print to STDOUT
	if ((!defined($verbose)) or ($verbose >= $level))	{
		print $str, "\n";
	}
	
	# write to log
	log_msg($str, $level);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
# also raises a warning for the exit code
sub print_warn	{
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	# we can no longer say the execution of the program has been error free
	raise_warning();
	
	chomp($str);
	
	# print to STDERR
	if ((!defined($verbose)) or ($level <= $verbose))	{
		print STDERR 'WARNING: ', $str, "\n";
	}
	
	# write to log
	log_msg($str, $level);
}

# accepts string, and level
# prints string if level is as high as verbose
# logs string if level is as high as loglevel
# also raises an error for the exit code
sub print_err	{
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ $level = 0; }
	
	# we can no longer say the execution of the program has been error free
	raise_error();
	
	chomp($str);
	
	# print to STDERR
	if ((!defined($verbose)) or ($level <= $verbose))	{
		print STDERR 'ERROR: ', $str, "\n";
	}
	
	# write to log
	log_err($str, $level);
}

# accepts string, and level
# logs string if level is as high as loglevel
sub log_msg	{
	my $str		= shift(@_);
	my $level	= shift(@_);
	my $result	= undef;
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ return (undef); }
	
	chomp($str);
	
	# if this is just noise, don't log it
	if (defined($loglevel) && ($level > $loglevel))	{
		return (undef);
	}
	
	# open logfile, write to it, close it back up
	# if we fail, don't use the usual print_* functions, since they just call this again
	if ((0 == $test) && (0 == $do_configtest))	{
		if (defined($config_vars{'logfile'}))	{
			$result = open (LOG, ">> $config_vars{'logfile'}");
			if (!defined($result))	{
				print STDERR "Could not open logfile $config_vars{'logfile'} for writing\n";
				exit(1);
			}
			
			print LOG '[', get_current_date(), '] ', $str, "\n";
			
			$result = close(LOG);
			if (!defined($result))	{
				print STDERR "Could not close logfile $config_vars{'logfile'}\n";
			}
		}
	}
}

# accepts string, and level
# logs string if level is as high as loglevel
# also raises a warning for the exit code
sub log_warn	{
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
sub log_err	{
	my $str		= shift(@_);
	my $level	= shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if (!defined($level))	{ return (undef); }
	
	# this run is no longer perfect since we have an error
	raise_error();
	
	chomp($str);
	
	$str = 'ERROR: ' . $str;
	log_msg($str, $level);
}

# log messages to syslog
# accepts message, facility, level
# only message is required
# return 1 on success, undef on failure
sub syslog_msg	{
	my $msg			= shift(@_);
	my $facility	= shift(@_);
	my $level		= shift(@_);
	my $result		= undef;
	
	if (!defined($msg))			{ return (undef); }
	if (!defined($facility))	{ $facility	= 'user'; }
	if (!defined($level))		{ $level	= 'notice'; }
	
	if (defined($config_vars{'cmd_logger'}))	{
		# extra verbose to display messages, verbose to display errors
		print_cmd("$config_vars{'cmd_logger'} -i -p $facility.$level -t rsnapshot $msg");
		
		# log to syslog
		if (0 == $test)	{
			$result = system($config_vars{'cmd_logger'}, '-i', '-p', "$facility.$level", '-t', 'rsnapshot', $msg);
			if (0 != $result)	{
				print_err("Warning! Could not log to syslog:", 2);
				print_err("$config_vars{'cmd_logger'} -i -p $facility.$level -t rsnapshot $msg", 2);
			}
		}
	}
	
	return (1);
}

# log warnings to syslog
# accepts warning message
# returns 1 on success, undef on failure
# also raises a warning for the exit code
sub syslog_warn	{
	my $msg = shift(@_);
	
	# this run is no longer perfect since we have an error
	raise_warning();
	
	return syslog_msg("WARNING: $msg", 'user', 'err');
}

# log errors to syslog
# accepts error message
# returns 1 on success, undef on failure
# also raises an error for the exit code
sub syslog_err	{
	my $msg = shift(@_);
	
	# this run is no longer perfect since we have an error
	raise_error();
	
	return syslog_msg("ERROR: $msg", 'user', 'err');
}

# sets exit code for at least a warning
sub raise_warning	{
	if ($exit_code != 1)	{
		$exit_code = 2;
	}
}

# sets exit code for error
sub raise_error	{
	$exit_code = 1;
}

# accepts no arguments
# returns the current date (for the logfile)
#
# there's probably a wonderful module that can do this all for me,
# but unless it comes standard with perl 5.004 and later, i'd rather do it this way :)
#
sub get_current_date	{
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
# returns undef if lockfile isn't defined in the config file, and 1 upon success
# also, it can make the program exit with 1 as the return value if it can't create the lockfile
#
# we don't use bail() to exit on error, because that would remove the
# lockfile that may exist from another invocation
sub add_lockfile	{
	# if we don't have a lockfile defined, just return undef
	if (!defined($config_vars{'lockfile'}))	{
		return (undef);
	}
	
	my $lockfile = $config_vars{'lockfile'};
	
	# valid?
	if (0 == is_valid_local_abs_path($lockfile))	{
		print_err ("Lockfile $lockfile is not a valid file name", 1);
		syslog_err("Lockfile $lockfile is not a valid file name");
		exit(1);
	}
	
	# does a lockfile already exist?
	if (1 == is_real_local_abs_path($lockfile))	{
		print_err ("Lockfile $lockfile exists, can not continue!", 1);
		syslog_err("Lockfile $lockfile exists, can not continue");
		exit(1);
	}
	
	# create the lockfile
	print_cmd("touch $lockfile");
	
	if (0 == $test)	{
		my $result = open(LOCKFILE, "> $lockfile");
		if (!defined($result))	{
			print_err ("Could not write lockfile $lockfile", 1);
			syslog_err("Could not write lockfile $lockfile");
			exit(1);
		}
		
		# print PID to lockfile
		print LOCKFILE $$;
		
		$result = close(LOCKFILE);
		if (!defined($result))	{
			print_err("Warning! Could not close lockfile $lockfile", 2);
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
sub remove_lockfile	{
	# if we don't have a lockfile defined, return undef
	if (!defined($config_vars{'lockfile'}))	{
		return (undef);
	}
	
	my $lockfile = $config_vars{'lockfile'};
	my $result = undef;
	
	if ( -e "$lockfile" )	{
		print_cmd("rm -f $lockfile");
		if (0 == $test)	{
			$result = unlink($lockfile);
			if (0 == $result)	{
				print_err ("Could not remove lockfile $lockfile", 1);
				syslog_err("Error! Could not remove lockfile $lockfile");
				exit(1);
			}
		}
	}
	
	return (1);
}

# accepts no arguments
# returns no arguments
# sets the locale to POSIX (C) to mitigate some problems with the rmtree() command
#
sub set_posix_locale	{
	# set POSIX locale
	# this may fix some potential problems with rmtree()
	# another solution is to enable "cmd_rm" in rsnapshot.conf
	print_msg("Setting locale to POSIX \"C\"", 4);
	setlocale(POSIX::LC_ALL, 'C');
}

# accepts no arguments
# returns no arguments
# creates the snapshot_root directory (chmod 0700), if it doesn't exist and no_create_root = 0
sub create_snapshot_root	{
	# make sure no_create_root == 0
	if (defined($config_vars{'no_create_root'}))	{
		if (1 == $config_vars{'no_create_root'})	{
			print_err ("rsnapshot refuses to create snapshot_root when no_create_root is enabled", 1);
			syslog_err("rsnapshot refuses to create snapshot_root when no_create_root is enabled");
			bail();
		}
	}
	
	# create the directory
	if ( ! -d "$config_vars{'snapshot_root'}" )	{
		print_cmd("mkdir -m 0700 -p $config_vars{'snapshot_root'}/");
		
		if (0 == $test)	{
			eval	{
				mkpath( "$config_vars{'snapshot_root'}/", 0, 0700 );
			};
			if ($@)	{
				bail(
					"Unable to create $config_vars{'snapshot_root'}/,\nPlease make sure you have the right permissions."
				);
			}
		}
	}
}

# accepts no arguments
# returns no arguments
# sets some global variables
sub get_current_interval	{
	
	# FIGURE OUT WHICH INTERVAL WE'RE RUNNING, AND HOW IT RELATES TO THE OTHERS
	# THEN RUN THE ACTION FOR THE CHOSEN INTERVAL
	# remember, in each hashref in this loop:
	#   "interval" is something like "daily", "weekly", etc.
	#   "number" is the number of these intervals to keep on the filesystem
	
	my $i = 0;
	foreach my $i_ref (@intervals)	{
		
		# this is the interval we're set to run
		if ($$i_ref{'interval'} eq $cmd)	{
			$interval_num = $i;
			
			# how many of these intervals should we keep?
			# we start counting from 0, so subtract one
			# i.e. 6 intervals == interval.0 .. interval.5
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
		# i.e. daily.0/ might get pulled from hourly.6/
		#
		$prev_interval_max = $$i_ref{'number'} - 1;
		
		$i++;
	}
}

# accepts the name of the interval to check
# checks the $interval_num global variable, and exits if it hasn't been set
# ($interval_num being set would prove we've already validated the intervals)
sub check_valid_interval	{
	my $interval = shift(@_);
	
	if (!defined($interval))		{ bail("Interval not specified in check_valid_interval()\n"); }
	if (!defined($interval_num))	{ bail("Interval \"$interval\" unknown, check $config_file"); }
}

# accepts no args
# prints out status to the logs, then exits the program with the current exit code
sub exit_with_status	{
	if (0 == $exit_code)	{
		syslog_msg("$run_string: completed successfully");
		log_msg   ("$run_string: completed successfully", 2);
		exit ($exit_code);
		
	} elsif (1 == $exit_code)	{
		syslog_err("$run_string: completed, but with some errors");
		log_err   ("$run_string: completed, but with some errors", 2);
		exit ($exit_code);
		
	} elsif (2 == $exit_code)	{
		syslog_warn("$run_string: completed, but with some warnings");
		log_warn   ("$run_string: completed, but with some warnings", 2);
		exit ($exit_code);
		
	# this should never happen
	} else	{
		syslog_err("$run_string: completed, but with no definite status");
		log_err   ("$run_string: completed, but with no definite status", 2);
		exit (1);
	}
}

# accepts no arguments
# returns no arguments
#
# exits the program with the status of the config file (i.e. Syntax OK).
# the exit code is 0 for success, 1 for failure (although failure should never happen)
sub exit_configtest	{
	# if we're just doing a configtest, exit here with the results
	if (1 == $do_configtest)	{
		if (1 == $config_perfect)	{
			print "Syntax OK\n";
			exit(0);
			
		# this should never happen, because any errors should have killed the program before now
		} else	{
			print "Syntax Error\n";
			exit(1);
		}
	}
}

# accepts no arguments
# prints out error messages since we can't find the config file
# exits with a return code of 1
sub exit_no_config_file	{
	# warn that the config file could not be found
	print STDERR "Config file \"$config_file\" does not exist or is not readable.\n";
	if (0 == $do_configtest)	{
		syslog_err("Config file \"$config_file\" does not exist or is not readable.");
	}
	
	# if we have the default config from the install, remind the user to create the real config
	if (-e "$config_file.default")	{
		print STDERR "Did you copy $config_file.default to $config_file yet?\n";
	}
	
	# exit showing an error
	exit(1);
}

# accepts a loglevel
# returns 1 if it's valid, 0 otherwise
sub is_valid_loglevel	{
	my $value	= shift(@_);
	
	if (!defined($value))	{ return (0); }
	
	if ($value =~ m/^\d$/)	{
		if (($value >= 1) && ($value <= 5))	{
			return (1);
		}
	}
	
	return (0);
}

# accepts one argument
# checks to see if that argument is set to 1 or 0
# returns 1 on success, 0 on failure
sub is_boolean	{
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
sub is_comment	{
	my $str = shift(@_);
	
	if (!defined($str))	{ return (undef); }
	if ($str =~ m/^#/)	{ return (1); }
	return (0);
}

# accepts string
# returns 1 if it is blank, or just pure white space
# returns 0 otherwise
sub is_blank	{
	my $str = shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if ($str =~ m/^\s*$/)	{ return (1); }
	return (0);
}

# accepts path
# returns 1 if it's a valid ssh absolute path
# returns 0 otherwise
sub is_ssh_path	{
	my $path	= shift(@_);
	
	if (!defined($path))				{ return (undef); }
	if ($path =~ m/^.*?\@.*?:\/.*$/)	{ return (1); }
	
	return (0);
}

# accepts path
# returns 1 if it's a syntactically valid anonymous rsync path
# returns 0 otherwise
sub is_anon_rsync_path	{
	my $path	= shift(@_);
	
	if (!defined($path))			{ return (undef); }
	if ($path =~ m/^rsync:\/\/.*$/)	{ return (1); }
	
	return (0);
}

# accepts proposed list for rsync_short_args
# makes sure that rsync_short_args is in the format '-abcde'
# (not '-a -b' or '-ab c', etc)
# returns 1 if it's OK, or 0 otherwise
sub is_valid_rsync_short_args	{
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
sub is_real_local_abs_path	{
	my $path	= shift(@_);
	
	if (!defined($path))	{ return (undef); }
	if (1 == is_valid_local_abs_path($path))	{
		if (-e "$path")	{
			return (1);
		}
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a syntactically valid absolute path
# returns 0 otherwise
sub is_valid_local_abs_path	{
	my $path	= shift(@_);
	
	if (!defined($path))	{ return (undef); }
	if ($path =~ m/^\//)	{
		if (0 == is_directory_traversal($path))	{
			 return (1);
		}
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a directory traversal attempt
# returns 0 if it's safe
sub is_directory_traversal	{
	my $path = shift(@_);
	
	if (!defined($path))		{ return (undef); }
	
	# /..
	if ($path =~ m/\/\.\./)	{ return (1); }
	
	# ../
	if ($path =~ m/\.\.\//)	{ return (1); }
	return (0);
}

# accepts path
# returns 1 if it's a file (doesn't have a trailing slash)
# returns 0 otherwise
sub is_file	{
	my $path = shift(@_);
	
	if (!defined($path))	{ return (undef); }
	
	if ($path !~ m/\/$/o)	{
		return (1);
	}
	
	return (0);
}

# accepts path
# returns 1 if it's a directory (has a trailing slash)
# returns 0 otherwise
sub is_directory	{
	my $path = shift(@_);
	
	if (!defined($path))	{ return (undef); }
	
	if ($path =~ m/\/$/o)	{
		return (1);
	}
	
	return (0);
}

# accepts string
# removes trailing slash, returns the string
sub remove_trailing_slash	{
	my $str = shift(@_);
	
	# it's not a trailing slash if it's the root filesystem
	if ($str eq '/')	{ return ($str); }
	
	$str =~ s/\/+$//;
	
	return ($str);
}

# accepts the interval to act on (i.e. hourly)
# this should be the smallest interval (i.e. hourly, not daily)
#
# rotates older dirs within this interval, hard links .0 to .1,
# and rsync data over to .0
#
# does not return a value, it bails instantly if there's a problem
sub backup_lowest_interval	{
	my $interval = shift(@_);
	
	# this should never happen
	if (!defined($interval))	{ bail('backup_lowest_interval() expects an argument'); }
	
	#
	# ROTATE THE HIGHER DIRECTORIES IN THIS INTERVAL
	#
	rotate_lowest_snapshots($interval);
	
	# SYNC LIVE FILESYSTEM DATA TO $interval.0
	# loop through each backup point and backup script
	foreach my $bp_ref (@backup_points)	{
		
		# actually rsync the given backup point into the snapshot root
		handle_backup_point( $interval, $bp_ref );
	}
	
	#
	# ROLLBACK FAILED BACKUPS
	#
	rollback_failed_backups($interval);
	
	# update mtime of $interval.0 to reflect the time this snapshot was taken
	print_cmd("touch $config_vars{'snapshot_root'}/$interval.0/");
	
	if (0 == $test)	{
		my $result = utime(time(), time(), "$config_vars{'snapshot_root'}/$interval.0/");
		if (0 == $result)	{
			bail("Could not utime(time(), time(), \"$config_vars{'snapshot_root'}/$interval.0/\");");
		}
	}
}

# accepts no arguments
# returns no arguments
# operates on directories in the lowest interval
# deletes the highest one, and rotates the ones below it
# if link_dest is enabled, .0 gets moved to .1
# otherwise, we do cp -al .0 .1
#
# if we encounter an error, this script will terminate the program with an error condition
#
sub rotate_lowest_snapshots	{
	my $interval = shift(@_);
	
	if (!defined($interval))	{ bail('interval not defined in rotate_lowest_snapshots()'); }
	
	# ROTATE DIRECTORIES
	#
	# remove oldest directory
	if ( (-d "$config_vars{'snapshot_root'}/$interval.$interval_max") && ($interval_max > 0) )	{
		print_cmd("$display_rm -rf $config_vars{'snapshot_root'}/$interval.$interval_max/");
		if (0 == $test)	{
			my $result = rm_rf( "$config_vars{'snapshot_root'}/$interval.$interval_max/" );
			if (0 == $result)	{
				bail("Error! rm_rf(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\")\n");
			}
		}
	}
	
	# rotate the middle ones
	if ($interval_max > 0)	{
		for (my $i=($interval_max-1); $i>0; $i--)	{
			if ( -d "$config_vars{'snapshot_root'}/$interval.$i" )	{
				print_cmd("mv ",
							"$config_vars{'snapshot_root'}/$interval.$i/ ",
							"$config_vars{'snapshot_root'}/$interval." . ($i+1) . "/");
				
				if (0 == $test)	{
					my $result = rename(
									"$config_vars{'snapshot_root'}/$interval.$i/",
									("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/')
					);
					if (0 == $result)	{
						my $errstr = '';
						$errstr .= "Error! rename(\"$config_vars{'snapshot_root'}/$interval.$i/\", \"";
						$errstr .= "$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/' . "\")";
						bail($errstr);
					}
				}
			}
		}
	}
	
	# .0 and .1 require more attention:
	if ( (-d "$config_vars{'snapshot_root'}/$interval.0") && ($interval_max > 0) )	{
		my $result;
		
		# if we're using rsync --link-dest, we need to mv .0 to .1 now
		if (1 == $link_dest)	{
			print_cmd("mv $config_vars{'snapshot_root'}/$interval.0/ $config_vars{'snapshot_root'}/$interval.1/");
			
			# move .0 to .1
			if (0 == $test)	{
				my $result = rename(
								"$config_vars{'snapshot_root'}/$interval.0/",
								"$config_vars{'snapshot_root'}/$interval.1/"
				);
				if (0 == $result)	{
					my $errstr = '';
					$errstr .= "Error! rename(\"$config_vars{'snapshot_root'}/$interval.0/\", ";
					$errstr .= "\"$config_vars{'snapshot_root'}/$interval.1/\")";
					bail($errstr);
				}
			}
		# otherwise, we hard link (except for directories, symlinks, and special files) .0 over to .1
		} else	{
			# call generic cp_al() subroutine
			if (0 == $test)	{
				$result = cp_al(
							"$config_vars{'snapshot_root'}/$interval.0/",
							"$config_vars{'snapshot_root'}/$interval.1/"
				);
				if (! $result)	{
					my $errstr = '';
					$errstr .= "Error! cp_al(\"$config_vars{'snapshot_root'}/$interval.0/\", ";
					$errstr .= "\"$config_vars{'snapshot_root'}/$interval.1/\")";
					bail($errstr);
				}
			}
		}
	}
}

# TODO: break out the guts of this subroutine into two more subs:
#  rsync_backup_point()
#  exec_backup_script()
#
# they will each be called from inside handle_backup_point(), as appropriate

# TODO: audit this subroutine for possible redundancy

# accepts interval, backup_point_ref, ssh_rsync_args_ref
# returns no args
# runs rsync on the given backup point
sub handle_backup_point	{
	my $interval	= shift(@_);
	my $bp_ref		= shift(@_);
	
	# validate subroutine args
	if (!defined($interval))	{ bail('interval not defined in handle_backup_point()'); }
	if (!defined($bp_ref))		{ bail('bp_ref not defined in handle_backup_point()'); }
	
	# set up default args for rsync and ssh
	my $ssh_args			= $global_default_ssh_args;
	my $rsync_short_args	= $global_default_rsync_short_args;
	my $rsync_long_args		= $global_default_rsync_long_args;
	
	# other misc variables
	my @cmd_stack				= undef;
	my @rsync_long_args_stack	= undef;
	my $src						= undef;
	my $script					= undef;
	my $tmpdir					= undef;
	my $result					= undef;
	
	# if the config file specified rsync or ssh args, use those instead of the hard-coded defaults in the program
	if (defined($config_vars{'rsync_short_args'}))	{
		$rsync_short_args = $config_vars{'rsync_short_args'};
	}
	if (defined($config_vars{'rsync_long_args'}))	{
		$rsync_long_args = $config_vars{'rsync_long_args'};
	}
	if (defined($config_vars{'ssh_args'}))	{
		$ssh_args = $config_vars{'ssh_args'};
	}
	
	# extra verbose?
	if ($verbose > 3)	{ $rsync_short_args .= 'v'; }
	
	# split up rsync long args into an array
	@rsync_long_args_stack	= ( split(/\s/, $rsync_long_args) );
	
	# append a trailing slash if src is a directory
	if (defined($$bp_ref{'src'}))	{
		if ((-d "$$bp_ref{'src'}") && ($$bp_ref{'src'} !~ /\/$/))	{
			$src = $$bp_ref{'src'} . '/';
		} else	{
			$src = $$bp_ref{'src'};
		}
	}
	
	# create missing parent directories inside the $interval.x directory
	my @dirs = split(/\//, $$bp_ref{'dest'});
	pop(@dirs);
	
	# don't mkdir for dest unless we have to
	my $destpath = "$config_vars{'snapshot_root'}/$interval.0/" . join('/', @dirs);
	
	# make sure we have a trailing slash
	if ($destpath !~ m/\/$/)	{
		$destpath .= '/';
	}
	
	# create the directory if it doesn't exist
	if ( ! -e "$destpath" )	{
		print_cmd("mkdir -m 0755 -p $destpath");
		
		if (0 == $test)	{
			eval	{
				mkpath( "$destpath", 0, 0755 );
			};
			if ($@)	{
				bail("Could not mkpath(\"$destpath\", 0, 0755);");
			}
		}
	}
	
	# IF WE HAVE A SRC DIRECTORY, SYNC IT TO DEST
	if (defined($$bp_ref{'src'}))	{
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
		if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'rsync_short_args'}) )	{
			$rsync_short_args = $$bp_ref{'opts'}->{'rsync_short_args'};
		}
		# RSYNC LONG ARGS
		if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'rsync_long_args'}) )	{
			@rsync_long_args_stack = split(/\s/, $$bp_ref{'opts'}->{'rsync_long_args'});
		}
		# SSH ARGS
		if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'ssh_args'}) )	{
			$ssh_args = $$bp_ref{'opts'}->{'ssh_args'};
		}
		# ONE_FS
		if ( defined($$bp_ref{'opts'}) && defined($$bp_ref{'opts'}->{'one_fs'}) )	{
			if (1 == $$bp_ref{'opts'}->{'one_fs'})	{
				$rsync_short_args .= 'x';
			}
		} elsif ($one_fs)	{
			$rsync_short_args .= 'x';
		}
		
		# SEE WHAT KIND OF SOURCE WE'RE DEALING WITH
		#
		# local filesystem
		if ( is_real_local_abs_path($src) )	{
			# no change
			
		# if this is a user@host:/path, use ssh
		} elsif ( is_ssh_path($src) )	{
			
			# if we have any args for SSH, add them
			if ( defined($ssh_args) )	{
				push( @rsync_long_args_stack, "--rsh=$config_vars{'cmd_ssh'} $ssh_args" );
				
			# no arguments is the default
			} else	{
				push( @rsync_long_args_stack, "--rsh=$config_vars{'cmd_ssh'}" );
			}
			
		# anonymous rsync
		} elsif ( is_anon_rsync_path($src) )	{
			# make rsync quiet if we're not running EXTRA verbose
			if ($verbose < 4)	{ $rsync_short_args .= 'q'; }
			
		# this should have already been validated once, but better safe than sorry
		} else	{
			bail("Could not understand source \"$src\" in backup_lowest_interval()");
		}
		
		# if we're using --link-dest, we'll need to specify .1 as the link-dest directory
		if (1 == $link_dest)	{
			if ( -d "$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}" )	{
				push(@rsync_long_args_stack, "--link-dest=$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}");
			}
		}
		
		# SPECIAL EXCEPTION:
		#   If we're using --link-dest AND the source is a file AND we have a copy from the last time,
		#   manually link interval.1/foo to interval.0/foo
		#
		#   This is necessary because --link-dest only works on directories
		#
		if ((1 == $link_dest) && (is_file($src)) && (-f "$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}"))	{
			# these are both "destination" paths, but we're moving from .1 to .0
			my $srcpath		= "$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}";
			my $destpath	= "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}";
			
			print_cmd("ln $srcpath $destpath");
			
			if (0 == $test)	{
				$result = link( "$srcpath", "$destpath" );
				
				if (!defined($result) or (0 == $result))	{
					print_err ("link(\"$srcpath\", \"$destpath\") failed", 2);
					syslog_err("link(\"$srcpath\", \"$destpath\") failed");
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
		if (defined($rsync_short_args) && ($rsync_short_args ne ''))	{
			push(@cmd_stack, $rsync_short_args);
		}
		#
		# rsync long args
		if (@rsync_long_args_stack && (scalar(@rsync_long_args_stack) > 0))	{
			foreach my $tmp_long_arg (@rsync_long_args_stack)	{
				if (defined($tmp_long_arg) && ($tmp_long_arg ne ''))	{
					push(@cmd_stack, $tmp_long_arg);
				}
			}
		}
		#
		# src
		push(@cmd_stack, $src);
		#
		# dest
		push(@cmd_stack, "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}");
		#
		# END RSYNC COMMAND ASSEMBLY
		
		
		# RUN THE RSYNC COMMAND FOR THIS BACKUP POINT BASED ON THE @cmd_stack VARS
		print_cmd(@cmd_stack);
		
		if (0 == $test)	{
			$result = system(@cmd_stack);
			
			# now we see if rsync ran successfully, and what to do about it
			if ($result != 0)	{
				# bitmask return value
				my $retval = get_retval($result);
				
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
				if ((1 == $link_dest) && (1 == $retval))	{
					print_err ("$config_vars{'cmd_rsync'} returned $retval. Does this version of rsync support --link-dest?", 2);
					syslog_err("$config_vars{'cmd_rsync'} returned $retval. Does this version of rsync support --link-dest?");
					
				# 23 and 24 are treated as warnings because users might be using the filesystem during the backup
				# if you want perfect backups, don't allow the source to be modified while the backups are running :)
				} elsif (23 == $retval)	{
					print_warn ("Some files and/or directories in $src only transferred partially during rsync operation", 4);
					syslog_warn("Some files and/or directories in $src only transferred partially during rsync operation");
					
				} elsif (24 == $retval)	{
					print_warn ("Some files and/or directories in $src vanished during rsync operation", 4);
					syslog_warn("Some files and/or directories in $src vanished during rsync operation");
					
				# other error
				} else	{
					print_err ("$config_vars{'cmd_rsync'} returned $retval", 2);
					syslog_err("$config_vars{'cmd_rsync'} returned $retval");
					
					# set this directory to rollback if we're using link_dest
					# (since $interval.0/ will have been moved to $interval.1/ by now)
					if (1 == $link_dest)	{
						push(@rollback_points, $$bp_ref{'dest'});
					}
				}
			}
		}
		
	# OR, IF WE HAVE A BACKUP SCRIPT, RUN IT, THEN SYNC IT TO DEST
	} elsif (defined($$bp_ref{'script'}))	{
		# work in a temp dir, and make this the source for the rsync operation later
		# not having a trailing slash is a subtle distinction. it allows us to use
		# the same path if it's NOT a directory when we try to delete it.
		$tmpdir = "$config_vars{'snapshot_root'}/tmp";
		
		# remove the tmp directory if it's still there for some reason
		# (this shouldn't happen unless the program was killed prematurely, etc)
		if ( -e "$tmpdir" )	{
			print_cmd("$display_rm -rf $tmpdir");
			
			if (0 == $test)	{
				# if it's a dir, delete it
				if ( -d "$tmpdir" )	{
					$result = rm_rf("$tmpdir");
					if (0 == $result)	{
						bail("Could not rm_rf(\"$tmpdir\");");
					}
				# if for some stupid reason it's a file, unlink it
				} else	{
					$result = unlink("$tmpdir");
					if (0 == $result)	{
						bail("unlink(\"$tmpdir\")");
					}
				}
			}
		}
		
		# we're creating now, not destroying. the tmp dir needs a trailing slash
		$tmpdir .= '/';
		
		# create the tmp directory
		print_cmd("mkdir -m 0755 -p $tmpdir");
		
		if (0 == $test)	{
			eval	{
				mkpath( "$tmpdir", 0, 0755 );
			};
			if ($@)	{
				bail("Unable to create \"$tmpdir\",\nPlease make sure you have the right permissions.");
			}
		}
		
		# change to the tmp directory
		print_cmd("cd $tmpdir");
		
		if (0 == $test)	{
			$result = chdir("$tmpdir");
			if (0 == $result)	{
				bail("Could not change directory to \"$tmpdir\"");
			}
		}
		
		# run the backup script
		#
		# the assumption here is that the backup script is written in such a way
		# that it creates files in it's current working directory.
		#
		# the backup script should return 0 on success, anything else is
		# considered a failure.
		#
		print_cmd($$bp_ref{'script'});
		
		if (0 == $test)	{
			$result = system( $$bp_ref{'script'} );
			if ($result != 0)	{
				# bitmask return value
				my $retval = get_retval($result);
				
				print_err ("backup_script $$bp_ref{'script'} returned $retval", 2);
				syslog_err("backup_script $$bp_ref{'script'} returned $retval");
			}
		}
		
		# change back to the previous directory
		# (/ is a special case)
		if ('/' eq $cwd)	{
			print_cmd("cd $cwd");
		} else	{
			print_cmd("cd $cwd/");
		}
		
		if (0 == $test)	{
			chdir($cwd);
		}
		
		# if we're using link_dest, pull back the previous files (as links) that were moved up if any.
		# this is because in this situation, .0 will always be empty, so we'll pull select things
		# from .1 back to .0 if possible. these will be used as a baseline for diff comparisons by
		# sync_if_different() down below.
		if (1 == $link_dest)	{
			my $lastdir	= "$config_vars{'snapshot_root'}/$interval.1/$$bp_ref{'dest'}/";
			my $curdir	= "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}/";
			
			# if we even have files from last time
			if ( -e "$lastdir" )	{
				
				# and we're not somehow clobbering an existing directory (shouldn't happen)
				if ( ! -e "$curdir" )	{
					
					# call generic cp_al() subroutine
					if (0 == $test)	{
						$result = cp_al( "$lastdir", "$curdir" );
						if (! $result)	{
							print_err("Warning! cp_al(\"$lastdir\", \"$curdir/\")", 2);
						}
					}
				}
			}
		}
		
		# sync the output of the backup script into this snapshot interval
		# this is using a native function since rsync doesn't quite do what we want
		#
		# rsync sees that the timestamps are different, and insists
		# on changing things even if the files are bit for bit identical on content.
		#
		print_cmd("sync_if_different(\"$tmpdir\", \"$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}\")");
		
		if (0 == $test)	{
			$result = sync_if_different("$tmpdir", "$config_vars{'snapshot_root'}/$interval.0/$$bp_ref{'dest'}");
			if (!defined($result))	{
				print_err("Warning! sync_if_different(\"$tmpdir\", \"$$bp_ref{'dest'}\") returned undef", 2);
			}
		}
		
		# remove the tmp directory
		if ( -e "$tmpdir" )	{
			print_cmd("$display_rm -rf $tmpdir");
			
			if (0 == $test)	{
				$result = rm_rf("$tmpdir");
				if (0 == $result)	{
					bail("Could not rm_rf(\"$tmpdir\");");
				}
			}
		}
		
	# this should never happen
	} else	{
		bail("Either src or script must be defined in backup_lowest_interval()");
	}
}

# accepts interval we're operating on
# returns no arguments
# rolls back failed backups, as defined in the @rollback_points array
sub rollback_failed_backups	{
	my $interval = shift(@_);
	
	if (!defined($interval))	{ bail('interval not defined in rollback_failed_backups()'); }
	
	# rollback failed backups (if we're using link_dest)
	foreach my $rollback_point (@rollback_points)	{
		# TODO: flesh this out and do proper error checking
		#
		# print STDERR "rolling back $rollback_point\n";
		#
		# rm_rf("$config_vars{'snapshot_root'}/$interval.0/$rollback_point");
		#
		# cp_al(
		#	"$config_vars{'snapshot_root'}/$interval.1/$rollback_point",
		#	"$config_vars{'snapshot_root'}/$interval.0/$rollback_point"
		# );
	}
}

# accepts the interval to act on, and the previous interval (i.e. daily, hourly)
# this should not be the lowest interval, but any of the higher ones
#
# rotates older dirs within this interval, and hard links
# the previous interval's highest numbered dir to this interval's .0,
#
# does not return a value, it bails instantly if there's a problem
sub rotate_higher_interval	{
	my $interval		= shift(@_);	# i.e. daily
	my $prev_interval	= shift(@_);	# i.e. hourly
	
	# this should never happen
	if (!defined($interval) or !defined($prev_interval))	{
		bail('rotate_higher_interval() expects 2 arguments');
	}
	
	# ROTATE DIRECTORIES
	#
	# delete the oldest one (if we're keeping more than one)
	if ( -d "$config_vars{'snapshot_root'}/$interval.$interval_max" )	{
		print_cmd("$display_rm -rf $config_vars{'snapshot_root'}/$interval.$interval_max/");
		
		if (0 == $test)	{
			my $result = rm_rf( "$config_vars{'snapshot_root'}/$interval.$interval_max/" );
			if (0 == $result)	{
				bail("Could not rm_rf(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\");");
			}
		}
	} else	{
		print_msg("$config_vars{'snapshot_root'}/$interval.$interval_max not present (yet), nothing to delete", 4);
	}
	
	# rotate the middle ones
	for (my $i=($interval_max-1); $i>=0; $i--)	{
		if ( -d "$config_vars{'snapshot_root'}/$interval.$i" )	{
			print_cmd("mv $config_vars{'snapshot_root'}/$interval.$i/ ",
						"$config_vars{'snapshot_root'}/$interval." . ($i+1) . "/");
			
			if (0 == $test)	{
				my $result = rename(
								"$config_vars{'snapshot_root'}/$interval.$i/",
								("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/')
				);
				if (0 == $result)	{
					my $errstr = '';
					$errstr .= "Error! rename(\"$config_vars{'snapshot_root'}/$interval.$i/\", \"";
					$errstr .= "$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/' . "\")";
					bail($errstr);
				}
			}
		} else	{
			print_msg("$config_vars{'snapshot_root'}/$interval.$i not present (yet), nothing to delete", 4);
		}
	}
	
	# prev.max and interval.0 require more attention
	if ( -d "$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max" )	{
		my $result;
		
		# if the previous interval has at least 2 snapshots,
		# or if the previous interval isn't the smallest one,
		# move the last one up a level
		if (($prev_interval_max >= 1) or ($interval_num >= 2))	{
			# mv hourly.5 to daily.0 (or whatever intervals we're using)
			print_cmd("mv $config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/ ",
						"$config_vars{'snapshot_root'}/$interval.0/");
			
			if (0 == $test)	{
				$result = rename(
								"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/",
								"$config_vars{'snapshot_root'}/$interval.0/"
				);
				if (0 == $result)	{
					my $errstr = '';
					$errstr .= "Error! rename(\"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/\", ";
					$errstr .= "\"$config_vars{'snapshot_root'}/$interval.0/\")";
					bail($errstr);
				}
			}
		} else	{
			print_err("$prev_interval must be above 1 to keep snapshots at the $interval level", 1);
			exit(1);
		}
	} else	{
		print_msg("$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max not present (yet), nothing to copy", 4);
	}
}

# stub subroutine
# calls either gnu_cp_al() or native_cp_al()
# returns the value directly from whichever subroutine it calls
# also prints out what's happening to the screen, if appropriate
sub cp_al	{
	my $src  = shift(@_);
	my $dest = shift(@_);
	my $result = 0;
	
	if (1 == $have_gnu_cp)	{
		print_cmd("$config_vars{'cmd_cp'} -al $src $dest");
		$result = gnu_cp_al("$src", "$dest");
		
	} else	{
		print_cmd("native_cp_al(\"$src\", \"$dest\")");
		$result = native_cp_al("$src", "$dest");
	}
	
	return ($result);
}

# this is a wrapper to call the GNU version of "cp"
# it might fail in mysterious ways if you have a different version of "cp"
#
sub gnu_cp_al	{
	my $src    = shift(@_);
	my $dest   = shift(@_);
	my $result = 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	if ( ! -d "$src" )	{
		print_err("gnu_cp_al() needs a valid directory as an argument", 2);
		return (0);
	}
	
	# make the system call to GNU cp
	$result = system( $config_vars{'cmd_cp'}, '-al', "$src", "$dest" );
	if ($result != 0)	{
		print_err("Warning! $config_vars{'cmd_cp'} failed. Perhaps this is not GNU cp?", 2);
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
# In the great perl tradition, this returns 1 on success, 0 on failure.
#
sub native_cp_al	{
	my $src    = shift(@_);
	my $dest   = shift(@_);
	my $dh     = undef;
	my $result = 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" )	{
		print_err("native_cp_al() needs a valid source directory as an argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st))	{
		print_err("Warning! Could not lstat(\"$src\")", 2);
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" )	{
		# print and/or log this if necessary
		if (($verbose > 4) or ($loglevel > 4))	{
			my $cmd_string = "mkdir(\"$dest\", " . get_perms($st->mode) . ")";
		
			if ($verbose > 4)	{
				print_cmd($cmd_string);
			} elsif ($loglevel > 4)	{
				log_msg($cmd_string, 4);
			}
		}
		
		$result = mkdir("$dest", $st->mode);
		if ( ! $result )	{
			print_err("Warning! Could not mkdir(\"$dest\", $st->mode);", 2);
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		# print and/or log this if necessary
		if (($verbose > 4) or ($loglevel > 4))	{
			my $cmd_string = "chown(" . $st->uid . ", " . $st->gid . ", \"$dest\")";
		
			if ($verbose > 4)	{
				print_cmd($cmd_string);
			} elsif ($loglevel > 4)	{
				log_msg($cmd_string, 4);
			}
		}
		
		$result = chown($st->uid, $st->gid, "$dest");
		if (! $result)	{
			print_err("Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");", 2);
			return(0);
		}
	}
	
	# READ DIR CONTENTS
	$dh = new DirHandle( "$src" );
	
	if (defined($dh))	{
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes)	{
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# make sure the node we just got is valid (this is highly unlikely to fail)
			my $st = lstat("$src/$node");
			if (!defined($st))	{
				print_err("Warning! Could not lstat(\"$src/$node\")", 2);
				next;
			}
			
			# SYMLINK (must be tested for first, because it will also pass the file and dir tests)
			if ( -l "$src/$node" )	{
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4))	{
					my $cmd_string = "copy_symlink(\"$src/$node\", \"$dest/$node\")";
				
					if ($verbose > 4)	{
						print_cmd($cmd_string);
					} elsif ($loglevel > 4)	{
						log_msg($cmd_string, 4);
					}
				}
				
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result)	{
					print_err("Warning! copy_symlink(\"$src/$node\", \"$dest/$node\")", 2);
					next;
				}
				
			# FILE
			} elsif ( -f "$src/$node" )	{
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4))	{
					my $cmd_string = "link(\"$src/$node\", \"$dest/$node\");";
				
					if ($verbose > 4)	{
						print_cmd($cmd_string);
					} elsif ($loglevel > 4)	{
						log_msg($cmd_string, 4);
					}
				}
				
				# make a hard link
				$result = link("$src/$node", "$dest/$node");
				if (! $result)	{
					print_err("Warning! Could not link(\"$src/$node\", \"$dest/$node\")", 2);
					next;
				}
				
			# DIRECTORY
			} elsif ( -d "$src/$node" )	{
				# print and/or log this if necessary
				if (($verbose > 4) or ($loglevel > 4))	{
					my $cmd_string = "native_cp_al(\"$src/$node\", \"$dest/$node\")";
				
					if ($verbose > 4)	{
						print_cmd($cmd_string);
					} elsif ($loglevel > 4)	{
						log_msg($cmd_string, 4);
					}
				}
				
				# call this subroutine recursively, to create the directory
				$result = native_cp_al("$src/$node", "$dest/$node");
				if (! $result)	{
					print_err("Warning! Recursion error in native_cp_al(\"$src/$node\", \"$dest/$node\")", 2);
					next;
				}
				
			# FIFO
			} elsif ( -p "$src/$node" )	{
				print_err("Warning! Ignoring FIFO $src/$node", 2);
				
			# SOCKET
			} elsif ( -S "$src/$node" )	{
				print_err("Warning! Ignoring socket: $src/$node", 2);
				
			# BLOCK DEVICE
			} elsif ( -b "$src/$node" )	{
				print_err("Warning! Ignoring special block file: $src/$node", 2);
				
			# CHAR DEVICE
			} elsif ( -c "$src/$node" )	{
				print_err("Warning! Ignoring special character file: $src/$node", 2);
			}
		}
		
	} else	{
		print_err("Could not open \"$src\". Do you have adequate permissions?", 2);
		return(0);
	}
	
	# close open dir handle
	if (defined($dh))	{ $dh->close(); }
	undef( $dh );
	
	# UTIME DEST
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4))	{
		my $cmd_string = "utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\");";
	
		if ($verbose > 4)	{
			print_cmd($cmd_string);
		} elsif ($loglevel > 4)	{
			log_msg($cmd_string, 4);
		}
	}
	$result = utime($st->atime, $st->mtime, "$dest");
	if (! $result)	{
		print_err("Warning! Could not utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\");", 2);
		return(0);
	}
	
	return (1);
}

# stub subroutine
# calls either cmd_rm_rf() or the native perl rmtree()
# returns 1 on success, 0 on failure
sub rm_rf	{
	my $path = shift(@_);
	my $result = 0;
	
	# make sure we were passed an argument
	if (!defined($path)) { return(0); }
	
	# extra bonus safety feature!
	# confirm that whatever we're deleting must be inside the snapshot_root
	if ("$path" !~ "^$config_vars{'snapshot_root'}")	{
		bail("rm_rf() tried to delete something outside of $config_vars{'snapshot_root'}! Quitting now!");
	}
	
	if (1 == $have_rm)	{
		$result = cmd_rm_rf("$path");
	} else	{
		$result = rmtree("$path", 0, 0);
	}
	
	return ($result);
}

# this is a wrapper to the "rm" program, called with the "-rf" flags.
sub cmd_rm_rf	{
	my $path = shift(@_);
	my $result = 0;
	
	# make sure we were passed an argument
	if (!defined($path)) { return(0); }
	
	if ( ! -e "$path" )	{
		print_err("cmd_rm_rf() needs a valid file path as an argument", 2);
		return (0);
	}
	
	# make the system call to /bin/rm
	$result = system( $config_vars{'cmd_rm'}, '-rf', "$path" );
	if ($result != 0)	{
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
sub show_disk_usage	{
	my $intervals_str = '';
	
	# find the intervals that apply here
	if (-r "$config_vars{'snapshot_root'}/")	{
		foreach my $interval_ref (@intervals)	{
			if (-r "$config_vars{'snapshot_root'}/$$interval_ref{'interval'}.0/")	{
				$intervals_str .= "$config_vars{'snapshot_root'}/$$interval_ref{'interval'}.* ";
			}
		}
	}
	chop($intervals_str);
	
	# if we can see any of them, find out how much space they're taking up
	if ('' ne $intervals_str)	{
		print "du -csh $intervals_str\n\n";
		my $retval = system("du -csh $intervals_str");
		if (0 == $retval)	{
			# exit with success
			exit(0);
		}
	} else	{
		print STDERR ("No intervals directories visible. Do you have permission to see the snapshot root?\n");
	}
	
	# exit showing error
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
sub sync_if_different	{
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $result	= 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" )	{
		print_err("sync_if_different() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# copy everything from src to dest
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4))	{
		my $cmd_string = "sync_cp_src_dest(\"$src\", \"$dest\")";
	
		if ($verbose > 4)	{
			print_cmd($cmd_string);
		} elsif ($loglevel > 4)	{
			log_msg($cmd_string, 4);
		}
	}
	$result = sync_cp_src_dest("$src", "$dest");
	if ( ! $result )	{
		print_err("Warning! sync_cp_src_dest(\"$src\", \"$dest\")", 2);
		return (0);
	}
	
	# delete everything from dest that isn't in src
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4))	{
		my $cmd_string = "sync_rm_dest(\"$src\", \"$dest\")";
	
		if ($verbose > 4)	{
			print_cmd($cmd_string);
		} elsif ($loglevel > 4)	{
			log_msg($cmd_string, 4);
		}
	}
	$result = sync_rm_dest("$src", "$dest");
	if ( ! $result )	{
		print_err("Warning! sync_rm_dest(\"$src\", \"$dest\")", 2);
		return (0);
	}
	
	return (1);
}

# accepts src, dest
# "copies" everything from src to dest, mainly using hard links
# called only from sync_if_different()
sub sync_cp_src_dest	{
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $dh		= undef;
	my $result	= 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" )	{
		print_err("sync_if_different() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st))	{
		print_err("Could not lstat(\"$src\")", 2);
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" )	{
		$result = mkdir("$dest", $st->mode);
		if ( ! $result )	{
			print_err("Warning! Could not mkdir(\"$dest\", $st->mode);", 2);
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		$result = chown($st->uid, $st->gid, "$dest");
		if (! $result)	{
			print_err("Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");", 2);
			return(0);
		}
	}
	
	# copy anything different from src into dest
	$dh = new DirHandle( "$src" );
	if (defined($dh))	{
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes)	{
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# make sure the node we just got is valid (this is highly unlikely to fail)
			my $st = lstat("$src/$node");
			if (!defined($st))	{
				print_err("Could not lstat(\"$src/$node\")", 2);
				return(0);
			}
			
			# if it's a symlink, create the link
			# this check must be done before dir and file because it will
			# pretend to be a file or a directory as well as a symlink
			if ( -l "$src/$node" )	{
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result)	{
					print_err("Warning! copy_symlink(\"$src/$node\", \"$dest/$node\")", 2);
				}
				
			# if it's a directory, recurse!
			} elsif ( -d "$src/$node" )	{
				$result = sync_cp_src_dest("$src/$node", "$dest/$node");
				if (! $result)	{
					print_err("Warning! Recursion error in sync_cp_src_dest(\"$src/$node\", \"$dest/$node\")", 2);
				}
				
			# if it's a file...
			} elsif ( -f "$src/$node" )	{
				
				# if dest exists, check for differences
				if ( -e "$dest/$node" )	{
					
					# if they are different, unlink dest and link src to dest
					if (1 == file_diff("$src/$node", "$dest/$node"))	{
						$result = unlink("$dest/$node");
						if (0 == $result)	{
							print_err("Warning! unlink(\"$dest/$node\")", 2);
							next;
						}
						$result = link("$src/$node", "$dest/$node");
						if (0 == $result)	{
							print_err("Warning! link(\"$src/$node\", \"$dest/$node\")", 2);
							next;
						}
						
					# if they are the same, just leave dest alone
					} else	{
						next;
					}
					
				# ok, dest doesn't exist. just link src to dest
				} else	{
					$result = link("$src/$node", "$dest/$node");
					if (0 == $result)	{
						print_err("Warning! link(\"$src/$node\", \"$dest/$node\")", 2);
					}
				}
				
			# FIFO
			} elsif ( -p "$src/$node" )	{
				print_err("Warning! Ignoring FIFO $src/$node", 2);
				
			# SOCKET
			} elsif ( -S "$src/$node" )	{
				print_err("Warning! Ignoring socket: $src/$node", 2);
				
			# BLOCK DEVICE
			} elsif ( -b "$src/$node" )	{
				print_err("Warning! Ignoring special block file: $src/$node", 2);
				
			# CHAR DEVICE
			} elsif ( -c "$src/$node" )	{
				print_err("Warning! Ignoring special character file: $src/$node", 2);
			}
		}
	}
	# close open dir handle
	if (defined($dh))	{ $dh->close(); }
	undef( $dh );
	
	return (1);
}

# accepts src, dest
# deletes everything from dest that isn't in src also
# called only from sync_if_different()
sub sync_rm_dest	{
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $dh		= undef;
	my $result	= 0;
	
	# make sure we were passed two arguments
	if (!defined($src))  { return(0); }
	if (!defined($dest)) { return(0); }
	
	# make sure we have a source directory
	if ( ! -d "$src" )	{
		print_err("sync_rm_dest() needs a valid source directory as its first argument", 2);
		return (0);
	}
	
	# make sure we have a destination directory
	if ( ! -d "$dest" )	{
		print_err("sync_rm_dest() needs a valid destination directory as its first argument", 2);
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# delete anything from dest that isn't found in src
	$dh = new DirHandle( "$dest" );
	if (defined($dh))	{
		my @nodes = $dh->read();
		
		# loop through all nodes in this dir
		foreach my $node (@nodes)	{
			
			# skip '.' and '..'
			next if ($node =~ m/^\.\.?$/o);
			
			# make sure the node we just got is valid (this is highly unlikely to fail)
			my $st = lstat("$dest/$node");
			if (!defined($st))	{
				print_err("Warning! Could not lstat(\"$dest/$node\")", 2);
				next;
			}
			
			# if this node isn't present in src, delete it
			if ( ! -e "$src/$node" )	{
				$result = rm_rf("$dest/$node");
				if (0 == $result)	{
					print_err("Warning! Could not delete \"$dest/$node\"", 2);
				}
				
			# ok, this also exists in src
			# if it's a directory, let's recurse into it and compare files there
			} elsif ( -d "$src/$node" )	{
				$result = sync_rm_dest("$src/$node", "$dest/$node");
				if ( ! $result )	{
					print_err("Warning! Recursion error in sync_rm_dest(\"$src/$node\", \"$dest/$node\")", 2);
				}
			}
		}
	}
	# close open dir handle
	if (defined($dh))	{ $dh->close(); }
	undef( $dh );
	
	return (1);
	
}

# accepts src, dest
# "copies" a symlink from src by recreating it in dest
# returns 1 on success, 0 on failure
sub copy_symlink	{
	my $src		= shift(@_);
	my $dest	= shift(@_);
	my $st		= undef;
	my $result	= undef;
	
	# make sure it's actually a symlink
	if ( ! -l "$src" )	{
		print_err("Warning! \"$src\" not a symlink in copy_symlink()", 2);
		return (0);
	}
	
	# make sure we aren't clobbering the destination
	if ( -e "$dest" )	{
		print_err("Warning! \"$dest\" exists!", 2);
	}
	
	# LSTAT
	$st = lstat("$src");
	if (!defined($st))	{
		print_err("Warning! lstat(\"$src\")", 2);
		return (0);
	}
	
	# CREATE THE SYMLINK
	# print and/or log this if necessary
	if (($verbose > 4) or ($loglevel > 4))	{
		my $cmd_string = "symlink(\"" . readlink("$src") . "\", \"$dest\");";
	
		if ($verbose > 4)	{
			print_cmd($cmd_string);
		} elsif ($loglevel > 4)	{
			log_msg($cmd_string, 4);
		}
	}
	$result = symlink(readlink("$src"), "$dest");
	if (! $result)	{
		print_err("Warning! Could not symlink(readlink(\"$src\"), \"$dest\")", 2);
		return (0);
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		if ( -e "$dest" )	{
			# print and/or log this if necessary
			if (($verbose > 4) or ($loglevel > 4))	{
				my $cmd_string = "chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");";
			
				if ($verbose > 4)	{
					print_cmd($cmd_string);
				} elsif ($loglevel > 4)	{
					log_msg($cmd_string, 4);
				}
			}
			
			$result = chown($st->uid, $st->gid, "$dest");
			
			if (! $result)	{
				print_err("Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\")", 2);
				return (0);
			}
		}
	}
	
	return (1);
}

# accepts a file permission number from $st->mode (i.e. 33188)
# returns a "normal" file permission number (i.e. 644)
# do the appropriate bit shifting to get a "normal" UNIX file permission mode
sub get_perms	{
	my $raw_mode = shift(@_);
	
	if (!defined($raw_mode))	{ return (undef); }
	
	# a lot of voodoo for just one line
	# http://www.perlmonks.org/index.pl?node_id=159906
	my $mode = sprintf("%04o", ($raw_mode & 07777));
	
	return ($mode);
}

# accepts return value from the system() command
# bitmasks it, and returns the same thing "echo $?" would
sub get_retval	{
	my $retval = shift(@_);
	
	if (!defined($retval))	{
		bail('get_retval() was not passed a value');
	}
	if ($retval !~ m/^\d+$/)	{
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
	
	# while loop condition flag
	my $done = 0;
	
	# boolean file comparison flag. assume they're the same.
	my $is_different = 0;
	
	if (! -r "$file1")  { return (undef); }
	if (! -r "$file2")  { return (undef); }
	
	# CHECK FILE SIZES FIRST
	$st1 = lstat("$file1");
	$st2 = lstat("$file2");
	
	if (!defined($st1))	{ return (undef); }
	if (!defined($st2))	{ return (undef); }
	
	# if the files aren't even the same size, they can't possibly be the same.
	# don't waste time comparing them more intensively
	if ($st1->size != $st2->size)	{
		return (1);
	}
	
	# ok, we're still here.
	# that means we have to compare files one chunk at a time
	
	# open both files
	$result = open(FILE1, "$file1");
	if (!defined($result))	{
		return (undef);
	}
	$result = open(FILE2, "$file2");
	if (!defined($result))	{
		close(FILE1);
		return (undef);
	}
	
	# compare files
	while ((0 == $done) && (read(FILE1, $buf1, $BUFSIZE)) && (read(FILE2, $buf2, $BUFSIZE)))	{
		# exit this loop as soon as possible
		if ($buf1 ne $buf2)	 {
			$is_different = 1;
			$done = 1;
			last;
		}
	}
	
	# close both files
	$result = close(FILE2);
	if (!defined($result))	{
		close(FILE1);
		return (undef);
	}
	$result = close(FILE1);
	if (!defined($result))	{
		return (undef);
	}
	
	# return our findings
	return ($is_different);
}

#####################
### PERLDOC / POD ###
#####################

=pod

=head1 NAME

rsnapshot - remote filesystem snapshot utility

=head1 SYNOPSIS

B<rsnapshot> [B<-vtxqVD>] [B<-c> cfgfile] [command]

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
located by default at B</etc/rsnapshot.conf>. An alternate one can be
specified on the command line. There are also additional options which
can be passed on the command line.

The command line options are as follows:

=over 4

B<-v> verbose, show shell commands being executed

B<-t> test, show shell commands that would be executed

B<-c> path to alternate config file

B<-x> one filesystem, don't cross partitions within each backup point

B<-q> quiet, supress non-fatal warnings

B<-V> same as -v, but show rsync output as well

B<-D> a firehose of diagnostic information

=back

=head1 CONFIGURATION

B</etc/rsnapshot.conf> is the default configuration file. All parameters
in this file must be seperated by tabs. B</etc/rsnapshot.conf.default>
can be used as a syntactically valid reference.

It is recommended that you copy B</etc/rsnapshot.conf.default> to
B</etc/rsnapshot.conf>, and then modify B</etc/rsnapshot.conf> to suit
your needs. What follows here is a list of allowed parameters:

=over 4

B<snapshot_root>  Local filesystem path to save all snapshots

B<no_create_root> If set to 1, rsnapshot won't create snapshot_root directory

B<cmd_rsync>      Full path to rsync (required)

B<cmd_ssh>        Full path to ssh (optional)

B<cmd_cp>         Full path to cp  (optional, but must be GNU version)

B<cmd_rm>         Full path to rm  (optional)

B<cmd_logger>     Full path to logger (optional, for syslog support)

=over 4

If you have GNU cp, you should uncomment cmd_cp, since you will get extra
functionality. If you don't have GNU cp, leave it commented out, and
rsnapshot will work almost as well. If you are using Linux, you have GNU
cp. If you're on BSD, Solaris, IRIX, etc., then there's a good chance you
don't have the right version. Never fear, you still have options. You can
get GNU cp set up on your system (possibly in an alternate path so as to
not conflict with your existing version). Or, if you only need support
for normal files, directories, and symlinks, you can just leave cmd_cp
commented out and rsnapshot will use a built-in perl substitute. This
will run about 40% slower, and will not let you back up the following
types of files:

=over 4

FIFO

Socket

Block / Character devices

=back

Furthermore, hard links to symlinks are not portable, so new symlinks
will be created when they need to be copied.

=back

B<interval>      [name] [number]

=over 4

"name" refers to the name of this interval (i.e. hourly, daily). "number"
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

Each backup point in <snapshot_root>/hourly.0/ will be rsynced with the
backup points specified in this config file later.

Intervals must be specified in the config file in order, from most
frequent to least frequent. The first entry is the one which will be
synced with the backup points. The subsequent intervals (i.e. daily,
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
otherwise do. The only drawback is that if a host becomes unavailable during
a backup operation, the last good files will get rotated up, and a full re-sync
will be required on the next pass.

=back

B<verbose             2>

=over 4

The amount of information to print out when the program is run. Allowed values
are 1 through 5. The default is 2.

1        Quiet            Show fatal errors only

2        Default          Show warnings and errors

3        Verbose          Show equivalent shell commands being executed

4        Extra Verbose    Same as verbose, but with still more output

5        Debug            All kinds of information

=back

B<loglevel            3>

=over 4

This number means the same thing as B<verbose> above, but it determines how
much data is written to the logfile, if one is being written.

=back

B<logfile             /var/log/rsnapshot>

=over 4

Full filesystem path to the rsnapshot log file. If this is defined, a log file
will be written, with the amount of data being controlled by B<loglevel>. If
this is commented out, no log file will be written.

=back

B<include             ???>

=over 4

This gets passed directly to rsync using the --include directive. This
parameter can be specified as many times as needed, with one pattern defined
per line. See the rsync(1) man page for the syntax.

=back

B<exclude             ???>

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
For example, "-an" is valid, while "-a -n" is not.

=back

B<rsync_long_args     --delete --numeric-ids>

=over 4

List of long arguments to pass to rsync. If not specified,
"--delete --numeric-ids" is the default.

=back

B<ssh_args			-p 22>

=over 4

Arguments to be passed to ssh. If not specified, the default is none.

=back

B<lockfile    /var/lock/subsys/rsnapshot>

=over 4

Lockfile to use when rsnapshot is run. This prevents a second invocation
from clobbering the first one. If not specified, no lock file is used.
Make sure to use a directory that is not world writeable for security
reasons.

=back

B<one_fs  1>

=over 4

Prevents rsync from crossing filesystem partitions. Setting this to a value
of 1 enables this feature. 0 turns it off. This parameter is optional.
The default is off.

=back

B<backup>  /local/path/                localhost/path/

B<backup>  root@example.com:/path/     example.com/path/

B<backup>  rsync://example.com/path2/  example.com/path2/

B<backup>  /local/path2/               localhost/path2/      one_fs=1

B<backup_script>    /usr/local/bin/backup_database.sh    db_backup/

=over 4

Examples:

B<backup   /etc/     etc/>

=over 4

Backs up /etc/ to <snapshot_root>/<interval>.0/etc/ using rsync on the local filesystem

=back

B<backup   root@example.com:/home/       example.com/home/>

=over 4

Backs up root@example.com:/home/ to <snapshot_root>/<interval>.0/example.com/home/
using rsync over ssh

=back

B<backup   rsync://example.com/pub/      example.com/pub/>

=over 4

Backs up rsync://example.com/pub/ to <snapshot_root>/<interval>.0/example.com/pub/
using an anonymous rsync server

=back

B<backup   /local/path2/    localhost/path2/    one_fs=1>

=over 4

This is the same as the first example, but notice how the fourth parameter is passed.
This sets this backup point to not span filesystem partitions. If the global one_fs
has been set, this will override it locally.

=back

B<backup_script      /usr/local/bin/backup_database.sh   db_backup/>

=over 4

In this example, we specify a script or program to run. This script should simply
create files and/or directories in it's current working directory. rsnapshot will
then take that output and move it into the directory specified in the third column.
So in this example, say the backup_database.sh script simply runs a command like:

=over 4

#!/bin/sh

mysqldump -uusername mydatabase > mydatabase.sql

=back

rsnapshot will take the generated "mydatabase.sql" file and move it into the
db_backup/ directory inside the snapshot interval, just the same as if it had
been sitting on the filesystem. If the backup script generates the same output
on the next run, no additional disk space will be taken up.

=back

=back

=back

Remember that tabs must seperate all elements, and that
there must be a trailing slash on the end of every directory.

A hash mark (#) on the beginning of a line is treated
as a comment.

Putting it all together (an example file):

=over 4

# THIS IS A COMMENT, REMEMBER TABS MUST SEPERATE ALL ELEMENTS

B<snapshot_root>   /.snapshots/

B<cmd_rsync>       /usr/bin/rsync

B<cmd_ssh>         /usr/bin/ssh

B<#cmd_cp>         /bin/cp

B<#cmd_rm>         /bin/rm

B<cmd_logger>      /usr/bin/logger

B<interval>        hourly  6

B<interval>        daily   7

B<interval>        weekly  7

B<interval>        monthly 3

B<backup>  /etc/                        localhost/etc/

B<backup>  /home/                       localhost/home/

B<backup>  root@foo.com:/etc/           foo.com/etc/

B<backup>  root@foo.com:/home/          foo.com/home/

B<backup>  root@mail.foo.com:/home/     mail.foo.com/home/

B<backup>  rsync://example.com/pub/     example.com/pub/

B<backup_script>    /usr/local/bin/backup_database.sh    db_backup/

=back

=head1 USAGE

B<rsnapshot> can be used by any user, but for system-wide backups
you will probably want to run it as root. Since backups tend to
get neglected if human intervention is required, the preferred
way is to run it from cron.

Here is an example crontab entry, assuming that intervals B<hourly>,
B<daily>, B<weekly> and B<monthly> have been defined in B</etc/rsnapshot.conf>

=over 4

B<0 */4 * * *         /usr/local/bin/rsnapshot hourly>

B<50 23 * * *         /usr/local/bin/rsnapshot daily>

B<40 23 1,8,15,22 * * /usr/local/bin/rsnapshot weekly>

B<30 23 1 * *         /usr/local/bin/rsnapshot monthly>

=back

This example will do the following:

=over 4

6 hourly backups a day (once every 4 hours, at 0,4,8,12,16,20)

1 daily backup every day, at 11:50PM

4 weekly backups a month, at 11:40PM, on the 1st, 8th, 15th, and 22nd

1 monthly backup every month, at 11:30PM on the 1st day of the month

=back

Remember that these are just the times that the program runs.
To set the number of backups stored, set the interval numbers in B</etc/rsnapshot.conf>

To check the disk space used by rsnapshot, you can call it with the "du" argument.

For example:

=over 4

B</usr/local/bin/rsnapshot du>

=back

This will show you exactly how much disk space is taken up in the snapshot root. This
feature requires the UNIX B<du> command to be installed on your system, and in your path.

=head1 EXIT VALUES

=over 4

B<0>  All operations completed successfully

B<1>  A fatal error occured

B<2>  Some warnings occured, but the backup still finished

=back

=head1 FILES

/etc/rsnapshot.conf

=head1 SEE ALSO

rsync(1), ssh(1), logger(1), sshd(1), ssh-keygen(1), perl(1), cp(1)

=head1 DIAGNOSTICS

Use the B<-t> flag to see what commands would have been executed. The
B<-v>, B<-V>, and B<-D> flags will print increasingly more information.
Much weird behavior can probably be attributed to plain old file system
permissions and ssh authentication issues.

=head1 BUGS

Swat them, or report them to B<nathan@rsnapshot.org>

=head1 NOTES

Make sure your /etc/rsnapshot.conf file has all elements seperated by tabs.
See /etc/rsnapshot.conf.default for a working example file.

Make sure you put a trailing slash on the end of all directory references.
If you don't, you may have extra directories created in your snapshots.
For more information on how the trailing slash is handled, see the
B<rsync(1)> manpage.

If you do not plan on making the backups readable by regular users, be
sure to make the snapshot directory chmod 700 root. If the snapshot
directory is readable by other users, they will be able to modify the
snapshots containing their files, thus destroying the integrity of the
snapshots.

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

For ssh to work unattended through cron, you will probably want to use
public key logins. Create an ssh key with no passphrase for root, and
install the public key on each machine you want to backup. If you are
backing up system files from remote machines, this probably means
unattended root logins. Another posibility is to create a second user
on the machine just for backups. Give the user a different name such
as "rsnapshot", but keep the UID and GID set to 0, to give root
privileges. However, make logins more restrictive, either through ssh
configuration, or using an alternate shell such as B<scponly>.

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
be unmanageable.

If you remove backup points in the config file, the previously archived
files under those points will permanently stay in the snapshots directory
unless you remove the files yourself. If you want to conserve disk space,
you will need to go into the <snapshot_root> directory and manually
remove the files from the smallest interval's ".0" directory.

For example, if you were previously backing up /home/ in home/, and
hourly is your smallest interval, you would need to do the following to
reclaim that disk space:

=over 4

rm -rf <snapshot_root>/hourly.0/home/

=back

Please note that the other snapshots previously made of /home/ will still
be using that disk space, but since the files are flushed out of hourly.0/,
they will no longer be copied to the subsequent directories, and will thus
be removed in due time as the rotations happen.

=head1 AUTHORS

Based on code originally by Mike Rubel

=over 4

B<http://www.mikerubel.org/computers/rsync_snapshots/>

=back

Rewritten and expanded in Perl by Nathan Rosenquist

=over 4

B<http://www.rsnapshot.org/>

=back

Carl Wilhelm Soderstrom B<(chrome@real-time.com)> created the RPM
.spec file which allowed the RPM package to be built, among other
things.

Ted Zlatanov (B<tzz@lifelogs.com>) contributed code, advice, patches
and many good ideas.

Ralf van Dooren (B<r.vdooren@snow.nl>) added and maintains the
rsnapshot entry in the FreeBSD ports tree.

Carl Boe (B<boe@demog.berkeley.edu>) Found several subtle bugs and
provided fixes for them.

=head1 COPYRIGHT

Copyright (C) 2003-2004 Nathan Rosenquist

Portions Copyright (C) 2002-2003 Mike Rubel, Carl Wilhelm Soderstrom,
Ted Zlatanov

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut

