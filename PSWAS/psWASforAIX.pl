#!/bin/perl
#############################################################
# WebSphere Usage Statistics
# =========================
# Copyright (C) 2011
# =========================
# Description:
# The program gathers usage statistics from WebSphere
# and places them under node "JVM Stats"
# =========================
# Usage: perl psWASforAIX.pl
#############################################################
use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", "$FindBin::Bin/../lib/perl");
use Wily::PrintMetric;

use strict;

my $psCommand='ps -eaf|awk \'/(WebSphere\/java)/&&!/grep/{print $2}\'|xargs -n1 ps vww|awk \'NF>5&&!/PID/{printf "%s\t%s\t%s\n",$7,$11,$NF;t+=$7;c+=$11}\'';
my @psResults=`$psCommand`;

# output results
#RSS	 CPU	 AppServer	# HEADER IS NOT DISPLAYED
#29272   0.4     appserver_1
#94428   0.4     appserver_2
#45820   0.5     nodeagent
#48476   0.3     appserver_3
#62148   0.6     appserver_4
#55352   0.3     appserver_5
#24948   0.2     appserver_6
#60848   0.5     appserver_7
#28588   0.5     appserver_8
#38428   0.2     appserver_9
#35140   0.5     appserver_10
#85056   0.3     appserver_11
#57240   0.2     appserver_12
#76744   0.6     dmgr
#69200   8.8     appserver_13
#39372   0.3     appserver_14
#71108   2.5     appserver_15

# initialize counter for total resident memory
my $total=0;

# parse results
foreach my $line (@psResults){
	chomp $line;
	# split the row
	my @jvmStats=split /\t/, $line;
	($total+=$_) for $jvmStats[0];
	# print metrics
	Wily::PrintMetric::printMetric(	type		=> 'StringEvent',
									resource	=> 'JVM Stats',
									subresource	=> $jvmStats[2],
									name		=> 'CPU (%)',
									value		=> $jvmStats[1],
								  );
	Wily::PrintMetric::printMetric(	type		=> 'IntCounter',
									resource	=> 'JVM Stats',
									subresource	=> $jvmStats[2],
									name		=> 'RSS',
									value		=> int($jvmStats[0]),
								  );
}
# print the total resident memory usage
Wily::PrintMetric::printMetric(	type		=> 'LongCounter',
								resource	=> 'JVM Stats',
								name		=> 'Total Resident Memory (KB)',
								value		=> $total,
							  );
