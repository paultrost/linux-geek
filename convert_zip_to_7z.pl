#!/usr/bin/perl

use strict;
use warnings;
use File::Path qw(rmtree);

# This script will convert zip files into 7z files. There is no license, it's in the public domain.

# Accept list of names from what is passed to it from the shell
# If filelist is specified (*.zip ?) then exit
if (!@ARGV) {
	die "Please specify a filename(s)\n";
}

# Temp directory that will be used for zip files manipulation
my $tmpdirectory = 'convert_tmp';

# For each file, make the temp firectory, unzip the zip, and archive the 7z
foreach my $file (@ARGV) {
    mkdir $tmpdirectory;
    my ( $filename, $extn ) = split( '.zip', $file );
    $extn = substr( $file , -3 );
    print "Uncompressing $file\n";
    chdir $tmpdirectory;
    qx(unzip "../$file" &>/dev/null);
    die "Could not uncompress $file: $!" if $? != 0;
    print "Compressing $filename.7z\n";
    qx(7z a "$filename.7z" &>/dev/null);
    die "Could not compress $filename: $!" if $? != 0;
    rename "$filename.7z", "../$filename.7z";
    chdir '../';
    print "Removing working directory and $file\n";
    rmtree $tmpdirectory;
    unlink $file;
    print "\n";
}
