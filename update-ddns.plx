#!/usr/bin/env perl

# do dynamic DNS updates on one or more hosts/domains for your
# DNS provider.  It is expected to be run from the crontab
# periodically.  Say like every half hour.

# It's primary value is that you can be away from home and depend
# on reaching your internal network/servers at home when your
# dynamic IP number, provided by your ISP, changes.

# Looks for the *last* existing config file it finds in the list of:
#   - $ENV{ HOME }/.config/update-ddns/update-ddns.conf
#   - $ENV{ UPDATE_DDNS_CONFIG_FILE }
#   - update-ddns.conf  in current directory
#   - file given by the option -c or --config

# It can update several domains in 1 run, each which may or
# may not have different authentication userid/passwords for
# a single new IP number.  
# For eg: for home.moxad.com, home.moxad.net and home.moxad.ca
# It keeps track of the IP number from the last run and if there
# is no change, then the program does nothing.

# You can specify several methods to get the external dynamic
# IP number given by your ISP.  If one method fails, others
# will be tried until all are tried before failing.  You can
# specify to randomize where in that list to start cycling from
# in case you don't want to be always using the first on the
# list and seen by that provider as over-using their free resourse
# to do a IP lookup on your connection.

# The config file specifies a 'service-provider'.  It can be any
# string - likely the name of your provider.  For eg: zoneedit.
# It uses this string to look for the library <string>.pl in the
# directory given in the config file with 'library-directory' and
# then dynamically loads it.

# That library file is expected to have a function called update_ddns().
# In this way, this code base can remain the same while someone can
# create their own new library/function that is specific for their provider
# and their API.  The API for that function is that the inputs are:
# userid, password, hostname-to-update, new-IP-address and timeout.
# The output is either 0 (OK) or 1 (not OK).  If it is not OK (1),
# it is expected that error messages will be sent to STDERR.

# At this time of creation, the only provided library is zoneedit.pl
# which understands their API.  That function can be used as a guide
# for creating other library functions for other providers which 
# should only differ in the (REST) URL that is sent, and processing
# the output back to determine success or failure.

# uses the Moxad::Config module to handle human-readable config files.
# uses the Moxad::Rcommand module to separate STDIN and STDERR into
# separate streams and to handle a timeout to avoid hung services

# Use -h or --help for options

# rj.white@moxad.com
# Aug 2022

use strict ;
use warnings ;
use lib "/usr/local/Moxad/lib" ;
use Moxad::Config ;
use Moxad::Rcommand qw( run_command_wait $STDIN_AND_STDOUT_SEPARATE ) ;
use File::Spec ;
use LWP::UserAgent();

# Globals 
our $G_progname = $0 ;
our $G_version  = "1.2" ;
our $G_debug    = 0 ;

# Constants
my $C_DEFAULT_TIMEOUT   = 30  ;
my $C_DEFAULT_RANDOMIZE = 'no' ;       # dont randomize get IP methods
my $C_DEFAULT_PROTOCOL  = 'zoneedit' ;
my $C_DEFAULT_IP_FILE   = "$ENV{ 'HOME' }/etc/update-ddns--IP-number" ;
my $C_DEFAULT_LIB_DIR   = "$ENV{ 'HOME' }/lib/Perl" ;

my $C_SECTION_AUTH      = 'authentication' ;
my $C_SECTION_GET_IP    = 'get-ip-number' ;
my $C_SECTION_HOSTS     = 'hosts' ;
my $C_SECTION_FILES     = 'files' ;
my $C_SECTION_PROTOCOL  = 'protocol' ;

my $C_KEYWORD_USERID    = 'userid' ;
my $C_KEYWORD_PASS      = 'password' ;
my $C_KEYWORD_HOSTS     = 'hostnames' ;
my $C_KEYWORD_METHODS   = 'methods' ;
my $C_KEYWORD_RANDOM    = 'randomize-methods' ;
my $C_KEYWORD_PROVIDER  = 'service-provider' ;
my $C_KEYWORD_IP_FILE   = 'save-ip-number' ;
my $C_KEYWORD_TIMEOUT   = 'timeout' ;
my $C_KEYWORD_LIB_DIR   = 'library-directory' ;

$G_progname     =~ s/^.*\/// ;


if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $config_file = undef ;
    my $ip_number = undef ;
    my $get_ip_via_Internet = 1 ;
    my $help_flag    = 0 ;
    my $force_update_flag = 0 ;
    my $only_hosts_flag = 0 ;
    my $save_ip_to_file_flag = 1 ;
    my $indicate_success_flag = 0 ;
    my $sub_name = (caller(0))[3] . "()" ;

    my %only_hosts = () ;

    my %scalar_values = (
        $C_KEYWORD_RANDOM    => $C_DEFAULT_RANDOMIZE,
        $C_KEYWORD_PROVIDER  => $C_DEFAULT_PROTOCOL,
        $C_KEYWORD_IP_FILE   => $C_DEFAULT_IP_FILE,
        $C_KEYWORD_TIMEOUT   => $C_DEFAULT_TIMEOUT,
        $C_KEYWORD_LIB_DIR   => $C_DEFAULT_LIB_DIR,
    ) ;
        
    # get options.
    # just the basics before reading (and maybe changing) our config file

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug++ ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
            if ( ! -f $config_file ) {
                print STDERR "$G_progname: config file not found: $config_file\n" ;
                return(1) ;
            }
        } 
    }

    # find the config file we really want

    $config_file = find_config_file( $config_file ) ;
    if ( not defined( $config_file )) {
        print STDERR "$G_progname: no config file found\n" ;
        return(1) ;
    }
    dprint( "$sub_name: using config file: $config_file" ) ;

    # read in config data

    # show config debug if -d/--debug flag used more than once
    my $config_debug = 0 ;
    $config_debug = 1 if ( $G_debug > 1 ) ;

    Moxad::Config->set_debug( $config_debug ) ;
    my $cfg1 = Moxad::Config->new(
        $config_file,
        "",         # no definitions file
        { 'AcceptUndefinedKeywords' => 'no' } ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }
    dprint( "$sub_name: Config data read ok" ) ;

    # sanity checking required sections

    my %got_sections = () ;
    my @needed_sections = ( $C_SECTION_AUTH, $C_SECTION_HOSTS,
                            $C_SECTION_FILES, $C_SECTION_GET_IP ) ;
    my @sections = $cfg1->get_sections() ;
    foreach my $section ( @sections ) {
        $got_sections{ $section } = 1 ;
    }
    my $num_errors = 0 ;
    foreach my $section ( @needed_sections ) {
        if ( not defined( $got_sections{ $section } )) {
            my $err = "missing section \'$section\' in $config_file" ;
            print STDERR "$G_progname: $err\n" ;
            $num_errors++ ;
        }
    }
    if ( $num_errors ) {
        print STDERR "$G_progname: giving up because of errors\n" ;
        return(1) ;
    }

    # now over-ride our defaults in %scalar_values with any scalar values we
    # find in the config file

    foreach my $section ( @sections ) {
        my @keywords = $cfg1->get_keywords( $section ) ;
        foreach my $keyword ( @keywords ) {
            my $type = $cfg1->get_type( $section, $keyword ) ;
            if ( $type eq "scalar" ) {
                my $value = $cfg1->get_values( $section, $keyword ) ;
                if ( defined( $scalar_values{ $keyword } )) {
                    my $old_value = $scalar_values{ $keyword } ;
                    my $msg = "updating $keyword: \'$old_value\' -> \'$value\'" ;
                    dprint( "$sub_name: $msg" ) ;
                } else {
                    dprint( "$sub_name: adding value \'$value\' to $keyword" ) ;
                }
                $scalar_values{ $keyword } = $value ;
            }
        }
    }

    # now process *all* our options now that any changes have been made to
    # our defaults via our config file

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-i" ) or ( $arg eq "--ip-num" )) {
            $get_ip_via_Internet = 0 ;
            $ip_number = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            # already done above
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;      # already done above
        } elsif (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            $help_flag++ ;
        } elsif (( $arg eq "-n" ) or ( $arg eq "--no-save-ip" )) {
            $save_ip_to_file_flag = 0 ;
        } elsif (( $arg eq "-s" ) or ( $arg eq "--show-success" )) {
            $indicate_success_flag = 1 ;
        } elsif (( $arg eq "-l" ) or ( $arg eq "--lib-dir" )) {
            $scalar_values{ $C_KEYWORD_LIB_DIR } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-o" ) or ( $arg eq "--only" )) {
            $only_hosts_flag++ ;
            my $o_hosts = $ARGV[ ++$i ] ;
            if ( $o_hosts =~ /,/ ) {
                my @hosts = split( /,/, $o_hosts ) ;
                for my $host ( @hosts ) {
                    $only_hosts{ lc( $host ) } = 1 ;
                }
            } else {
                $only_hosts{ lc( $o_hosts ) } = 1 ;
            }
        } elsif (( $arg eq "-f" ) or ( $arg eq "--ip-file" )) {
            $scalar_values{ $C_KEYWORD_IP_FILE } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-r" ) or ( $arg eq "--randomize" )) {
            $scalar_values{ $C_KEYWORD_RANDOM } = 'yes' ;
        } elsif (( $arg eq "-F" ) or ( $arg eq "--force-update" )) {
            $force_update_flag++ ;
        } elsif (( $arg eq "-p" ) or ( $arg eq "--provider" )) {
            $scalar_values{ $C_KEYWORD_PROVIDER } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-t" ) or ( $arg eq "--timeout" )) {
            $scalar_values{ $C_KEYWORD_TIMEOUT } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "Program version: $G_version\n" ;
            print "Config module version: $Moxad::Config::VERSION\n" ;
            print "Rcommand module version: $Moxad::Rcommand::VERSION\n" ;
            return(0) ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        }
    }
    # these values should now be set, either from defaults, or from the
    # config file over-riding them.

    my $ip_file   = $scalar_values{ $C_KEYWORD_IP_FILE } ;
    my $randomize = $scalar_values{ $C_KEYWORD_RANDOM } ;
    my $provider  = $scalar_values{ $C_KEYWORD_PROVIDER } ;
    my $timeout   = $scalar_values{ $C_KEYWORD_TIMEOUT } ;
    my $lib_dir   = $scalar_values{ $C_KEYWORD_LIB_DIR } ;

    # we defer printing out the help info till after we have set defaults
    # and read our config file, so we can see defaults in the usage printed

    if ( $help_flag ) {
        printf "usage: %s [option]*\n%s %s %s %s %s %s %s %s %s %s %s %s %s %s",
            $G_progname,
            "\t[-c|--config file]   (config-file (default=$config_file)\n",
            "\t[-d|--debug]         (debugging output)\n",
            "\t[-h|--help]          (help)\n",
            "\t[-f|--ip-file file]  (IP-file (default=$ip_file))\n",
            "\t[-i|--ip-num IP#]    (IP number)\n",
            "\t[-l|--lib-dir str]   (library directory (default=$lib_dir))\n",
            "\t[-o|--only host]     (restrict to only this host given))\n",
            "\t[-n|--no-save-ip]    (don't save the IP)\n",
            "\t[-r|--randomize]     (randomize the method to get ip number)\n",
            "\t[-s|--show-success]  (indicate if successful.  normally silent)\n",
            "\t[-t|--timeout num]   (timeout (default=$timeout secs))\n",
            "\t[-p|--provider str]  (DDNS provider (default=$provider))\n",
            "\t[-F|--force-update]  (force DDNS update)\n",
            "\t[-V|--version]       (print version of this program)\n" ;

        return(0) ;
    }

    if ( ! -d $lib_dir ) {
        print STDERR "$G_progname: missing library directory: $lib_dir\n" ;
        return(1) ;
    }

    # need to load the routine specifically for the provider needed
    # if we can't load the library, there is no point continuing

    if ( load_library( $lib_dir, $provider )) {
        print STDERR "$G_progname: can't load library for \'$provider\'\n" ;
        print STDERR "$G_progname: need to supply library in $lib_dir\n" ;
        return(1) ;
    }

    my @ddns_hosts = $cfg1->get_values( $C_SECTION_HOSTS, $C_KEYWORD_HOSTS ) ;
    my $num_hosts = @ddns_hosts ;
    if ( $num_hosts == 0 ) {
        print STDERR "$G_progname: No hosts given in config file\n" ;
        return(1) ;
    }
    dprint( "$sub_name: Number of hosts given is $num_hosts" ) ;

    # get authentication info and fill out arrays if need be.

    my @userids = $cfg1->get_values( $C_SECTION_AUTH, $C_KEYWORD_USERID ) ;
    my @passwords = $cfg1->get_values( $C_SECTION_AUTH, $C_KEYWORD_PASS ) ;
    return(1) if ( fillout( \@userids, $num_hosts )) ;
    return(1) if ( fillout( \@passwords, $num_hosts )) ;

    dprint( "$sub_name: we now have authentication info" ) ;

    # now pick a method to get our IP number

    my @get_ip_methods = $cfg1->get_values( $C_SECTION_GET_IP, $C_KEYWORD_METHODS ) ;
    my $num_methods = @get_ip_methods ;
    dprint( "$sub_name: we have $num_methods methods to get our IP" );

    # see if we want to randomize which method we use

    if ( $randomize =~ /^yes$/i ) {
        $randomize = 1 ;
    } else {
        $randomize = 0 ;
    }

    dprint( "$sub_name: randomize = $randomize" ) ;

    # now go get our Internet number
    if ( $get_ip_via_Internet ) {
        $ip_number = get_our_ip_number( \@get_ip_methods, $randomize, $timeout ) ;
        if ( not defined( $ip_number )) {
            my $err = "unable to get our IP number from Internet" ;
            print STDERR "${G_progname}: $err\n" ;
            return(1) ;
        }
    }
    dprint( "$sub_name: our Internet number is $ip_number" ) ;

    my $old_ip_num = get_old_ip( $ip_file ) ;

    my $ip_num_changed = 0 ;
    if ( defined( $old_ip_num )) {
        dprint( "$sub_name: OLD IP num = $old_ip_num" ) ;
        # we got our OLD IP number.  Check if its changed from now
        if ( $old_ip_num ne $ip_number ) {
            my $msg = "IP number has changed from $old_ip_num to $ip_number" ;
            dprint( "$sub_name: $msg" ) ;
            $ip_num_changed++ ;
            if ( $save_ip_to_file_flag ) {
                return(1) if ( save_old_ip( $ip_number, $ip_file ) ) ;
            }
        } else {
            dprint( "$sub_name: IP number has not changed." ) ;
        }
    } else {
        print STDERR "$G_progname: initializing $ip_file\n" ;
        if ( $save_ip_to_file_flag ) {
            return(1) if ( save_old_ip( $ip_number, $ip_file ) ) ;
        }
    }

    my $num_errs = 0 ;
    if ( $ip_num_changed or $force_update_flag ) {
        dprint( "FORCING update using $ip_number" ) if ( $force_update_flag ) ;
        dprint( "$sub_name: updating DDNS record using IP $ip_number" ) ;
        for ( my $i=0 ; $i < $num_hosts ; $i++ ) {
            my $host = $ddns_hosts[ $i ] ;
            my $host_lc = lc( $host ) ;
            my $user = $userids[ $i ] ;
            my $pass = $passwords[ $i ] ;
            if ( $only_hosts_flag ) {
                # we used the -o option.  Only process hosts given.
                if ( not defined( $only_hosts{ $host_lc } )) {
                    dprint( "skipping $host - not amongst -o hosts given" ) ;
                    next ;
                }
            }
            if ( update_ddns( $user, $pass, $host, $ip_number, $timeout )) {
                $num_errs++ ;
            } else {
                # seems to have gone OK.  normally we are silent about it
                if ( $indicate_success_flag ) {
                    my $msg = "updated $host from $old_ip_num to $ip_number" ;
                    print "$G_progname: $msg\n" ;
                }
            }
        }
    } else {
        dprint( "$sub_name: nothing to do.  quitting" ) ;
    }
    if ( $num_errs ) {
        my $err = "errors encountered in updating DDNS records" ;
        print STDERR "$G_progname: $err\n" ;
        return(1) ;
    } else {
        return(0) ;
    }
}


# read an IP number saved in a file
# The file can contain comments beginning with '#'
# Only supports IPv4
#
# Arguments:
#   1:      filename
# Returns:
#   undef   - could not get an IP number
#   v4 IP number
# Globals:
#   $G_progname

sub get_old_ip {
    my $file = shift ;

    my $sub_name = (caller(0))[3] . "()" ;

    dprint( "$sub_name: getting old saved IP from $file" ) ;
    if ( ! -f $file ) {
        print STDERR "$G_progname: warning: no such file: $file\n" ;
        return( undef );
    }

    my $fd  ;
    if ( ! open( $fd, "<", $file )) {
        print STDERR "$G_progname: warning: can't read file $file\n" ;
        return( undef );
    }

    my @lines = <$fd> ;
    chomp( @lines ) ;
    close( $fd ) ;

    foreach my $line ( @lines ) {
        next if ( $line eq "" ) ;
        next if ( $line =~ /^#/ ) ;
        next if ( $line =~ /^\s+$/ ) ;

        # return the first thing that looks like an IP
        if ( $line =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
            return( $line ) ;
        }
    }

    my $err = "warning: could not get an IP number from $file" ;
    print STDERR "$G_progname: $err\n" ;
    return( undef );
}


# save IP number saved into a file
# The file can contain comments beginning with '#'
#
# Arguments:
#   1:      IP number
#   2:      filename
# Returns:
#   0:      OK
#   1:      not OK
# Globals:
#   $G_progname

sub save_old_ip {
    my $ip_num = shift ;
    my $file = shift ;

    my $sub_name = (caller(0))[3] . "()" ;
    my $fd  ;
    if ( ! open( $fd, ">", $file )) {
        print STDERR "$G_progname: warning: can't open for write: $file\n" ;
        return(1);
    }

    my $dayt = gmtime() ;
    print $fd "# saved IP number from program $G_progname on $dayt\n\n" ;
    print $fd "$ip_num\n" ;

    dprint( "$sub_name: IP $ip_num written to $file" ) ;
    close( $fd ) ;
    return(0) ;
}


# get our IP number
#   cycles through a number of methods, given in the config file, to
#   get the IP number.  Tries one at a time until it sees a valid
#   looking IPv4 number until all are tried.  Either returns a valid
#   IPv4 number or undefined.
#
# Arguments:
#   1:  reference to an array of methods to try - from config file
#   2:  flag on whether to randomize where to start in methods list
#   3:  timeout in seconds - in case a lookup hangs
# Returns:
#   IPv4 number - OK
#   undefined   - not OK
# Globals:
#   $G_progname

sub get_our_ip_number {
    my $methods_ref = shift ;
    my $random_flag = shift ;
    my $timeout     = shift ;

    my $start_method_indx = 0 ;
    my @methods_used = () ;
    my $num_methods_tried = 0 ;
    my $ip_number = undef ;

    my $sub_name = (caller(0))[3] . "()" ;

    if (( ref( $methods_ref ) eq "" ) or ( ref( $methods_ref ) ne "ARRAY" )) {
        print STDERR "$G_progname: 1st arg to $sub_name is not an array reference\n" ;
        return( $ip_number ) ;
    }
    my $num_methods = @{$methods_ref} ;
    dprint( "$sub_name: we have $num_methods methods to get our IP number" ) ;

    if ( $random_flag ) {
        $start_method_indx = int( rand( $num_methods ) ) ;
        dprint( "$sub_name: randomizing methods to try to get IP" ) ;
        my $method = ${$methods_ref}[ $start_method_indx ] ;
        dprint( "$sub_name: using index $start_method_indx.  method: $method" ) ;
    }

    Moxad::Rcommand::set_debug( $G_debug ) ;     # turn on debugging
    Moxad::Rcommand::set_debug_fd(2) ;  # send debug output to stderr

    my $method_indx = $start_method_indx ;
    dprint( "$sub_name: using a timeout of $timeout secs" ) ;
    my $num_warnings = 0 ;
    my $last_method_tried = undef ;
    while ( $num_methods_tried < $num_methods ) {
        $num_methods_tried++ ;
        my $method = ${$methods_ref}[ $method_indx ] ;

        dprint( "$sub_name: trying method: $method" ) ;

        my @output = () ;
        my @errors = () ;
        my %options = (
            'timeout'  => $timeout,      # seconds
            'stderr'   => $STDIN_AND_STDOUT_SEPARATE,
        ) ;

        # point to next method to use if this one craps out.
        $method_indx++ ;
        $method_indx = 0 if ( $method_indx >= $num_methods ) ;

        $last_method_tried = $method ;
        my $errs = run_command_wait( $method, \@output, \@errors, \%options ) ;
        if ( $errs ) {
            foreach my $err ( @errors ) {
                chomp( $err ) ;
                print STDERR "$G_progname: $err\n" ;
                print STDERR "$G_progname: method tried was: $method\n" ;
                $num_warnings++ ;
            }
            # keep going anyway
        }
        next if ( @output == 0 ) ;

        $ip_number = $output[0] ;
        chomp( $ip_number ) ;
        if ( $ip_number =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
            dprint( "$sub_name: Got a good looking IP: \'$ip_number\'" ) ;
            last ;
        } else {
            dprint( "$sub_name: IP doesn't look good: \'$ip_number\'" ) ;
            $ip_number = undef ;
        }
    }

    if ( $num_methods_tried == $num_methods ) {
        dprint( "$sub_name: tried ALL $num_methods of our methods!" ) ;
    }
    if ( defined( $ip_number )) {
        dprint( "$sub_name: Got final IP number of \'$ip_number\'" ) ;
        if ( $num_warnings ) {
            my $msg = "had success with method: $last_method_tried" ;
            print STDERR "$G_progname: $msg\n" ;
        }
    } else {
        dprint( "$sub_name: could not get an IP number" ) ;
    }
    return( $ip_number ) ;
}


# fill out an array if trailing values are missing
#   For eg:  If there are 3 expected values in the userid array,
#   but only 1 value is give, the missing trailing two values
#   will be copied from the 1st (last) value in the array.
#
# Arguments:
#   1:  reference to array of values
#   2:  number of values in the array expected
# Returns:
#   0:  OK
#   1:  not OK
# Globals:
#   $G_progname

sub fillout {
    my $array_ref = shift ;
    my $max_num   = shift ;

    my $sub_name = (caller(0))[3] . "()" ;
    if (( ref( $array_ref ) eq "" ) or ( ref( $array_ref ) ne "ARRAY" )) {
        print STDERR "$G_progname: 1st arg to $sub_name is not an array reference\n" ;
        return(1) ;
    }
    if ( $max_num !~ /^\d+$/ ) {
        print STDERR "$G_progname: 2nd arg to $sub_name is not a number\n" ;
        return(1) ;
    }

    my $size_of_array = @{$array_ref} ;
    if ( $size_of_array >= $max_num ) {
        # nothing to do
        return(0) ;
    }

    my $last_value = @{$array_ref}[-1] ;
    for ( ; $size_of_array < $max_num ; $size_of_array++ ) {
        @{$array_ref}[ $size_of_array ] = $last_value ;
    }
    return(0) ;
}


# send a URL request
#
# Arguments:
#   1:  URL
#   2:  reference to array of errors to return
#   3:  reference of array of data returned
#   4:  timeout - defaults to $C_DEFAULT_TIMEOUT secs
# Returns:
#   0:  ok
#   1:  error
# Globals:
#   none

sub send_request {
    my $url       = shift ;
    my $error_ref = shift ;
    my $data_ref  = shift ;
    my $timeout   = shift ;

    my $sub_name = (caller(0))[3] . "()" ;

    # sanity checking of arguments
    if (( ref( $error_ref ) eq "" ) or ( ref( $error_ref ) ne "ARRAY" )) {
        return(1) ;
    }
    if (( not defined( $url )) or ( $url eq "" )) {
        my $msg = "$sub_name: (Arg 1) URL is undefined or empty string" ;
        push( @{$error_ref}, $msg ) ;
        return(1) ;
    }
    if (( ref( $data_ref ) eq "" ) or ( ref( $data_ref ) ne "ARRAY" )) {
        my $err = "$sub_name: Arg 3 is not an ARRAY reference to return data" ;
        push( @{$error_ref},  $err ) ;
        return(1) ;
    }

    if (( not defined( $timeout )) or ( $timeout eq "" )) {
        $timeout = $C_DEFAULT_TIMEOUT ;
    }

    if ( $timeout !~ /^\d+$/ ) {
        my $err = "$sub_name: timeout ($timeout) is non-numeric" ;
        push( @{$error_ref}, $err ) ;
        return(1) ;
    }

    dprint( "$sub_name: URL = \'$url\'" ) ;
    dprint( "$sub_name: using timeout = \'$timeout\'" ) ;

    my $ua = LWP::UserAgent->new( timeout => $timeout );

    # you need to look like a browser to get past Cloudflare
    $ua->default_header( 'User-Agent' => 'Mozilla/5.0' ) ;
    $ua->cookie_jar( {} ) ;     # maybe needed by Cloudflare in future?
    $ua->env_proxy;
    my $response = $ua->get( $url ) ;

    my $response_body;
    if ( $response->is_success ) {
        $response_body = $response->decoded_content ;
    } else {
        my $reason = $response->status_line ;
        push( @{$error_ref},  "$sub_name: $reason" ) ;
        return(1) ;
    }

    $response_body = "" if ( not defined( $response_body )) ;
    chomp( $response_body ) ;

    my @lines = split( /[\n\r]/, $response_body ) ;
    foreach my $line ( @lines ) {
        chomp( $line ) ;
        push( @{$data_ref}, $line ) ;
    }
    return(0) ;
}



# debug print
#
# Arguments:
#     1:  message
# Returns:
#     0
# Globals:
#     $G_debug

sub dprint {
    my $msg = shift ;
    return(0) if ( $G_debug == 0 ) ;

    print "debug: $msg\n" ;
    return(0) ;
}


# find the config file we really want and that exists.
# accept the *last* existing one in the order of:
#   $ENV{ HOME }/.config/update-ddns/update-ddns.conf"
#   $ENV{ UPDATE_DDNS_CONFIG_FILE }
#   update-ddns.conf in the current directory
#   given by option -c or --config
#
# Arguments:
#     1:  value given with option to program
# Returns:
#     config-file (which could be undef)
# Globals:
#     none

sub find_config_file {
    my $config_option = shift ;

    my @configs = () ;
    my $final_config = undef ;

    # first the HOME directory
    my $home = $ENV{ HOME } ;
    push( @configs, "${home}/.config/update-ddns/update-ddns.conf" ) ;

    # next an environment variable
    my $c = $ENV{ 'UPDATE_DDNS_CONFIG_FILE' } ;
    push( @configs, $c ) if ( defined( $c )) ;

    push( @configs, "./update-ddns.conf" ) ;

    # finally if an over-riding option was given
    push( @configs, $config_option ) if defined( $config_option ) ;

    # accept the last one found that exists
    foreach my $c ( @configs ) {
        $final_config = $c if ( -f $c ) ;
    }
    return( $final_config ) ;
}


# load the library we need
# Args:
#   1:  provider
# Returns:
#   0:  success
#   1:  was not able to load the library
# Globals:
#   none

sub load_library {
    my $lib_dir = shift ;
    my $provider = shift ;

    my $sub_name = (caller(0))[3] . "()" ;

    my $f = File::Spec->catfile( $lib_dir, "${provider}.pl" ) ;
    dprint( "$sub_name: loading libary $f" ) ;

    # check if the library exists
    if ( -f $f ) {
        require $f ;
        dprint( "$sub_name: libary $f successfully loaded" ) ;
        return(0) ;
    } else {
        return(1) ;     # failure
    }
}

__END__

=head1 NAME

update-ddns - update DNS records at your DNS service provider

=head1 SYNOPSIS

update-ddns [option]*

=head1 DESCRIPTION

update-ddns does DNS updates for one or more hosts at your DNS provider.
It is typically run from the crontab periodically - like every half hour.
It's primary value is that you can be away from home and depend on
reaching your internal network/servers at home when your dynamic IP
number, provided by your ISP, changes.

It can update several hostnames in a single run for different domains,
each which may or may not have different authentication userid/passwords
for a single new IP number.  For eg: for the 3 hosts in the 3 domains
of home.moxad.com, home.moxad.net and home.moxad.ca.  It keeps track
of the IP number from the last run and if there is no change, then the
program does nothing and exits.

You can specify several methods to get the external dynamic IP number
assigned by your ISP.  If one method fails, others will be tried until all
are tried before giving up.  You can specify to randomize where in that
list to start cycling from, in case you don't want to be always using
the first on the list and seen by that provider as over-using their free
resourse to do a IP lookup on your connection.

The first time run, it will notice that you do not yet have a 'save-ip-number'
file to store the IP number.  It will create this file, with your IP number,
and exit.  The next time it is run, it will compare the value found in that file
to your current assigned IP number.

Note that at this time, only IPv4 is supported.

Note that currently the only DNS service provider supported is Zoneedit.
But that library/function can be copied to a new library and slightly
modified to use their expected URL input and to process their output
to determine success or failure.  See section "SUPPORT FOR OTHER DNS
PROVIDERS"

Use -h or --help for options

=head1 OPTIONS

=head2 -c|--config file

Provide a different config file to be used instead of any of the other default locations.

=head2 -d|--debug

Provide debug output to help trace a problem or understand an unexpected behaviour.
If the debug flag is given more than once, it will also turn on debugging in the
Moxad::Rcommand and Moxad::Config modules.

=head2 -f|--ip-file filename

Change the file that the IP number is saved to that gets compared each run to see if
your ISP changed your dynamic IP number.  The hard-coded default is
${HOME}/etc/update-ddns--IP-number.  This is then over-ridden by whatever 
'save-ip-number' is set to in the config file.  And that is over-ridden by this option.

=head2 -h|--help

Print out options of the program, also showing some defaults

=head2 -i|--ip-num IP#

Supply an IP number to use instead of using the methods in the config file
to look up what IP number is currently assigned by your ISP.  If this
option is used, it will behave as if you got it via normal methods, and
then checked against the IP number that is stored in 'save-ip-number'.
And so if they are different, it will then save that different number.
Unless the -n|--no-save-ip option is used.

=head2 -l|--lib-dir directory

Change the library directory where your library is located to handle
talking to your DNS provider.  It is normally set in the config file using
'library-directory'.  This option will over-ride that.  The hard-coded
value in the program is ${HOME}/lib/Perl.

=head2 -n|--nosave-ip

Don't save the IP number into the file given with 'save-ip-number'
in the config file.

=head2 -o|--only hostname[,hostname]*

Restrict the hosts to update to those given with this option.  In order
for any of them to be used, they have to be listed in the config file
under 'hostnames'.  The hosts can be comma separated, or the option can
be used multiple times with one or more hosts.

=head2 -p|--provider string

This will change which provider library you wish to use.  The default
hard-coded value is 'zoneedit'.  This is over-ridden in the config file
with the 'service-provider'.  This option over-rides both.

=head2 -r|--randomize

Pick a random method listed under 'methods' in the config file, to start
with when trying to get the IP number.  If each method is failing, loop
back to the start of the list if the last one is reached and fails.
Stop after all methods are tried.

=head2 -s|--show-success

Normally if an IP address is successfully updated at the DNS provider,
the program is silent.  This will print a message showing that the 
IP number changed and that the update succeeded, if this option is used.

=head2 -t|--timeout seconds

Change the timeout to the given value.  The hard-coded default is 30
seconds.  This is over-ridden by any value in the config file given by
'timeout'.  This option will override them both.

=head2 -F|--force-update

This option will force an update at the DNS provider even if the program
determines that your IP address has not changed.  Note that for some providers,
like zoneedit, if it sees that the IP number is already that value, then it
may return an error saying that.

=head2 -V|--version

Print the version numbers of this program as well as the Moxad modules that
it uses.

=head1 SUPPORT FOR OTHER DNS PROVIDERS

The config file specifies a 'service-provider'.  It can be any string,
ideally the name of your provider.  For eg: 'zoneedit'.  It uses this string
to look for the library <string>.pl in the directory given in the config
file with 'library-directory' and then dynamically loads it.

That library file is expected to have a function called update_ddns().
In this way, this code base can remain the same while someone can
create their own new library/function that is specific for their provider
and their API.

To create a new library for your provider (if it is not provided here),
you can just copy the existing zoneedit.pl library and make a small number
of changes to match their expected input URL, and process their output
returned to determine success or failure.  It is expected that 90% of
the code in the new copied library can remain untouched.  Call that new
library a meaningful name and point your config file to it by changing
'service-provider'.

=head1 DNS PROVIDER LIBRARY API

The API for the library to talk to your DNS provider is that the inputs are:

    userid, password, hostname-to-update, new-IP-address, timeout

The output is either 0 (OK) or 1 (not OK).  

If it is not OK (1), it is expected that error messages will be sent
to STDERR.

At this time of creation, the only provided library is zoneedit.pl
which understands their API.  That function can be used as a guide
for creating other library functions for other providers which 
should only differ in the (REST) URL that is sent, and processing
the output back to determine success or failure.

The directory where the library is found is given in the config file
with 'library-directory'.

=head1 REQUIREMENTS

uses the Moxad::Config module to handle human-readable config files.
This is available at https://github.com/rjwhite/Perl-config-module

uses the Moxad::Rcommand module to separate STDIN and STDERR into
separate streams and to handle a timeout to avoid hung services.
This is available at https://github.com/rjwhite/Perl-run-command

=head1 CONFIG FILE

The program looks in several places to find the config file.  Of the
list of places it finds a config file, it will use the B<last> on the
list that has an existing file.  That list of places to look is:

 - ${HOME}/.config/update-ddns/update-ddns.conf
 - The environment variable UPDATE_DDNS_CONFIG_FILE
 - update-ddns.conf in the current directory
 - given by option -c or --config

So the -c or --config option will over-ride any other config files found
if the file exists.

=head1 Config file example

    # The userid and password are arrays.  The size is determined by the
    # size of the data given by the hostnames.  If the number of values
    # given by the userid or password is less than the number of hostnames,
    # then the missing values will be filled with the last given value.
    # So, if the userid is the same for say 3 hostnames, but each hostname
    # to be updated has a different password, then only one value need be
    # given for the userid.

    authentication:
        userid   (array)    = my_userid
        password (array)    = API-password-1, \
                              API-password-2, \
                              API-password-3

    # These are methods to use to get the IP number assigned by our ISP.
    # If randomize-methods is set to yes, then the program will pick
    # a method at random to start at.  If it does not get a result that
    # looks like an IP number then another method will be tried, until
    # all are tried and fail.

    get-ip-number:
        methods  (array)    = curl -s icanhazip.com, \
                              curl -s ifconfig.me, \
                              curl -s 'https://api.ipify.org', \
                              curl -s 'http://checkip.dyndns.org' | \
                                  sed 's/.*Current IP Address: \([0-9\.]*\).*/\1/g'
        randomize-methods   = yes

    hosts:
        hostnames (array)   = home.my-domain.ca, \
                              home.my-domain.com, \
                              home.my-domain.net

    files:
        save-ip-number      = /home/my-userid/etc/update-ddns--IP-number
        library-directory   = /home/my-userid/lib/Perl

    # The 'service-provider' is the name of the library found in your 
    # library-directory.  So 'zoneedit' will be zoneedit.pl
    # You can call it anything you want but it is recommended that it
    # be a meaningful name to represent your DNS provider

    protocol:
        service-provider    = zoneedit

    timeout:
        timeout             = 20

=head1 SEE ALSO

Heidelberg, Germany.  It's nice.

=head1 AUTHOR

RJ White, E<lt>rj.white@moxad.comE<gt>

=head1 COPYRIGHT AND LICENSE

 Copyright 2022 RJ White
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

=cut
