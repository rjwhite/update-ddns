# update a DDNS record using the Zoneedit API
# This library is dynamically loaded by the update-ddns program.
#
# Arguments:
#   1:  userid
#   2:  password
#   3:  hostname of the DYN record to update
#   4:  IP address
#   5:  timeout in seconds
# Returns:
#   0:  OK
#   1:  not OK
# Globals:
#   G_progname
# output:
#   Any errors encountered will be output to STDERR

sub update_ddns {
    my $userid   = shift ;
    my $password = shift ;
    my $fqdn     = shift ;
    my $ip_num   = shift ;
    my $timeout  = shift ;

    my $sub_name = (caller(0))[3] . "()" ;
    dprint( "$sub_name: updating DDNS with IP $ip_num for $fqdn" ) ;

    my @errors = () ;
    my @output = () ;

    my $url = "https://${userid}:${password}@" .
              "api.cp.zoneedit.com/dyn/generic.php?" .
              "hostname=$fqdn&myip=${ip_num}" ;
    dprint( "$sub_name: URL = $url" ) ;

    # finally ready to send the request

    my @errors = () ;
    my @output = () ;
    my $ret = send_request( $url, \@errors, \@output, $timeout ) ;
    if ( $ret ) {
        if ( @errors == 0 ) {
            # got an error return but no error messages
            my $err = "$sub_name: Arg 2 to send_request() must be bad" ;
            print STDERR "${G_progname}: ${sub_name}: $err\n" ;
            return(1) ;
        }
        # print out the errors and return
        foreach my $error ( @{$error_ref}) {
            print STDERR "${G_progname}: ${sub_name}: $error\n" ;
        }
        return(1) ;
    } else {
        # the send request did not encounter problems, but we still may
        # have errors updating the IP.
        # For zoneedit, we expect back a single string
        # eg: <ERROR CODE="708" TEXT="Failed Login: moxad" ZONE="test.moxad.ca">

        my $num_lines = @output ;
        if ( $num_lines > 1 ) {
            my $err = "expected 1 line back, got $num_lines" ;
            print STDERR "${G_progname}: ${sub_name}: $err\n" ;
            # keep going...
        }
        if ( $num_lines == 0 ) {
            my $err = "got back no output.  status unknown" ;
            print STDERR "${G_progname}: ${sub_name}: $err\n" ;
            return(1) ;
        }

        my $response = $output[0] ;
        $response = $1 if ( $response =~ /<(.*)>/ ) ;
        if ( $response =~ /ERROR CODE=\"([\d]+)\"/ ) {
            # the single line return is already a decent readable error message
            # just print that instead of trying to parse it
            print STDERR "${G_progname}: ${sub_name}: $response\n" ;
            return(1) ;
        }

        # sucessful
        if ( $response =~ /SUCCESS CODE/ ) {
            dprint( "$sub_name: success for IP $ip_num for $fqdn" ) ;
            return(0) ;
        }

        # if we made it here, then we don't recognise this response.
        # flag it and assume it is an error

        print STDERR "${G_progname}: ${sub_name}: don't recognise response\n" ;
        print STDERR "${G_progname}: ${sub_name}: $response\n" ;
        return(1) ;
    }
}

1;
