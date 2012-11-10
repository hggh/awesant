# Awesant::Input::File

## Options

### path

The path to the log file.

### save_position

Experimental feature.

If the option save_position is set to true then the last position
of the log file is saved to a file. The inode and the byte position
is stored. If Awesant is down then it can resume its works where it
was stopped. This is useful if you don't want to lose less data as
possible of your log files.

Please note that this feature is experimental and does not keep log file
rotations if the agent was down and restarted. If the inode is the same
that was stored then it can jump the last read byte position.

