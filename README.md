# update-ddns
update DNS records at your DNS service provider

## Description

update-ddns does DNS updates for one or more hosts at your DNS provider.
It is typically run from the crontab periodically - like every half hour.
It's primary value is that you can be away from home and depend on
reaching your internal network/servers at home when your dynamic IP
number, provided by your ISP, changes.

It can update several hostnames in a single run for different domains,
each which may or may not have different authentication userid/passwords
for a single new IP number.  For eg: for the 3 hosts in the 3 domains
of home.my-domain.com, home.my-domain.net and home.my-domain.ca.  It keeps track
of the IP number from the last run and if there is no change, then the
program does nothing and exits.

You can specify several methods to get the external dynamic IP number
assigned by your ISP.  If one method fails, others will be tried until all
are tried before giving up.  You can specify to randomize where in that
list to start cycling from, in case you don't want to be always using
the first on the list and seen by that provider as over-using their free
resource to do a IP lookup on your connection.

The first time run, it will notice that you do not yet have a
'save-ip-number' file to store the IP number.  It will create this file,
with your IP number, and exit.  The next time it is run, it will compare
the value found in that file to your current assigned IP number.

Note that at this time, only IPv4 is supported.

You can specify in the config file a program 'vpn-test' to run, to see
if you are currently running a VPN that has changed your IP number.  If it
determines a VPN is in use, it will prevent update-ddns from updating your
DNS records for that temporary IP number.

Note that currently the only DNS service provider supported is Zoneedit.
But that library/function can be copied to a new library and slightly
modified to use their expected URL input and to process their output
to determine success or failure.  See section "Support for other DNS providers"

Use -h or --help for options

## Example usages
The --help or -h option will print the options available:

        % update-ddns --help

        usage: update-ddns [option]*
            [-c|--config file]   (config-file (default=./update-ddns.conf)
            [-d|--debug]         (debugging output)
            [-f|--file file]     (IP-file (default=/home/userid/etc/IP-number))
            [-h|--help]          (help)
            [-i|--ip-num IP#]    (use this IP number instead of lookup)
            [-l|--lib-dir str]   (library directory (default=/home/userid/lib/Perl))
            [-n|--no-save-ip]    (don't save the IP)
            [-o|--only host]     (restrict to only this host given))
            [-p|--provider str]  (DDNS provider (default=zoneedit))
            [-r|--randomize]     (randomize the method to get ip number)
            [-s|--show-success]  (indicate if successful.  normally silent)
            [-t|--timeout num]   (timeout (default=12 secs))
            [-D|--disable]       (create lock file (/home/userid/etc/update-ddns-lockfile))
            [-E|--enable]        (remove lock file (/home/userid/etc/update-ddns-lockfile))
            [-F|--force-update]  (force DDNS update)
            [-S|--show-ip]       (show current IP number and exit)
            [-V|--version]       (print version (1.3))

The following will provide an indication to STDOUT when the program was successful.
Normally it is silent with success, but given the very few times your dynamic
IP address will change, you may wish to be alerted when it happens.  
You can also keep a log of changes via the optional 'log-file' given in the config file.

        % update-ddns --show-success

The following will only try to update the two hostnames of **test.my-domain.ca**
and **test.my-domain.net** out of the entire list given by 'hostnames' in the config file.  
Multiple --only or -o options may be used, and the hosts can also be comma separated:

        % update-ddns --only test.my-domain.ca --only test.my-domain.net
        % update-ddns --o test.my-domain.ca,test.my-domain.net

# Support for other DNS providers
The config file specifies a 'service-provider'. It can be any string,
ideally the name of your provider. For eg: 'zoneedit'. It uses this string
to look for the library \<string\>.pl in the directory given in the config
file with 'library-directory' and then dynamically loads it.

That library file is expected to have a function called update_ddns(). In
this way, this code base can remain the same while someone can create
their own new library/function that is specific for their provider and
their API.

To create a new library for your provider (if it is not provided here),
you can just copy the existing zoneedit.pl library and make a small number
of changes to match their expected input URL, and process their output
returned to determine success or failure. It is expected that 90% of the
code in the new copied library can remain untouched. Call that new library
a meaningful name and point your config file to it by changing
'service-provider'.

# DNS provider library API

The API for the library for your DNS provider is that the inputs are:

    userid, password, hostname-to-update, new-IP-address, timeout

The output is either 0 (OK) or 1 (not OK).

If it is not OK (1), it is expected that error messages will be sent to
STDERR.

At this time of creation, the only provided library is zoneedit.pl which
understands their API. That function can be used as a guide for creating
other library functions for other providers which should only differ in
the (REST) URL that is sent, and processing the output back to determine
success or failure.

The directory where the library is found is given in the config file with
'library-directory'.

# REQUIREMENTS
uses the Moxad::Config module to handle human-readable config files. This
is available at https://github.com/rjwhite/Perl-config-module

uses the Moxad::Rcommand module to separate STDOUT and STDERR into separate
streams and to handle a timeout to avoid hung services. This is available
at https://github.com/rjwhite/Perl-run-command

# config file
The program looks in several places to find the config file. Of the list
of places it finds a config file, it will use the last on the list that
has an existing file. That list of places to look is:

    - ${HOME}/.config/update-ddns/update-ddns.conf
    - The environment variable UPDATE_DDNS_CONFIG_FILE
    - update-ddns.conf in the current directory
    - given by option -c or --config

So the -c or --config option will over-ride any other config files found
if the file exists.

# config file example

    # The userid and password are arrays.  The size is determined by the
    # size of the data given by the hostnames.  If the number of values
    # given by the userid or password is less than the number of hostnames,
    # then the missing values will be filled with the last given value.
    # So, if the userid is the same for say 3 hostnames, but each hostname
    # to be updated has a different password, then only one value need be
    # given for the userid.

    authentication:
        userid   (array)    = my-login-name
        password (array)    = my-API-password-1, \
                              my-API-password-2, \
                              my-API-password-3

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
        log-file            = /home/my-userid/logs/update-ddns.log

    # The 'service-provider' is the name of the library found in your
    # library-directory.  So 'zoneedit' will be zoneedit.pl
    # You can call it anything you want but it is recommended that it
    # be a meaningful name to represent your DNS provider

    protocol:
        service-provider    = zoneedit

    timeout:
        timeout             = 20

    disable:
        lock-file           = /home/my-userid/etc/update-ddns-lockfile
        vpn-test            = /home/my-userid/bin/test-for-vpn  nordtun
