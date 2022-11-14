#!/usr/bin/env perl
# this script prints a pretty report from rsnapshot output
# in the rsnapshot.conf you must set
# verbose >= 4
# and add --stats to rsync_long_args
# then setup crontab 'rsnapshot daily 2>&1 | rsnapreport.pl | mail -s"SUBJECT" backupadm@adm.com
# don't forget the 2>&1 or your errors will be lost to stderr
# If you would prefer to leave the rsnapshot.conf verbose value unchanged,
# an alternative is to pass the -V option to rsnapshot.
# For example: rsnapshot -V daily 2>&1 | rsnapreport.pl
################################
## Copyright 2006 William Bear
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
################################
use strict;
use warnings;
use English '-no_match_vars';
use File::Spec;			# splitdir()

my $bufsz = 2;
my %bkdata=();
my @errors=();

sub pretty_print(){
	my $ofh = select(STDOUT);
	$FORMAT_NAME="BREPORTBODY";
	$FORMAT_TOP_NAME="BREPORTHEAD";
	select($ofh);

	foreach my $source (sort keys %bkdata){
		if($bkdata{$source} =~ /error/i) { print "ERROR $source $bkdata{$source}"; next; }
		my $files = $bkdata{$source}{'files'};
		my $filest = $bkdata{$source}{'files_tran'};
		my $filelistgentime = $bkdata{$source}{'file_list_gen_time'};
		my $filelistxfertime = $bkdata{$source}{'file_list_trans_time'};
		my $bytes = $bkdata{$source}{'file_size'}/1000000; # convert to MB
		my $bytest = $bkdata{$source}{'file_tran_size'}/1000000; # convert to MB
		$source =~ s/^[^\@]+\@//; # remove username
		format BREPORTHEAD =
SOURCE                          TOTAL FILES   FILES TRANS      TOTAL MB     MB TRANS   LIST GEN TIME  LIST XFER TIME
--------------------------------------------------------------------------------------------------------------------
.
		format BREPORTBODY =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<	@>>>>>>>>>>   @>>>>>>>>>> @#########.## @########.##   @>>>>>>>>>>>>  @>>>>>>>>>>>>>
$source,                        $files,       $filest,    $bytes,       $bytest,       $filelistgentime, $filelistxfertime
.
		write STDOUT;
	}
}

sub nextLine($){
	my($lines) = @_;
	my $line = <>;
	push(@$lines,$line);
	return shift @$lines;
}


my $linux_lvm_lv = undef;
my @rsnapout = ();

# load readahead buffer
for(my $i=0; $i < $bufsz; $i++){
	$rsnapout[$i] = <>;
}

while (my $line = nextLine(\@rsnapout)){
        while($line =~ /\s+\\$/){ # combine wrapped lines
		$line =~ s/\\$//g;
		$line .= nextLine(\@rsnapout);
	}
	if($line =~ /^[\/\w]+\/lvcreate\h+-[-\w]/) { # Look for LVM snapshot
		# Extract the LVM logical volume from the lvcreate command.
		my $lvpath = (split /\s+/, $line)[-1];
		my ($vg, $lv) = (File::Spec->splitdir($lvpath))[-2,-1];
		$linux_lvm_lv = 'lvm://' . $vg . '/' . $lv . '/';
	}
	# find start rsync command line
	elsif($line =~ /^[\/\w]+\/rsync\h+-[-\w]/) {
		my @rsynccmd=();
		push(@rsynccmd,split(/\s+/,$line)); # split into command components
		my $source;
		# Use LVM logical volume name if it exists.
		if ($linux_lvm_lv) {
			$source = $linux_lvm_lv;
		}
		else {
			# count backwards: source always second to last
			$source = $rsynccmd[-2];
		}
		#print $source;
		while($line = nextLine(\@rsnapout)){
  			# this means we are missing stats info
			if($line =~ /^[\/\w]+\/rsync\h+-[-\w]/){
				unshift(@rsnapout,$line);
				push(@errors,"$source NO STATS DATA");
				last;
			}
			# stat record
			if($line =~ /^total size is\s+\d+/){ last; } # this ends the rsync stats record
			# Number of files: 1,325 (reg: 387, dir: 139, link: 799)
			elsif($line =~ /Number of files:\s+([\d,]+)/){
				$bkdata{$source}{'files'}=$1;
				$bkdata{$source}{'files'}=~ s/,//g;
			}
			# Number of regular files transferred: 1
			elsif($line =~ /Number of (regular )?files transferred:\s+([\d,]+)/){
				$bkdata{$source}{'files_tran'}=$2;
			}
			# Total file size: 1,865,857 bytes
			elsif($line =~ /Total file size:\s+([\d,]+)/){
				$bkdata{$source}{'file_size'}=$1;
				$bkdata{$source}{'file_size'}=~ s/,//g;
			}
			elsif($line =~ /Total transferred file size:\s+([\d,]+)/){
				$bkdata{$source}{'file_tran_size'}=$1;
				$bkdata{$source}{'file_tran_size'}=~ s/,//g;
			}
			elsif($line =~ /File list generation time:\s+(.+)/){
				$bkdata{$source}{'file_list_gen_time'}=$1;
			}
			elsif($line =~ /File list transfer time:\s+(.+)/){
				$bkdata{$source}{'file_list_trans_time'}=$1;
			}
			elsif($line =~ /^(rsync error|ERROR): /){ push(@errors,"$source $line"); } # we encountered an rsync error
		}
		# If this was a logical volume, we are done with it.
		$linux_lvm_lv = undef;
	}
	elsif($line =~ /^(rsync error|ERROR): /){ push(@errors,$line); } # we encountered an rsync error
}

pretty_print();
if(scalar @errors > 0){
	print "\nERRORS\n";
	print join("\n",@errors);
	print "\n";
}
