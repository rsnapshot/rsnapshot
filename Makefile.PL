#!/usr/bin/env perl
#
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => "rsnapshot",
	# disable till we know, where the mistake is
	#VERSION => `git describe --tags --always`,
	MAN1PODS => {
		'src/rsnapshot.pl' => 'src/rsnapshot.1',
		'src/rsnapshot-diff.pl' => 'src/rsnapshot-diff.1',
	},

	META_MERGE => {
		"meta-spec" => { version => 2 },
		resources => {
			repository => {
				type => 'git',
				url => 'git://github.com/rsnapshot/rsnapshot.git',
				web => 'https://github.com/rsnapshot/rsnapshot',
			},
		},
	},
	#PM_FILTER => 'sed "s%@PERL@%/usr/bin/perl%g"', # this is the old filter
	# does not work:
	PM_FILTER => qq{ /usr/bin/sed -e "s,rsnapshot,/usr/bin/perl,g" },
	PM => {
		'src/rsnapshot.pl' => '$(INST_BIN)/rsnapshot',
		'src/rsnapshot-diff.pl' => '$(INST_BIN)/rsnapshot-diff',
	},
);
