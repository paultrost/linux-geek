#!/usr/bin/env perl

use strict;
use warnings;

use LWP::UserAgent;
use MIME::Base64;
use XML::Simple;
use LWP::Simple;
use Socket;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use Net::SMTP::SSL;

#-------------------------------------------------------------------------------
#  Parse command line options
#-------------------------------------------------------------------------------
pod2usage(1) if !@ARGV;

my %args = (
    'smtp_port' => 587,
    'helo'      => hostname(),
);

GetOptions(
    \%args,              'help|?',
    'domain=s',          'host=s',
    'cpanel_user=s',     'cpanel_pass=s',
    'cpanel_domain=s',   'ip=s',
    'helo=s',            'smtp_port=s',
    'email_auth_user=s', 'email_auth_pass=s',
    'email_addr=s',      'outbound_server=s',
);

pod2usage(1) if $args{'help'};

die "Required parameters not specified\n"
  unless $args{'domain'}
  and $args{'host'}
  and $args{'cpanel_user'}
  and $args{'cpanel_pass'}
  and $args{'cpanel_domain'};

$args{'$email_addr'} = $args{'email_auth_user'} if !$args{'email_addr'};

my $send_email = 0;
$send_email = 1 if $args{'email_addr'};

my $status;

#-------------------------------------------------------------------------------
#  Set user account parameters, should probably be moved to a config file
#-------------------------------------------------------------------------------
my $auth = 'Basic '
  . MIME::Base64::encode( $args{'cpanel_user'} . ':' . $args{'cpanel_pass'} );

#-------------------------------------------------------------------------------
#  Disable SSL validation
#-------------------------------------------------------------------------------
my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );

#-------------------------------------------------------------------------------
#  Main code body
#-------------------------------------------------------------------------------

# Set update IP to detected remote IP address if IP not specified on cmd line
my $url = 'http://cpanel.net/myip';
if ( !defined $args{'ip'} ) {
    $status = "Couldn't detect remote IP, please check the URL $url.\n";
    $args{'ip'} = get($url);
    if ( !$args{'ip'} ) {
        ($send_email) ? send_email($status) : print $status;
        exit(1);
    }
    chomp $args{'ip'};
}

# Get current host IP address and see if it matches the given IP
my ( $linenumber, $current_ip ) =
  get_zone_data( $args{'domain'}, $args{'host'} );
if ( $current_ip eq $args{'ip'} ) {

#print "Detected remote IP $args{'ip'} matches current IP $current_ip; no IP update needed.\n";
    exit(0);
}

#print "Trying to update $args{'host'} IP to $args{'ip'} ...\n";
my $result = set_host_ip( $args{'domain'}, $linenumber, $args{'ip'} );
if ( $result eq 'succeeded' ) {
    $status = "Update successful! Changed $current_ip to $args{'ip'}\n";
    ($send_email) ? send_email($status) : print $status;
    exit(0);
}
else {
    $status = "Update not successful, $result\n";
    ($send_email) ? send_email($status) : print $status;
    exit(1);
}

exit(1);    #if we get here, something bad happened

sub send_email {
    my $body_text = shift;
    my $smtp_method =
      ( $args{'smtp_port'} == 465 ) ? 'Net::SMTP::SSL' : 'Net::SMTP';

    # If the SMTP transaction is failing, add 'Debug => 1,' to the method below
    # which will output the full details of the SMTP connection
    my $smtp = $smtp_method->new(
        $args{'outbound_server'},
        Port    => $args{'smtp_port'},
        Hello   => $args{'helo'},
        Timeout => 10,
      )
      or die
"Could not connect to $args{'outbound_server'} using port $args{'smtp_port'}\n$@\n";

    $smtp->auth( $args{'email_auth_user'}, $args{'email_auth_pass'} );
    $smtp->mail( $args{'email_auth_user'} );
    $smtp->to( $args{'email_addr'} );
    $smtp->data();
    $smtp->datasend("From: $args{'email_auth_user'}\n");
    $smtp->datasend("To: $args{'email_addr'}\n");
    $smtp->datasend(
        "Subject: Ouutput of $0 for $args{'host'}.$args{'domain'}\n");
    $smtp->datasend( 'Date: ' . localtime() . "\n" );
    $smtp->datasend("\n");
    $smtp->datasend($body_text);
    $smtp->dataend();
    $smtp->quit();
    return;
}

sub get_zone_data {
    my ( $domain, $hostname ) = @_;
    $hostname .= ".$domain.";

    my $xml = XML::Simple->new;
    my $request =
      HTTP::Request->new( GET =>
"https://$args{'cpanel_domain'}:2083/xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=fetchzone&domain=$domain"
      );
    $request->header( Authorization => $auth );
    my $response = $ua->request($request);

    my $zone;
    eval { $zone = $xml->XMLin( $response->content ) };
    if ( !defined $zone ) {
        $status =
"Couldn't connect to $args{'cpanel_domain'} to fetch zone contents for $domain\n";
        $status .=
"Please ensure \$args{'cpanel_domain'}, \$args{'cpanel_user'}, and \$args{'cpanel_pass'} are set correctly.\n";
        ($send_email) ? send_email($status) : print $status;
        exit(1);
    }

    # Assuming we find the zone, iterate over it and find the $hostname record
    my ( $linenumber, $address, $found_hostname );
    if ( $zone->{'data'}->{'status'} eq '1' ) {
        my $count = @{ $zone->{'data'}->{'record'} };
        my $item  = 0;
        while ( $item <= $count ) {
            my $name = $zone->{'data'}->{'record'}[$item]->{'name'};
            my $type = $zone->{'data'}->{'record'}[$item]->{'type'};
            if ( ( defined($name) && $name eq $hostname ) && ( $type eq 'A' ) )
            {
                $linenumber = $zone->{'data'}->{'record'}[$item]->{'Line'};
                $address    = $zone->{'data'}->{'record'}[$item]->{'address'};
                $found_hostname = 1;
            }
            $item++;
        }
    }
    else {
        $status =
"Couldn't fetch zone for $domain.\n$zone->{'event'}->{'data'}->{'statusmsg;'}\n";
        ($send_email) ? send_email($status) : print $status;
        exit(1);
    }

    if ( !$found_hostname ) {
        $status =
"No A record present for $hostname, please verify it exists in the cPanel zonefile!\n";
        ($send_email) ? send_email($status) : print $status;
        exit(1);
    }

    return ( $linenumber, $address );
}

sub set_host_ip {
    my ( $domain, $linenumber, $newip ) = @_;

    my $xml = XML::Simple->new;
    my $request =
      HTTP::Request->new( GET =>
"https://$args{'cpanel_domain'}:2083/xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=edit_zone_record&domain=$domain&line=$linenumber&address=$newip"
      );
    $request->header( Authorization => $auth );
    my $response   = $ua->request($request);
    my $reply      = $xml->XMLin( $response->content );
    my $set_status = $reply->{'data'}->{'status'};
    return ( $set_status == 1 ) ? 'succeeded' : $reply->{'data'}->{'statusmsg'};
}

=pod

=head1 NAME

 cpanel-dnsupdater.pl

=cut

=head1 VERSION

 0.5

=cut

=head1 USAGE

 cpanel-dnsupdater.pl [options]

 Example:
 cpanel-dnsupdater.pl --host home --domain domain.tld --cpanel_user cptest --cpanel_pass 12345 --cpanel_domain cptest.tld

=cut

=head1 DESCRIPTION

 Updates the IP address of an A record on a cPanel hosted domain. If no email address is supplied to the script, then all output is printed to STDOUT instead of emailed.

=cut

=head1 ARGUMENTS

=head2  Required

  --host          Host name to update in the domain's zonefile. eg. 'www'
  --domain        Name of the domain to update
  --cpanel_user   cPanel account login name
  --cpanel_pass   cPanel account password
  --cpanel_domain cPanel account domain name

=head2  Optional

  --ip              IP address to update the A record with. This defaults to the detected external IP.
  --email_auth_user Email address for SMTP Auth
  --email_auth_pass Password for SMTP Auth (use \ to escape characters)
  --email_addr      Email address to send successful/error report to (defaults to email_auth_user)
  --outbound_server Server to send mail through
  --smtp_port       SMTP port to connect to, the default is 587 but 465 for SSL and 25 are supported as well
  --helo            Change the HELO that is sent to the outbound server, this setting defaults to the current hostname


=cut

=head1 EXIT STATUS

 Exits with 1 if there was any issue updating the record. Exits with 0 if IP was either changed, or the pulled IP matches the specified IP.

=head1 AUTHOR

 Paul Trost <paul.trost@trostfamily.org>
 Original code by Stefan Gofferje - http://stefan.gofferje.net/

=cut

=head1 LICENSE AND COPYRIGHT

 Copyright 2012, 2013, 2014, 2015.
 This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License v2, or at your option any later version.
 <http://gnu.org/licenses/gpl.html>
