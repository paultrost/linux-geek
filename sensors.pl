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
# Version: 0.2.1     #
# 2014-01-03         #
######################

use strict;
use warnings;
use Hardware::SensorsParser;
use Math::Round;
use Sys::Info;

######################
# User set variables #
######################

# Set temp warning thresholds
my $cpu_temp_warn  = 65;
my $mb_temp_warn   = 60;
my $disk_temp_warn = 35;

# What disks do you want to monitor temp on?
my @disks = qx(ls /dev/sd[a-z]);

###############################################
# Set flag if -errorsonly option is specified #
###############################################

my $errorsonly = 1 if ( /-errorsonly/ ~~ @ARGV );

########################################
## Stop if not called as the root user #
########################################

die "This script has to be run as root!\n" if ( $> != 0 );

##############################################
# Ensure prerequisite programs are installed #
##############################################

chomp( my $hddtemp = qx(which hddtemp) );
if ( !-x $hddtemp ) {
    die "'hddtemp' is not installed or is not executable.\n";
}

##############################################
# Instantiate objects and gather information #
##############################################

my $sensors       = Hardware::SensorsParser->new;
my @chipset_names = $sensors->list_chipsets;
my $info          = Sys::Info->new;
my $cpu           = $info->device('CPU');
my $os            = $info->os;

#########################
# Process sensor values #
#########################

my @errors;
my @output;

foreach my $chipset (@chipset_names) {
    my $count_cpu = 0;
    my $count_fan = 0;
    my @sensor_names = $sensors->list_sensors($chipset);
    @sensor_names = sort(@sensor_names);
    foreach my $sensor (@sensor_names) {

        # Get CPU temps
        if ( $sensor =~ qr(Core) ) {
            if ($count_cpu == 0) {
                push ( @output, "\n" );
                push ( @output, "CPU/MB Temperature(s)" );
                push ( @output, "---------------------" );
            }
            my ($temp_c, $temp_f) = get_temp( $sensor, $chipset, $sensor );
            push( @output, "$sensor temperature: ${temp_c} C (${temp_f} F)" );
            $count_cpu = 1;
            push( @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C!" )
              if ( $temp_c > $cpu_temp_warn );
        }

        # Get Motherboard temp
        if ( $sensor =~ qr(M/BTemp) ) {
            my ($temp_c, $temp_f) = get_temp( 'M/B', $chipset, $sensor );
            push( @output, "$sensor temperature: ${temp_c} C (${temp_f} F)" );
            push( @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C!" )
              if ( $temp_c > $mb_temp_warn );
        }

        # Get Fan speeds
        if ( $sensor =~ /fan/ ) {
            if ($count_fan == 0) {
                push ( @output, "Fan Speeds" );
                push ( @output, "----------" );
            }
            my $speed_value = get_fan_speed( 'Fan', $chipset, $sensor );
            $sensor =~ s/f/F/;
            push( @output, "$sensor speed: $speed_value RPM" );
            $count_fan = 1;
        }
    }
}

# Get sensor values for disks
push ( @output, "\n" );
push ( @output, "Drive Temperature(s):" );
push ( @output, "---------------------" );
foreach my $disk (@disks) {
    chomp($disk);
    my ( $temp_c, $temp_f ) = get_disk_temp($disk);
    if ( $temp_c !~ 'N/A' ) {
        push( @output, "$disk temperature: ${temp_c} C (${temp_f} F)" );
        push( @errors, "ALERT: $disk temperature threshold exceeded, $temp_c C" )
          if ( -e $disk and $temp_c > $disk_temp_warn);
    }
}

##################
# Display Output #
##################

if (!$errorsonly) {
    print "\n";
    print "Operating System:\n", $os->name( long => 1 ) . "\n";
    print "\n";
    print "\n";
    print "CPU:\n", scalar $cpu->identify . "\n";
    print join( "\n", @output ), "\n";
    print "\n";
}
    
if (@errors) {
    print "\n";
    print join( "\n", @errors ), "\n";
    print "\n";
}


###############
# Subroutines #
###############

sub get_temp {
    my ( $realname, $sensor, $sensorname ) = @_;
    my $temp_value = $sensors->get_sensor_value( $sensor, $sensorname, 'input' );
    my $temp_c     = round($temp_value);
    my $temp_f     = round( ( $temp_c * 9 ) / 5 + 32 );
    return ( $temp_c, $temp_f );
}

sub get_fan_speed {
    my ( $realname, $sensor, $sensorname ) = @_;
    my $speed_value = round($sensors->get_sensor_value( $sensor, $sensorname, 'input' ));
    return ($speed_value eq '0') ? 'N/A' : $speed_value;
}
    
sub get_disk_temp {
    chomp( my $disk   = shift );
    chomp( my $temp_c = qx(hddtemp -n $disk --unit=C 2>/dev/null) );
    # Exit out if disk can't return temperature
    return 'N/A' if ( !$temp_c or $temp_c =~ qr(S.M.A.R.T. not available) );

    my $temp_f = round( ( $temp_c * 9 ) / 5 + 32 );
    return ( $temp_c, $temp_f );
}
