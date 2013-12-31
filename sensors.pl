#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: sensors.pl
#
#        USAGE: ./sensors.pl  
#
#  DESCRIPTION: Display output of CPU and System temps 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Paul Trost 
#      VERSION: 1.0
#      CREATED: 09/07/2013 06:55:31 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Hardware::SensorsParser;
use Math::Round;

# TODO

# Add output flag so default behavior is no output
# Add email report if @errors is true

##############################################
# Ensure prerequisite programs are installed #
##############################################

die "Either 'hddtemp' is not installed or the calling user doesn't have execute access to it.\n"
    if ( !-x '/usr/bin/hddtemp' and !-x '/usr/sbin/hddtemp' );

#####################
# Declare variables #
#####################

my @errors;
my @output;
my $cpu_temp_warn   = 65;
my $mb_temp_warn    = 60;
my $drive_temp_warn = 45;

# What drives do you want to monitor temp on?
my @drives = qx(ls /dev/sd*);

######################
# Instantiate object #
######################

my $sensors       = new Hardware::SensorsParser();
my @chipset_names = $sensors->list_chipsets();

#########################
# Process sensor values #
#########################

foreach my $chipset (@chipset_names) {
    my $count_cpu = 0;
    my $count_fan = 0;
    my @sensor_names = $sensors->list_sensors($chipset);
    foreach my $sensor (@sensor_names) {
        # Get CPU temps
        if ( $sensor =~ qr(Core) ) {
            if ($count_cpu == 0) {
                push ( @output, "\n" );
                push ( @output, "CPU/MB Temperature(s)" );
                push ( @output, "---------------------" );
            }
            get_temp( $sensor, $chipset, $sensor, $cpu_temp_warn );
            $count_cpu = 1;
        }
        # Get Motherboard temp
        if ( $sensor =~ qr(M/BTemp) ) {
            get_temp( 'M/B', $chipset, $sensor, $mb_temp_warn );
        }
        if ( $sensor =~ qr(fan) ) {
            if ($count_fan == 0) {
                push ( @output, "Fan Speeds" );
                push ( @output, "----------" );
            }
            get_fan_speed( 'Fan', $chipset, $sensor, $mb_temp_warn );
            $count_fan = 1;
        }
    }
}
#push ( @output, "\n" );

# Get sensor values for drives
push ( @output, "\n" );
push ( @output, "Drive Temperature(s):" );
push ( @output, "---------------------" );
get_drive_temp($_) foreach @drives;

##################
# Display Output #
##################

print "\n";
print join("\n", @output),"\n";

if (@errors) {
    print "\n";
    print join("\n", @errors),"\n";
}

print "\n";

###############
# Subroutines #
###############

sub get_temp {
    my ( $realname, $sensor, $sensorname, $tempwarn ) = @_;
    my $temp_value = $sensors->get_sensor_value( $sensor, $sensorname, 'input' );
    my $temp_c = round($temp_value);
    my $temp_f = round( ( $temp_c * 9 ) / 5 + 32 );
    push( @output, "$realname temperature: ${temp_c} C (${temp_f} F)" );
    push( @errors, "ALERT: $realname temperature is $temp_c!" )
      if ( $temp_c > $tempwarn );
} 

sub get_fan_speed {
    my ( $realname, $sensor, $sensorname ) = @_;
    my $speed_value = round($sensors->get_sensor_value( $sensor, $sensorname, 'input' ));
    return if ( $speed_value == 0 );
    push( @output, "$realname speed: $speed_value RPM" );
}
    
sub get_drive_temp {
    chomp( my $drive = shift );
    chomp( my $temp_c = qx(hddtemp -n $drive --unit=C) );
    # Exit out if drive can't return temperature
    return if $temp_c =~ qr(S.M.A.R.T. not available);

    my $temp_f = round( ( $temp_c * 9 ) / 5 + 32 );
    if ( -e $drive ) {
        push( @output, "$drive temperature: ${temp_c} C (${temp_f} F)" );
        push( @errors, "ALERT: Drive $drive temperature is $temp_c" )
          if $temp_c > $drive_temp_warn;
    }
}
