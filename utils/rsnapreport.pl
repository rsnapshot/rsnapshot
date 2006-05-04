#!/usr/bin/env perl
# this script prints a pretty report from rsnapshot output
# in the rsnapshot.conf you must set
# verbose >= 3
# and add --stats to rsync_long_args
# then setup crontab 'rsnapshot daily 2>&1 | rsnapreport.pl | mail -s"SUBJECT" backupadm@adm.com
# don't forget the 2>&1 or your errors will be lost to stderr
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

my $bufsz = 2;
my %bkdata=();
my @errors=();

sub pretty_print(){
	my $ofh = select(STDOUT);
	$FORMAT_NAME="BREPORTBODY";
	$FORMAT_TOP_NAME="BREPORTHEAD";
	select($ofh);

	foreach my $source (keys %bkdata){
		if($bkdata{$source} =~ /error/i) { print "ERROR $source $bkdata{$source}"; next; }
		my $files = $bkdata{$source}{'files'};
		my $filest = $bkdata{$source}{'files_tran'};
		my $filelistgentime = $bkdata{$source}{'file_list_gen_time'};
		my $filelistxfertime = $bkdata{$source}{'file_list_trans_time'};
		my $bytes= $bkdata{$source}{'file_size'}/1000000; # convert to MB
		my $bytest= $bkdata{$source}{'file_tran_size'}/1000000; # convert to MB
		$source =~ s/^[^\@]+\@//; # remove username
format BREPORTHEAD =
SOURCE                          TOTAL FILES   FILES TRANS      TOTAL MB     MB TRANS   LIST GEN TIME  FILE XFER TIME
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
	

my @rsnapout = ();

# load readahead buffer
for(my $i=0; $i < $bufsz; $i++){
	$rsnapout[$i] = <>;
}

while (my $line = nextLine(\@rsnapout)){
	if($line =~ /^[\/\w]+\/rsync/) { # find start rsync command line
		my @rsynccmd=();
		while($line =~ /\s+\\$/){ # combine wrapped lines
			$line =~ s/\\$//g;
			$line .= nextLine(\@rsnapout);
		}
		push(@rsynccmd,split(/\s+/,$line)); # split into command components
		my $source = $rsynccmd[-2]; # count backwards: source always second to last
		#print $source;
		while($line = nextLine(\@rsnapout)){
  			# this means we are missing stats info
			if($line =~ /^[\/\w]+\/rsync/){ 
				unshift(@rsnapout,$line);
				push(@errors,"$source NO STATS DATA");
				last;  
			}
			# stat record
			if($line =~ /^total size is\s+\d+/){ last; } # this ends the rsync stats record
			elsif($line =~ /Number of files:\s+(\d+)/){
				$bkdata{$source}{'files'}=$1;
			}
			elsif($line =~ /Number of files transferred:\s+(\d+)/){
				$bkdata{$source}{'files_tran'}=$1;
			}
			elsif($line =~ /Total file size:\s+(\d+)/){
				$bkdata{$source}{'file_size'}=$1;
			}
			elsif($line =~ /Total transferred file size:\s+(\d+)/){
				$bkdata{$source}{'file_tran_size'}=$1;
			}
			elsif($line =~ /File list generation time:\s+(.+)/){
				$bkdata{$source}{'file_list_gen_time'}=$1;
			}
			elsif($line =~ /File list transfer time:\s+(.+)/){
				$bkdata{$source}{'file_list_trans_time'}=$1;
			}
			elsif($line =~ /ERROR/){ push(@errors,"$source $line"); } # we encountered an rsync error
		}
	}
	elsif($line =~ /ERROR/){ push(@errors,$line); } # we encountered an rsync error
}

pretty_print();
if(scalar @errors > 0){
	print "\nERRORS\n";
	print join("\n",@errors);
	print "\n";
}
