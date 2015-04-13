#!/usr/bin/env perl 

use strict;
use warnings;
use Net::SMTP::SSL;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use Filesys::Df;


#################################
## USER CONFIGURABLE VARIABLES ##
#################################

my @rsyncopts = qw(
--archive
--update
--delete
);

############################################################################
## Stop if not called as the root user or if a previous run is still going #
############################################################################

my $tmpfile = '/tmp/backuprunning';

die "This script has to be run as root!\n" if ( $> != 0 );
die "$0 is still running from previous execution!\n" if -e $tmpfile;

#############################################
# Display help screen if no arguments given # 
#############################################

pod2usage(1) if !@ARGV;

###########################################################
# Parse positional parameters for flags and set variables #
###########################################################

# Set defaults for positional parameters

my %args = (
    smtp_port => '587',
    helo      => hostname(),
    debug_smtp => 0,
);
# Get the options from the command line
GetOptions( \%args,
    'help|?',
    'smtp_port=s',
    'helo=s',
    'debug',
    'debug_smtp',
    'target=s',
    'email_auth_user=s',
    'email_auth_pass=s',
    'email_addr=s',
    'outbound_server=s',
    'folder=s@',
    'exclude=s@',
);

$args{'email_addr'} ||= $args{'email_auth_user'};

# Display help screen if -help option specified
pod2usage(1) if $args{'help'};

# Display error if one of the required parameters isn't specified
die "Not all required parameters specified, run '$0 --help' and check your arguments\n"
  unless ( $args{'target'}
    and $args{'email_auth_user'}
    and $args{'email_auth_pass'}
    and $args{'outbound_server'}
    and $args{'folder'} );



############################
# Build rsync options list #
############################

if ( $args{'debug'} ) { push( @rsyncopts, '--verbose' ); }
if ( $args{'exclude'} ) {
    foreach my $item ( @{ $args{'exclude'} } ) {
        push( @rsyncopts, "--exclude $item" );
    }
}

###############################
# Additional variables needed #
###############################

my $error    = 0;
my $hostname = hostname();
my $date     = localtime();

#############################
# Validate target directory #
#############################

open( my $error_list, '>', \ my $validate_errors );

if ( !-d $args{'target'} ) {
    print {$error_list} "$args{'target'} does not exist, create manually.\n";
}

close $error_list;
die $validate_errors . "\n" if $validate_errors;

###########################################################
# Rsync each folder in $args{'folder'} to $args{'target'} #
###########################################################

open( my $report, '>', \ my $report_text ) or die "$!\n";
open( my $tmp_filename, '>', $tmpfile )
    or die "Could not open $tmpfile, $!\n";
close $tmp_filename;

foreach my $folder ( @{ $args{'folder'} } ) {
    print {$report} "Now backing up folder '$folder':\n";
    my $out = qx( rsync @rsyncopts $folder $args{'target'} 2>&1 );

    if ( $? != 0 and $out !~ /sent.*bytes.*received.*bytes/ ) {
        print {$report} "Could not copy $folder to $args{'target'}\n\n";
        print {$report} $out;
        $error++;
    }
    else {
        print {$report} $out;
        if ( $args{'debug'} ) { print {$report} "\n\n"; }
    }
}
unlink $tmpfile;

#################### 
# Finalize @REPORT #
#################### 

# Set status message for report to failed or successful based on if 
# error messages beginning with * were found
$date = localtime();
print {$report} "Backup finished at $date\n";
my $status = ($error) ? "failed or couldn't rsync a specified directory" : 'successful';
close $report;

######################################################
# Send backup successful/failed message to recipient #
######################################################

$report_text = "Date: $date\n\n" . $report_text;
my $smtp_method = ( $args{'smtp_port'} eq '465' ) ? 'Net::SMTP::SSL' : 'Net::SMTP';

# If the SMTP transaction is failing, use --debug_smtp
# which will output the full details of the SMTP connection
my $smtp      = $smtp_method->new(
    $args{'outbound_server'},
    Port            => $args{'smtp_port'},
    Hello           => $args{'helo'},
    Timeout         => 10,
    Debug           => $args{'debug_smtp'},
) or die "Could not connect to $args{'outbound_server'} using port $args{'smtp_port'}\n$!\n";

send_email();

exit ($error) ? 1 : 0;


sub send_email {
    $smtp->auth( $args{'email_auth_user'}, $args{'email_auth_pass'} );
    $smtp->mail( $args{'email_auth_user'} );
    $smtp->to( $args{'email_addr'} );
    $smtp->data();
    $smtp->datasend("From: $args{'email_auth_user'}\n");
    $smtp->datasend("To: $args{'email_addr'}\n");
    $smtp->datasend("Subject: Backup $status for $hostname\n");
    $smtp->datasend($report_text);
    $smtp->dataend();
    $smtp->quit();
    return;
}


=pod

=head1 NAME

 backup.pl

=cut

=head1 VERSION

 0.8.1

=cut

=head1 USAGE

 backup.pl [options] [parameters]

 Example:
 backup.pl --target /backup --email_addr me@me.com --email_auth_user me@me.com --email_auth_pass 12345 --outbound_server mail.myserver.com --folder /etc --folder /usr/local/ --folder /home --exclude Movies

=cut

=head1 DESCRIPTION

 Rsync list of folders to a mounted device

=cut

=head1 ARGUMENTS
 
=head2  Required

 --target          Target directory for rsync
 --email_auth_user Email address for SMTP Auth
 --email_auth_pass Password for SMTP Auth (use \ to escape characters)
 --email_addr      Email address to send backup report to (defaults to email_auth_user)
 --outbound_server Server to send mail through
 --folder          Directory to back up (for multiple directories see example)

=head2  Optional

 --help            Display available and required options
 --email_addr      Email address to send backup report to (defaults to email_auth_user)
 --smtp_port       SMTP port to connect to, the default is 587 but 465 for SSL and 25 are supported as well
 --helo            Change the HELO that is sent to the outbound server, this setting defaults to the current hostname
 --debug           Enable verbose output of rsync for debugging
 --debug_smtp      Enable verbose screen output for SMTP transaction emailing the report
 --exclude         File / Directory to be excluded from backup. For a directory, its subdirectories will also be excluded

=cut

=head1 EXIT STATUS
 
 Exits with 1 if there was a caught error in the rsync process, otherwise 0.

=cut

=head1 AUTHOR

 Paul Trost <paul.trost@trostfamily.org>

=cut

=head1 LICENSE AND COPYRIGHT
  
 Copyright 2014.
 This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License v2, or at your option any later version.
 <http://gnu.org/licenses/gpl.html>

=cut
