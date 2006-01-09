#!/usr/bin/perl

=head

APPLICATION INFO:

Name: rsnapshotDB 1.2.0
Bugs: rsnapshot-discuss@lists.sf.net
License: GPL 2.0 http://www.gnu.org/licenses/gpl.txt
Web: http://www.rsnapshot.org

Author: Anthony Ettinger
Email: aettinger@sdsualumni.org
Blog: http://www.chovy.com


NOTES:

This script was originally written to function as a MySQL database backup script in conjunction with the open source Perl/rsync backup program "rsnapshot".  rsnapshot can be found at: http://www.rsnapshot.org/

In order to backup a database remotely, the necessary database user must be able to connect remotely to the database server from your IP number (some ISPs only allow access from localhost - you may need to email your admin and ask for your IP/domain to be given access).

Tip: If you have a dynamic ip, register for free with dyndns.org (use "ddclient" to update it).
Your admin needs to allow database connections from yourbox.dyndns.org.

It is extremely important that you secure the /etc/rsnapshotDB.conf file so only YOU (the user who's cronjob this is running from) can read the file, 'chmod 0600 /etc/rsnapshotDB.conf', as it will store the database passwords in plain text format.

If you don't know who YOU are - type 'whoami' or ask a friend.

For best results, configure and run this script from /etc/rsnapshot.conf.

INSTALL:

see INSTALL.txt

TODO:

see TODO.txt

CHANGES:

see CHANGES.txt

=cut

use warnings;
use strict;
use Cwd 'cwd';
use Data::Dumper;
use DBI;
use POSIX qw(strftime);
#use lib ('.');
#use rsnapshotDB;

=head

WARNING: type 'chmod 0600 /etc/rsnapshotDB.conf'
file must contain 'dbtype:username:password:host'
Currently 'dbtype' supported can be either 'mysql' or 'pgsql'
Only one entry per line. Functionality is similar to /etc/DBPASSWD,
however passwords are stored in plain text and NOT encrypted
"#"s are allowed as comments in the following file:

Note: rsnapshotdb.list is deprecated in favor of XML config rsnapshotDB.conf and rsnapshotDB.xsd

=cut

my $dbpasswd = '/etc/rsnapshotDB.conf';
my $xsd = '/etc/rsnapshotDB.xsd'; #used to validate config file
my $xmlUsage = 1; #0 if using flat-list configuation file (deprecated).
my $verbose = 2; #0 for no warning/status messages, increase for more.

=head

WARNING:

Setting the "temporary" directory:
1) the db dump might get left behind on error
2) the temp directory could fill up, depending on size of db and quota of user or directory

=cut

my $tmpDir = '$HOME/tmp'; #may want to change this^
my $niceness = '19'; #amount of CPU/Mem -20 high, 19 low priority.

=head

DUMPERS:

Location of "dumper" program(s)
type 'which <db-dumper>' to find the path (ie - 'which mysqldump')
Note: the hash key here must match 'dbtype' field in $dbpasswd file.

=cut
my $dumper = {
		'mysql'	=> {
			bin	=> &whichbin('mysqldump') || '/usr/local/mysqldump',
			user	=> '-u',
			pass	=> '-p',
			host	=> '-h',
			opts	=> '--opt -C' #db specific options
		},

		'pgsql'	=> {
			bin	=> &whichbin('pg_dump') || '/usr/local/pgsql/bin/pg_dump',
			user	=> '-U',
			pass	=> '-p',
			host	=> '-h',
			opts	=> '',
		},
	};

main();

sub main
{

	#check mode of $dbpasswd file
	my ($mode_dbpasswd) = (stat($dbpasswd))[2];
	$mode_dbpasswd = sprintf "%04o", $mode_dbpasswd & 07777;
	my $localTmpDir = cwd();

	unless (-o $dbpasswd && $mode_dbpasswd eq '0600')
	{
		die "Please secure '$dbpasswd' file. Type 'chmod 0600 $dbpasswd'.\n";
	}

	unless ($xmlUsage && -f $xsd)
	{
	
		warn "You are not validating '$dbpasswd' against an XMLSchema file: '$xsd'. Defaulting to flat file format for '$dbpasswd'.\n";
	}

	#read in passwords from file
	read_dbpasswd();
}

sub read_dbpasswd
{
	if ($xmlUsage)
	{
		my $xobj = rsnapshotDB->new( {
				'dbpasswd' => "$dbpasswd",
				'xsd' => "$xsd",
				'dumper' => $dumper,
				'tmpDir' => "$tmpDir",
				'verbose' => "$verbose",
			} );	

		my $validity = $xobj->validateXML; #boolean test

		if ($validity)
		{
			my $status = $xobj->parseXML();
		}
=head

END OF THE LINE:

If you've gotten this far with no "die" errors, you should be good to go with XML config rsnapshotDB.conf vs. flat list rsnapshotdb.list

Check the $localTmpDir or your /backups/.snapshot/foo/wherever you put your database backups using rsnapshot.conf.

=cut

		
	} else {

		open(DBPASSWD, $dbpasswd) or die "$!";

		while(<DBPASSWD>)
		{
			chomp;
			next if (/^#/); #skip comments
			my ($dbtype, $user, $pass, $host) = split(/:/);

			#retrieve databases accessible by user
			show_databases($dbtype, $user, $pass, $host);
		}

		close(DBPASSWD);
	}
}

sub show_databases
{
	my ($dbtype, $user, $pass, $host) = @_;
	my $names = []; #list of database names
	my $bin = $dumper->{$dbtype}->{'bin'};

	die "$dbtype dumper not found: $bin - Add binary path to '\$dumper'" unless ($bin);

	my $dbh = DBI->connect("dbi:$dbtype:host=$host", $user, $pass) or die DBI->errstr;


	#execute show databases query
	my $sth = $dbh->prepare("SHOW DATABASES") or die $dbh->errstr;
	$sth->execute() or die $dbh->errstr;

	#fetch results from query
	while (my $row = $sth->fetch)
	{
		push(@{$names}, $row->[0]);
	}

	$sth->finish();

	dump_databases($names, $dbtype, $user, $pass, $host);

	$dbh->disconnect();

	return;
}

sub dump_databases
{
	my ($names, $dbtype, $user, $pass, $host) = @_;
	my $timestamp = strftime "%F-%H.%M", localtime;
	my $bin = $dumper->{$dbtype}->{'bin'};

	#fix with more extensible loop
	my $user_arg = $dumper->{$dbtype}->{'user'};
	my $pass_arg = $dumper->{$dbtype}->{'pass'};
	my $host_arg = $dumper->{$dbtype}->{'host'};
	my $opts_arg = $dumper->{$dbtype}->{'opts'};

	foreach my $db (@{$names})
	{
		#file: dbtype--host--db--time.tar.gz
		#this is going to get ugly...

		my $file = join('--', $dbtype, $host, $db, $timestamp);

		my $localTmpDir = eval $tmpDir;
		chdir($localTmpDir);

		my $dump_cmd = "$bin $user_arg $user $pass_arg" . "$pass $host_arg $host $opts_arg $db > $file.sql";
		my $tar_cmd = "tar czf $localTmpDir/$file.tar.gz $file.sql";
		my $rm_cmd = "rm $file.sql";

=head
		#print Dumper($dump_cmd);

		#print "Backing up $db from $host\n";
=cut
		system($dump_cmd) == 0 or die "$!";
		system($tar_cmd) == 0 or die "$!";
		system($rm_cmd) == 0 or die "$!";

	}
}

=head

WHICH DUMPER:

Loads the default system dumper paths (ie - which mysqldump).
Note: currently, does not check on remote server as it should.

=cut

sub whichbin
{
	my $bin = shift;
	
	return qx{ echo -n `which $bin 2>/dev/null` } unless ($?) == 256;

}

package rsnapshotDB;

=head

rsnapshotDB.pm

=cut

use strict;
use Data::Dumper;
use Cwd 'cwd';
use POSIX qw(strftime);
use XML::Validator::Schema;
use XML::Simple;
use Net::SSH::Perl;
use DBI;

sub new
{
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = bless( {}, $class );

	my %data = ref($_[0]) eq 'HASH' ? %{$_[0]} : (@_);

	$self->_dbpasswd($data{'dbpasswd'});
	$self->_xsd($data{'xsd'});
	$self->_tmpDir($data{'tmpDir'});
	$self->_verbose($data{'verbose'});
	$self->_dumper($data{'dumper'});

	return $self;
}

sub validateXML
{
	my $self = shift;
	my $xml = $self->_dbpasswd;
	my $xsd = $self->_xsd;

	my $validator = XML::Validator::Schema->new(file=> $xsd);
	my $parser = XML::SAX::ParserFactory->parser(Handler => $validator);

	$self->v("WAITING: validating xml...");
	eval { $parser->parse_uri($xml) };
	die "File failed validation: $@" if $@;
	$self->v("FINISH: validated '$xml' against '$xsd'.");

	return $self;

}

=head
Utitility to parse our XML file for values
=cut

sub parseXML
{
	my $self = shift;

	#start xml parsing of conf file.
	my $xml = $self->_dbpasswd();
	my $parser = XML::Simple->new();

	#hardcoded xml tag names
	my $xmlRef = $parser->XMLin($xml, ForceArray => ['hostGroup', 'hostPair', 'databaseHost', 'defaultSSHHost'] ); 

	#count hostGroup tags
	my $hostGroups = scalar(@{$xmlRef->{'hostGroup'}});

	#process hostGroups
	for (my $i=0; $i<$hostGroups; $i++)
	{

		$self->v("START: hostGroup...");

		#save default hostGroup ssh host
		my $defaultSSHHost = {};

		#process  hostPairs
		foreach my $hostPair (@{$xmlRef->{'hostGroup'}->[$i]->{'hostPair'}})
		{

			$self->v("START: hostPair...");
			#save databaseHost hashref
			my $databaseHost = $hostPair->{'databaseHost'};

			if ( exists($hostPair->{'defaultSSHHost'}[0]->{'hostType'}) )
			{
				#save default and continue to use it
				$defaultSSHHost = $hostPair->{'defaultSSHHost'};

			}

			$self->loginSSH($defaultSSHHost, $databaseHost);

			$self->v("END: hostPair\n");
		}

		$self->v("END: hostGroup\n");
	}

	return $self;
}

=head

LOGIN REMOTELY:

This is the section where you authenticate with the remote ssh server.

I'm pretty sure, you can just leave off the password flags if you know what you're doing in the XML Config file rsnapshotDB.conf.

Requirement: Net::SSH::Perl. If you don't have root, read about how to install a perl module as an under privileged user (it IS possible - /home/username/modules/).

=cut


sub loginSSH
{
	my ($self, $sshHost, $dbHost) = @_;
	#see 'man ssh-keygen' to automate without password prompt

	if ($sshHost->[0]->{'hostType'} =~ /^ssh\d*$/)
	{
	
		my $login = Net::SSH::Perl->new($sshHost->[0]->{'hostname'}, debug => 0, protocol => '2,1');


		if ($sshHost->[0]->{'password'}){
			$self->v("WAITING: ssh password login attempt...");
			$login->login($sshHost->[0]->{'username'}, $sshHost->[0]->{'password'});
			$self->v("FINISH: Logged in via SSH password.");
		} else {
=head
PREFERRED METHOD:

Type '$man ssh-keygen' for logging into an ssh server without a password.
=cut
			$self->v("WAITING: ssh login attempt...");
			$login->login($sshHost->[0]->{'username'});
			$self->v("FINISH: Logged in via SSH.");
		}

		#grab user's database list
		$self->showDBs($sshHost, $dbHost, $login);
	} else {
		die "Only 'hostType' of 'ssh1' or 'ssh2' is currently supported\n";
	}

	return $self;
}

sub showDBs
{
=head
This <em>should</em> pull down the list of your database user's databases from the XML configuration file.
Note: This is done locally, not on the remote SSH server with db access.Since we're not writing or reading there isn't a lock on the table. The one restriction here is that you can actually access your database server remotely.

Some ISPs allow it or will add your ip (see:foo.dyndns.org) if your IP changes frequently or '%.chicago.myisp.net'. This typically would only be a problem with a home user. 
=cut
	my ($self, $sshHost, $dbHost, $login) = @_;

	my $dumper = $self->_dumper();
	my $dbType = $dbHost->[0]->{'dbType'};
	my $dbhost = $dbHost->[0]->{'dbhostname'};
	my $dbuser = $dbHost->[0]->{'dbusername'};
	my $dbpass = $dbHost->[0]->{'dbpassword'};
	my $dumpBin = $dumper->{$dbType}->{'bin'};
	my $dbNames = []; #results from SHOW DATABASES;

	die "$dbType dumper not found: $dumpBin - Add binary path to '\$dumper'" unless ( -f $dumpBin );

	my $dbh = DBI->connect("dbi:$dbType:host=$dbhost", $dbuser, $dbpass) or die DBI->errstr;

=head

TODO:

see TODO.txt to move this into a remote command (more secure).

=cut

	#execute show databases query
	my $sth = $dbh->prepare("SHOW DATABASES") or die $dbh->errstr;
	$sth->execute() or die $dbh->errstr;

	#fetch results from query
	while (my $row = $sth->fetch)
	{
		push(@{$dbNames}, $row->[0]);
	}

	$sth->finish();
	$dbh->disconnect();

	$self->dumbDB($sshHost, $dbHost, $dbNames, $login);

	return $self;

}

=head

DUMP DATABASE:


This is the bulk of the app, which logins to an internal ssh server with access to the database server. The main reason for speeding this application up was becauase a remote  database pull is extremely inefficient.

The idea here is to use ssh-keygen from this account to your remote ssh server, then do the database dump, and secure copy ('man scp') the file back here locally.

The gained result here should be seconds vs. minutes by pulling the database remotely (to us), and locally (to the database server) from the database server. If this makes no sense, don't worry about it, I got carried away on this one. :|
=cut


sub dumbDB
{
	my ($self, $sshHost, $dbHost, $dbNames, $login) = @_;
	my $tmpDir = $self->_tmpDir(); #tmp directory path
	my $localTmpDir = cwd();
	my ($stdout, $stderr, $exit) = $login->cmd( "echo -n $tmpDir" );
	my $remoteTmpDir = $stdout;

	unless ($exit) {
		$self->v("CMD: get remote tmp dir '$remoteTmpDir'.", 2);
	} else {
		warn "FAIL: set remote tmp dir '$tmpDir' $stderr.\n";
	}

	#reset
	($stdout, $stderr, $exit) = ();

	#db info
	my $dbType = $dbHost->[0]->{'dbType'};
	my $dbhost = $dbHost->[0]->{'dbhostname'};
	my $dbuser = $dbHost->[0]->{'dbusername'};
	my $dbpass = $dbHost->[0]->{'dbpassword'};

	#ssh info
	my $hostType = $sshHost->[0]->{'hostType'};
	my $host = $sshHost->[0]->{'hostname'};
	my $user = $sshHost->[0]->{'username'};
	my $pass = $sshHost->[0]->{'password'};

	#dumper arguments
	my $dumpBin = $self->_dumper->{$dbType}->{'bin'};
        my $dumpHostArg = $self->_dumper->{$dbType}->{'host'};
        my $dumpUserArg = $self->_dumper->{$dbType}->{'user'};
        my $dumpPassArg = $self->_dumper->{$dbType}->{'pass'};
        my $dumpOptsArg = $self->_dumper->{$dbType}->{'opts'};

	foreach my $dbName (@{$dbNames})
	{
		my $timestamp = strftime "%F-%H.%M", localtime;
		my $file = join('--', $dbType, $dbhost, $dbName, $timestamp);

                ($stdout, $stderr, $exit) = $login->cmd("test -d $remoteTmpDir");

		if ($exit)
		{
			warn "FAIL: test -d $remoteTmpDir.\n";
			($stdout, $stderr, $exit) = ();
			($stdout, $stderr, $exit) = $login->cmd("mkdir -m 0700 $remoteTmpDir");
			unless ($exit) {
				$self->v("CMD: mkdir -m 0700 $remoteTmpDir.", 2);
			} else {
				warn "FAIL: mkdir -m 0700 $remoteTmpDir $stderr.\n";
			}
		}

		#reset
		($stdout, $stderr, $exit) = ();

		#done regardless of existing tmp dir or not
		($stdout, $stderr, $exit) = $login->cmd("chmod 0700 $remoteTmpDir");
	
		unless ($exit) {
			$self->v("CMD: chmod on '$remoteTmpDir'.", 2);
			($stdout, $stderr, $exit) = ();
		} else {
			warn "FAIL: chmod on '$remoteTmpDir' $stderr.\n";
		}

		wait;

		#reset
		($stdout, $stderr, $exit) = ();

		#the actual .sql.gz remote file creation!
                my $remoteDumpCmd = "nice --adjustment=$niceness $dumpBin $dumpUserArg $dbuser $dumpPassArg" . "$dbpass $dumpHostArg $dbhost $dumpOptsArg $dbName > $remoteTmpDir/$file.sql";

		$self->v("WAITING: remote dump...");
		$self->v("CMD: $remoteDumpCmd", 2);
		($stdout, $stderr, $exit) = $login->cmd($remoteDumpCmd);
		$self->v("FINISH: remote dump.");


		wait;

		unless ($exit) {
			$self->v("CMD: Completed remote dump '$remoteDumpCmd'.", 2);
		} else {
			warn "FAIL: '$remoteDumpCmd' $stderr.\n";
		}

		#reset
		($stdout, $stderr, $exit) = ();
		my $remoteGZipCmd = "nice --adjustment=$niceness gzip $remoteTmpDir/$file.sql";
	
		$self->v("WAITING: remote gzip...");
		$self->v("CMD: $remoteGZipCmd", 2);
		($stdout, $stderr, $exit) = $login->cmd($remoteGZipCmd);
		$self->v("FINISH: remote gzip.");

		wait;

		unless ($exit) {
			$self->v("CMD: Completed '$remoteGZipCmd'.", 2);
		} else {
			warn "FAIL: '$remoteGZipCmd' $stderr.\n";
		}

=head
SECURE COPY:

At this point it's necessary to use ssh-keygen to connect to the server,the local command is using Net::SSH::Perl, please install locally (as root or even as under privileged user).

=cut

		#reset
		($stdout, $stderr, $exit) = ();
	
                my $localSCPCmd = "nice --adjustment=$niceness scp $user\@$host:$remoteTmpDir/$file.sql.gz $localTmpDir";

		my $localLogin = Net::SSH::Perl->new('localhost', debug => 0, protocol => '2,1');
		my $localUser = `echo -n \`whoami\``;

		$self->v("WAITING: local ssh login attempt...");
		($stdout, $stderr, $exit) = $localLogin->login($localUser);
		$self->v("FINISH: local ssh login.");

		unless ($exit)
		{
			$self->v("DONE: Local login as '$localUser'", 2);
		} else {
			warn "FAIL: '$localUser' $stderr\n";
		}

		$self->v("WAITING: local scp...");
		$self->v("$localSCPCmd", 2);
		($stdout, $stderr, $exit) = $localLogin->cmd($localSCPCmd);
		$self->v("FINISH: local scp.");

		wait;
	
		unless ($exit) {

			$self->v("DONE: local scp '$localSCPCmd'.", 2);

			$self->remoteRemove($login, $remoteTmpDir, $file);
		} else {

			warn "FAIL: '$localSCPCmd' $stderr. Skipping remoteRemove()\n";
		}
	}

	return $self;
}

sub remoteRemove
{

	my ($self, $login, $remoteTmpDir, $file) = @_;

	#reset
	my ($stdout, $stderr, $exit) = ();

	my $remoteRMCmd = "nice --adjustment=$niceness rm $remoteTmpDir/$file.sql.gz";

	$self->v("WAITING: remote remove...");
	($stdout, $stderr, $exit) = $login->cmd($remoteRMCmd);
	$self->v("FINISH: remote remove.");

	wait;

	unless ($exit)
	{
		$self->v("DONE: remote remove '$file.sql.gz'.", 2);

	} else {
		warn "FAIL: '$remoteRMCmd' $stderr.\n";
	} 

	#reset
	($stdout, $stderr, $exit) = ();

	return $self;	
}

=head

ARCHIVING:


The move from $localTmpDir to '/backups/.snapshot/database' is determined in rsnapshot.conf and backup database.pl option (see 'man rsnapshot' for script usage). In this case rsnapshotdb.pl
=cut


=head

VERBOSITY:

Typically, you would first want to test rsnapshotDB with verbosity set to 1 in the rsnapshotdb.pl see:$verbose => 1.

You can increase verbosity ie - 2 instead of 1. Typically, this will dump commands that are being execute remotely and/or locally.

=cut

sub v
{
	my ($self, $msg, $level) = @_;

	unless ($level) { $level = 1; }

	if ($self->_verbose >= $level) {
		print "$msg\n";
	}

	return $self;
}

#Class::Accessors simulation
sub _dbpasswd
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'dbpasswd'};
	}

	$self->{'dbpasswd'} = shift;

	return $self->{'dbpasswd'};
}

sub _xsd
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'xsd'};
	}

	$self->{'xsd'} = shift;

	return $self->{'xsd'};
}

sub _dumper
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'dumper'};
	}

	$self->{'dumper'} = shift;

	return $self->{'dumper'};
}

sub _tmpDir
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'tmpDir'};
	}

	$self->{'tmpDir'} = shift;

	return $self->{'tmpDir'};
	#escape special chars and spaces here.
	#use Cwd;
}

sub _verbose
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'verbose'};
	}

	$self->{'verbose'} = shift;

	return $self->{'verbose'};
}


1;

=head
MORE INFO:

see README.txt
=cut
