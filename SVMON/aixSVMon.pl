#!/bin/perl

=head1 NAME

 aixSVMon.pl

=head1 SYNOPSIS

 IntroscopeEPAgent.properties configuration

 introscope.epagent.plugins.stateless.names=SVMON
 introscope.epagent.stateless.SVMON.command=perl <epa_home>/epaplugins/aix/aixSVMon.pl
 introscope.epagent.stateless.SVMON.delayInSeconds=15

=head1 DESCRIPTION

 Pulls Java native heap (working storage) statistics

 To see help information:

 perl <epa_home>/epaplugins/aix/aixSVMon.pl --help

 or run with no commandline arguments.

 To test against sample output, use the DEBUG flag:

 perl <epa_home>/epaplugins/aix/aixSVMon.pl --debug

=head1 AUTHOR

 Hiko Davis, Principal Services Consultant, CA Technologies

=head1 COPYRIGHT

 Copyright (c) 2015

 This plug-in is provided AS-IS, with no warranties, so please test thoroughly!

=cut

use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", "$FindBin::Bin/../lib/perl");
use Wily::PrintMetric;

use Getopt::Long;

use strict;

=head2 SUBROUTINES

=cut

=head3 USAGE

 Prints help information for this program

=cut
sub usage {
    print "Unknown option: @_\n" if ( @_ );
    print "usage: $0 [--help|-?]\n";
    exit;
}

my ($interval, $help, $debug);

# get commandline parameters or display help
&usage if ( @ARGV < 1 or
    not GetOptions( 'help|?'  =>  \$help,
                    'debug!'  =>  \$debug,
                  )
    or defined $help );

# array to hold command or debug results
my @arrayResults;

# if debug is enabled, use the sample output for displaying results
if ($debug) {
	@arrayResults = <<END_OUTPUT;
Unit: page
-------------------------------------------------------------------------------
     Pid Command          Inuse      Pin     Pgsp  Virtual
  221326 java             20619     6326     9612    27584

    Vsid      Esid Type Description              PSize  Inuse   Pin Pgsp Virtual
    502d         d work text or shared-lib code seg  m    585     0    1     585
       0         0 work kernel segment               m    443   393    4     444
   14345         3 work working storage             sm   2877     0 7865    9064
   15364         e work shared memory segment       sm   1082     0 1473    1641
   1b36a         f work working storage             sm    105     0  106     238
   17386         - work                              s    100    34   64     146
   1a38b         2 work process private             sm      7     4   24      31
END_OUTPUT
} else {
	# commandline option for svmon
	# TODO create method to get pid the the command
	my $svmonCommand = 'svmon -P [pid] -O commandline=on,segment=on,filterprop=notempty';
	@arrayResults = `svmonCommand`;
}

# skip the first 6 rows
@arrayResults = @arrayResults[6..$#arrayResults];

# parse the results and report the relevant metrics

# TODO look for 'working storage'