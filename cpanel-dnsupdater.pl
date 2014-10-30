#!/usr/bin/env perl

use strict;
use LWP::UserAgent;
use MIME::Base64;
use XML::Simple;
use LWP::Simple;
use Socket;
use Getopt::Long;
use Pod::Usage;


pod2usage(1) if !@ARGV;

#-------------------------------------------------------------------------------
#  Parse command line options
#-------------------------------------------------------------------------------
my $param_domain;
my $param_host;
my $param_ip;
my $help;

GetOptions(
    'help|?'   => \$help,
    'domain=s' => \$param_domain,
    'host=s'   => \$param_host,
    'ip=s'     => \$param_ip,
);

pod2usage(1) if $help;

#-------------------------------------------------------------------------------
#  Set user account parameters, should probably be moved to a config file
#-------------------------------------------------------------------------------
my $cpanel_domain = "";
my $user          = "";
my $pass          = "";
my $auth          = "Basic " . MIME::Base64::encode( $user . ":" . $pass );

#-------------------------------------------------------------------------------
#  Disable SSL validation
#-------------------------------------------------------------------------------
my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );

#-------------------------------------------------------------------------------
#  Main code body
#-------------------------------------------------------------------------------

# Set update IP to detected remote IP address if IP not specified on cmd line
my $url = "http://cpanel.net/myip";
if ( !defined $param_ip ) {
    $param_ip = get($url)
      or die "Couldn't get detected remote IP, please check the URL $url.\n";
    chomp $param_ip;
}
    
my ( $linenumber, $current_ip ) = get_zone_data( $param_domain, $param_host );

if ( $current_ip eq $param_ip ) {
    print "Detected remote IP $param_ip matches current IP $current_ip, no IP update needed.\n";
    exit(0);
}

print "Trying to update $param_host IP to $param_ip ...\n";
my $result = set_host_ip( $param_domain, $linenumber, $param_ip );
if ( $result eq "1" ) {
    print "Update successful! Changed $current_ip to $param_ip\n";
    exit(0);
}
else {
    print "$result\n";
}

exit(1);

sub get_zone_data {
    my ( $domain, $hostname ) = @_;
    $hostname .= ".$domain.";

    my $xml      = XML::Simple->new;
    my $request  = HTTP::Request->new( GET => "https://$cpanel_domain:2083/xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=fetchzone&domain=$domain" );

    $request->header( Authorization => $auth );
    my $response = $ua->request($request);

    my $linenumber = '';
    my $address;
    my $found_hostname;
    my $zone;
    eval { $zone = $xml->XMLin( $response->content ) };
    print "Couldn't connect to $cpanel_domain to fetch zone contents for $domain\n";
    print "Please ensure \$cpanel_domain, \$user, and \$pass are set correctly.\n";
    die if !defined $zone;

    if ( $zone->{'data'}->{'status'} eq "1" ) {
        my $count = @{ $zone->{'data'}->{'record'} };
        my $oldip = "";
        for ( my $item = 0 ; $item <= $count ; $item++ ) {
            my $name = $zone->{'data'}->{'record'}[$item]->{'name'};
            my $type = $zone->{'data'}->{'record'}[$item]->{'type'};

            if ( ( $name eq $hostname ) && ( $type eq "A" ) ) {
                $linenumber  = $zone->{'data'}->{'record'}[$item]->{'Line'};
                $address     = $zone->{'data'}->{'record'}[$item]->{'address'};
                $found_hostname = 1;
            }
        }
    }
    else {
        die "Couldn't fetch zone for $domain.\n$zone->{'event'}->{'data'}->{'statusmsg;'}\n";
    }

    die "No A record present for $hostname, please verify it exists in the cPanel zonefile!\n" if !$found_hostname;
    return ( $linenumber, $address );
}

sub set_host_ip {
    my ( $domain, $linenumber, $newip ) = @_;

    my $result     = "";
    my $xml        = XML::Simple->new;
    my $request    = HTTP::Request->new( GET => "https://$cpanel_domain:2083/xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=edit_zone_record&domain=$domain&line=$linenumber&address=$newip" );
    $request->header( Authorization => $auth );
    my $response   = $ua->request($request);
    my $reply = $xml->XMLin( $response->content );
    if ( $reply->{'data'}->{'status'} eq "1" ) {
        $result = "1";
    }
    else {
        $result = $reply->{'data'}->{'statusmsg'};
    }
    return ($result);
}



=pod

=head1 NAME

 cpanel-dnsupdater.pl

=cut

=head1 VERSION

 0.1

=cut

=head1 USAGE

 cpanel-dnsupdater.pl [options]

 Example:
 cpanel-dnsupdater.pl --host home --domain domain.tld

=cut

=head1 DESCRIPTION

 Updates the IP address of an A record on a cPanel hosted domain

=cut

=head1 ARGUMENTS

=head2  Required

  --host        Host name to update in the domain's zonefile. eg. 'www'
  --domain      Name of the domain to update

=head2  Optional

  --ip          IP address to update the A record with. This defaults to the detected external IP.

=cut

=head1 EXIT STATUS

 Exits with 1 if there was any issue updating the record, otherwise 0.

=head1 AUTHOR

 Paul Trost <paul.trost@trostfamily.org>
 Original code by Stefan Gofferje - http://stefan.gofferje.net/

=cut

=head1 LICENSE AND COPYRIGHT

 Copyright 2012, 2013, 2014.
 This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License v2, or at your option any later version.
 <http://gnu.org/licenses/gpl.html>
