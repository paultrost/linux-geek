#!/usr/bin/env perl 

##############################################################################
# Copyright (C) 2013                                                         #
#                                                                            #
# This program is free software; you can redistribute it and/or modify       #
# it under the terms of the GNU General Public License as published by       #
# the Free Software Foundation; either version 2 of the License, or          #
# (at your option) any later version.                                        #
#                                                                            #
# This program is distributed in the hope that it will be useful,            #
# but WITHOUT ANY WARRANTY; without even the implied warranty of             #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the               #
# GNU General Public License for more details.                               #
#                                                                            #
# You should have received a copy of the GNU General Public License along    #
# with this program; if not, write to the Free Software Foundation, Inc.,    #
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.                #
##############################################################################

######################
# Author: Paul Trost #
# Version: 0.3.4     #
# 2013-07-20         #
######################

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

my @rsyncopts = qw( -auv --delete);

########################################
## Stop if not called as the root user #
########################################

die "This script has to be run as root!\n" if ( $> != 0 );

###########################################################
# Parse positional parameters for flags and set variables #
###########################################################

# Set defaults for positional parameters
my $help;
my $smtp_port = '587';
my $helo      = hostname;
my $device;
my $mountpoint;
my $fstype;
my $email_auth_addr;
my $email_auth_pass;
my $email_addr = $email_auth_addr;
my $outbound_server;
my $folders;

# Get the options from the command line
GetOptions(
    'help|?'            => \$help,
    'smtp_port=s'       => \$smtp_port,
    'helo=s'            => \$helo,
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
pod2usage(1) if ( $help or !@ARGV );

# Display error if one of the required parameters isn't specified
die "Not all required parameters specified, run '$0 --help' and check your arguments\n"
  unless ( 
        $device
    and $mountpoint
    and $fstype
    and $email_addr
    and $email_auth_addr
    and $email_auth_pass
    and $outbound_server
    and $folders
  );

=head1 NAME

backup.pl - Rsync list of folders to a mounted device

=head1 SYNOPSIS

backup.pl [options] [parameters]

Options:

 --help            Display available and required options
 --smtp_port       SMTP port to connect to, the default is 587 but 465 for SSL and 25 are supported as well
 --helo            Change the HELO that is sent to the outbound server, this setting defaults to the current hostname

Required Parameters:
 
 --device          Block device to mount
 --mountpoint      Directory to mount device at
 --fstype          Filesystem type on the device (ext4, ntfs, etc..)
 --email_auth_addr Email address for SMTP Auth
 --email_auth_pass Password for SMTP Auth (use \ to escape characters)
 --email_addr      Email address to send backup report to (defaults to email_auth_addr)
 --outbound_server Server to send mail through
 --folders         Directories to back up (for multiple folders, see example)

Example:

  backup.pl --device /dev/sdc1 --mountpoint /backup --fstype ext4 --email_addr me@me.com --email_auth_user me@me.com --email_auth_pass 12345 --outbound_server mail.myserver.com --folder "/etc /usr/local/ /home"

=cut

###############################
# Additional variables needed #
###############################

my $status;
my $nounmount;
my $error;
my @REPORT;
my $hostname = hostname;
chomp( my $date     = qx(date) );

#######################################################
# Check to see that $device and $mountpoint are valid #
#######################################################

die "$device is not a valid block device\n"          if ( !-b $device );
die "$mountpoint does not exist, create manually.\n" if ( !-d $mountpoint );

#################
# Begin @REPORT #
#################

push @REPORT, "Starting backup of $hostname at $date\n\n";

my $drivemount = qx(mount $device $mountpoint -t $fstype 2>&1);
if ($drivemount) {
    push @REPORT, "*** Could not mount $device on $mountpoint ***\n\n$drivemount\n";
    $nounmount = 1;
}
else {
    push @REPORT, "$device has been mounted on $mountpoint\n\n";
}

################################################
# Rsync each folder in @folders to $mountpoint #
################################################

# Testing for false $drivemount seems backwards yes, but keep in mind
# this is testing captured output of the mount command which will only
# have output in a failure
if ( !$drivemount ) {
    my @folders = split( / / , $folders );
    foreach my $folder (@folders) {
        if ( !-d $folder ) {
            push @REPORT, "*** Folder $folder isn't valid, not trying to rsync it ***\n\n";
            $error++;
            next;
        }

        # Actually run rsync
        my $output = qx(rsync @rsyncopts $folder $mountpoint);

        if ( $output !~ /sent.*bytes.*received.*bytes/ ) {
            push @REPORT, "Could not copy $folder to $mountpoint\n\n";
            push @REPORT, $output;
            $error++;
        }
        else {
            push @REPORT, "Now backing up folder '$folder':\n";
            push @REPORT, "$output\n\n";
        }
    }
}

####################### 
### Unmount $device ###
####################### 

# Unmount $device, but only if this script was what mounted it
$drivemount = qx(umount $mountpoint 2>&1) if !$nounmount;

if ( $drivemount and !$nounmount ) {
    push @REPORT, "*** $device could not be unmounted from ${mountpoint} ***:\n\n $drivemount\n\n";
    $error++;
}
elsif ($nounmount) {
    push @REPORT, "*** $device was already mounted on $mountpoint, not attemping to unmount ***\n\n";
    $error++;
}
else {
    push @REPORT, "$device has been unmounted from $mountpoint\n\n";
}

#################### 
# Finalize @REPORT #
#################### 

# Set status message for report to failed or successful based on if 
# error messages beginning with * were found
chomp( $date = qx(date) );
push @REPORT, "Backup finished at $date\n";
if ($error) {
    $status = 'failed or couldn\'t rsync a specified directory';
}
else {
    $status = 'successful';
}

######################################################
# Send backup successful/failed message to recipient #
######################################################

my $smtp_method = $smtp_port eq '465' ? 'Net::SMTP::SSL' : 'Net::SMTP';

# If the SMTP transaction is failing, add 'Debug => 1,' to the method below
# which will output the full details of the SMTP conenction
my $smtp = $smtp_method->new(
    $outbound_server,
    Port    => $smtp_port,
    Hello   => $helo,
    Timeout => 10,
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
$smtp->datasend(@REPORT);
$smtp->dataend;
$smtp->quit;
