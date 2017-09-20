########################################################################
# Introscope EPAgent Plugin Script                               
#                                                                      
# CA Wily Introscope(R) Version 9.0.6.0 Release 9.0.6.0
# Copyright (c) 2011 CA. All Rights Reserved.
# Introscope(R) is a registered trademark of CA.
#
########################################################################
# NMON Log Reader
# --------------------
# This Plugin Script reports metrics based on the 
# alerts configured in the nmonLogReader.cfg file.
# It takes 4 optional command line arguments:
# 1) sleepTime - the number of seconds to delay
#                between each scan of the log file
#                for new messages.
# 2) logfileDir - the directory in which the log files are 
#                 located.  This MUST end in a '/' or '\'
#                 depending on the Operating System being used.
# 3) logfile    - the regular expression that corresponds to 
#                 the name of logfiles generated.  
# 4) subResource - the sub-resource part of the metric name
#
# Example:
# perl nmonLogReader.pl -sleepTime 30 -logfileDir "c:/temp/logs"
#
########################################################################

#import our modules
use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/../lib/perl",
         "$FindBin::Bin/../../lib/perl","$FindBin::Bin/../../lib/perl");
use Wily::Config; # Config file parser
use Wily::nmonLogReader; # log reading

use strict;
use Getopt::Long;

$| = 1; # auto-flush STDOUT

# load the configs
my $config = Wily::Config::parseConfig("$FindBin::Bin/nmonLogReader.cfg");

# Get and Check command line arguments here...
#
GetOptions(
        'sleepTime=i'   => \($config->{'SLEEPTIME'}),
	    'logfileDir=s'  => \($config->{'LOGFILEDIR'}),
	    'logfile=s'     => \($config->{'LOGFILE'}),
	    'subResource=s' => \($config->{'SUBRESOURCE'}),
	    'n=i'           => \($config->{'NUMLOOPS'}),
	   );

# read the logfile based on these configuration options
Wily::nmonLogReader::readLog($config);

