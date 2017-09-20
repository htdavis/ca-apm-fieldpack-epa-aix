#!/usr/bin/perl
=head1 NAME

 aixDiskStats.pl

=head1 SYNOPSIS

 IntroscopeEPAgent.properties configuration

 introscope.epagent.plugins.stateless.names=DISKSTATS
 introscope.epagent.stateless.DISKSTATS.command=perl <epa_home>/epaplugins/aix/aixDiskStats.pl [/filesystem1 /filesystem2 ...]
 introscope.epagent.stateless.DISKSTATS.delayInSeconds=900 (less for more frequent updates)

=head1 DESCRIPTION

 The program will create two nodes --
 Device, which provides metrics by device name
 Disk, which provides metrics by mount point

 To see help information:

 perl <epa_home>/epaplugins/aix/aixDiskStats.pl --help

 or run with no commandline arguments.

 To test against sample output, use the DEBUG flag:

 perl <epa_home>/epaplugins/aix/aixDiskStats.pl --debug

=head1 CAVEATS

 I've noticed a weird bug when attempting to filter on only root filesystem "/".
 I don't think you'll ever want to do this, but just know that it doesn't work.

=head1 ISSUE TRACKING

 Submit any bugs/enhancements to: https://github.com/htdavis/ca-apm-fieldpack-epa-aix/issues

=head1 AUTHOR

 Hiko Davis, Sr Engineering Service Architect, CA Technologies

=head1 COPYRIGHT

 Copyright (c) 2011-2017

 This plug-in is provided AS-IS, with no warranties, so please test thoroughly!

=cut

use strict;
use warnings;

use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", "$FindBin::Bin/../lib/perl", "$FindBin::Bin/../../lib/perl");
use Wily::PrintMetric;

use Getopt::Long;
use Scalar::Util qw(looks_like_number);

sub usage {
    print "Unknown option: @_\n" if ( @_ );
    print "usage: $0 [/filesystem1 /filesystem2 ...] [--help|-?] [--debug]\n\n";
    print "\tAdding a filesystem to the commandline will cause the program to\n";
    print "\tonly report metrics for the specified device and/or disk.\n";
    exit;
}

my ($help, $debug);
&usage if ( not GetOptions( 'help|?' => \$help,
                            'debug!' => \$debug,
                          )
            or defined $help );

# get the mounted disks specified on the command line
my $mountedDisksRegEx = '.'; # default is match all
if ( scalar(@ARGV) > 0 ) {
    foreach my $item ( @ARGV ) {
        if ( $item eq $debug ) { next; } else {
            $mountedDisksRegEx = join('|', @ARGV);
        }
    }
}

my ($iostatCommand, @iostatResults);
my ($dfCommand, @dfResults);

if ( $debug ) {
    # use here-docs for command results
    @iostatResults = <<"EOF" =~ m/(^.*\n)/mg;

System configuration: lcpu=2 drives=3 paths=6 vdisks=2

Disks:        % tm_act     Kbps      tps    Kb_read   Kb_wrtn
hdisk1           5.2     417.8      61.6   2076006648  1101763592
hdisk5           0.5      50.8       2.4   236607956  149605396
hdisk3           0.8      99.3      13.2   154868307  600239296
EOF

    @dfResults = <<"EOF" =~ m/(^.*\n)/mg;
Filesystem    1024-blocks      Used      Free %Used    Iused    Ifree %Iused Mounted on
/dev/hd4           327680    177208    150472   55%     9925    35769    22% /
/dev/hd2          2883584   2042796    840788   71%    33977   192192    16% /usr
/dev/hd9var        327680     65820    261860   21%      605    58386     2% /var
/dev/hd3          4194304   2894400   1299904   70%     2741   315598     1% /tmp
/dev/hd1           196608       768    195840    1%      122    43654     1% /home
/dev/hd11admin      131072       364    130708    1%        5    29105     1% /admin
/proc                   -         -         -    -         -        -     -  /proc
/dev/hd10opt      1179648    437160    742488   38%     9511   167326     6% /opt
/dev/lv_audit      262144       584    261560    1%        9    58147     1% /audit
/dev/http_lv       851968    648240    203728   77%     2804    46276     6% /apps/httpserver_6
/dev/was6_lv      7274496   5771964   1502532   80%    53371   428237    12% /apps/websphere6
/dev/apps_lv      2162688   1347500    815188   63%    45737   213015    18% /apps/webapps
/dev/tmpwaslv     4096000   3385884    710116   83%    54179   245384    19% /apps/tmpInstallwas6
/dev/was6_bck      327680    210296    117384   65%        6    26111     1% /apps/was_bck
/dev/tmpapp_lv      131072      4012    127060    4%        5    31494     1% /apps/tmp
/dev/cft_lv        229376    163444     65932   72%      328    15091     3% /bnp/cft
/dev/u06_lv         32768       892     31876    3%       10     7169     1% /u06
/dev/http_lv2      851968    480228    371740   57%     2774    83450     4% /apps/httpserver_6s
/dev/smwa          393216    298540     94676   76%     1684    23515     7% /apps/netegrity
EOF

} else {
    # iostat command for AIX disks
    $iostatCommand = 'iostat -d';
    # Get the device stats
    @iostatResults = `$iostatCommand`;
    # df command for AIX
    $dfCommand = 'df -kv';
    # Get the disk stats
    @dfResults = `$dfCommand`;
}


# parse the iostat results and report the
# relevant data using metrics
for my $i ( 4..$#iostatResults ) {
	chomp $iostatResults[$i]; # remove trailing new line
	my @deviceStats = split (/\s+/, $iostatResults[$i]);
	my $deviceName = $deviceStats[0];

	# now, check to see if the user specified this device on the command line.
	next if $deviceName !~ /$mountedDisksRegEx/i;
	
	# report iostats
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
									resource    => 'Device',
									subresource => $deviceName,
									name        => 'Kb_wrtn',
									value       => int ($deviceStats[5]),
								  );
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
								    resource    => 'Device',
								    subresource => $deviceName,
								    name        => 'Kb_read',
								    value       => int ($deviceStats[4]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $deviceName,
								    name        => 'tps',
								    value       => sprintf("%.0f",$deviceStats[3]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $deviceName,
								    name        => 'Kbps',
								    value       => sprintf("%.0f",$deviceStats[2]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $deviceName,
								    name        => 'tm_act (%)',
								    value       => sprintf("%.0f", $deviceStats[1]),
								  );
}


for my $d ( 1..$#dfResults ) {
  chomp $dfResults[$d]; # remove trailing new line
  my @dfStats = split (/\s+/, $dfResults[$d]);
  my $fsName = $dfStats[0];
  my $diskName = $dfStats[8];

	# now, check to see if the user specified this disk on the command line.
	next if $diskName !~ /$mountedDisksRegEx/i;

	# report zero if value is blank/null
	if(!defined($dfStats[3]) || !looks_like_number($dfStats[3]))
	   {$dfStats[7] = 0; $dfStats[6] = 0; $dfStats[5] = 0; $dfStats[4] = 0; $dfStats[3] = 0; $dfStats[2] = 0; $dfStats[1] = 0;}
	else {chop $dfStats[4]; chop $dfStats[7]; }

	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Inodes (%)',
								    value       => int($dfStats[7]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Free Inodes',
								    value       => int($dfStats[6]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Inodes',
								    value       => int($dfStats[5]),
								  );
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Disk Space (%)',
								    value       => int($dfStats[4]),
								  );
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Free Disk Space (MB)',
								    value       => int ($dfStats[3] / 1024),
								  );
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Disk Space (MB)',
								    value       => int ($dfStats[2] / 1024),
								  );
	Wily::PrintMetric::printMetric( type        => 'LongCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Total Disk Space (MB)',
								    value       => int ($dfStats[1] / 1024),
								  );
	Wily::PrintMetric::printMetric( type        => 'StringEvent',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Filesystem',
								    value       => $dfStats[0],
								  );
}
