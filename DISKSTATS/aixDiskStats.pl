#!/bin/perl
#############################################################
# AIX Disk Stats
# =========================
# Copyright (C) 2011
# =========================
# Description: 
# The program will create two nodes: Device, which
# provides metrics by device name; Disk, which provides metrics by mount point.
# =========================
# Usage: perl aixDiskStats.pl [/filesystem1 /filesystem2 ...]
#
# Adding a filesystem to the commandline will cause the program to only report
# metrics for the specified device and/or disk.
#############################################################
use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", "$FindBin::Bin/../lib/perl");
use Wily::PrintMetric;

use strict;


# get the mounted disks specified on the command line
my $mountedDisksRegEx = '.'; # default is match all
if (scalar(@ARGV) > 0) {
	$mountedDisksRegEx = join('|', @ARGV);
}

# iostat command for AIX disks
my $iostatCommand = 'iostat -d';
# Get the device stats
my @iostatResults = `$iostatCommand`;
# Get rid of the header lines for each command
@iostatResults = @iostatResults[4..$#iostatResults];
# Output on AIX:
#
#System configuration: lcpu=2 drives=3 paths=6 vdisks=2
#
#Disks:        % tm_act     Kbps      tps    Kb_read   Kb_wrtn
#hdisk1           5.2     417.8      61.6   2076006648  1101763592
#hdisk5           0.5      50.8       2.4   236607956  149605396
#hdisk3           0.8      99.3      13.2   154868307  600239296

# parse the iostat results and report the
# relevant data using metrics
foreach my $isline (@iostatResults) {
	chomp $isline; # remove trailing new line
	my @deviceStats = split (/\s+/, $isline);
	my $device = $deviceStats[0];

	# now, check to see if the user specified this device on the command
	# line.
	next if $device !~ /$mountedDisksRegEx/i;
	
	# report iostats
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
									resource    => 'Device',
									subresource => $device,
									name        => 'Kb_wrtn',
									value       => int ($deviceStats[5]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $device,
								    name        => 'Kb_read',
								    value       => int ($deviceStats[4]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $device,
								    name        => 'tps',
								    value       => int ($deviceStats[3]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $device,
								    name        => 'Kbps',
								    value       => int ($deviceStats[2]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Device',
								    subresource => $device,
								    name        => 'tm_act (%)',
								    value       => int ($deviceStats[1]),
								  );
}

# df command for AIX
my $dfCommand = 'df -kv';
# Get the disk stats
my @dfResults = `$dfCommand`;
# Get rid of the header lines for each command
@dfResults = @dfResults[1..$#dfResults];
# Output on AIX:
#Filesystem    1024-blocks      Used      Free %Used    Iused    Ifree %Iused Mounted on
#/dev/hd4           327680    177208    150472   55%     9925    35769    22% /
#/dev/hd2          2883584   2042796    840788   71%    33977   192192    16% /usr
#/dev/hd9var        327680     65820    261860   21%      605    58386     2% /var
#/dev/hd3          4194304   2894400   1299904   70%     2741   315598     1% /tmp
#/dev/hd1           196608       768    195840    1%      122    43654     1% /home
#/dev/hd11admin      131072       364    130708    1%        5    29105     1% /admin
#/proc                   -         -         -    -         -        -     -  /proc
#/dev/hd10opt      1179648    437160    742488   38%     9511   167326     6% /opt
#/dev/lv_audit      262144       584    261560    1%        9    58147     1% /audit
#/dev/http_lv       851968    648240    203728   77%     2804    46276     6% /apps/httpserver_6
#/dev/was6_lv      7274496   5771964   1502532   80%    53371   428237    12% /apps/websphere6
#/dev/apps_lv      2162688   1347500    815188   63%    45737   213015    18% /apps/webapps
#/dev/tmpwaslv     4096000   3385884    710116   83%    54179   245384    19% /apps/tmpInstallwas6
#/dev/was6_bck      327680    210296    117384   65%        6    26111     1% /apps/was_bck
#/dev/tmpapp_lv      131072      4012    127060    4%        5    31494     1% /apps/tmp
#/dev/cft_lv        229376    163444     65932   72%      328    15091     3% /bnp/cft
#/dev/u06_lv         32768       892     31876    3%       10     7169     1% /u06
#/dev/http_lv2      851968    480228    371740   57%     2774    83450     4% /apps/httpserver_6s
#/dev/smwa          393216    298540     94676   76%     1684    23515     7% /apps/netegrity

foreach my $dfLine (@dfResults) {
  chomp $dfLine; # remove trailing new line
  my @dfStats = split (/\s+/, $dfLine);
  my $fsName = $dfStats[0];
  my $diskName = $dfStats[8];

	# now, check to see if the user specified this disk on the command
	# line.
	next if $diskName !~ /$mountedDisksRegEx/i;

	# report the df stats
	# each of the integer values are explicitly converted to prevent epagent
	# from reporting errors for the metric type
	
	# Just print the Inodes Used as a Percent
	# chop gets rid of '%' in the capacity
	chop $dfStats[7];
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
	# Just print the Used Disk Space as a Percent
	# chop gets rid of '%' in the capacity
	chop $dfStats[4];
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Disk Space (%)',
								    value       => int($dfStats[4]),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Free Disk Space (MB)',
								    value       => int ($dfStats[3] / 1024),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
								    resource    => 'Disk',
								    subresource => $diskName,
								    name        => 'Used Disk Space (MB)',
								    value       => int ($dfStats[2] / 1024),
								  );
	Wily::PrintMetric::printMetric( type        => 'IntCounter',
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
