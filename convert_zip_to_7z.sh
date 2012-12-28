#!/bin/bash

# This script will convert zip files into 7z files. There is no license, it's in the public domain.

# Accept list of names from what is passed to it from the shell
# If filelist is specified (*.zip ?) then exit
if [ ! "$@" ]; then
    echo "Please specify a filename(s)"
    exit 1
fi

# Temp directory that will be used for zip files manipulation
TempDirectory="converttmp"

# For each file, make the temp firectory, unzip the zip, and archive the 7z
for file in "$@"; do
    mkdir -p "${TempDirectory}"
    # Get file name
    # See http://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
    # 1st answer
    filename=$(basename "$file")
    extension="${filename##*.}"
    filename="${filename%.*}"
    cd "$TempDirectory"
    echo "Uncompressing $file"
    unzip "../${file}" &> /dev/null
    echo "Compressing $filename.7z"
    7z a "${filename}".7z * &> /dev/null
    mv *.7z ../
    cd ../
    echo "Removing working directory and $file"
    rm -rf "${TempDirectory}"
    rm -f "$file"
    echo
done
