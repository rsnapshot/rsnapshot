#!@PERL@ -w

##############################################################################
# rsnapshot-diff
# by David Cantrell <david@cantrell.org.uk>
#
# This program calculates the differences between two directories. It is
# designed to work with two different subdirectories under the rsnapshot
# snapshot_root. For example:
#
#   rsnapshot-diff /.snapshots/daily.0/ /.snapshots/daily.1/
#
# http://www.rsnapshot.org/
##############################################################################

# $Id: rsnapshot-diff.pl,v 1.6 2010/08/10 13:00:15 drhyde Exp $

=head1 NAME

rsnapshot-diff - a utility for comparing the disk usage of two snapshots
taken by rsnapshot

=cut

use strict;

use constant DEBUG => 0;
use Getopt::Std;

my $program_name = 'rsnapshot-diff';

my %opts;
my $verbose = 0;
my $ignore = 0;
my $show_size = 0;

my $result = getopts('vVhHis', \%opts);

# help
if ($opts{'h'}) {
    print qq{
    $program_name [-vVHhi] dir1 dir2

    $program_name shows the differences between two 'rsnapshot' backups.

    -h    show this help
    -H    also show "human" sizes - MB and GB as well as just bytes
    -i    ignore symlinks, directories, and special files in verbose output
    -s    show the size of each changed file
    -v    be verbose
    -V    be more verbose (mutter about unchanged files and about symlinks)
    dir1  the first directory to look at
    dir2  the second directory to look at

    if you want to look at directories called '-h' or '-v' pass a
    first parameter of '--'.

    $program_name always show the changes made starting from the older
    of the two directories.
};
	exit;
}

=head1 SYNOPSIS

rsnapshot-diff [-h|vVi] dir1 dir2

=head1 DESCRIPTION

rsnapshot-diff is a companion utility for rsnapshot, which traverses two
parallel directory structures and calculates the difference between them.
By default it is silent apart from displaying summary information at the
end, but it can be made more verbose.

In the summary, "added" files may very well include files which at first
glance also appear at the same place in the older directory structure.
However, because the files differ in some respect, they are different files.
They have a different inode number.  Consequently if you use -v most of its
output may appear to be pairs of files with the same name being removed
and added.

=head1 OPTIONS

=over 4

=item -h (help)

Displays help information

=item -H (human)

Display more human-friendly numbers - as well as showing the number of
bytes changed, also show MB and GB.

=item -i (ignore)

If verbosity is turned on, -i suppresses information about symlinks,
directories, and special files.

=item -s (show size)

Show the size of each changed file after the + or - sign.  To sort the files by
decreasing size, use this option and run the output through "sort -k 2 -rn".

=item -v (verbose)

Be verbose.  This will spit out a list of all changes as they are encountered,
apart from symlink, as well as the summary at the end.

=item -V (more verbose)

Be more verbose - as well as listing changed files, unchanged files and
symlinks will be listed too.

=item dir1 and dir2

These are the only compulsory parameters, and should be the names of two
directories to compare.  Their order doesn't matter, rsnapshot-diff will
always compare the younger to the older, so files that appear only in the
older will be reported as having been removed, and files that appear only
in the younger will be reported as having been added.

=back

=cut

# verbose
if ($opts{'v'}) { $verbose = 1; }

# extra verbose
if ($opts{'V'}) { $verbose = 2; }

# ignore
if ($opts{'i'}) { $ignore = 1; }

# size
if ($opts{'s'}) { $show_size = 1; }

if(!exists($ARGV[1]) || !-d $ARGV[0] || !-d $ARGV[1]) {
    die("$program_name\nUsage: $program_name [-vVhi] dir1 dir2\nType $program_name -h for details\n");
}

my($dirold, $dirnew) = @ARGV;
my($addedfiles, $addedspace, $deletedfiles, $deletedspace) = (0, 0, 0, 0);
my($addedspace_mb, $addedspace_gb, $deletedspace_mb, $deletedspace_gb) = (0, 0, 0, 0);

($dirold, $dirnew) = ($dirnew, $dirold) if(-M $dirold < -M $dirnew);

# remove trailing slahes, if any
$dirold =~ s/\/+$//;
$dirnew =~ s/\/+$//;

print "Comparing $dirold to $dirnew\n";

compare_dirs($dirold, $dirnew);

$addedspace_mb = sprintf("%.2f", $addedspace / (1024 * 1024));
$addedspace_gb = sprintf("%.2f", $addedspace_mb / 1024);
$deletedspace_mb = sprintf("%.2f", $deletedspace / (1024 * 1024));
$deletedspace_gb = sprintf("%.2f", $deletedspace_mb / 1024);

print "Between $dirold and $dirnew:\n";
print "  $addedfiles were added, taking $addedspace bytes".
  ($opts{H} ? " ($addedspace_mb MB, $addedspace_gb GB)" : '').
  "\n";
print "  $deletedfiles were removed, saving $deletedspace bytes".
  ($opts{H} ? " ($deletedspace_mb MB, $deletedspace_gb GB)" : '').
  "\n";

sub compare_dirs {
    my($old, $new) = @_;

    opendir(OLD, $old) || die("Can't open dir $old\n");
    opendir(NEW, $new) || die("Can't open dir $new\n");
    my %old = map {
        my $fn = $old.'/'.$_;
        ($_, (mystat($fn))[1])
    } grep { $_ ne '.' && $_ ne '..' } readdir(OLD);
    my %new = map {
        my $fn = $new.'/'.$_;
        ($_, (mystat($fn))[1])
    } grep { $_ ne '.' && $_ ne '..' } readdir(NEW);
    closedir(OLD);
    closedir(NEW);

    my @added = grep { !exists($old{$_}) } keys %new;
    my @deleted = grep { !exists($new{$_}) } keys %old;
    my @changed = grep { !-d $new.'/'.$_ && exists($old{$_}) && $old{$_} != $new{$_} } keys %new;

    add(map { $new.'/'.$_ } @added, @changed);
    remove(map { $old.'/'.$_ } @deleted, @changed);

    if($verbose == 2) {
        my %changed = map { ($_, 1) } @changed, @added, @deleted;
        print "0 $new/$_\n" foreach(grep { !-d "$new/$_" && !exists($changed{$_}) } keys %new);
    }
    
    foreach (grep { !-l $new.'/'.$_ && !-l $old.'/'.$_ && -d $new.'/'.$_ && -d $old.'/'.$_ } keys %new) {
        print "Comparing subdirs $new/$_ and $old/$_ ...\n" if(DEBUG);
        compare_dirs($old.'/'.$_, $new.'/'.$_);
    }
}

sub add {
    my @added = @_;
    print "Adding ".join(', ', @added)."\n" if(DEBUG && @added);
    foreach(grep { !-d } @added) {
        $addedfiles++;
        my $size = (mystat($_))[7];
        $addedspace += $size;
        # if ignore is on, only print files
        unless ($ignore && (-l || !-f)) {
            print ''.($show_size ? "+ $size $_" : "+ $_").
	          (-l $_ ? ' (symlink)' : '').
		  "\n"
	        if($verbose == 2 || ($verbose == 1 && !-l $_));
        }
    }
    foreach my $dir (grep { !-l && -d } @added) {
        opendir(DIR, $dir) || die("Can't open dir $dir\n");
        add(map { $dir.'/'.$_ } grep { $_ ne '.' && $_ ne '..' } readdir(DIR))
    }
}

sub remove {
    my @removed = @_;
    print "Removing ".join(', ', @removed)."\n" if(DEBUG && @removed);
    foreach(grep { !-d } @removed) {
        $deletedfiles++;
        my $size = (mystat($_))[7];
        $deletedspace += $size;
        # if ignore is on, only print files
        unless ($ignore && (-l || !-f)) {
            print ''.($show_size ? "- $size $_" : "- $_").
	          (-l $_ ? ' (symlink)' : '').
		  "\n"
	        if($verbose == 2 || ($verbose == 1 && !-l $_));
        }
    }
    foreach my $dir (grep { !-l && -d } @removed) {
        opendir(DIR, $dir) || die("Can't open dir $dir\n");
        remove(map { $dir.'/'.$_ } grep { $_ ne '.' && $_ ne '..' } readdir(DIR))
    }
}

{
    my $device;

    sub mystat {
        local $_ = shift;
        my @stat = (-l) ? lstat() : stat();

        # on first stat, memorise device
        $device = $stat[0] unless(defined($device));
        die("Can't compare across devices.\n(looking at $_)\n")
            unless($device == $stat[0] || -p $_);

        return @stat;
    }
}

=head1 SEE ALSO

rsnapshot

=head1 BUGS

Please report bugs (and other comments) to the rsnapshot-discuss mailing list:

L<http://lists.sourceforge.net/lists/listinfo/rsnapshot-discuss>

=head1 AUTHOR

David Cantrell E<lt>david@cantrell.org.ukE<gt>

=head1 COPYRIGHT

Copyright 2005-2010 David Cantrell

=head1 LICENCE

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
