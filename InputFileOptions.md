# Awesant::Input::File

## Description

Log files as input. Log file rotation is supported, but note that
you should configure delayed compression for log files.

## Options

### path

The path to the log file.

### save_position

Experimental feature.

If the option save_position is set to true then the last position
with the inode of the log file is saved to a file. If Awesant is down
then it can resume its work where it was stopped. This is useful if you
want to lose as less data as possible of your log files.

Please note that this feature is experimental and does not keep log file
rotations.

