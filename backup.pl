#!/usr/bin/env perl 

use strict;
use warnings;
use Net::SMTP::SSL;
use Authen::SASL;
use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;


#################################
## USER CONFIGURABLE VARIABLES ##
#################################

my @rsyncopts = qw( -au --delete );

############################################################################
## Stop if not called as the root user or if a previous run is still going #
############################################################################

die "This script has to be run as root!\n" if ( $> != 0 );
die "$0 is still running from previous execution!\n" if -e '/tmp/backuprunning';

#############################################
# Display help screen if no arguments given # 
#############################################

pod2usage(1) if !@ARGV;

###########################################################
# Parse positional parameters for flags and set variables #
###########################################################

# Set defaults for positional parameters
my $help;
my $smtp_port = '587';
my $helo      = hostname();
my $debug;
my $debug_smtp;
my $device;
my $mountpoint;
my $fstype;
my $email_auth_addr;
my $email_auth_pass;
my $email_addr = $email_auth_addr;
my $outbound_server;
my $folders;
my $tmpfile = '/tmp/backuprunning';

# Get the options from the command line
GetOptions(
    'help|?'            => \$help,
    'smtp_port=s'       => \$smtp_port,
    'helo=s'            => \$helo,
    'debug'             => \$debug,
    'debug_smtp'        => \$debug_smtp,
    'device=s'          => \$device,
    'mountpoint=s'      => \$mountpoint,
    'fstype=s'          => \$fstype,
    'email_auth_addr=s' => \$email_auth_addr,
    'email_auth_pass=s' => \$email_auth_pass,
    'email_addr=s'      => \$email_addr,
    'outbound_server=s' => \$outbound_server,
    'folders=s'         => \$folders,
);

# Display help screen if -help option specified
pod2usage(1) if $help;

# Display error if one of the required parameters isn't specified
die "Not all required parameters specified, run '$0 --help' and check your arguments\n"
  unless ( $device and $mountpoint and $fstype and $email_addr and $email_auth_addr and $email_auth_pass and $outbound_server and $folders );

###############################
# Additional variables needed #
###############################

my $nounmount;
my $error    = 0;
my $hostname = hostname();
my $date     = localtime();

#######################################################
# Check to see that $device and $mountpoint are valid #
#######################################################

die "$device is not a valid block device\n"          if ( !-b $device );
die "$mountpoint does not exist, create manually.\n" if ( !-d $mountpoint );

my $space = qx(df $device | grep -v '^Filesystem' | awk 'NF=6{print \$4}NF==5{print \$3}{}');
die "Mount point $mountpoint is out of space.\n" if $space == 0;

open( my $report, '>', \ my $report_text );

#################
# Begin @REPORT #
#################

print $report "Starting backup of $hostname at $date\n\n";

my $drivemount = qx(mount $device $mountpoint -t $fstype 2>&1);
if ($drivemount) {
    print $report "*** Could not mount $device on $mountpoint ***\n\n$drivemount\n";
    $nounmount = 1;
}
else {
    print $report "$device has been mounted on $mountpoint\n\n";
}

################################################
# Rsync each folder in @folders to $mountpoint #
################################################

open( my $tmp_filename, '>', $tmpfile )
    or die "Could not open $tmpfile, $!\n";
close $tmp_filename;

# Testing for false $drivemount seems backwards yes, but keep in mind
# this is testing captured output of the mount command which will only
# have output in a failure
if ( !$drivemount ) {
    my @folders = split( / / , $folders );
    if ($debug) { push( @rsyncopts, '--verbose' ); }
    foreach my $folder (@folders) {
        if ( !-d $folder ) {
            print $report "*** Folder $folder isn't valid, not trying to rsync it ***\n\n";
            $error++;
            next;
        }

        # Actually run rsync
        print $report "Now backing up folder '$folder':\n";
        my $out = qx(rsync @rsyncopts $folder $mountpoint);

        if ( $? != 0 and $out !~ /sent.*bytes.*received.*bytes/ ) {
            print $report "Could not copy $folder to $mountpoint\n\n";
            print $report $out;
            $error++;
        }
        else {
            print $report $out;
            if ($debug) { print $report "\n\n"; }
        }
    }
}

unlink $tmpfile;

####################### 
### Unmount $device ###
####################### 

# Unmount $device, but only if this script was what mounted it
if (!$nounmount) { $drivemount = qx(umount $mountpoint 2>&1); }

if ( $drivemount && !$nounmount ) {
    print $report "*** $device could not be unmounted from ${mountpoint} ***:\n\n $drivemount\n\n";
    $error++;
}
elsif ($nounmount) {
    print $report "*** $device was already mounted on $mountpoint, not attemping to unmount ***\n\n";
    $error++;
}
else {
    print $report "\n$device has been unmounted from $mountpoint\n\n";
}

#################### 
# Finalize @REPORT #
#################### 

# Set status message for report to failed or successful based on if 
# error messages beginning with * were found
$date = localtime();
print $report "Backup finished at $date\n";
my $status = ($error) ? "failed or couldn't rsync a specified directory" : 'successful';

close $report;

######################################################
# Send backup successful/failed message to recipient #
######################################################

my $smtp_method = ( $smtp_port eq '465' ) ? 'Net::SMTP::SSL' : 'Net::SMTP';

# If the SMTP transaction is failing, add 'Debug => 1,' to the method below
# which will output the full details of the SMTP connection
my $debug_val = ($debug_smtp) ? 1 : 0;
my $smtp      = $smtp_method->new(
    $outbound_server,
    Port    => $smtp_port,
    Hello   => $helo,
    Timeout => 10,
    Debug   => $debug_val,
) or die "Could not connect to $outbound_server using port $smtp_port\n$!\n";

$smtp->auth( $email_auth_addr, $email_auth_pass );
$smtp->mail($email_auth_addr);
$smtp->to($email_addr);
$smtp->data();
$smtp->datasend("From: $email_auth_addr\n");
$smtp->datasend("To: $email_addr\n");
$smtp->datasend("Subject: Backup $status for $hostname\n");
$smtp->datasend("Date: $date\n");
$smtp->datasend("\n");
$smtp->datasend($report_text);
$smtp->dataend();
$smtp->quit();

exit ($error) ? 1 : 0;


=pod

=head1 NAME

 backup.pl

=head1 VERSION

 0.7

=head1 USAGE

 backup.pl [options] [parameters]

 Example:
 backup.pl --device /dev/sdc1 --mountpoint /backup --fstype ext4 --email_addr me@me.com --email_auth_user me@me.com --email_auth_pass 12345 --outbound_server mail.myserver.com --folder "/etc /usr/local/ /home"


=head1 DESCRIPTION

 Rsync list of folders to a mounted device

=head1 REQUIRED ARGUMENTS
 
 --device          Block device to mount
 --mountpoint      Directory to mount device at
 --fstype          Filesystem type on the device (ext4, ntfs, etc..)
 --email_auth_addr Email address for SMTP Auth
 --email_auth_pass Password for SMTP Auth (use \ to escape characters)
 --email_addr      Email address to send backup report to (defaults to email_auth_addr)
 --outbound_server Server to send mail through
 --folders         Directories to back up (for multiple folders, see example)

=head1 OPTIONS

 --help            Display available and required options
 --smtp_port       SMTP port to connect to, the default is 587 but 465 for SSL and 25 are supported as well
 --helo            Change the HELO that is sent to the outbound server, this setting defaults to the current hostname
 --debug           Enable verbose output of rsync for debugging
 --debug_smtp      Enable verbose screen output for SMTP transaction emailing the report

=head1 EXIT STATUS
 
 Exits with 1 if there was a caught error in the rsync process, otherwise 0.

=head1 AUTHOR

 Paul Trost <paul.trost@trostfamily.org>

=head1 LICENSE AND COPYRIGHT
  
 Copyright 2014.
 This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License v2, or at your option any later version.
 <http://gnu.org/licenses/gpl.html>

=cut
