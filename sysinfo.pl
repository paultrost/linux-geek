#!/usr/bin/env perl 

use 5.010;
use strict;
use warnings;
use Sys::Hostname;
use File::Which;
use Hardware::SensorsParser;
use Math::Round;
use Sys::Info;
use Sys::Load qw/getload uptime/;
use Time::Duration;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
no if $] >= 5.018, warnings => 'experimental'; # turn off smartmatch warnings

######################
# User set variables #
######################

# Set temp warning thresholds
my $cpu_temp_warn  = 65;
my $mb_temp_warn   = 60;
my $disk_temp_warn = 40;

# What disks do you want to monitor temp on?
# This can be a quoted list like "/dev/sda", "/dev/sdb" as well
my @disks = glob '/dev/*d[a-z]';

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
    my $prog_path = which($prog);
    die "$prog is not installed or is not executable. Please install and run $0 again.\n"
        if ( !$prog_path || !-x $prog_path );
}

##############################################
# Instantiate objects and gather information #
##############################################

my $sensors       = Hardware::SensorsParser->new;
my @chipset_names = $sensors->list_chipsets;

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
        given ($sensor) {
            # Get CPU temps
            when ( /Core/ ) {
                if ( $count_cpu == 0 ) {
                    push @output, "\n";
                    push @output, header('CPU/MB Temperature(s)');
                    push @output, '---------------------';
                }
                my ( $temp_c, $temp_f ) = get_temp( $sensor, $chipset, $sensor );
                push @output, item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
                if ( $temp_c > $cpu_temp_warn ) {
                    push @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)";
                }
                $count_cpu = 1;
            }

            # Get Motherboard temp
            when ( /M\/BTemp/ ) {
                my ( $temp_c, $temp_f ) = get_temp( 'M/B', $chipset, $sensor );
                push @output, item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
                if ( $temp_c > $mb_temp_warn ) {
                    push @errors, "ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)"
                }
            }

            # Get Fan speeds
            when ( /fan/ ) {
                if ( $count_fan == 0 ) {
                    push @output, header('Fan Speeds');
                    push @output, '----------';
                }
                my $speed_value = get_fan_speed( 'Fan', $chipset, $sensor );
                $sensor =~ s/f/F/;
                push @output, item("$sensor speed: ") . value("$speed_value RPM");
                $count_fan = 1;
            }
        }
    }
}

# Get sensor values for disks
push @output, "\n";
push @output, header('Drive Temperature(s) and Status:');
push @output, '---------------------';
my $disk_models;
foreach (@disks) { get_disk_info($_) };

##################
# Display Output #
##################

if ( !$errorsonly ) {
    my $hostname = hostname() . "\n";
    my $os       = get_os() . "\n";
    my $info     = Sys::Info->new;
    my $proc     = $info->device('CPU');
    my $cpu      = scalar $proc->identify . "\n";

    my $memstats = qx( free -m | grep Mem | awk {'print \$2,\$3,\$4,\$5,\$6,\$7'} );
    my ( $m_total, $m_used, $m_free, $m_shared, $m_buffered, $m_cached ) = split ' ', $memstats;
    my $memory = "${m_total}M Total: ${m_used}M Used, ${m_free}M Free, ${m_buffered}M Buffered, ${m_cached}M Cached\n";

    my $swapstats = qx( free -m | grep Swap | awk {'print \$2,\$3,\$4'} );
    my ( $s_total, $s_used, $s_free ) = split ' ', $swapstats;
    my $swap = "${s_total}M Total: ${s_used}M Used, ${s_free}M Free\n";

    my $uptime  = duration( int uptime() ) . "\n";
    my $sysload = ( getload() )[0] . "\n";
    my $disks   = "\n$disk_models";

    print "\n";
    print item('Hostname:      '), value($hostname);
    print item('OS:            '), value($os);
    print item('CPU:           '), value($cpu);
    print item('Memory:        '), value($memory);
    print item('Swap:          '), value($swap);
    print item('System uptime: '), value($uptime);
    print item('System load:   '), value($sysload);
    print item('Disks:         '), value($disks);
    if ( $] < 5.018 ) {  print "\n\n" };    #extra spacing needed for Perl < 5.18
    print join( "\n", @output ), "\n";
    print "\n";
}

if (@errors) {
    print "\n";
    foreach (@errors) { print alert("$_\n") };
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
    my ($temp_c) = $smart_info =~ /(Temperature_Celsius.*\n)/;

    if ($temp_c) {
        chomp $temp_c;
        $temp_c =~ s/ //g;
        $temp_c =~ s/.*-//;
        $temp_c =~ s/\(.*\)//;
    }

    if ( !$temp_c || $smart_info =~ qr/S.M.A.R.T. not available/x ) {
        return 'N/A';
    }
    else {
        my $temp_f = round( ( $temp_c * 9 ) / 5 + 32 );
        return ( $temp_c, $temp_f );
    }
}

sub get_disk_health {
    my $smart_info = shift;
    my ($health) = $smart_info =~ /(SMART overall-health self-assessment.*\n)/;

    if ( defined $health and $health =~ /PASSED|FAILED/x ) {
        $health =~ s/.*result: //;
        chomp $health;
        return $health;
    }
    else {
        return 'N/A';
    }
}

sub get_disk_model {
    my ( $disk, $smart_info ) = @_;
    my ($model) = $smart_info =~ /(Device\ Model.*\n)/;
    if ( defined $model ) {
        $model =~ s/.*:\ //;
        $model =~ s/^\s+|\s+$//g;
    }
    return ($model) ? "$disk: $model\n" : "$disk: N/A\n";
}

sub get_disk_info {
    my $disk = shift;
    chomp $disk;

    my $smart_info  = qx(smartctl -a $disk);
    my $disk_health = get_disk_health($smart_info);
    $disk_models .= get_disk_model( $disk, $smart_info );

    my ( $temp_c, $temp_f ) = get_disk_temp($smart_info);
    if ( $temp_c !~ 'N/A' ) {
        push @output, item("$disk Temperature: ") . value("${temp_c} C (${temp_f} F) ") . item('Health: ') . value($disk_health);
        if ( -e $disk and $temp_c > $disk_temp_warn ) {
            push @errors, "ALERT: $disk temperature threshold exceeded, $temp_c C (${temp_f} F)";
        }
        if ( $disk_health !~ 'PASSED' ) {
            push @errors, "ALERT: $disk may be dying, S.M.A.R.T. status: $disk_health";
        }
    }
    else {
        push @output, item("$disk Temperature: ") . value('N/A ') . item('Health: ') . value($disk_health);
    }
    return;
}

sub get_os {
    chomp( my $release = qx(lsb_release -d) );
    chomp( my $kernel  = qx(uname -r) );
    ( undef, $release ) = split /:/, $release;
    $release =~ s/^\s+//s;

    return "$release | Kernel: $kernel";
}


=pod

=head1 NAME

 sysinfo.pl

=head1 VERSION

 0.9.9

=head1 USAGE

 sysinfo.pl [options]

=head1 DESCRIPTION

 Gather information from system sensors, and S.M.A.R.T. drive statuses.

=head1 OPTIONS

 -errorsonly            Only display error output
 -nocolor               Do not display output in color, useful for running through cron

=head1 AUTHOR

 Paul Trost <paul.trost@trostfamily.org>

=head1 LICENSE AND COPYRIGHT
  
 Copyright 2014.
 This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License v2, or at your option any later version.
 <http://gnu.org/licenses/gpl.html>

=cut
