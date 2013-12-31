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
# Version: 0.2       #
# 2013-07-17         #
######################

use strict;
use warnings;
use File::Path qw(rmtree);

# Accept list of names from what is passed to it from the shell
die "No valid .zip name given, please specify a filename(s)\n"
  if ( !@ARGV or $ARGV[0] =~ /\.7z/ );

die "No .zip files found in directory\n"
  if ( $ARGV[0] =~ /\*.zip/ );

# Temp directory that will be used for zip files manipulation
my $tmpdirectory = 'convert_tmp';

# Verify that any necessary third party programs are installed
die "Aborting, 7zip is not installed!\n"
  if ( !-e '/usr/bin/7z' and !-e '/usr/local/bin/7z' );
die "Aborting, unzip is not installed!\n"
  if ( !-e '/usr/bin/unzip' and !-e '/usr/local/bin/unzip' );

# For each file, make the temp firectory, unzip the zip, and archive the 7z
print "\n";
foreach my $file (@ARGV) {
    mkdir $tmpdirectory;
    my ( $filename, $extn ) = split( '.zip', $file );
    $extn = substr( $file, -3 );
    print "Uncompressing $file\n";
    chdir $tmpdirectory;
    qx(unzip "../$file" &>/dev/null);
    die "Could not uncompress $file: $!" if $? != 0;
    print "Compressing $filename.7z\n";
    qx(7z a "$filename.7z" \* &>/dev/null);
    die "Could not compress $filename: $!" if $? != 0;
    rename "$filename.7z", "../$filename.7z";
    chdir '../';
    print "Removing working directory and $file\n";
    rmtree $tmpdirectory;
    unlink $file;
    print "\n";
}
