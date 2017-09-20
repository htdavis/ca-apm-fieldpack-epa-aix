#!/usr/bin/perl

=head1 NAME

 aixSystStat.pl

=head1 SYNOPSIS

 IntroscopeEPAgent.properties configuration

 introscope.epagent.plugins.stateless.names=AIX
 introscope.epagent.stateless.AIX.command=perl <epa_home>/epaplugins/aix/SYSSTAT/aixSystStat.pl
 introscope.epagent.stateless.AIX.delayInSeconds=15

=head1 DESCRIPTION

 Pulls svmon & vmstat statistics

 To see help information:

 perl <epa_home>/epaplugins/aix/aixSystStat.pl --help

 or run with no commandline arguments.

 To test against sample output, use the DEBUG flag:

 perl <epa_home>/epaplugins/aix/aixSystStat.pl --debug

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
use lib ("$FindBin::Bin", "$FindBin::Bin/lib/perl",
         "$FindBin::Bin/../lib/perl", "$FindBin::Bin/../../lib/perl");
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

my ($help, $debug);

# get commandline parameters or display help
&usage if( not GetOptions( 'help|?'  =>  \$help,
                           'debug!'  =>  \$debug,
                         )
           or defined $help );

# array to hold command or debug results
my (@svmonResults, @vmstatResults);

# if debug is enabled, use the sample output for displaying results
if ($debug) {
    @vmstatResults = <<"END_VMSTAT" =~ m/(^.*\n)/mg;
 8  0 4343133 888077   0   0   0   0    0   0  86 3669 3595  8  6 86  0  0.09  28.4
END_VMSTAT

    @svmonResults = <<"END_SVMON" =~ m/(^.*\n)/mg;
memory     20736.00    18448.86     2031.14     2330.52    18510.35    2027.39   Ded-E
pg space    4096.00        55.1

               work        pers        clnt       other
pin         2112.66           0        8.23      465.62
in use     18433.31           0      271.55

END_SVMON
} else {
    my ($svmonCommand, $vmstatCommand);
    # commands to be executed
    $svmonCommand = 'svmon -G -O summary=basic,unit=MB|tail -7';
    $vmstatCommand = 'vmstat 1 2|tail -1';
    
    # execute commands and stuff results into arrays
    @svmonResults = `$svmonCommand`;
    @vmstatResults = `$vmstatCommand`;
}


# parse through svmon results
for my $i (0..$#svmonResults) {
    # exit if $i eq 6
    last if $i == 6;

    # skip next if $i eq 2 or 3
    next if $i == [2-3];
    
    # remove EOL char
    chomp $svmonResults[$i];
    
    # remove trailing spaces
    $svmonResults[$i] =~ s/\s+$//;

    # split on spaces
    my @values = split (/\s{2,}/, $svmonResults[$i]);
    
    if ($i == 0 || $i == 1) {
        # 'pg space' return zeros values 3-7
        if ($i == 1)
            {$values[3] = 0; $values[4] = 0; $values[5] = 0; $values[6] = 0; $values[7] = "None";}
        # print results
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Size (MB)',
                                        value       => sprintf("%.0f", $values[1]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'In Use (MB)',
                                        value       => sprintf("%.0f", $values[2]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Free (MB)',
                                        value       => sprintf("%.0f", $values[3]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Pinned Memory (MB)',
                                        value       => sprintf("%.0f", $values[4]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Virtual Memory (MB)',
                                        value       => sprintf("%.0f", $values[5]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Available Memory (MB)',
                                        value       => sprintf("%.0f", $values[6]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'StringEvent',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Mode',
                                        value       => $values[7],
                                      );
    } elsif ($i == 4 || $ i == 5) {
        # if 'in use' return zero for 'other segments'
        if ($i == 5) {$values[4] = 0;}
        # print results
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Work Segments (MB)',
                                        value       => sprintf("%.0f", $values[1]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Persistent Segments (MB)',
                                        value       => sprintf("%.0f", $values[2]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Client Segments (MB)',
                                        value       => sprintf("%.0f", $values[3]),
                                      );
        Wily::PrintMetric::printMetric( type        => 'IntCounter',
                                        resource    => 'System Resource Utilization',
                                        subresource => $values[0],
                                        name        => 'Other Segments',
                                        value       => sprintf("%.0f", $values[4]),
                                      );
    }   
}

# parse through vmstat results
# remove EOL char
chomp $vmstatResults[0];

# remove leading and trailing spaces
$vmstatResults[0] =~ s/^\s+//;
$vmstatResults[0] =~ s/\s+$//;

# split on spaces
my @results = split (/\s+/, $vmstatResults[0]);

# print results
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Kernel Threads',
                                name        =>  'Threads in Run Queue',
                                value       =>  $results[0],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Kernel Threads',
                                name        =>  'Threads in Wait Queue',
                                value       =>  $results[1],
                              );
Wily::PrintMetric::printMetric( type        =>  'LongCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Memory',
                                name        =>  'Active Virtual Pages',
                                value       =>  $results[2],
                              );
Wily::PrintMetric::printMetric( type        =>  'LongCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Memory',
                                name        =>  'Free List Size',
                                value       =>  $results[3],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Pages In\Out List',
                                value       =>  $results[4],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Pages In',
                                value       =>  $results[5],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Pages Out',
                                value       =>  $results[6],
                              );
Wily::PrintMetric::printMetric( type        =>  'LongCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Pages Freed',
                                value       =>  $results[7],
                              );
Wily::PrintMetric::printMetric( type        =>  'LongCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Pages Scanned',
                                value       =>  $results[8],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Page',
                                name        =>  'Clock Cycles by Page',
                                value       =>  $results[9],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Faults',
                                name        =>  'Device Interrupts',
                                value       =>  $results[10],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Faults',
                                name        =>  'Systems Calls',
                                value       =>  $results[11],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'Faults',
                                name        =>  'Content Switches',
                                value       =>  $results[12],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'User %',
                                value       =>  sprintf("%.0f", $results[13]),
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'System %',
                                value       =>  sprintf("%.0f", $results[14]),
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'Idle %',
                                value       =>  sprintf("%.0f", $results[15]),
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'Idle Time Waiting For IO %',
                                value       =>  sprintf("%.0f", $results[16]),
                              );
Wily::PrintMetric::printMetric( type        =>  'StringEvent',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'Physical Processors Used',
                                value       =>  $results[17],
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'Physical Processors Used (100x)',
                                value       =>  $results[17] * 100,
                              );
Wily::PrintMetric::printMetric( type        =>  'IntCounter',
                                resource    =>  'System Resource Utilization',
                                subresource =>  'CPU',
                                name        =>  'Entitlement Util %',
                                value       =>  sprintf("%.0f", $results[18]),
                              );
