#!/bin/perl

=head1 NAME

 aixSVMon.pl

=head1 SYNOPSIS

 IntroscopeEPAgent.properties configuration

 introscope.epagent.plugins.stateless.names=SVMON
 introscope.epagent.stateless.SVMON.command=perl <epa_home>/epaplugins/aix/aixSVMon.pl
 introscope.epagent.stateless.SVMON.delayInSeconds=15

=head1 DESCRIPTION

 Pulls Java native heap (working storage) statistics for a particular process

 To see help information:

 perl <epa_home>/epaplugins/aix/aixSVMon.pl --help

 or run with no commandline arguments.

 To test against sample output, use the DEBUG flag:

 perl <epa_home>/epaplugins/aix/aixSVMon.pl --debug

=head1 ISSUE TRACKING

 Submit any bugs/enhancements to: https://github.com/htdavis/ca-apm-fieldpack-epa-aix/issues

=head1 AUTHOR

 Hiko Davis, Sr Engineering Services Architect, CA Technologies

=head1 COPYRIGHT

 Copyright (c) 2017

 This plug-in is provided AS-IS, with no warranties, so please test thoroughly!

=cut

use strict;
use warnings;

use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", "$FindBin::Bin/../lib/perl", "$FindBin::Bin/../../lib/perl");
use Wily::PrintMetric;

use Getopt::Long;


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
	@arrayResults = <<"END_OUTPUT" =~ m/(^.*\n)/mg;
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
	# commandline option for svmon; use double-quotes to expand $ARGV[0] before execution
	my $svmonCommand = "svmon -P $ARGV[0] -O commandline=on,segment=on,filterprop=notempty|tail -10";
	@arrayResults = `svmonCommand`;
}


my (@vals, $procName);

for my $i (3..$#arrayResults){
    ##print "line $i: $arrayResults[$i]\n";
    if ($i == 3){
        # remove EOL char
        chomp $arrayResults[$i];
        # remove leading and trailing spaces
        $arrayResults[$i] =~ s/^\s+//;
        #$arrayResults[$i] =~ s/\s+$//;
        # split the string
        @vals = split (/\s+/, $arrayResults[$i]);
        $procName = $vals[1];
        # print the results
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'SVMon',
                                        subresource => $procName,
                                        name        => 'Pid',
                                        value       => $vals[0],
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => $procName,
                                        name        => 'Inuse',
                                        value       => int($vals[2]),
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => $procName,
                                        name        => 'Pin',
                                        value       => int($vals[3]),
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => $procName,
                                        name        => 'Pgsp',
                                        value       => int($vals[4]),
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => $procName,
                                        name        => 'Virtual',
                                        value       => int($vals[5]),
                                       );
    } elsif ($arrayResults[$i] =~ /^$/){ $i++; next; }
     else {
        # remove EOL char
        chomp $arrayResults[$i];
        # remove leading spaces
        $arrayResults[$i] =~ s/^\s+//;
        # split the string
        @vals = split(/\s+/, $arrayResults[$i], 4);
        # reverse and split $vals[3]
        my $line = reverse $vals[3];
        #print $line . "\n"; ##for debugging
        my @revVals = split(/\s+/, $line, 6);
        # replace and add values to @vals
        splice(@vals, 3, 6, @revVals);
        my ($description, $psize, $inuse, $pin, $pgsp, $virtual);
        # reverse values before printing metrics
        if (!defined($vals[8])){$description = "unknown";}
        else {$description = reverse $vals[8];}
        $psize = reverse $vals[7];
        $inuse = reverse $vals[6];
        $pin = reverse $vals[5];
        $pgsp = reverse $vals[4];
        $virtual = reverse $vals[3];
        # check if Type value is a hyphen and replace with "unknown"
        if ($vals[1] =~ /\-/){ $vals[1] = "unknown"; }
        # print the results using Vsid as the subresource
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Esid',
                                        value       => $vals[1],
                                       );
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Type',
                                        value       => $vals[2],
                                       );
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Description',
                                        value       => $description,
                                       );
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Psize',
                                        value       => $psize,
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Inuse',
                                        value       => $inuse,
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Pin',
                                        value       => $pin,
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Pgsp',
                                        value       => $pgsp,
                                       );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'SVMon',
                                        subresource => "$procName|Vsid|". $vals[0],
                                        name        => 'Virtual',
                                        value       => $virtual,
                                       );
    }
}
