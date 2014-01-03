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
die "No valid .7z name given, please specify a filename(s)\n"
  if ( !@ARGV or $ARGV[0] =~ /\.zip/ );

die "No .zip files found in directory\n"
  if ( $ARGV[0] =~ /\*.zip/ );

# Temp directory that will be used for zip files manipulation
my $tmpdirectory = 'convert_tmp';

# Verify that any necessary third party programs are installed
die "Aborting, 7zip is not installed!\n"
  if ( !-e '/usr/bin/7z' and !-e '/usr/local/bin/7z' );
die "Aborting, zip is not installed!\n"
  if ( !-e '/usr/bin/zip' and !-e '/usr/local/bin/zip' );

# For each file, make the temp firectory, unzip the zip, and archive the 7z
print "\n";
foreach my $file (@ARGV) {
    mkdir $tmpdirectory;
    my ( $filename, $extn ) = split( '.7z', $file );
    $extn = substr( $file, -2 );
    print "Uncompressing $file\n";
    chdir $tmpdirectory;
    qx(7z x "../$file" &>/dev/null);
    die "Could not uncompress $file: $!" if $? != 0;
    print "Compressing $filename.zip\n";
    qx(zip -9 -q -r "$filename.zip" \*);
    die "Could not compress $filename: $!" if $? != 0;
    chomp( my $file_ok = qx(zip -T "$filename.zip") );
    die "$filename.zip failed verification" if $file_ok !~ /test of.*OK/;
    print "$file_ok\n";
    rename "$filename.zip", "../$filename.zip";
    chdir '../';
    print "Removing working directory and $file\n";
    rmtree $tmpdirectory;
    unlink $file;
    print "\n";
}
