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
use Cwd;
use DirHandle;
use Getopt::Std;
use File::Path;
use File::stat;

#########################
### DECLARE VARIABLES ###
#########################

my $VERSION = '1.0.8';

# default configuration file
my $config_file;

# hash to hold variables from the configuration file
my %config_vars;

# array of hash_refs containing the destination backup point
# and either a source dir or a script to run
my @snapshot_points;

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

# assume the config file syntax is OK unless we encounter problems
my $file_syntax_ok = 1;

# count the lines in the config file, so the user can pinpoint errors more precisely
my $file_line_num = 0;

# assume we don't have any of these programs
my $have_gnu_cp	= 0;
my $have_rsync	= 0;
my $have_ssh	= 0;

# flags that change the outcome of the program, and configurable by both cmd line and config flags
my $test			= 0; # turn verbose on, but don't execute any filesystem commands
my $do_configtest	= 0; # parse config file and exit
my $one_fs			= 0; # one file system (don't cross partitions within a backup point)

# how much noise should we make?
my $quiet			= 0; # don't display warnings about FIFOs and special files if enabled
my $verbose			= 0; # show the shell commands being executed
my $extra_verbose	= 0; # show extra verbose messages
my $debug			= 0; # super verbose debugging messages

# remember what directory we started in
my $cwd = cwd();

######################
### AUTOCONF STUFF ###
######################

# this file works both "as-is", and when it has been parsed by autoconf for installation
# the variables with "@" symbols on both sides get replaced during ./configure

# autoconf variables (may have too many slashes)
my $autoconf_sysconfdir	= '@sysconfdir@';
my $autoconf_prefix		= '@prefix@';

# consolidate multiple slashes
$autoconf_sysconfdir	=~ s/\/+/\//g;
$autoconf_prefix		=~ s/\/+/\//g;

# remove trailing slashes
$autoconf_sysconfdir	=~ s/\/$//g;
$autoconf_prefix		=~ s/\/$//g;

# if --sysconfdir was not set explicitly during ./configure, but we did use autoconf
if ($autoconf_sysconfdir eq '${prefix}/etc')	{
	$config_file = "$autoconf_prefix/etc/rsnapshot.conf";
	
# if --sysconfdir was set explicitly at ./configure, overriding the --prefix setting
} elsif ($autoconf_sysconfdir ne ('@' . 'sysconfdir' . '@'))	{
	$config_file = "$autoconf_sysconfdir/rsnapshot.conf";
	
# if all else fails, use the old standard from the pre-autoconf versions
} else	{
	$config_file = '/etc/rsnapshot.conf';
}

undef ($autoconf_sysconfdir);
undef ($autoconf_prefix);

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
### GET COMMAND LINE INPUT ###
##############################

# GET COMMAND LINE OPTIONS
getopt('c', \%opts);
getopts('vVtqx', \%opts);
$cmd = $ARGV[0];

# alternate config file
if (defined($opts{'c'}))	{
	$config_file = $opts{'c'};
}

# verbose (or extra verbose)?
if (defined($opts{'v'}))	{
	$verbose = 1;
}
if (defined($opts{'V'}))	{
	$verbose = 1;
	$extra_verbose = 1;
}

# debug
if (defined($opts{'D'}))	{
	$verbose = 1;
	$extra_verbose = 1;
	$debug = 1;
}

# test?
if (defined($opts{'t'}))	{
	$test = 1;
	$verbose = 1;
}

# quiet?
if (defined($opts{'q'}))	{
	$quiet = 1;
}

# one file system?
if (defined($opts{'x'}))	{
	$one_fs = 1;
}

# COMMAND LINE ARGS
if ( ! $cmd )	{
	show_usage();
	exit(0);
}
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
if ($cmd eq 'configtest')	{
	$do_configtest = 1;
}
# if we made it here, we didn't exit

#########################
### PARSE CONFIG FILE ###
#########################

if ( -f "$config_file" )	{
	open(CONFIG, $config_file) or bail("Could not open config file \"$config_file\"\nAre you sure you have permission?");
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
			config_error($file_line_num, $line);
			$file_syntax_ok = 0;
			next;
		}
		
		# SNAPSHOT_ROOT
		if ($var eq 'snapshot_root')	{
			# make sure this is a full path
			if (0 == is_valid_local_abs_path($value))	{
				config_error($file_line_num, "$line - snapshot_root must be a full path");
				$file_syntax_ok = 0;
				next;
			}
			
			# remove the trailing slash(es) if present
			$value = remove_trailing_slash($value);
			
			# if path exists already, make sure it's a directory
			if ((-e "$value") && (! -d "$value"))	{
				config_error($file_line_num, $line);
				# exit now since we'd get unnecessary failures by snapshot_root being undefined
				bail("snapshot_root must be a directory");
			}
			
			$config_vars{'snapshot_root'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		
		# CHECK FOR RSYNC (required)
		if ($var eq 'cmd_rsync')	{
			if ( -x "$value" )	{
				$config_vars{'cmd_rsync'} = $value;
				$have_rsync = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_error($file_line_num, $line);
				bail("could not find $value, please fix cmd_rsync in $config_file");
			}
		}
		
		# CHECK FOR SSH (optional)
		if ($var eq 'cmd_ssh')	{
			if ( -x "$value" )	{
				$config_vars{'cmd_ssh'} = $value;
				$have_ssh = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_error($file_line_num, $line);
				bail("could not find $value, please fix cmd_ssh in $config_file");
			}
		}
		
		# CHECK FOR GNU cp (optional)
		if ($var eq 'cmd_cp')	{
			if ( -x "$value" )	{
				$config_vars{'cmd_cp'} = $value;
				$have_gnu_cp = 1;
				$line_syntax_ok = 1;
				next;
			} else	{
				config_error($file_line_num, $line);
				bail("Could not find $value, please fix cmd_cp in $config_file");
			}
		}
		
		# INTERVALS
		if ($var eq 'interval')	{
			if (!defined($value))		{ bail("Interval can not be blank"); }
			if ($value !~ m/^[\w\d]+$/)	{ bail("\"$value\" is not a valid entry, must be alphanumeric characters only"); }
			
			if (!defined($value2))		{ bail("\"$value\" number can not be blank"); }
			if ($value2 !~ m/^\d+$/)	{ bail("\"$value2\" is not an integer"); }
			if (0 == $value2)			{ bail("\"$value\" can not be 0"); }
			
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
			
			if ( !defined($config_vars{'snapshot_root'}) )	{	bail("snapshot_root needs to be defined before backup points"); }
			
			# make sure we have a local path for the destination
			# (we do NOT want a local path)
			if ( is_valid_local_abs_path($dest) )	{
				bail("Backup destination $dest must be a local path");
			}
			
			# make sure we aren't traversing directories (exactly 2 dots can't be next to each other)
			if ( is_directory_traversal($src) )		{ bail("Directory traversal attempted in $src"); }
			if ( is_directory_traversal($dest) )	{ bail("Directory traversal attempted in $dest"); }
			
			# validate source path
			#
			# local absolute?
			if ( is_real_local_abs_path($src) )	{
				$line_syntax_ok = 1;
				
			# syntactically valid remote ssh?
			} elsif ( is_ssh_path($src) )	{
				# if it's an absolute ssh path, make sure we have ssh
				if (0 == $have_ssh)	{ bail("Cannot handle $src, cmd_ssh not defined in $config_file"); }
				$line_syntax_ok = 1;
				
			# if it's anonymous rsync, we're ok
			} elsif ( is_anon_rsync_path($src) )	{
				$line_syntax_ok = 1;
				
			# fear the unknown
			} else	{
				bail("Source directory \"$src\" doesn't exist");
			}
			
			# validate destination path
			#
			if ( is_valid_local_abs_path($dest) )	{ bail("Full paths not allowed for backup destinations"); }
			
			# if we have special options specified for this backup point, remember them
			if (defined($opt_str) && $opt_str)	{
				$opts_ref = parse_backup_opts($opt_str);
				if (!defined($opts_ref))	{
					bail("Syntax error on line $file_line_num in extra opts: $opt_str");
				}
			}
			
			# remember src/dest
			# also, first check to see that we're not backing up the snapshot directory
			if ((is_real_local_abs_path("$src")) && ($config_vars{'snapshot_root'} =~ $src))	{
				
				# remove trailing slash from source, since we will be using our own
				$src = remove_trailing_slash($src);
				
				opendir(SRC, "$src") or bail("Could not open $src");
				
				while (my $node = readdir(SRC))	{
					next if ($node =~ m/^\.\.?$/o);	# skip '.' and '..'
					
					if ("$src/$node" ne "$config_vars{'snapshot_root'}")	{
						my %hash;
						$hash{'src'}	= "$src/$node";
						$hash{'dest'}	= "$dest/$node";
						if (defined($opts_ref))	{
							$hash{'opts'} = $opts_ref;
						}
						push(@snapshot_points, \%hash);
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
				push(@snapshot_points, \%hash);
			}
			
			next;
		}
		
		# BACKUP SCRIPTS
		if ($var eq 'backup_script')	{
			my $script		= $value;	# backup script to run
			my $dest		= $value2;	# dest directory
			my %hash;
			
			if ( !defined($config_vars{'snapshot_root'}) )	{ bail("snapshot_root needs to be defined before backup points"); }
			
			# make sure the script is a full path
			if (1 == is_valid_local_abs_path($dest))	{
				bail("Backup destination $dest must be a local path");
			}
			
			# make sure we aren't traversing directories (exactly 2 dots can't be next to each other)
			if (1 == is_directory_traversal($dest))	{ bail("Directory traversal attempted in $dest"); }
			
			# validate destination path
			if ( is_valid_local_abs_path($dest) )	{ bail("Full paths not allowed for backup destinations"); }
			
			# make sure script exists and is executable
			if ( ! -x "$script" )	{
				bail("Backup script \"$script\" is not executable or does not exist");
			}
			
			$hash{'script'}	= $script;
			$hash{'dest'}	= $dest;
			
			$line_syntax_ok = 1;
			
			push(@snapshot_points, \%hash);
			
			next;
		}
		
		# GLOBAL OPTIONS from the config file
		# ALL ARE OPTIONAL
		#
		# ONE_FS
		if ($var eq 'one_fs')	{
			if (!defined($value))		{ bail("one_fs can not be blank"); }
			if (!is_boolean($value))	{ bail("\"$value\" is not a valid entry, must be 0 or 1 only"); }
			
			if (1 == $value)	{ $one_fs = 1; }
			$line_syntax_ok = 1;
			next;
		}
		# LOCKFILE
		if ($var eq 'lockfile')	{
			if (!defined($value))	{ bail("lockfile can not be blank"); }
			if (0 == is_valid_local_abs_path("$value"))	{
				 bail("lockfile must be a full path");
			}
			$config_vars{'lockfile'} = $value;
			$line_syntax_ok = 1;
			next;
		}
		# RSYNC SHORT ARGS
		if ($var eq 'rsync_short_args')	{
			$config_vars{'rsync_short_args'} = $value;
			$line_syntax_ok = 1;
			next;
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
		
		# make sure we understood this line
		# if not, warn the user, and prevent the program from executing
		if (0 == $line_syntax_ok)	{
			config_error($file_line_num, $line);
			$file_syntax_ok = 0;
			next;
		}
	}
	close(CONFIG) or print STDERR "Warning! Could not close $config_file\n";
	
	# make sure we got rsync in there somewhere
	if (0 == $have_rsync)	{
		print STDERR "cmd_rsync was not defined.\n";
		$file_syntax_ok = 0;
	}
	
	# CONFIG TEST ONLY?
	# if so, pronounce success and quit right here
	if ($do_configtest && $file_syntax_ok)	{
		print "Syntax OK\n";
		exit(0);
	}
} else	{
	print STDERR "Config file \"$config_file\" does not exist or is not readable.\n";
	if (-e "$config_file.default")	{
		print STDERR "Did you copy $config_file.default to $config_file yet?\n";
	}
	exit(-1);
}

# BAIL OUT HERE IF THERE WERE ERRORS IN THE CONFIG FILE
if (0 == $file_syntax_ok)	{
	print STDERR "---------------------------------------------------------------------\n";
	print STDERR "Errors were found in $config_file, rsnapshot can not continue.\n";
	print STDERR "If you think an entry looks right, make sure you don't have\n";
	print STDERR "spaces where only tabs should be.\n";
	exit(-1);
}

# IF WE'RE USING A LOCKFILE, TRY TO ADD IT
# the program will bail if one exists
if (defined($config_vars{'lockfile'}))	{
	add_lockfile( $config_vars{'lockfile'} );
}

# FIGURE OUT WHICH INTERVAL WE'RE RUNNING, AND HOW IT RELATES TO THE OTHERS
# THEN RUN THE ACTION FOR THE CHOSEN INTERVAL
# remember, in each hashref in this loop:
#   "interval" is something like "daily", "weekly", etc.
#   "number" is the number of these intervals to keep on the filesystem
#
my $i = 0;
foreach my $i_ref (@intervals)	{
	
	# this is the interval we're set to run
	if ($$i_ref{'interval'} eq $cmd)	{
		$interval_num = $i;
		
		# how many of these intervals should we keep?
		if ($$i_ref{'number'} > 0)	{
			$interval_max = $$i_ref{'number'} - 1;
		} else	{
			bail("$$i_ref{'interval'} can not be set to 0");
		}
		
		# ok, exit this entire block
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
	if ($$i_ref{'number'} > 0)	{
		$prev_interval_max = $$i_ref{'number'} - 1;
	} else	{
		bail("$$i_ref{'interval'} can not be set to 0");
	}
	
	$i++;
}
undef($i);

# MAKE SURE THE USER IS REQUESTING TO RUN ON AN INTERVAL WE UNDERSTAND
if (!defined($interval_num))	{
	bail("Interval \"$cmd\" unknown, check $config_file");
}

################################
### BEGIN FILESYSTEM ACTIONS ###
################################

# CREATE SNAPSHOT_ROOT IF IT DOESN'T EXIST, WITH THE FILE PERMISSIONS 0700
if ( ! -d "$config_vars{'snapshot_root'}" )	{
	if (1 == $verbose)	{ print "mkdir -m 0700 -p $config_vars{'snapshot_root'}\n"; }
	if (0 == $test)	{
		eval	{
			mkpath( "$config_vars{'snapshot_root'}", 0, 0700 );
		};
		if ($@)	{
			bail("Unable to create $config_vars{'snapshot_root'},\nPlease make sure you have the right permissions.");
		}
	}
}

# ACTUALLY RUN THE BACKUP JOB
if (0 == $interval_num)	{
	# if this is the most frequent interval, actually do the backups here
	backup_interval($cmd);
	
} else	{
	# this is not the most frequent unit, just rotate
	rotate_interval($cmd, $prev_interval);
}

# if we have a lockfile, remove it
if (defined($config_vars{'lockfile'}))	{
	remove_lockfile($config_vars{'lockfile'});
}

# if we got this far, assume success. the program is done running
exit(0);

###################
### SUBROUTINES ###
###################

# concise usage information
# runs when rsnapshot is called with no arguments
sub show_usage	{
	print "rsnapshot $VERSION\n";
	print "Usage: rsnapshot [-vtxqVD] [-c /alt/config/file] <interval>|configtest|help|version\n";
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

# accepts an error string
# prints to STDERR, and exits safely and consistently
sub bail	{
	my $str = shift(@_);
	
	if ($str)	{ print STDERR $str . "\n"; }
	remove_lockfile($config_vars{'lockfile'});
	exit(-1);
}

# accepts line number, errstr
# prints a config file error
sub config_error	{
	my $line_num	= shift(@_);
	my $errstr		= shift(@_);
	
	if (!defined($line_num))	{ $line_num = -1; }
	if (!defined($errstr))		{ $errstr = 'config_error() called without an error string!'; }
	
	print STDERR "Error in $config_file on line $line_num: $errstr\n";
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
	}
	
	# validate args
	# ONE_FS
	if ( defined($parsed_opts{'one_fs'}) )	{
		if (!is_boolean($parsed_opts{'one_fs'}))	{
			return (undef);
		}
	# RSYNC SHORT ARGS
	} elsif ( defined($parsed_opts{'rsync_short_args'}) )	{
		# pass unchecked
		
	# RSYNC LONG ARGS
	} elsif ( defined($parsed_opts{'rsync_long_args'}) )	{
		# pass unchecked
		
	# SSH ARGS
	} elsif ( defined($parsed_opts{'ssh_args'}) )	{
		# pass unchecked
		
	# if we don't know about it, it doesn't exist
	} else	{
		return (undef);
	}
	
	
	# if we got anything, return it as an array_ref
	if (%parsed_opts)	{
		return (\%parsed_opts);
	}
	
	return (undef);
}

# accepts the path to the lockfile we will try to create
# this either works, or exits the program at -1
#
# we don't use bail() to exit on error, because that would remove the
# lockfile that may exist from another invocation
sub add_lockfile	{
	my $lockfile = shift(@_);
	
	if (!defined($lockfile))	{
		print STDERR "add_lockfile() requires a value\n";
		exit(-1);
	}
	
	# valid?
	if (0 == is_valid_local_abs_path($lockfile))	{
		print STDERR "Lockfile $lockfile is not a valid file name\n";
		exit(-1);
	}
	
	# does a lockfile already exist?
	if (1 == is_real_local_abs_path($lockfile))	{
		print STDERR "Lockfile $lockfile exists, can not continue!\n";
		exit(-1);
	}
	
	if (1 == $verbose)	{ print "touch $lockfile\n"; }
	
	# create the lockfile
	my $result = open(LOCKFILE, "> $lockfile");
	if (!defined($result))	{
		print STDERR "Could not write lockfile $lockfile\n";
		exit(-1);
	}
	$result = close(LOCKFILE);
	if (!defined($result))	{
		print STDERR "Warning! Could not close lockfile $lockfile\n";
	}
}

# accepts the path to a lockfile and tries to remove it
# this subroutine either works, or it exits -1
#
# we don't use bail() to exit on error, because that would call
# this subroutine twice in the event of a failure
sub remove_lockfile	{
	my $lockfile	= shift(@_);
	my $result		= undef;
	
	if (defined($lockfile))	{
		if (1 == $verbose)	{ print "rm -f $lockfile\n"; }
		
		if ( -e "$lockfile" )	{
			$result = unlink($lockfile);
			if (0 == $result)	{
				print STDERR "Error! Could not remove lockfile $lockfile\n";
				exit(-1);
			}
		}
	}
}

# accepts one argument
# checks to see if that argument is set to 1 or 0
# returns 1 on success, 0 on failure
sub is_boolean	{
	my $var = shift(@_);
	
	if (!defined($var))	{ return (undef); }
	
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
	if ($str =~ /^#/)	{ return (1); }
	return (0);
}

# accepts string
# returns 1 if it is blank, or just pure white space
# returns 0 otherwise
sub is_blank	{
	my $str = shift(@_);
	
	if (!defined($str))		{ return (undef); }
	if ($str =~ /^\s*$/)	{ return (1); }
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

# accepts path
# returns 1 if it's a syntactically valid absolute path
# returns 0 otherwise
sub is_valid_local_abs_path	{
	my $path	= shift(@_);
	
	if (!defined($path))	{ return (undef); }
	if ($path =~ m/^\//)	{ return (1); }
	
	return (0);
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

sub is_directory_traversal	{
	my $path = shift(@_);
	
	if (!defined($path))					{ return (undef); }
	if ($path =~ m/[^\/\.]\.{2}[^\/\.]/)	{ return (1); }
	return (0);
}

# accepts string
# removes trailing slash, returns the string
sub remove_trailing_slash	{
	my $str = shift(@_);
	
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
sub backup_interval	{
	my $interval = shift(@_);
	
	# this should never happen
	if (!defined($interval))	{ bail('backup_interval() expects an argument'); }
	
	# set up default args for rsync and ssh
	my $default_rsync_short_args	= '-a';
	my $default_rsync_long_args		= '--delete --numeric-ids';
	my $default_ssh_args			= undef;
	
	# if the config file specified rsync or ssh args, use those instead
	if (defined($config_vars{'rsync_short_args'}))	{
		$default_rsync_short_args = $config_vars{'rsync_short_args'};
	}
	if (defined($config_vars{'rsync_long_args'}))	{
		$default_rsync_long_args = $config_vars{'rsync_long_args'};
	}
	if (defined($config_vars{'ssh_args'}))	{
		$default_ssh_args = $config_vars{'ssh_args'};
	}
	
	# extra verbose?
	if (1 == $extra_verbose)	{ $default_rsync_short_args .= 'v'; }
	
	# ROTATE DIRECTORIES
	#
	# remove oldest directory
	if ( -d "$config_vars{'snapshot_root'}/$interval.$interval_max" )	{
		if (1 == $verbose)	{ print "rm -rf $config_vars{'snapshot_root'}/$interval.$interval_max/\n"; }
		if (0 == $test)	{
			my $result = rmtree( "$config_vars{'snapshot_root'}/$interval.$interval_max/", 0, 0 );
			if (0 == $result)	{
				bail("Error! rmtree(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\",0,0)\n");
			}
		}
	}
	
	# rotate the middle ones
	for (my $i=($interval_max-1); $i>0; $i--)	{
		if ( -d "$config_vars{'snapshot_root'}/$interval.$i" )	{
			if (1 == $verbose)	{
				print "mv $config_vars{'snapshot_root'}/$interval.$i/ $config_vars{'snapshot_root'}/$interval." . ($i+1) . "/\n";
			}
			if (0 == $test)	{
				my $result = rename( "$config_vars{'snapshot_root'}/$interval.$i/", ("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/') );
				if (0 == $result)	{
					bail("Error! rename(\"$config_vars{'snapshot_root'}/$interval.$i/\", \"" . ("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/') . "\")");
				}
			}
		}
	}
	
	# hard link (except for directories, symlinks, and special files) .0 over to .1
	if ( -d "$config_vars{'snapshot_root'}/$interval.0" )	{
		my $result;
		
		# decide which verbose message to show, if at all
		if (1 == $verbose)	{
			if (1 == $have_gnu_cp)	{
				print "$config_vars{'cmd_cp'} -al $config_vars{'snapshot_root'}/$interval.0/ $config_vars{'snapshot_root'}/$interval.1/\n";
			} else	{
				print "native_cp_al(\"$config_vars{'snapshot_root'}/$interval.0/\", \"$config_vars{'snapshot_root'}/$interval.1/\")\n";
			}
		}
		# call generic cp_al() subroutine
		if (0 == $test)	{
			$result = cp_al( "$config_vars{'snapshot_root'}/$interval.0/", "$config_vars{'snapshot_root'}/$interval.1/" );
			if (! $result)	{
				bail("Error! cp_al(\"$config_vars{'snapshot_root'}/$interval.0/\", \"$config_vars{'snapshot_root'}/$interval.1/\")");
			}
		}
	}
	
	# SYNC LIVE FILESYSTEM DATA TO $interval.0
	# loop through each backup point and backup script
	foreach my $sp_ref (@snapshot_points)	{
		my @cmd_stack				= undef;
		my $src						= undef;
		my $script					= undef;
		my $tmpdir					= undef;
		my $result					= undef;
		my $ssh_args				= $default_ssh_args;
		my $rsync_short_args		= $default_rsync_short_args;
		my @rsync_long_args_stack	= ( split(/\s/, $default_rsync_long_args) );
		
		# append a trailing slash if src is a directory
		if (defined($$sp_ref{'src'}))	{
			if ((-d "$$sp_ref{'src'}") && ($$sp_ref{'src'} !~ /\/$/))	{
				$src = $$sp_ref{'src'} . '/';
			} else	{
				$src = $$sp_ref{'src'};
			}
		}
		
		# create missing parent directories inside the $interval.x directory
		my @dirs = split(/\//, $$sp_ref{'dest'});
		pop(@dirs);
		
		# don't mkdir for dest unless we have to
		my $destpath = "$config_vars{'snapshot_root'}/$interval.0/" . join('/', @dirs);
		if ( ! -e "$destpath" )	{
			if (1 == $verbose)	{ print "mkdir -m 0755 -p $destpath/\n"; }
			if (0 == $test)	{
				eval	{
					mkpath( "$destpath/", 0, 0755 );
				};
				if ($@)	{
					bail("Could not mkpath(\"$destpath/\", 0, 0755);");
				}
			}
		}
		
		# IF WE HAVE A SRC DIRECTORY, SYNC IT TO DEST
		if (defined($$sp_ref{'src'}))	{
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
			if ( defined($$sp_ref{'opts'}) && defined($$sp_ref{'opts'}->{'rsync_short_args'}) )	{
				$rsync_short_args = $$sp_ref{'opts'}->{'rsync_short_args'};
			}
			# RSYNC LONG ARGS
			if ( defined($$sp_ref{'opts'}) && defined($$sp_ref{'opts'}->{'rsync_long_args'}) )	{
				@rsync_long_args_stack = split(/\s/, $$sp_ref{'opts'}->{'rsync_long_args'});
			}
			# SSH ARGS
			if ( defined($$sp_ref{'opts'}) && defined($$sp_ref{'opts'}->{'ssh_args'}) )	{
				$ssh_args = $$sp_ref{'opts'}->{'ssh_args'};
			}
			# ONE_FS
			if ( defined($$sp_ref{'opts'}) && defined($$sp_ref{'opts'}->{'one_fs'}) )	{
				if (1 == $$sp_ref{'opts'}->{'one_fs'})	{
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
				if (0 == $extra_verbose)	{ $rsync_short_args .= 'q'; }
				
			# this should have already been validated once, but better safe than sorry
			} else	{
				bail("Could not understand source \"$src\" in backup_interval()");
			}
			
			# assemble the final command
			@cmd_stack = (
				$config_vars{'cmd_rsync'}, $rsync_short_args, @rsync_long_args_stack,
					$src, "$config_vars{'snapshot_root'}/$interval.0/$$sp_ref{'dest'}"
			);
			
			# RUN THE RSYNC COMMAND FOR THIS BACKUP POINT
			# BASED ON THE @cmd_stack VARS
			if (1 == $verbose)	{ print join(' ', @cmd_stack, "\n"); }
			if (0 == $test)		{ system(@cmd_stack); }
			
		# OR, IF WE HAVE A BACKUP SCRIPT, RUN IT, THEN SYNC IT TO DEST
		} elsif (defined($$sp_ref{'script'}))	{
			# work in a temp dir, and make this the source for the rsync operation later
			$tmpdir = "$config_vars{'snapshot_root'}/tmp/";
			
			# remove the tmp directory if it's still there for some reason
			# (this shouldn't happen unless the program was killed prematurely, etc)
			if ( -e "$tmpdir" )	{
				if (1 == $verbose)	{ print "rm -rf $tmpdir\n"; }
				if (0 == $test)	{
					$result = rmtree("$tmpdir", 0, 0);
					if (0 == $result)	{
						bail("Could not rmtree(\"$tmpdir\",0,0);");
					}
				}
			}
			
			# create the tmp directory
			if (1 == $verbose)	{ print "mkdir -m 0755 -p $tmpdir\n"; }
			if (0 == $test)	{
				eval	{
					mkpath( "$tmpdir", 0, 0755 );
				};
				if ($@)	{
					bail("Unable to create \"$tmpdir\",\nPlease make sure you have the right permissions.");
				}
			}
			
			# change to the tmp directory
			if (1 == $verbose)	{ print "cd $tmpdir\n"; }
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
			if (1 == $verbose)	{ print "$$sp_ref{'script'}\n"; }
			if (0 == $test)	{
				system( $$sp_ref{'script'} );
			}
			
			# change back to the previous directory
			if (1 == $verbose)	{ print "cd $cwd\n"; }
			if (0 == $test)	{
				chdir($cwd);
			}
			
			# sync the output of the backup script into this snapshot interval
			# this is using a native function since rsync doesn't quite do what we want
			#
			# rsync sees that the timestamps are different, and insists
			# on changing things even if the files are bit for bit identical on content.
			#
			if (1 == $verbose)	{ print "sync_if_different(\"$tmpdir\", \"$config_vars{'snapshot_root'}/$interval.0/$$sp_ref{'dest'}\")\n"; }
			if (0 == $test)	{
				$result = sync_if_different("$tmpdir", "$config_vars{'snapshot_root'}/$interval.0/$$sp_ref{'dest'}");
				if (!defined($result))	{
					bail("sync_if_different(\"$tmpdir\", \"$$sp_ref{'dest'}\") returned undef");
				}
			}
			
			# remove the tmp directory
			if ( -e "$tmpdir" )	{
				if (1 == $verbose)	{ print "rm -rf $tmpdir\n"; }
				if (0 == $test)	{
					$result = rmtree("$tmpdir", 0, 0);
					if (0 == $result)	{
						bail("Could not rmtree(\"$tmpdir\",0,0);");
					}
				}
			}
			
		# this should never happen
		} else	{
			bail("Either src or script must be defined in backup_interval()");
		}
	}
	
	# update mtime of $interval.0 to reflect the time this snapshot was taken
	if (1 == $verbose)	{ print "touch $config_vars{'snapshot_root'}/$interval.0/\n"; }
	if (0 == $test)	{
		my $result = utime(time(), time(), "$config_vars{'snapshot_root'}/$interval.0/");
		if (0 == $result)	{
			bail("Could not utime(time(), time(), \"$config_vars{'snapshot_root'}/$interval.0/\");");
		}
	}
}

# accepts the interval to act on, and the previous interval (i.e. daily, hourly)
# this should not be the lowest interval, but any of the higher ones
#
# rotates older dirs within this interval, and hard links
# the previous interval's highest numbered dir to this interval's .0,
#
# does not return a value, it bails instantly if there's a problem
sub rotate_interval	{
	my $interval		= shift(@_);	# i.e. daily
	my $prev_interval	= shift(@_);	# i.e. hourly
	
	# this should never happen
	if (!defined($interval) or !defined($prev_interval))	{
		bail('rotate_interval() expects 2 arguments');
	}
	
	# ROTATE DIRECTORIES
	#
	# delete the oldest one
	if ( -d "$config_vars{'snapshot_root'}/$interval.$interval_max" )	{
		if (1 == $verbose)	{ print "rm -rf $config_vars{'snapshot_root'}/$interval.$interval_max/\n"; }
		if (0 == $test)	{
			my $result = rmtree( "$config_vars{'snapshot_root'}/$interval.$interval_max/", 0, 0 );
			if (0 == $result)	{
				bail("Could not rmtree(\"$config_vars{'snapshot_root'}/$interval.$interval_max/\",0,0);");
			}
		}
	}
	
	# rotate the middle ones
	for (my $i=($interval_max-1); $i>=0; $i--)	{
		if ( -d "$config_vars{'snapshot_root'}/$interval.$i" )	{
			if (1 == $verbose)	{ print "mv $config_vars{'snapshot_root'}/$interval.$i/ $config_vars{'snapshot_root'}/$interval." . ($i+1) . "/\n"; }
			if (0 == $test)	{
				my $result = rename( "$config_vars{'snapshot_root'}/$interval.$i/", ("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/') );
				if (0 == $result)	{
					bail("error during rename(\"$config_vars{'snapshot_root'}/$interval.$i/)\", \"" . ("$config_vars{'snapshot_root'}/$interval." . ($i+1) . '/') . "\");");
				}
			}
		}
	}
	
	# hard link (except for directories) previous interval's oldest dir over to .0
	if ( -d "$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max" )	{
		if (1 == $verbose)	{
			if (1 == $have_gnu_cp)	{
				print "$config_vars{'cmd_cp'} -al $config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/ ";
				print "$config_vars{'snapshot_root'}/$interval.0/\n";
			} else	{
				print "native_cp_al(\"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/\", ";
				print "\"$config_vars{'snapshot_root'}/$interval.0/\")\n";
			}
		}
		if (0 == $test)	{
			my $result = cp_al( "$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/", "$config_vars{'snapshot_root'}/$interval.0/" );
			if (! $result)	{
				bail("Error! cp_al(\"$config_vars{'snapshot_root'}/$prev_interval.$prev_interval_max/\", \"$config_vars{'snapshot_root'}/$interval.0/\") failed");
			}
		}
	}
}

# stub subroutine
# calls either gnu_cp_al() or native_cp_al()
# returns the value directly from whichever subroutine it calls
sub cp_al	{
	my $src  = shift(@_);
	my $dest = shift(@_);
	my $result = 0;
	
	if (1 == $have_gnu_cp)	{
		$result = gnu_cp_al("$src", "$dest");
	} else	{
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
		print STDERR "gnu_cp_al() needs a valid directory as an argument\n";
		return (0);
	}
	
	# make the system call to GNU cp
	$result = system( $config_vars{'cmd_cp'}, '-al', "$src", "$dest" );
	if ($result != 0)	{
		print STDERR "Warning! $config_vars{'cmd_cp'} failed. Perhaps this is not GNU cp?\n";
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
		print STDERR "native_cp_al() needs a valid source directory as an argument\n";
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st))	{
		print STDERR "Could not lstat(\"$src\")\n";
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" )	{
		if (1 == $debug)	{ print "mkdir(\"$dest\", " . get_perms($st->mode) . ");\n"; }
		
		$result = mkdir("$dest", $st->mode);
		if ( ! $result )	{
			print STDERR "Warning! Could not mkdir(\"$dest\", $st->mode);\n";
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		if (1 == $debug)	{ print "chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");\n"; }
		
		$result = chown($st->uid, $st->gid, "$dest");
		if (! $result)	{
			print STDERR "Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");\n";
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
				print STDERR "Could not lstat(\"$src/$node\")\n";
				return(0);
			}
			
			# SYMLINK (must be tested for first, because it will also pass the file and dir tests)
			if ( -l "$src/$node" )	{
				if (1 == $debug)	{ print "copy_symlink(\"$src/$node\", \"$dest/$node\")\n"; }
				
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result)	{
					bail("Error! copy_symlink(\"$src/$node\", \"$dest/$node\")");
				}
				
			# FILE
			} elsif ( -f "$src/$node" )	{
				
				# make a hard link
				if (1 == $debug)	{ print "link(\"$src/$node\", \"$dest/$node\");\n"; }
				
				$result = link("$src/$node", "$dest/$node");
				if (! $result)	{
					print STDERR "Warning! Could not link(\"$src/$node\", \"$dest/$node\")\n";
					return (0);
				}
				
			# DIRECTORY
			} elsif ( -d "$src/$node" )	{
				
				if (1 == $debug)	{ print "native_cp_al(\"$src/$node\", \"$dest/$node\")\n"; }
				
				# call this subroutine recursively, to create the directory
				$result = native_cp_al("$src/$node", "$dest/$node");
				if (! $result)	{
					print STDERR "Warning! Recursion error in native_cp_al(\"$src/$node\", \"$dest/$node\")\n";
					return (0);
				}
				
			# FIFO
			} elsif ( -p "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring FIFO $src/$node\n"; }
				
			# SOCKET
			} elsif ( -S "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring socket: $src/$node\n"; }
				
			# BLOCK DEVICE
			} elsif ( -b "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring special block file: $src/$node\n"; }
				
			# CHAR DEVICE
			} elsif ( -c "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring special character file: $src/$node\n"; }
			}
		}
		
	} else	{
		print STDERR "Could not open \"$src\". Do you have adequate permissions?\n";
		return(0);
	}
	
	# close open dir handle
	if (defined($dh))	{ $dh->close(); }
	undef( $dh );
	
	# UTIME DEST
	if (1 == $debug)	{ print "utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\");\n"; }
	
	$result = utime($st->atime, $st->mtime, "$dest");
	if (! $result)	{
		print STDERR "Warning! Could not utime(" . $st->atime . ", " . $st->mtime . ", \"$dest\");\n";
		return(0);
	}
	
	return (1);
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
		print STDERR "sync_if_different() needs a valid source directory as its first argument\n";
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# copy everything from src to dest
	if (1 == $debug)	{ print "sync_cp_src_dest(\"$src\", \"$dest\")\n"; }
	$result = sync_cp_src_dest("$src", "$dest");
	if ( ! $result )	{
		bail("sync_cp_src_dest(\"$src\", \"$dest\")");
	}
	
	# delete everything from dest that isn't in src
	if (1 == $debug)	{ print "sync_rm_dest(\"$src\", \"$dest\")\n"; }
	$result = sync_rm_dest("$src", "$dest");
	if ( ! $result )	{
		bail("sync_rm_dest(\"$src\", \"$dest\")");
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
		print STDERR "sync_if_different() needs a valid source directory as its first argument\n";
		return (0);
	}
	
	# strip trailing slashes off the directories,
	# since we'll add them back on later
	$src  = remove_trailing_slash($src);
	$dest = remove_trailing_slash($dest);
	
	# LSTAT SRC
	my $st = lstat("$src");
	if (!defined($st))	{
		print STDERR "Could not lstat(\"$src\")\n";
		return(0);
	}
	
	# MKDIR DEST (AND SET MODE)
	if ( ! -d "$dest" )	{
		$result = mkdir("$dest", $st->mode);
		if ( ! $result )	{
			print STDERR "Warning! Could not mkdir(\"$dest\", $st->mode);\n";
			return(0);
		}
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		$result = chown($st->uid, $st->gid, "$dest");
		if (! $result)	{
			print STDERR "Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");\n";
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
				print STDERR "Could not lstat(\"$src/$node\")\n";
				return(0);
			}
			
			# if it's a symlink, create the link
			# this check must be done before dir and file because it will
			# pretend to be a file or a directory as well as a symlink
			if ( -l "$src/$node" )	{
				$result = copy_symlink("$src/$node", "$dest/$node");
				if (0 == $result)	{
					print STDERR "Warning! copy_symlink(\"$src/$node\", \"$dest/$node\")\n";
				}
				
			# if it's a directory, recurse!
			} elsif ( -d "$src/$node" )	{
				$result = sync_cp_src_dest("$src/$node", "$dest/$node");
				if (! $result)	{
					print STDERR "Error! recursion error in sync_cp_src_dest(\"$src/$node\", \"$dest/$node\")\n";
					return (0);
				}
				
			# if it's a file...
			} elsif ( -f "$src/$node" )	{
				
				# if dest exists, check for differences
				if ( -e "$dest/$node" )	{
					
					# if they are different, unlink dest and link src to dest
					if (1 == file_diff("$src/$node", "$dest/$node"))	{
						$result = unlink("$dest/$node");
						if (0 == $result)	{
							print "Error! unlink(\"$dest/$node\")\n";
							return (0);
						}
						$result = link("$src/$node", "$dest/$node");
						if (0 == $result)	{
							print "Error! link(\"$src/$node\", \"$dest/$node\")\n";
							return (0);
						}
						
					# if they are the same, just leave dest alone
					} else	{
						next;
					}
					
				# ok, dest doesn't exist. just link src to dest
				} else	{
					$result = link("$src/$node", "$dest/$node");
					if (0 == $result)	{
						print STDERR "Error! link(\"$src/$node\", \"$dest/$node\")\n";
						return (0);
					}
				}
				
			# FIFO
			} elsif ( -p "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring FIFO $src/$node\n"; }
				
			# SOCKET
			} elsif ( -S "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring socket: $src/$node\n"; }
				
			# BLOCK DEVICE
			} elsif ( -b "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring special block file: $src/$node\n"; }
				
			# CHAR DEVICE
			} elsif ( -c "$src/$node" )	{
				if (0 == $quiet)	{ print STDERR "Warning! Ignoring special character file: $src/$node\n"; }
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
		print STDERR "sync_rm_dest() needs a valid source directory as its first argument\n";
		return (0);
	}
	
	# make sure we have a destination directory
	if ( ! -d "$dest" )	{
		print STDERR "sync_rm_dest() needs a valid destination directory as its first argument\n";
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
				print STDERR "Error! Could not lstat(\"$dest/$node\")\n";
				return(0);
			}
			
			# if this node isn't present in src, delete it
			if ( ! -e "$src/$node" )	{
				$result = rmtree("$dest/$node", 0, 0);
				if (0 == $result)	{
					print STDERR "Error! Could not delete \"$dest/$node\"";
					return (0);
				}
				
			# ok, this also exists in src
			# if it's a directory, let's recurse into it and compare files there
			} elsif ( -d "$src/$node" )	{
				$result = sync_rm_dest("$src/$node", "$dest/$node");
				if ( ! $result )	{
					print STDERR "Error! recursion error in sync_rm_dest(\"$src/$node\", \"$dest/$node\")\n";
					return (0);
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
		print STDERR "Warning! \"$src\" not a symlink in copy_symlink()\n";
		return (0);
	}
	
	# make sure we aren't clobbering the destination
	if ( -e "$dest" )	{
		print STDERR "Warning! \"$dest\" exists!\n";
	}
	
	# LSTAT
	$st = lstat("$src");
	if (!defined($st))	{
		print STDERR "Warning! lstat(\"$src\")\n";
		return (0);
	}
	
	# CREATE THE SYMLINK
	if (1 == $debug)	{ print "symlink(\"" . readlink("$src") . "\", \"$dest\");\n"; }
	
	$result = symlink(readlink("$src"), "$dest");
	if (! $result)	{
		print STDERR "Warning! Could not symlink(readlink(\"$src\"), \"$dest\")\n";
		return (0);
	}
	
	# CHOWN DEST (if root)
	if (0 == $<)	{
		if ( -e "$dest" )	{
			if (1 == $debug)	{ print "chown(" . $st->uid . ", " . $st->gid . ", \"$dest\");\n"; }
			
			$result = chown($st->uid, $st->gid, "$dest");
			if (! $result)	{
				print STDERR "Warning! Could not chown(" . $st->uid . ", " . $st->gid . ", \"$dest\")\n";
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
	
	# ok, we're still here. that means we have to...
	
	# COMPARE FILES ONE CHUNK AT A TIME
	open(FILE1, "$file1") or return (undef);
	open(FILE2, "$file2") or return (undef);
	
	while ((0 == $done) && (read(FILE1, $buf1, $BUFSIZE)) && (read(FILE2, $buf2, $BUFSIZE)))	{
		# exit this loop as soon as possible
		if ($buf1 ne $buf2)	 {
			$is_different = 1;
			$done = 1;
		}
	}
	
	close(FILE2) or return (undef);
	close(FILE1) or return (undef);
	
	return ($is_different);
}

#####################
### PERLDOC / POD ###
#####################

=pod

=head1 NAME

rsnapshot - remote filesystem snapshot utility

=head1 SYNOPSIS

B<rsnapshot> [B<-vtxqVD>] [B<-c> /alt/config/file] [command]

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

B<snapshot_root> local filesystem path to save all snapshots

B<cmd_rsync>     full path to rsync (required)

B<cmd_ssh>       full path to ssh (optional)

B<cmd_cp>        full path to cp  (optional, but must be GNU version)

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

B<rsync_short_args    -a>

=over 4

List of short arguments to pass to rsync. If not specified,
"-a" is the default.

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

=head1 AUTHOR

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

=head1 COPYRIGHT

Copyright (C) 2003 Nathan Rosenquist

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

=head1 FILES

/etc/rsnapshot.conf

=head1 SEE ALSO

rsync(1), ssh(1), sshd(1), ssh-keygen(1), perl(1), cp(1)

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

Make sure your snapshot directory is only readable by root. If you would
like regular users to be able to restore their own backups, there are a
number of ways this can be accomplished. One such scenario would be:

Set B<snapshot_root> to B</.private/.snapshots> in B</etc/rsnapshot.conf>

Set the file permissions on these directories as follows:

=over 4

drwx------    /.private

drwxr-xr-x    /.private/.snapshots

=back

Export the /.private/.snapshots directory over read-only NFS, a read-only
Samba share, etc.

If you do not plan on making the backups readable by regular users, be
sure to make the snapshot directory chmod 700 root. If the snapshot
directory is readable by other users, they will be able to modify the
snapshots containing their files, thus destroying the integrity of the
snapshots.

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

rsync transfers are done using the --numeric-ids option. This means that
user names and group names are ignored during transfers, but the UID/GID
information is kept intact. The assumption is that the backups will be
restored in the same environment they came from. Without this option,
multi-server backups would be unmanageable.

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

=cut

