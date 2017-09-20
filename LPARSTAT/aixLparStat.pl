#!/bin/perl

=head1 NAME

 aixLparStat.pl

=head1 SYNOPSIS

 IntroscopeEPAgent.properties configuration

 introscope.epagent.plugins.stateless.names=LPARSTAT
 introscope.epagent.stateless.LPARSTAT.command=perl <epa_home>/epaplugins/aix/LPARSTAT/aixLparStat.pl
 introscope.epagent.stateless.LPARSTAT.delayInSeconds=15

=head1 DESCRIPTION

 Pulls lpar configurations

 To see help information:

 perl <epa_home>/epaplugins/aix/aixLparStat.pl --help

 or run with no commandline arguments.

 To test against sample output, use the DEBUG flag:

 perl <epa_home>/epaplugins/aix/LPAR/aixLparStat.pl --debug

=head1 AUTHOR

 Hiko Davis, Principal Services Consultant, CA Technologies

=head1 COPYRIGHT

 Copyright (c) 2017

 This plug-in is provided AS-IS, with no warranties, so please test thoroughly!

=cut

use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl", 
         "$FindBin::Bin/../lib/perl", "$FindBin::Bin/../../lib/perl");
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

my ($help, $debug);

# get commandline parameters or display help
&usage if ( not GetOptions( 'help|?'  =>  \$help,
                            'debug!'  =>  \$debug,
                          )
            or defined $help );

# array to hold command or debug results
my @arrayResults;

# if debug is enabled, use the sample output for displaying results
if ($debug) {
    @arrayResults = <<"END_OUTPUT" =~ m/(^.*\n)/mg;
Node Name                                  : nodeDemo1
Partition Name                             : nodeDemo1
Partition Number                           : 13
Type                                       : Shared-SMT-4
Mode                                       : Uncapped
Entitled Capacity                          : 0.30
Partition Group-ID                         : 32781
Shared Pool ID                             : 0
Online Virtual CPUs                        : 2
Maximum Virtual CPUs                       : 8
Minimum Virtual CPUs                       : 1
Online Memory                              : 12288 MB
Maximum Memory                             : 36864 MB
Minimum Memory                             : 4096 MB
Variable Capacity Weight                   : 40
Minimum Capacity                           : 0.10
Maximum Capacity                           : 0.80
Capacity Increment                         : 0.01
Maximum Physical CPUs in system            : 64
Active Physical CPUs in system             : 32
Active CPUs in Pool                        : 32
Shared Physical CPUs in system             : 32
Maximum Capacity of Pool                   : 3200
Entitled Capacity of Pool                  : 2265
Unallocated Capacity                       : 0.00
Physical CPU Percentage                    : 15.00%
Unallocated Weight                         : 0
Memory Mode                                : Dedicated-Expanded
Total I/O Memory Entitlement               : -
Variable Memory Capacity Weight            : -
Memory Pool ID                             : -
Physical Memory in the Pool                : -
Hypervisor Page Size                       : -
Unallocated Variable Memory Capacity Weight: -
Unallocated I/O Memory entitlement         : -
Memory Group ID of LPAR                    : -
Desired Virtual CPUs                       : 2
Desired Memory                             : 12288 MB
Desired Variable Capacity Weight           : 40
Desired Capacity                           : 0.30
Target Memory Expansion Factor             : 1.70
Target Memory Expansion Size               : 20736 MB
Power Saving Mode                          : Disabled
Sub Processor Mode                         : -
END_OUTPUT
} else {
    # commandline option for lparstat
    my $lparstatCommand = 'lparstat -i';
    # execute command
    @arrayResults = `$lparstatCommand`;
}

# parse through results
for (my $i = 0; $i < @arrayResults.length; $i++) {
    # end loop if $i equals 42
    last if ($i == 42);
    # skip line if $i matches
    next if ($i == [2-3] || $i == [6-7] || $i == [14-17] || $i == [22-24] || $i == [26-40]);
    # remove EOL char
    chomp $arrayResults[$i];
    # split on ': '
    my ($metric, $value) = split (/: /, $arrayResults[$i]);
    # remove trailing spaces
    $metric =~ s/\s+$//;
    if ($i == 1 || $i == 4) {
        # return StringEvent
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric,
                                        value       => $value,
                                      );
    } elsif ($metric eq 'Entitled Capacity') {
        # return as StringEvent
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric,
                                        value       => $value,
                                      );
       # return as IntCounter
       Wily::PrintMetric::printMetric( type         => 'IntCounter',
                                       resource     => 'LPARSTAT',
                                       subresource  => '',
                                       name         => $metric . ' 100x',
                                       value        => int($value * 100),
                                     );
    } elsif ($metric =~ /^.*Virtual\sCPUs$/) {
        # return as IntCounter
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric,
                                        value       => $value,
                                      );
    } elsif ($metric =~ /^.*Memory$/) {
        # remove 'MB' from $value
        my ($countValue, $countType) = split (/\s/, $value);
        # return as LongCounter
        Wily::PrintMetric::printMetric( type        => 'LongCounter',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric . ' ('. $countType . ')',
                                        value       => $countValue,
                                      );
    } elsif ($metric =~ /^.*Physical\sCPUs\sin\ssystem$/) {
        # return as IntCounter
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric,
                                        value       => $value,
                                      );
    } elsif ($metric =~ /^Physical\sCPU\sPercentage$/) {
        # return as IntCounter
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric,
                                        value       => sprintf("%.0f", $value),
                                      );
    } elsif ($metric =~ /^Target\sMemory\sExpansion\sSize$/) {
        # remove 'MB' from $value
        my ($countValue, $countType) = split (/\s/, $value);
        # return as LongCounter
        Wily::PrintMetric::printMetric( type        => 'LongCounter',
                                        resource    => 'LPARSTAT',
                                        subresource => '',
                                        name        => $metric . ' ('. $countType . ')',
                                        value       => $countValue,
                                      );
    };
}
