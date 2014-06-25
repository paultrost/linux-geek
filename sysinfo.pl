#!/usr/bin/env perl 

##############################################################################
# Copyright (C) 2013                                                         #
#                                                                            #
# This program is free software; you can alertistribute it and/or modify     #
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

######################################
# Author: Paul Trost                 #
# Email:  paul.trost@trostfamily.org #
# Version 0.9                        #
######################################

use strict;
use warnings;
use Hardware::SensorsParser;
use Math::Round;
use Linux::Distribution qw(distribution_name distribution_version);
use Sys::Info;
use Sys::Load qw/getload uptime/;
use Sys::Hostname;
use Sys::MemInfo qw(totalmem freemem totalswap);
use Time::Duration;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
no if $] >= 5.018, warnings => "experimental"; # turn off smartmatch warnings

######################
# User set variables #
######################

# Set temp warning thresholds
my $cpu_temp_warn  = 65;
my $mb_temp_warn   = 60;
my $disk_temp_warn = 40;

# What disks do you want to monitor temp on?
# This can be a quoted list like "/dev/sda", "/dev/sdb" as well
chomp( my @disks = qx(ls /dev/sd[a-z]) );

###############################################
# Set flag if -errorsonly option is specified #
###############################################

my $errorsonly = ( /-errorsonly/ ~~ @ARGV ) ? 1 : 0;
my $color      = ( /-nocolor/    ~~ @ARGV ) ? 0 : 1;

########################################
## Stop if not called as the root user #
########################################

die "This script has to be run as root!\n" if ( $> != 0 );

##############################################
# Ensure prerequisite programs are installed #
##############################################

my @required_progs = qw(smartctl);
foreach my $prog (@required_progs) {
    chomp( my $prog_path = qx(which $prog 2>/dev/null) );
    die "$prog is not installed or is not executable. Please install and run $0 again.\n"
      if ( !$prog_path || !-x $prog_path );
}

##############################################
# Instantiate objects and gather information #
##############################################

my $sensors       = Hardware::SensorsParser->new;
my @chipset_names = $sensors->list_chipsets;

my $info          = Sys::Info->new;
my $cpu           = $info->device('CPU');

my $uptime        = int uptime();
my $load          = (getload())[0];
my $hostname      = hostname();
my $os            = distribution_name() . ' ' . distribution_version();
my $free_mem      = int( freemem() / 1024 / 1024 );
my $total_mem     = int( totalmem() / 1024 / 1024 );

#########################
# Process sensor values #
#########################

my @errors;
my @output;

foreach my $chipset (@chipset_names) {
    my $count_cpu    = 0;
    my $count_fan    = 0;
    my @sensor_names = sort( $sensors->list_sensors($chipset) );
    foreach my $sensor (@sensor_names) {

        # Get CPU temps
        if ( $sensor =~ /Core/ ) {
            if ($count_cpu == 0) {
                push @output, "\n";
                push @output, header("CPU/MB Temperature(s)");
                push @output, "---------------------";
            }
            my ( $temp_c, $temp_f ) = get_temp( $sensor, $chipset, $sensor );
            push @output, item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
            push @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)"
              if ( $temp_c > $cpu_temp_warn );
            $count_cpu = 1;
        }

        # Get Motherboard temp
        if ( $sensor =~ m{M/BTemp} ) {
            my ($temp_c, $temp_f) = get_temp( 'M/B', $chipset, $sensor );
            push @output, item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
            push @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)"
              if ( $temp_c > $mb_temp_warn );
        }

        # Get Fan speeds
        if ( $sensor =~ /fan/ ) {
            if ( $count_fan == 0 ) {
                push @output, header("Fan Speeds");
                push @output, "----------" ;
            }
            my $speed_value = get_fan_speed( 'Fan', $chipset, $sensor );
            $sensor =~ s/f/F/;
            push @output, item("$sensor speed: ") . value("$speed_value RPM");
            $count_fan = 1;
        }
    }
}

# Get sensor values for disks
push @output, "\n";
push @output, header("Drive Temperature(s) and Status:");
push @output, "---------------------";
my $disk_models;
foreach my $disk (@disks) {
    chomp($disk);
    my $smart_info  = qx(smartctl -a $disk);
    my $disk_health = get_disk_health($smart_info);
    $disk_models .= get_disk_model( $disk, $smart_info );
    my ( $temp_c, $temp_f ) = get_disk_temp($smart_info);
    if ( $temp_c !~ 'N/A' ) {
        push @output, item("$disk Temperature: ") . value("${temp_c} C (${temp_f} F) ") . item("Health: ") . value($disk_health);
        push @errors, "ALERT: $disk temperature threshold exceeded, $temp_c C (${temp_f} F)"
          if ( -e $disk and $temp_c > $disk_temp_warn );
        push @errors, "ALERT: $disk may be dying, S.M.A.R.T. status: $disk_health"
          if ( $disk_health !~ 'PASSED' );
    }
    else {
        push @output, item("$disk Temperature: N/A, Health: ") . value($disk_health);
    }
}

##################
# Display Output #
##################

if ( !$errorsonly ) {
    print "\n";
    print item("Hostname:      "), value("$hostname\n");
    print item("OS:            "), value("$os\n");
    print item("CPU:           "), value(scalar $cpu->identify . "\n");
    print item("Memory:        "), value("${free_mem}M / ${total_mem}M \n");
    print item("System uptime: "), value(duration($uptime) . "\n");
    print item("System load:   "), value("$load\n");
    print item("Disks:         "), value("\n$disk_models");
    print "\n\n" if $] < 5.018; #extra spacing needed for Perl < 5.18
    print join( "\n", @output ), "\n";
    print "\n";
}
    
if (@errors) {
    print "\n";
    print alert("$_\n") foreach (@errors);
    print "\n";
}


###############
# Subroutines #
###############

sub item {
    my $text = shift;
    return ($color) ? BOLD GREEN $text : $text;
}

sub value {
    my $text = shift;
    return ($color) ? BOLD YELLOW $text : $text;
}

sub alert {
    my $text = shift;
    return ($color) ? BOLD RED $text : $text;
}

sub header {
    my $text = shift;
    return ($color) ? BOLD BLUE $text : $text;
}

sub get_temp {
    my ( $realname, $sensor, $sensorname ) = @_;
    my $temp_value = $sensors->get_sensor_value( $sensor, $sensorname, 'input' );
    my $temp_c     = round($temp_value);
    my $temp_f     = round( ( $temp_c * 9 ) / 5 + 32 );
    return ( $temp_c, $temp_f );
}

sub get_fan_speed {
    my ( $realname, $sensor, $sensorname ) = @_;
    my $speed_value = round( $sensors->get_sensor_value( $sensor, $sensorname, 'input' ) );
    return ( $speed_value eq '0' ) ? 'N/A' : $speed_value;
}

sub get_disk_temp {
    my $smart_info = shift;
    my ($temp_c)   = $smart_info =~ /(Temperature_Celsius.*\n)/;
    chomp($temp_c) if $temp_c;

    if ($temp_c) {
        $temp_c =~ s/ //g;
        $temp_c =~ s/.*-//;
        $temp_c =~ s/\(.*\)//;
    }
    
    if ( !$temp_c || $smart_info =~ qr/S.M.A.R.T. not available/ ) {
        return 'N/A';
    }
    else {
        my $temp_f = round( ( $temp_c * 9 ) / 5 + 32 );
        return ( $temp_c, $temp_f );
    }
}

sub get_disk_health {
    my $smart_info = shift;
    my ($health)   = $smart_info =~ /(SMART overall-health self-assessment.*\n)/;

    if ( $health and $health =~ /PASSED|FAILED/ ) {
        $health =~ s/.*result: //s;
        chomp($health);
        return $health;
    }
    else {
        return 'N/A';
    }
}

sub get_disk_model {
    my ( $disk, $smart_info ) = @_;
    my ($model) = $smart_info =~ /(Device\ Model.*\n)/;
    if ($model) {
        $model =~ s/.*:\ //s;
        $model =~ s/^\s+|\s+$//g;
    }
    return ($model) ? "$disk: $model\n" : "$disk: N/A\n";
}
