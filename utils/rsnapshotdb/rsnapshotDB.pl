#!/usr/bin/perl

=pod

=head1 NAME: rsnapshotDB

Web: http://www.rsnapshot.org

Bugs: rsnapshot-discuss@lists.sf.net

License: GPL http://www.gnu.org/licenses/gpl.txt

Version: 1.2.1

=head1 AUTHOR: Anthony Ettinger

Email: aettinger<--at-->sdsualumni<--dot-->org

Blog: http://anthony.ettinger.name


=head1 DESCRIPTION:

This script was originally written to function as a MySQL database backup script in conjunction with the open source Perl/rsync backup program "rsnapshot".  rsnapshot can be found at: http://www.rsnapshot.org/

In order to backup a database remotely, the necessary database user must be able to connect remotely to the database server from a trusted secure shell server. (some ISPs only allow access from an internal network - you may need to make sure you do have internal access from an internal ssh server to the database server).

IF YOU DON'T HAVE SSH KEYS, this program isn't for you. (see:man ssh-keygen).

It is extremely important that you secure the /etc/rsnapshotDB.conf file so only YOU (the user who's cronjob this is running from) can read the file, 'chmod 0600 /etc/rsnapshotDB.conf', as it will store the database passwords in plain text format.

If you don't know who YOU are - type 'whoami' or ask a friend.

For best results, configure and run this script from /etc/rsnapshot.conf. (see:'man rsnapshot', backup_script).

=head2 SEE ALSO:

INSTALL.txt, TODO.txt, CHANGES.txt

=cut

use warnings;
use strict;
use Cwd 'cwd';
use Data::Dumper;
use DBI;
use POSIX qw(strftime);

=head3

WARNING: type 'chmod 0600 /etc/rsnapshotDB.conf'
Currently 'dbtype' supported can be either 'mysql' or 'pgsql'
Functionality is similar to /etc/DBPASSWD,
however passwords are stored in plain text and NOT encrypted
<!-- comments --> are allowed in the following file:

Note: rsnapshotdb.list is deprecated in favor of XML config rsnapshotDB.conf and rsnapshotDB.xsd

=cut

my $dbpasswd = '/etc/rsnapshotDB.conf';
my $xsd = '/etc/rsnapshotDB.xsd'; #used to validate config file
my $xmlUsage = 1; #0 if using flat-list configuation file (deprecated).
my $verbose = 2; #0 for no warning/status messages, increase for more.

=head2 WARNING:

Setting the "temporary" directory:
1) the db dump might get left behind on error
2) the temp directory could fill up, depending on size of db and quota of user or directory

=cut

my $tmpDir = '$HOME/tmp'; #may want to change this^
my $niceness = '19'; #amount of CPU/Mem -20 high, 19 low priority.
my $sshOption = '-o TCPKeepAlive=yes'; #keep ssh alive (avoid timeouts)

=head2 DUMPERS:

Location of "dumper" program(s)
type 'which <db-dumper>' to find the path (ie - 'which mysqldump')
Note: the hash key here must match 'dbtype' field in $dbpasswd file.

=cut

my $dbApp = {
	'mysql'	=> {
		'dumper' => {
			bin	=> 'mysqldump',
			opts	=> '--opt -C',
			user	=> '-u',
			pass	=> '-p',
			host	=> '-h',
		},
		'prompt'	=> {
			bin	=> 'mysql',
			opts	=> '-s',
			user	=> '-u',
			pass	=> '-p',
			host	=> '-h',
		},
	},
	'pgsql'	=> {
		'dumper' => {
			 bin => 'pg_dump',
			opts	=> '',
			user	=> '-U',
			pass	=> '-p',
			host	=> '-h',
		},
		'prompt' => {
			bin	=> 'pgsql',
			opts	=> '',
			user	=> '-U',
			pass	=> '-p',
			host	=> '-h',
		},
	},
};

init();

sub init
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
				'dbpasswd' 	=> $dbpasswd,
				'xsd'		=> $xsd,
				'dbApp' 	=> $dbApp,
				'tmpDir'	=> $tmpDir,
				'verbose'	=> $verbose,
			} );	

		my $validity = $xobj->validateXML; #boolean test

		if ($validity)
		{
			#main module dump routine called within
			my $status = $xobj->parseXML();
		}
	} else {
		die "flat list is deprecated, please see INSTALL.txt";
	}
}

=pod

=head1

END OF THE LINE:

If you've gotten this far with no "die" errors, you should be good to go with XML config rsnapshotDB.conf vs. flat list rsnapshotdb.list

Check the $localTmpDir or your /backups/.snapshot/foo/wherever you put your database backups using rsnapshot.conf.

=cut

package rsnapshotDB;

=pod

=head1 rsnapshotDB.pm

=cut

use strict;
use Data::Dumper;
use Cwd 'cwd';
use POSIX qw(strftime);
use XML::Validator::Schema;
use XML::Simple;

sub new
{
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = bless( {}, $class );

	my $timestamp = localtime;
	my %data = ref($_[0]) eq 'HASH' ? %{$_[0]} : (@_);

	$self->_dbpasswd($data{'dbpasswd'});
	$self->_xsd($data{'xsd'});
	$self->_tmpDir($data{'tmpDir'});
	$self->_verbose($data{'verbose'});
	$self->_dbApp($data{'dbApp'});
	$self->v("\n\nSTART TIME: $timestamp", 0);

	return $self;
}

sub validateXML
{
	my $self = shift;
	my $xml = $self->_dbpasswd;
	my $xsd = $self->_xsd;

	my $validator = XML::Validator::Schema->new(file=> $xsd);
	my $parser = XML::SAX::ParserFactory->parser(Handler => $validator);

	$self->v("WAITING: validating xml...", 1);
	eval { $parser->parse_uri($xml) };
	die "File failed validation: $@" if $@;
	$self->v("FINISH: validated '$xml' against '$xsd'.", 1);

	return $self;

}

=pod

=head1 C<parseXML()>

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

		$self->v("START: hostGroup...", 1);

		#save default hostGroup ssh host
		my $defaultSSHHost = {};

		#process  hostPairs
		foreach my $hostPair (@{$xmlRef->{'hostGroup'}->[$i]->{'hostPair'}})
		{

			$self->v("START: hostPair...", 1);
			#save databaseHost hashref
			my $databaseHost = $hostPair->{'databaseHost'};

			if ( exists($hostPair->{'defaultSSHHost'}[0]->{'hostType'}) )
			{
				#save default and continue to use it
				$defaultSSHHost = $hostPair->{'defaultSSHHost'};

			}

			$self->showDB($defaultSSHHost, $databaseHost);

			$self->v("END: hostPair\n", 1);
		}

		$self->v("END: hostGroup\n", 1);
	}

	return $self;
}

=pod

=head2 LOGIN REMOTELY:

This is the section where you authenticate with the remote ssh server.

I'm pretty sure, you can just leave off the password flags if you know what you're doing in the XML Config file rsnapshotDB.conf.

Requirement: Net::SSH::Perl. If you don't have root, read about how to install a perl module as an under privileged user (it IS possible - /home/username/modules/).


=head2 SHOW DATABASES:

C<$self-\>showDB();>

This <em>should</em> pull down the list of your database user's databases from the XML configuration file.

Note: This is done on the remote SSH server with db access. Since we're not writing or reading there isn't a lock on the table. The one restriction here is that you can actually access your database server remotely from an internal ssh server via ssh tunneling.

=head2 PATH:

Make sure your prompt binary (ie - mysql) and dumper binary (ie - mysqldump) are in your default path for the ssh user.

=cut

sub showDB
{
	my ($self, $sshHost, $dbHost) = @_;
	#ssh
	my $user   = $sshHost->[0]->{'username'};
	my $host   = $sshHost->[0]->{'hostname'};
	#db
	my $dbApp = $self->_dbApp();
	my $dbType = $dbHost->[0]->{'dbType'};
	my $dbuser = $dbHost->[0]->{'dbusername'};
	my $dbpass = $dbHost->[0]->{'dbpassword'};
	my $dbhost = $dbHost->[0]->{'dbhostname'};

	#add dbApp binaries to you PATH on the server(s)
	my $dumper = $dbApp->{$dbType}->{'dumper'}->{'bin'};
	my $prompt = $dbApp->{$dbType}->{'prompt'}->{'bin'};
	my $dbNames = []; #results from SHOW DATABASES;
	my $dbpass_arg = defined($dbpass) ? "$dbApp->{$dbType}->{'prompt'}->{'pass'}$dbpass" : ''; #dbpass not required
	

	$self->v("START: showDB command...", 1);
	my $cmdShowDB = "ssh $sshOption $user\@$host \"echo -n 'SHOW DATABASES;' | \ $dbApp->{$dbType}->{'prompt'}->{'bin'} \ $dbApp->{$dbType}->{'prompt'}->{'opts'} \ $dbApp->{$dbType}->{'prompt'}->{'user'} $dbuser \ $dbpass_arg \ $dbApp->{$dbType}->{'prompt'}->{'host'} $dbhost\""; 

	my $out = qx/$cmdShowDB/ or warn 'SHOW DATABASES failed...';
	$self->v("CMD: $cmdShowDB -> $out.", 2);
	$self->v("DONE: showDB command.", 1);

	#fetch results from query
	push(@{$dbNames}, split(/\n/, $out));
	$self->v(Dumper($dbNames), 2);
	$self->dumbDB($sshHost, $dbHost, $dbNames);

	return $self;
}

=pod

=head2 DUMP DATABASE:

This is the bulk of the app, via ssh tunneling, logs in to an internal ssh server with access to the database server. The main reason for speeding this application up was becauase a remote  database pull is extremely inefficient directly over the internet.

The idea here is to use ssh-keygen from this account to your remote ssh server, then do the database dump, and secure copy ('man scp') the file back here locally.

The gained result here should be seconds vs. minutes.

=cut


sub dumbDB
{
	my ($self, $sshHost, $dbHost, $dbNames) = @_;
	my $user   = $sshHost->[0]->{'username'};
	my $host   = $sshHost->[0]->{'hostname'};
	#db
	my $dbApp  = $self->_dbApp();
	my $dbType = $dbHost->[0]->{'dbType'};
	my $dbuser = $dbHost->[0]->{'dbusername'};
	my $dbpass = $dbHost->[0]->{'dbpassword'};
	my $dbhost = $dbHost->[0]->{'dbhostname'};

	#add dbApp binaries to you PATH on the server(s)
	my $dumper = $dbApp->{$dbType}->{'dumper'}->{'bin'};
	my $prompt = $dbApp->{$dbType}->{'prompt'}->{'bin'};

	my $tmpDir = $self->_tmpDir(); #remote tmp directory path
	my $localTmpDir = cwd(); #need by rsnapshot
	my $cmdRemoteTmpDir = "ssh $sshOption $user\@$host 'echo -n $tmpDir'";

	$self->v("CMD: remote tmp dir '$cmdRemoteTmpDir'.", 2);
	my $remoteTmpDir = qx/$cmdRemoteTmpDir/ or warn "REMOTE TMP DIR failed...";
	$self->v("SET: remote temp dir... '$remoteTmpDir'", 1);

	#dumper arguments
	my $dumpOptsArg = $dbApp->{$dbType}->{'dumper'}->{'opts'};
	my $dumpHostArg = $dbApp->{$dbType}->{'dumper'}->{'host'};
	my $dumpUserArg = $dbApp->{$dbType}->{'dumper'}->{'user'};
	my $dumpPassArg = $dbApp->{$dbType}->{'dumper'}->{'pass'};

	foreach my $dbName (@{$dbNames})
	{
		my $ftimestamp = strftime "%F-%H.%M", localtime;
		$self->v("FTIMESTAMP: $ftimestamp", 1);

		my $file = join('--', $dbType, $dbhost, $dbName, $ftimestamp);
		my $cmdTestRTD = "ssh $sshOption $user\@$host 'test -d $remoteTmpDir'";
		$self->v("CMD: $cmdTestRTD.", 2);

		my $out = qx/$cmdTestRTD/;

		if ($?)
		{
			$self->v("FAIL: $cmdTestRTD, $out.", 0);
			my $cmdCreateRTD = "ssh $sshOption TCPKeepAlive $user\@$host 'mkdir -m 0700 $remoteTmpDir'";
			my $out = qx/$cmdCreateRTD/;
			$self->v("CMD: $cmdCreateRTD.", 2);
			$self->v("FAIL: $cmdCreateRTD, $out", 0) if $?;

		} else {
			my $cmdChmodRTD = "ssh $sshOption $user\@$host 'chmod 0700 $remoteTmpDir'";
			my $out = qx/$cmdChmodRTD/;

			$self->v("FAIL: $cmdChmodRTD, $out.", 2) if $?;
		}
	
		#the actual .sql.gz remote file creation!
		my $cmdRemoteDump = "ssh $sshOption $user\@$host 'umask 0077;nice --adjustment=$niceness $dumper \ $dumpOptsArg $dumpUserArg $dbuser $dumpPassArg" . "$dbpass $dumpHostArg $dbhost \ $dbName > $remoteTmpDir/$file.sql'";

		$self->v("WAITING: remote dump...", 1);
		$out = qx/$cmdRemoteDump/;
		$self->v("FAIL: $cmdRemoteDump, $out.", 0) if $?;
		$self->v("CMD: $cmdRemoteDump", 2);
		$self->v("FINISH: remote dump.", 1);

		my $cmdRemoteGZip = "ssh $sshOption $user\@$host 'nice --adjustment=$niceness gzip --fast $remoteTmpDir/$file.sql'";
	
		$self->v("WAITING: remote gzip...", 1);
		$self->v("CMD: $cmdRemoteGZip", 2);
		$out = qx/$cmdRemoteGZip/;
		$self->v("FAIL: $cmdRemoteGZip, $out.", 0) if $?;
		$self->v("FINISH: remote gzip.", 1);

		my $cmdRemoteSCP = "scp $user\@$host:$remoteTmpDir/$file.sql.gz $localTmpDir";
		$self->v("WAITING: remote scp...", 1);
		$self->v("CMD: $cmdRemoteSCP", 2);
		$out = qx/$cmdRemoteSCP/;
		$self->v("FAIL: $cmdRemoteSCP, $out.", 0) if $?;
		$self->v("FINISH: remote scp.", 1);

		my $cmdRemoteRM = "ssh $sshOption $user\@$host 'nice --adjustment=$niceness rm $remoteTmpDir/$file.sql.gz'";

		$self->v("WAITING: remote remove...", 1);
		$self->v("CMD: $cmdRemoteRM", 2);
		$out = qx/$cmdRemoteRM/;
		$self->v("FAIL: $cmdRemoteRM, $out.", 0) if $?;
		$self->v("FINISH: remote remove.", 1);
	}
}

=pod

=head2

SECURE COPY:

At this point it's necessary to use ssh-keygen to connect to the server, the local command is using SSH tunneling.

ARCHIVING:


The move from $localTmpDir to '/backups/.snapshot/database' is determined in rsnapshot.conf and backup rsnapshotDB.pl option (see 'man rsnapshot' for script usage).

VERBOSITY:

Typically, you would first want to test rsnapshotDB with verbosity set to 1 in the rsnapshotdb.pl see:$verbose => 1.

You can increase verbosity ie - 2 instead of 1. Typically, this will dump commands that are being execute remotely and/or locally.

LOG FILE:

/var/log/rsnapshotDB

=cut

sub v
{
	my ($self, $msg, $level) = @_;

	open(LOG, ">>/var/log/rsnapshotDB") or warn "$!";
	chmod 0600, "/var/log/rsnapshotDB";

	if ($self->_verbose >= $level) {
		print LOG "$msg\n";
	}

	close(LOG);

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

sub _binPath
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'binPath'};
	}

	$self->{'_binPath'} = shift;

	return $self->{'_binPath'};
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

sub _dbApp
{
	my $self = shift;

	if (@_ == 0)
	{
		return $self->{'dbApp'};
	}

	$self->{'dbApp'} = shift;

	return $self->{'dbApp'};
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

=pod

=head1 MORE INFO:

see README.txt

=cut
