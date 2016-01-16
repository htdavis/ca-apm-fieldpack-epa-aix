########################################################################
# Introscope EPAgent Logfile Reader Perl Library
#                                                                      
# CA Wily Introscope(R) Version 9.0.6.0 Release 9.0.6.0
# Copyright (c) 2011 CA. All Rights Reserved.
# Introscope(R) is a registered trademark of CA.
#
########################################################################
# LogReader Module
########################################################################

package Wily::nmonLogReader;

use strict;

#----------------
# Import Modules
#----------------
use FindBin;
use lib ("$FindBin::Bin", "$FindBin::Bin/../lib/perl", "$FindBin::Bin/..");
use Wily::PrintMetric;

#-----------
# Constants
#-----------
my $kLogFileDirKey        = 'LOGFILEDIR';    # Config Properties/Keys: General
my $kLogFileKey           = 'LOGFILE';
my $kSleepTimeKey         = 'SLEEPTIME';
my $kResourceKey          = 'RESOURCE';
my $kSubResourceKey       = 'SUBRESOURCE';
my $kNumLoops             = 'NUMLOOPS';
my $kNullPadding          = 'NULLPADDING';

my $kLineFormatKey        = 'LINE_FORMAT';   # Config Properties/Keys: Line Fmt
my $kLineFormatDelimKey   = 'DELIMITER';    
my $kLineFormatFieldsKey  = 'FIELDS';        

my $kMetricKey            = 'METRICS';       # Config Properties/Keys: Metrics
my $kOldMetricKey         = 'ALERTS';
my $kMetricMatchKey       = 'match';
my $kMetricMatchRuleKey   = 'matchRule';
my $kMetricMatchActionKey = 'matchAction';
my $kMetricTypeKey        = 'metricType';
my $kMetricNameKey        = 'metricName';
my $kMetricValueKey       = 'metricValue';
my $kExtendedKey          = 'extended';

my $kCurrentCountMacro    = 'CURRENTCOUNT';  # Built-in macro variables
my $kTotalCountMacro      = 'TOTALCOUNT';
my $kLineMacro            = 'LINE';
my $kDateMacro            = 'DATE';
my $kLogMacro             = 'LOG';

my $kSumCountMacro        = '_SUM';
my $kNumEntriesCountMacro = '_NUM_ENTRIES';

#---------
# Globals
#---------
my %MACROS = ();
my %COUNT_NUM_ENTRIES = (); # used in sub COUNT() to count # keys

my %TOTAL_COUNTS;              # Hashes to keep track of total and
my %CURRENT_COUNTS;            #   current counts for each match.
my %COUNTED_IT;                # Track if we've counted match/match_rules 
                               #   already for cases where match/match_rules
                               #   are duplicated across metric cfg blocks
my %COUNTER_METRICS_LIST = (); # Utility hash for queuing of metrics that 
                               #   reference $TOTALCOUNT or $CURRENTCOUNT
                               #   for delayed, printing of single metric

#----------------
# Subroutines
#----------------

# Returns the most recently modified file in the given directory
# Also takes a regular expression to select from a group of files
sub getMostRecentlyModifiedFile {
    my $dir = shift;
    my $file = shift;

    # Trim whitespace
    $dir =~ s/\s*$//;
    $dir =~ s/^\s*//;
    $file =~ s/\s*$//;
    $file =~ s/^\s*//;

    # delete any trailing slashes
    #
    $dir  =~ s@[/\\]+\s*$@@;
    $file =~ s@[/\\]+\s*$@@;
    
    opendir(DIR, $dir) || die "Error opening file directory: $dir";
    
    my %matchingFiles; # the hash for files matched,
                       # keyed on modified dates with 
                       # filenames as the values
    
    my $curFile = undef;
    
    # Iterate through all the files in the directory
    # and keep track of the ones that fit the logfile pattern.
    # Also, grab the date modified for those files
    while (defined ($curFile = readdir(DIR))) {
        ### print "currentfile:$curFile\n";
		if( $curFile =~ /^$file$/i ) {
            my $fullFileName = &fullFileName($dir, $curFile);
            my @fileStats = stat($fullFileName);
            # fileStats[9] = when the file was last modified
            $matchingFiles{$fileStats[9]} = $curFile;    
        }
    }
    
    # now sort all the modification dates and get the 
    # most recently modified file
    my @sortedDates = sort keys %matchingFiles;
    my $mostRecentFile = $matchingFiles{$sortedDates[$#sortedDates]};
    
    closedir(DIR);
    return $mostRecentFile;
}

# this returns the full file name (including path)
# given the path (first argument) and file name (second argument).
sub fullFileName {
    my $dir = shift;
    my $file = shift;
    my $separator = "";
   
    # Trim whitespace
    $dir =~ s/\s*$//;
    $dir =~ s/^\s*//;
    $file =~ s/\s*$//;
    $file =~ s/^\s*//;

    # check to see if the directory ends in / or \
    #
    if( $dir !~ m@[/\\]\s*$@ ) {
        if ($dir =~ m@/@) {
            $separator = '/';
        } elsif ($dir =~ m@\\@) {
            $separator = "\\";
        } else {
            # default to forward slash (perl can use either)
            $separator = '/';
        }
    }
    return $dir . $separator . $file;
}

sub binarySearchLastCharPos {
    my ($filename, $lower, $upper) = @_;

    my $pos = int( ($lower + $upper) / 2);
    return $upper if ($pos == $lower || $pos == $upper);

    open(TMP, "<$filename");
    seek(TMP, $pos, 0);
    my $line = <TMP>;

    close(TMP);

    if ($line =~ /^\000/) {
        # line starts with nulls...file pos too high
        #
        $upper = $pos;
        
    } elsif ($line =~ /\000/) {
        # line contains nulls...find start of null...done
        #
        my $nullpos = index($line, "\000");
        return($pos + $nullpos);
    } else {
        # line contains all chars...file pos too low
        #
        $lower = $pos;
    }
    $pos = &binarySearchLastCharPos($filename, $lower, $upper);
    return $pos;
}

# Returns position of last character (non-null) of file
# Args: $filename    (fully-qualified name of logfile)
#       $nullpadding (boolean to indicate whether file has trailing or
#                     padded nulls)
#
sub getLastCharPos {
    my %args = @_;
    my $filename    = $args{filename};
    my $nullpadding = $args{nullpadding};

    my $pos = 0;

    my @fileStats = stat($filename);
    my $size = $fileStats[7];    # current size
    if ($nullpadding) {
        # binary search for byte pos of 1st-null line
        $pos = &binarySearchLastCharPos($filename, -1, $size);
    } else {
        # logfile is all text, so pos is eof or $size
        $pos = $size;
    }
    return $pos;
}

sub clearCurrentCounters {
    # Clear the COUNTER_METRICS_LIST and CURRENTCOUNT values
    #
    %COUNTER_METRICS_LIST = (); # For queued/delay printing (single value)
    %CURRENT_COUNTS = ();       # $CURRENTCOUNT across all $matchKey's

    # Clear MACROS 
    # 
    foreach my $key (keys %MACROS) {
        if ($key =~ /::$kCurrentCountMacro\b/) {
            delete $MACROS{$key};
        }
    }

    # Clear helper counter hash -- for advanced aggregations (SUM, TOTAL)
    # 
    foreach my $key (keys %COUNT_NUM_ENTRIES) {
        if ($key =~ /::$kCurrentCountMacro\b/) {
            delete $COUNT_NUM_ENTRIES{$key};
        }
    }
}

sub clearDollarMacros {
    for (my $i=0; $i<100; $i++) {
        last if !defined($MACROS{$i});
        $MACROS{$i} = undef;
    }
}

sub setMacros {
    my %macros = @_;
    for my $key (keys %macros) {
        ### print "### adding \$MACROS{$key} = $macros{$key}\n";
        $MACROS{$key} = $macros{$key};
    }
}

# Expands config file variable references ($varName, ${varName}), 
# built-in variables ($CURRENTCOUNT, $TOTALCOUNT, $LINE, $DATE, etc.),
# and code references (&Package::Function()).
#
sub evalMacros {

    my $buffer = shift; # one argument, orig buffer w/ macros

    1 if %MACROS;       # MAGIC: forces MACROS to be visible in this scope
                        #        which is needed due to heavy dose of eval
                        #        magic below

    my $macro_var;
    my $macro_val;
    my $key;
    my $finalEval = 0;

    return ($buffer) if ($buffer !~ /\$/ &&               # return if no '$' vars
                         $buffer !~ /(^|[^\\])\&\{?\w+/); # and no func calls

    # If surrounded by braces, or                       (code block)
    # if surrounded by double quotes                    (string to be eval'ed)
    # if surrounded by parens (1st and last char) 
    #    or contains logical AND '&&' or OR '||'        (boolean)
    # We should do a final eval on the expression.
    # Strip surrounding parens/braces (leave quotes), and mark flag.
    #
    if ($buffer =~ /^["\(\{](.*)["\)\}]$/ || $buffer =~ /\&\&|\|\|/) {
        $buffer =~ s/^[\(\{](.*)[\)\}]$/$1/;
        $finalEval = 1;
    }

    ### print "\n### buffer=<$buffer>\n";

    my $result; # result

    my @TOKENS = split(/\s*([\&][\&]|[\|][\|])\s*/, $buffer);
    ### print "### TOKENS=" . join(',',@TOKENS) . "\n";
    foreach my $token (@TOKENS) {
        if ( $token =~ /\&\&|\|\|/ ) {
            $result .= " $token ";
            next;
        }

        # Substitute Variables
        #
        # while ( $token =~ m@(^|[^\\])\$((\{[^\}]+\})|(\S+\b))@ ) {
        while ( $token =~ m@(^|[^\\])\$((\{[/.:\w]+\})|([/.:\w]+\b))@ ) {
            $macro_var = '\$'.$2;
            ($key = $2) =~ s/[\{\}]//g;

            if (ref($MACROS{$key}) eq 'CODE') {
                $macro_val = &{$MACROS{$key}};
                ### print "### MACRO is CODE REF: \$macro_val = $MACROS{$key}\n";
            } elsif ( (ref($MACROS{$key}) eq 'HASH')  ||
                      (ref($MACROS{$key}) eq 'ARRAY') ||
                      (ref($MACROS{$key}) eq 'SCALAR')   ) {

                $macro_val = "_MACROS{$key}"; # HACK: don't want to replace 
                                              # '$MACROS' so use '_MACROS'

                ### print "### MACRO is HASH/ARRAY/SCALAR REF: \$macro_val = $MACROS{$key}\n";

            } else {
                $macro_val = $MACROS{$key};
                ### print "### MACRO is SCALAR: \$macro_val = <$MACROS{$key}>\n";
            }

            ### print "### VAR: \$token=$token, var=$macro_var, val=$macro_val\n";
            $token =~ s/$macro_var/$macro_val/g;

            ### print "### VAR: \$token=$token\n";

        } # Substitute Variables
          # while ( $token =~ m@(^|[^\\])\$((\{[^\}]+\})|(\S+\b))@ )

        $token =~ s/_MACROS\{/\$MACROS\{/g;

        # NOTE: To simplify parsing, syntax must be as follows:
        #       1) Simple func call, no args: &foo()
        #       2) Func call with args must use &func('a','b','c')
        #             &goo(6, 7, &foo);

        no strict 'refs';

        # Evaluate Func Calls With Args
        #
        while ( $token =~ /(^|[^\\])\&([\w:]+)\(([^\(\)\&]*)\)/ ) {
            my $t2 = $2;
            my $t3 = $3;

            my $func_name = $2;
            my $func_args = $3;
            my @func_args = split(/\s*,\s*/, $func_args);

            my $tmp = join(',',@func_args);
            ### print "### \$t2=<$t2>, \$t3=<$t3>, \$func_name=<$func_name>, \$func_args=<$tmp>\n";

            $macro_var = '\&'.$func_name.'\(([^\(\)\&]*)\)'; 
            my $func_call = '&'.$func_name.'('.$func_args.')';
            ### print "### \$func_call=<$func_call>\n"; 
            $macro_val = eval $func_call;

            ### print "### CODE: \$token=$token, var=$macro_var, val=$macro_val\n";

            $token =~ s/$macro_var/$macro_val/g;

            ### print "### CODE: \$token=<$token>\n";

        } # Evaluate Func Calls With Args
          # while ( $token =~ /(^|[^\\])\&([\w:]+)\(([^\(\)\&]*)\)/ )

        use strict; 

        $result .= $token;

    } # foreach my $token (@TOKENS)

    # Unescape all escaped chars (e.g. '\$' -> '$')
    # $result =~ s/\\(.)/$1/g;
    $result =~ s/\\\$/\$/g;

    # If it's a boolean expression i.e. surrounded by parens OR
    # if it's a block i.e. surrounded by braces, OR
    # if it's a double-quoted string, perform additional eval
    #
    if ($finalEval) {
        ### print "### evalMacros: evaluating boolean \$result=<$result>\n";
        $result = eval $result;
    }

    ### print "### evalMacros: returning \$result=<$result>\n";
    return $result;
}

# A generic helper func to count. Updates %MACROS based on args.
# Uses an underlying hash, %COUNT_NUM_ENTRIES, in order to facilitate
# various aggregate count functions e.g. SUM
#
# args: $module    - a module or category for namespace partitioning
#       $tag       - a tag marking some event/occurrence
#                    '_SUM' is reserved and tracks total counts across all keys
#       The macro variable name is created by concatenating: "$module::$tag"
#
#       $valueExpr - optional arg. Sets macro variable using $valueExpr 
#                    if specified. Can be of form: (+|-)?(\d+) 
#                    Otherwise increments macro variable.
#
sub COUNT {
    my ($module, $tag, $valueExpr) = @_;

    ### print "### COUNT: module=<$module>, tag=<$tag>, valueExpr=<$valueExpr>\n";
    my $key        = $module.'::'.$tag;
    my $sumKey     = $module.'::'.$kSumCountMacro;
    my $numKeysKey = $module.'::'.$kNumEntriesCountMacro;

    $COUNT_NUM_ENTRIES{$key}++;

    ### print "### COUNT: key=<$key>, sumKey=<$sumKey>\n";

    # 2002 10 02 jenko FUTURE: add other vars
    #my $ceilKey  = "$module::_CEILING";
    #my $floorKey = "$module::_FLOOR";
    #my $avgKey   = "$module::_AVERAGE";

    my $oldValue = $MACROS{$key};

    if ($valueExpr) {
        if ($valueExpr =~ /^\s*\d+\s*$/) {             # set to number
            $MACROS{$key} = $valueExpr;
        } elsif ($valueExpr =~ /^\s*\+\s*(\d+)\s*$/) { # add number
            $MACROS{$key} += $1;
        } elsif ($valueExpr =~ /^\s*\-\s*(\d+)\s*$/) { # subtract number
            $MACROS{$key} -= $1;
        } else {
          # do nothing
          # 2002 10 03 jenko FIXME: error-handling?
        }
    } else { # default is increment
        $MACROS{$key}++;
    }

    $MACROS{$sumKey} += ( $MACROS{$key} - $oldValue );
    ### print "### COUNT: \$MACROS{$sumKey} = $MACROS{$sumKey}\n";

    my @theKeys = grep(/^$module/, keys %COUNT_NUM_ENTRIES);

    $MACROS{$numKeysKey} = scalar(@theKeys);
    ### print "### COUNT: COUNT_NUM_ENTRIES\n";
    ### foreach my $tmp (sort keys %COUNT_NUM_ENTRIES) {
    ###    print "    \$COUNT_NUM_ENTRIES{$tmp} = $COUNT_NUM_ENTRIES{$tmp}\n";
    ### }
}

sub MATCH_LINE {

    # args: @lineFormat must be hash with the following elements:
    #         DELIMITER: field delimiter, specified as a regex
    #         FIELDS:    an array of single-elem hashes
    #                    where each hash key defines a fieldName/varName and 
    #                    the hash value defines the regular expr that will 
    #                    match the field. The order of the @FIELDS array 
    #                    (i.e. order of the hashes) is important--it must 
    #                    match the actual field ordering within the log file.
    #                    NOTE: we could have skipped the hashes and done a 
    #                    straight array.
    #
    my ($lineFormatRef, $line) = @_;
    my %lineFormat             = %{$lineFormatRef};

    $line   = $MACROS{$kLineMacro} if !$line; # default is last line read

    my $delim  = $lineFormat{$kLineFormatDelimKey};
    my @fields = @{$lineFormat{$kLineFormatFieldsKey}};
    my @fieldNames = ();
    my @fieldParens = (); # counts the number of unescaped parens in each
                         # field regex expression, so that we can line up
                         # the parsing with $1, $2, etc. vars


    # create regex from @lineFormat 
    #
    my $regExp;
    foreach my $elem (@fields) {
        my %elemHash = %{$elem};
        if ( scalar(keys %elemHash) != 1 ) {
            print STDERR "MATCH_LINE called with bad $kLineFormatKey\n";
            print STDERR join(',',%elemHash) . "\n";
            # 2002 10 01 jenko FIXME: error-handling, we're in an eval
            #
            exit(1); 
        }

        foreach my $fieldName (keys %elemHash) {
            my $fieldRE = $elemHash{$fieldName};
            $regExp .= '(' . $fieldRE . ')'; # every field surrounded by ()'s
            push(@fieldNames, $fieldName);
            # Calculate number of matching, unescaped parentheses
            # and put in fieldParens array (required by &getDollarVars)
            # in case any expressions contain parens in order to line up
            # dollar vars w/ correct parens
            my $tmp = $fieldRE;
            $tmp =~ s/\\\\//g;                  # skip escaped backslashes 
            $tmp =~ s/\\[\(\)]//g;              # skip escaped parens
            my $numLeft  = ($tmp =~ s/\(/\(/g); # num left parens
            my $numRight = ($tmp =~ s/\(/\(/g); # num right parens
            die "### Bad paren count logic"     # fatal error if our count 
                if ($numLeft != $numRight);     #   logic is wrong.
            push(@fieldParens, $numLeft);
            ### print "### field<$fieldName> has <$numLeft> parens\n";
        }

        $regExp .= $delim if $elem ne $fields[$#fields];
    }
    # print "### MATCH_LINE: line=<$line>, regExp=<$regExp>\n";
    
    # match against $line
    #
    if ($line =~ /$regExp/) {
        # eval and set MACRO variables
        #
        my %vars = &getDollarVars( string   => $line,
                                   regex    => $regExp,
                                   package  => $kLineFormatKey,
                                   nameMap  => \@fieldNames,
                                   parenMap => \@fieldParens,
                                 );
        &clearDollarMacros();
        &setMacros(%vars);
        return 1;
    } else {
        return 0;
    }
}

sub getDollarVars {

    my %args = @_;
    my $str      = $args{string};
    my $re       = $args{regex};
    my $package  = $args{package};
    $package .= '::' if $package;
    my @nameMap  = @{$args{nameMap}}  if defined($args{nameMap});
    my @parenMap = @{$args{parenMap}} if defined($args{parenMap});

    my %vars;

    # 2002 10 29 jenko FIXME MAGIC: some scope issue with '$str =~' line
    # if it's inside 'if' clause, then $+[] vars not set properly. If
    # we pull it outside, all is ok.
    #if ($str && $re) { 
    #   # reset $ vars if $str, $re passed in
    #   #
    #   ### print "### getDollarVars: str=<$str>, RE=<$re>\n";
    #   # $str =~ /$re/;
    #} else {
    #   ### print "### getDollarVars: using current RE \$ vars\n";
    #}
    $str =~ /$re/ if ($str && $re);

    my $reIndex = 1;
    my $i = 1;
    while (defined($+[$reIndex])) {
        my $val = substr($str, $-[$reIndex], $+[$reIndex] - $-[$reIndex]);
        ### print "### getDollarVars: var $reIndex = <$val>\n";
        my $varName = $reIndex;
        $varName = $nameMap[$i-1] if scalar(@nameMap);

        my $fqn = "${package}${varName}";
        $vars{$fqn} = $val;
        ### print "### getDollarVars: setting \$vars{$fqn}=<$val>\n";

        $reIndex++;                   # Normal increment from the parens we
                                      #   add around each regex sub-expression
        $reIndex += $parenMap[$i-1]   # Add offset from user-specified parens 
            if scalar(@parenMap);     #   in each regex sub-expression

        $i++;
    }
    return %vars;
}

sub matches {
    my ($line, $match, $match_rule) = @_;

    my $matchFlag     = 1; # default is true i.e. will match
    my $matchRuleFlag = 1; # if match/match_rule not specified

    $matchFlag     = ($line =~ /$match/)        if $match;
    $matchRuleFlag = (&evalMacros($match_rule)) if $match_rule;

    return ($matchFlag && $matchRuleFlag);
}

sub containsCounterMacro {

    my ($valueString) = @_;

    if ( ($valueString =~ /(\$|::)($kTotalCountMacro|$kCurrentCountMacro)\b/)||
         ($valueString =~ /::($kSumCountMacro|$kNumEntriesCountMacro)/) ) {
        return 1;
    } 
    return 0;
}

# 2002 10 02 jenko FIXME: add validation logic for .cfg file
# o repeated metric names
# o bad syntax ?
# o required variables/settings
#
sub checkConfig {
}

sub processMetric {
    my %args         = @_;
    my $aLine        = $args{line};
    my $aMatchKey    = $args{matchKey};
    my $aMatch       = $args{match};
    my $aMatchRule   = $args{matchRule};
    my $aMatchAction = $args{matchAction};
    my $aMetricType  = $args{metricType};
    my $aResource    = $args{resource};
    my $aSubresource = $args{subresource};
    my $aMetricName  = $args{metricName};
    my $aMetricValue = $args{metricValue};
    my $aDefaults    = $args{defaults};    # hash reference

    my $matched = 0; # whether the line matches or not

    if ( &matches($aLine, $aMatch, $aMatchRule) ) {

        my %vars = &getDollarVars( string   => $aLine,
                                   regex    => $aMatch,
                                 );

        &clearDollarMacros();
        &setMacros(%vars);

        if ($aMatchAction) {
            # We want to support both simple scalar i.e. matchAction => '...'
            # and array syntax for multiple actions i.e. matchAction => [,,,]
            my @matchActionList;
            if ( !ref($aMatchAction) ) {
                # scalar string, so put it in array
                @matchActionList = ($aMatchAction);
                ### print "### processMetric: SCALAR aMatchAction=<$aMatchAction>\n";

            } elsif ( ref($aMatchAction) eq 'ARRAY' ) {
                @matchActionList = @{$aMatchAction};
                ### print "### processMetric: ARRAY REF aMatchAction=<$aMatchAction>\n";
            } else {
                # 2002 10 04 jenko FIXME: error-handling
                die "Bad config file syntax: matchAction <$aMatchAction>";
            }
            foreach my $action (@matchActionList) {
                ### print "### processMetric: eval action=<$action>\n";
                evalMacros($action);
            }
        }

        # Some metric cfg blocks share the same match and/or match_rule
        # if so, we don't want to double-count. %COUNTED_IT gets cleared
        # with each new line.
        #
        if (!$COUNTED_IT{$aMatchKey}) {
            $COUNTED_IT{$aMatchKey}++;
            $TOTAL_COUNTS{$aMatchKey}++;
            $CURRENT_COUNTS{$aMatchKey}++;
        }

        # Update the dynamic macros available to the user
        # $TOTALCOUNT, $CURRENTCOUNT
        #
        $MACROS{$kTotalCountMacro}   = $TOTAL_COUNTS{$aMatchKey};
        $MACROS{$kCurrentCountMacro} = $CURRENT_COUNTS{$aMatchKey};

        # If we weren't supposed to eval the metricName, then
        # it will be the empty string now.
        # Need to do this so that the user can either
        # put in text or perl statements as 
        # the types, names and values
        #
        my $metricName = &evalMacros($aMetricName);
        if ($metricName eq "") {
            $metricName = $aMetricName;
        }

        my $metricValue = &evalMacros($aMetricValue);
        if ($metricValue eq "") {
            $metricValue = $aMetricValue;
        }

		my @line;
        if ($metricName && $metricValue && $aMetricType) {
            if ( &containsCounterMacro($aMetricValue) ) {

                # in case $metricValue = '$TOTALCOUNT' or '$CURRENTCOUNT'
                # delay processing until after the loop so that we only
                # output one metric

                $COUNTER_METRICS_LIST{$metricName} = [ $aMetricType, 
                                                       $aResource, 
                                                       $aSubresource, 
                                                       $metricName, 
                                                       $metricValue ];
            } elsif ( $metricValue =~ /\d+\.\d/ ) {
			
				# print "metricname:$metricName\n";
				if ( $metricName =~ /|.*$/ ) {
					@line = split /([^|]+)$/, $metricName;
					$aSubresource = $line[0];
					$metricName = $line[1];
					if ( $metricValue =~ /\./ ) {
						use POSIX;
						my @value = split /\./, $metricValue;
						if ( $value[1] ge 5 ) {
							$metricValue = ceil $metricValue;
						} else {
							$metricValue = floor $metricValue;
						}
					}
					# print "metrictype:$aMetricType\n";
					# print "resource:$aResource\n";
					# print "subresource:$aSubresource\n";
					# print "metricname:$metricName\n";
					# print "metricvalue:sprintf('%d',$metricValue)\n";
				}
                Wily::PrintMetric::printMetric( type        => $aMetricType, 
                                                resource    => $aResource,
                                                subresource => $aSubresource,
                                                name        => $metricName,
                                                value       => $metricValue,
                                              );
			} else { 

                Wily::PrintMetric::printMetric( type        => $aMetricType, 
                                                resource    => $aResource,
                                                subresource => $aSubresource,
                                                name        => $metricName,
                                                value       => $metricValue,
                                              );
            }
        }

        $matched = 1;
    } else {
        $matched = 0;
    }

    return $matched;
}

sub getMetricSettings {
    my $metricHashRef = shift; 

    my %metricCfg = %{$metricHashRef};

    my $match = $metricCfg{$kMetricMatchKey};
    my $matchRE = $match; 
    my $matchREFlags = "";

    if ($match =~ /^m(.)/) {        # to support regex flags e.g. m/foo/i
        my $delim = $1;
        if ($match =~ s/^m$delim(.*)$delim(\w*)/$1/) {
            $matchRE = eval "qr($1)$2";
        } 
    } 
    my $match_rule   = $metricCfg{$kMetricMatchRuleKey};
    my $matchKey     = "$matchRE||$match_rule";
    my $match_action = $metricCfg{$kMetricMatchActionKey};

    my %settings = (
        matchKey     => $matchKey,
        match        => $matchRE,
        matchRule    => $match_rule,
        matchAction  => $match_action,
        metricType   => $metricCfg{$kMetricTypeKey},
        metricName   => $metricCfg{$kMetricNameKey},
        metricValue  => $metricCfg{$kMetricValueKey}
    );

    return %settings;
}

sub processMetricList {
    my %args = @_;
    my $metricListRef = $args{metricList};
    my $line          = $args{line};
    my $resource      = $args{resource};
    my $subresource   = $args{subresource};

    my @metricList = @{$metricListRef};

    # Iterate through the metrics and report any matches
    #
    foreach my $metricBlock (@metricList) {

        my %settings = &getMetricSettings($metricBlock);

        # Add in other config file settings and current line
        #
        $settings{line}        = $line;
        $settings{resource}    = $resource;
        $settings{subresource} = $subresource;

        # Will check if 'line' matches 'match' && 'matchRule'
        # If so => Update dollar vars
        #          Eval 'matchAction'
        #          Update COUNTER macros
        #          Print/Queue metric if name,type,value supplied
        # 
        my $match = &processMetric(%settings); 

        if ($match) {
            # 'extended' property allows us to share top-level match, matchRules,
            # matchActions. Typically, just put additional sub-matchRules,
            # sub-matchActions, and metricType,Name,Values in 'extended' value,
            # which is an array of hashes.

            my $extended = $metricBlock->{$kExtendedKey};
            if ( defined($extended) && ref($extended) eq 'ARRAY' ) {
                &processMetricList( metricList  => $extended, 
                                    line        => $line, 
                                    resource    => $resource,
                                    subresource => $subresource );
            }
        }

    } # foreach $metricBlock (@metricList)
}

#
#
sub waitForFile {

    my %args = @_;

    my $dir   = $args{dir};
    my $file  = $args{file};
    my $delay = $args{delay};

    my $startAtBeginning = 0;
    my $mostRecentFile = "";  

    while($mostRecentFile eq "") {
        $mostRecentFile = &getMostRecentlyModifiedFile($dir, $file);
        if ($mostRecentFile eq "") {
            # mark a flag so we can start at beginning of file when it does appear
            $startAtBeginning = 1;
            # sleep the desired amount
            sleep $delay;
            warn "No available log file:$file\n";
        } 
    } 

    return($mostRecentFile, $startAtBeginning);
}

# this procedure reads the log files and reports
# any metrics in xml format
#
sub readLog {

    my $config = shift;

    # Make all config variables available as Macro vars
    #
    &setMacros(%{$config});

    # backwards-compat w/ old .cfg files, new cfg setting should be 'METRICS'
    #
    my $metricList;
    if ( defined($config->{$kMetricKey}) ) {
        $metricList = $config->{$kMetricKey};
    } elsif ( defined($config->{$kOldMetricKey}) ) {
        $metricList = $config->{$kOldMetricKey};
    }

    if(! -e $config->{$kLogFileDirKey}) {
        die "No such log file directory: $config->{$kLogFileDirKey}";
    }
    
    # Wait around if there are no available log files
    #
    my ($mostRecentFile, $startAtBeginning) = 
                            &waitForFile( dir   => $config->{$kLogFileDirKey},
                                          file  => $config->{$kLogFileKey},
                                          delay => $config->{$kSleepTimeKey},
                                        );

    my $fullFileName = &fullFileName($config->{$kLogFileDirKey}, $mostRecentFile);

    # start at end of the file, only if file existed before start of log reader
    #
    my $curpos = 0;
    if (!$startAtBeginning) {
        $curpos = &getLastCharPos(filename    => $fullFileName,
                                  nullpadding => $config->{$kNullPadding},
                                 );
    }
    # Keep looping forever if '-n N' not specified OR if we haven't 
    # looped N times.
    #
    my $numLoops = undef;
    $numLoops = $config->{$kNumLoops} if defined($config->{$kNumLoops});
    while ( !defined($numLoops) || ($numLoops > 0) ) {

        $numLoops-- if defined($numLoops);

        # now make sure another file hasn't been modified
        #
        my ($recentFile, $startOver) = 
                           &waitForFile( dir   => $config->{$kLogFileDirKey},
                                         file  => $config->{$kLogFileKey},
                                         delay => $config->{$kSleepTimeKey},
                                       );

        my $latestpos = &getLastCharPos(filename    => $fullFileName,
                                  nullpadding => $config->{$kNullPadding},
                                 );

        # if the file being modified has changed, then update our most recent file
        if ($mostRecentFile ne $recentFile || $startOver) {
          $mostRecentFile = $recentFile;
          $fullFileName = &fullFileName($config->{$kLogFileDirKey}, $mostRecentFile);
          $curpos = 0;
        }elsif ($mostRecentFile eq $recentFile && $latestpos < $curpos ) {
	  		$curpos=0;
    	}

        # update the dynamic macros available to the user
        #
        $MACROS{$kLogMacro}          = $mostRecentFile;

        my $rv = open(LOGFILE, "<$fullFileName");
        if (!$rv) {
            if (-e $fullFileName) {
                die "Error opening file: $fullFileName";
            } else {
                next; # just loop and block in case file deleted in middle
            }
        }

        seek(LOGFILE, $curpos, 0);

        while (my $line = <LOGFILE>) {

          last if ($config->{$kNullPadding} &&
                   $line =~ /^\000/
                  );
          $curpos = tell(LOGFILE);

          %COUNTED_IT = (); # reset for each line

          # get rid of any newline chars
          chomp $line;

          next if $line =~ /^\s*$/;     # skip empty lines

          # Update the dynamic macros available to the user:
          # $LINE, $DATE
          #
          $MACROS{$kLineMacro} = $line; 
          $MACROS{$kDateMacro} = localtime;

          &processMetricList(metricList  => $metricList, 
                             line        => $line,
                             resource    => $config->{$kResourceKey},
                             subresource => $config->{$kSubResourceKey} );

        } # while ( $line = <LOGFILE> )

        close(LOGFILE);

        # Print out all metrics with $TOTALCOUNT or $CURRENTCOUNT
        #
        foreach my $key (sort keys %COUNTER_METRICS_LIST) {
            my ($metricType, $resource, $subresource, $metricName, $metricValue) =
                @{ $COUNTER_METRICS_LIST{$key} };

            Wily::PrintMetric::printMetric( type        => $metricType, 
                                            resource    => $resource,
                                            subresource => $subresource,
                                            name        => $metricName,
                                            value       => $metricValue,
                                          );
        }

        &clearCurrentCounters();

        # Sleep the specified amount if we have more loops to go
        #
        sleep $config->{$kSleepTimeKey} if ( !defined($numLoops) || ($numLoops>0) );

    } # while ( !defined($numLoops) || ($numLoops > 0) ) 
}

1;
