#!/usr/bin/env perl 

use 5.010;
use strict;
use warnings;
use Sys::Hostname;
use Linux::Distribution qw(distribution_name distribution_version);
use File::Which;
use Hardware::SensorsParser;
use Sys::Info;
use Sys::Load qw/getload uptime/;
use Time::Duration;
use Term::ANSIColor qw(:constants);
use Math::Round;
use Disk::SMART;
$Term::ANSIColor::AUTORESET = 1;
no if $] >= 5.018, warnings => 'experimental'; # turn off smartmatch warnings

######################
# User set variables #
######################

# Set temp warning thresholds
my $cpu_temp_warn  = 65;
my $mb_temp_warn   = 60;
my $disk_temp_warn = 40;

#######################################
# Stop if not called as the root user #
#######################################

die "This script has to be run as root!\n" if ( $> != 0 );

###################################
# Set list of disks on the system #
###################################

chomp( my @disks = glob '/dev/*d[a-z]' );
my $smart = Disk::SMART->new(@disks);

#***************************************#
# NOTHING BELOW HERE SHOULD BE CHANGED! #
#***************************************#

###############################################
# Set flag if -errorsonly option is specified #
###############################################

my $errorsonly = ( /-errorsonly/ ~~ @ARGV ) ? 1 : 0;
my $color      = ( /-nocolor/    ~~ @ARGV ) ? 0 : 1;

##############################################
# Ensure prerequisite programs are installed #
##############################################

my @required_progs = qw(smartctl);
foreach my $prog (@required_progs) {
    my $prog_path = which($prog);
    die "$prog is not installed or is not executable. Please install and run $0 again.\n"
        if ( !$prog_path || !-x $prog_path );
}

####################################################
# Setup file handles for logging output and errors #
####################################################

open( my $output, '>', \ my $sensors_out) or die "$!\n";
open( my $errors, '>', \ my $err_out) or die "$!\n";

#########################
# Process sensor values #
#########################

my $sensors = Hardware::SensorsParser->new;

# Get sensors values for CPU/fans
foreach my $chipset ( $sensors->list_chipsets ) {
    my $count_cpu = 0;
    my $count_fan = 0;
    my @sensor_names = sort( $sensors->list_sensors($chipset) );
    foreach my $sensor (@sensor_names) {
        given ($sensor) {
            # Get CPU temps
            when ( /Core/ ) {
                if ( $count_cpu == 0 ) {
                    print {$output} "\n";
                    print {$output} header('CPU/MB Temperature(s)');
                    print {$output} "---------------------\n";
                }
                my ( $temp_c, $temp_f ) = get_temp( $sensor, $chipset, $sensor );
                print {$output} item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
                if ( $temp_c > $cpu_temp_warn ) {
                    print {$errors} alert("ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)");
                }
                $count_cpu = 1;
            }

            # Get Motherboard temp
            when ( /M\/BTemp/ ) {
                my ( $temp_c, $temp_f ) = get_temp( 'M/B', $chipset, $sensor );
                print {$output} item("$sensor temperature: ") . value("${temp_c} C (${temp_f} F)");
                if ( $temp_c > $mb_temp_warn ) {
                    print {$errors} alert("ALERT: $sensor temperature threshold exceeded, $temp_c C (${temp_f} F)");
                }
            }

            # Get Fan speeds
            when ( /fan/ ) {
                if ( $count_fan == 0 ) {
                    print {$output} header('Fan Speeds');
                    print {$output} "----------\n";
                }
                my $speed_value = get_fan_speed( 'Fan', $chipset, $sensor );
                $sensor =~ s/f/F/;
                print {$output} item("$sensor speed: ") . value("$speed_value RPM");
                $count_fan = 1;
            }
        }
    }
}

# Get sensor values for disks
print {$output} "\n";
print {$output} header('Drive Temperature(s) and Status:');
print {$output} "-------------------------------\n";
my $disk_models;
foreach my $disk (@disks) {
    my $disk_health = $smart->get_disk_health($disk);
    $disk_models .= $smart->get_disk_model($disk) . "\n";

    my ( $temp_c, $temp_f ) = $smart->get_disk_temp($disk);
    if ( $temp_c !~ 'N/A' ) {
        print {$output} item("$disk Temperature: ") . value("${temp_c} C (${temp_f} F) ", 0);
        print {$output} item('Health: ') . value($disk_health);
        if ( -e $disk and $temp_c > $disk_temp_warn ) {
            print {$errors} alert("ALERT: $disk temperature threshold exceeded, $temp_c C (${temp_f} F)");
        }
        if ( $disk_health !~ 'PASSED' ) {
            print {$errors} alert("ALERT: $disk may be dying, S.M.A.R.T. status: $disk_health");
        }
    }
    else {
        print {$output} item("$disk Temperature: ") . value( 'N/A ', 0 );
        print {$output} item('Health: ') . value($disk_health);
    }
}

close $output;
close $errors;

##################
# Display Output #
##################

if ( !$errorsonly ) {
    my $hostname = hostname();
    my $os       = get_os();
    my $info     = Sys::Info->new;
    my $proc     = $info->device('CPU');
    my $cpu      = scalar $proc->identify;

    my ( $m_total, $m_used, $m_free, $m_shared, $m_buffered, $m_cached, $s_total, $s_used, $s_free ) = get_mem_stats();
    my $memory = "${m_total}M Total: ${m_used}M Used, ${m_free}M Free, ${m_buffered}M Buffered, ${m_cached}M Cached";
    my $swap   = "${s_total}M Total: ${s_used}M Used, ${s_free}M Free";

    my $uptime  = duration( int uptime() );
    my $sysload = ( getload() )[0];
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
    print "$sensors_out\n";
}

if ($err_out) { print "$err_out\n" };

###############
# Subroutines #
###############

sub item {
    my $text = shift;
    return ($color) ? BOLD GREEN $text : $text;
}

sub value {
    my ( $text, $newline ) = @_;
    $newline //= 1;
    if ($newline) { $text .= "\n" };
    return ($color) ? BOLD YELLOW $text : $text;
}

sub alert {
    my $text = shift;
    $text .= "\n";
    return ($color) ? BOLD RED $text : $text;
}

sub header {
    my $text = shift;
    $text .= "\n";
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
    return ( $speed_value ne '0' ) ? $speed_value : 'N/A';
}

sub get_os {
    my $linux   = Linux::Distribution->new;
    my $distro  = ucfirst $linux->distribution_name();
    my $version = $linux->distribution_version();
    $version =~ s/^\s+|\s+$//g; #trim beginning and ending whitepace

    open( my $kernel_out, '-|', 'uname -r' ) or die "uname command could not be executed\n";
    chomp( my $kernel = <$kernel_out> );
    close $kernel_out;

    open( my $arch_out, '-|', 'uname -i' ) or die "uname command could not be executed\n";
    chomp( my $arch = <$arch_out> );
    close $arch_out;

    return "Distro: $distro $version | Arch: $arch | Kernel: $kernel";
}

sub get_mem_stats {
    open( my $stats_out, '-|', 'free -m' ) or die "free command could not be executed\n";
    my @raw_stats = <$stats_out>;
    close $stats_out;

    my @stats_processed;
    my @stats_lines;
    foreach my $line (@raw_stats) {
        next if $line !~ /Mem|Swap/;
        chomp $line;
        @stats_lines = split( /\s* /, $line );
        foreach (@stats_lines) {
            if ($_ =~ /[0-9]/ ) { push @stats_processed, $_ };
        }
    }
    return @stats_processed;
}


=pod

=head1 NAME

 sysinfo.pl

=head1 VERSION

 1.3.1

=head1 USAGE

 sysinfo.pl [options]

=head1 DESCRIPTION

 Gather information from system sensors to display CPU temperatures and fan RPMs. Also display S.M.A.R.T. capable drive statuses.

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
