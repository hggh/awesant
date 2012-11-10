=head1 NAME

Awesant::Input::File - Files as input.

=head1 SYNOPSIS

    # Create a new tail-like object.
    my $input = Awesant::Input::File->new(
        path => "/var/log/messages",
        save_position => "yes", # experimental
    );

    # Pull the next 100 lines that was appended
    # to the log file.
    $input->pull(lines => 100);

=head1 DESCRIPTION

This module is just for internal usage.

=head1 OPTIONS

=head2 path

The path to the log file.

=head2 save_position

Experimental feature.

If the option save_position is set to true then the last position
of the log file is saved to a file. The inode and the byte position
is stored. If Awesant is down then it can resume its works where it
was stopped. This is useful if you don't want to lose less data as
possible of your log files.

Please note that this feature is experimental and does not keep log file
rotations if the agent was down and restarted. If the inode is the same
that was stored then it can jump the last read byte position.

=head1 METHODS

=head2 new

Create a new input object.

=head2 get_lastpos

Get the last position if the option C<save_position> is true.

=head2 open_logfile

Open the log file and store the inode for later checks.

=head2 check_logfile

This method just checks if the inode has changed of the currently opened
file and the file that is found on the file system. If logrotate moved
the file, then the inode changed. In this case the rotated file is read
until its end and then the file will be closed to re-open the new file
on the file system.

=head2 pull(lines => $number)

This methods reads the excepted number of lines or until the end of the
file and returns the lines as a array reference.

=head2 validate

Validate the configuration that is passed to the C<new> constructor.

=head2 log

Just a accessor to the logger.

=head1 PREREQUISITES

    Fcntl
    Params::Validate
    Log::Handler

=head1 EXPORTS

No exports.

=head1 REPORT BUGS

Please report all bugs to <support(at)bloonix.de>.

=head1 AUTHOR

Jonny Schulz <support(at)bloonix.de>.

=head1 COPYRIGHT

Copyright (C) 2012 by Jonny Schulz. All rights reserved.

=cut


package Awesant::Input::File;

use strict;
use warnings;
use Fcntl qw( :flock O_WRONLY O_CREAT O_RDONLY );
use Params::Validate qw();
use Log::Handler;

our $VERSION = "0.1";

sub new {
    my $class = shift;
    my $opts = $class->validate(@_);
    my $self = bless $opts, $class;

    $self->{log} = Log::Handler->get_logger("awesant");
    $self->{reached_end_of_file} = 0;
    $self->get_lastpos;
    $self->open_logfile;

    return $self;
}

sub get_lastpos {
    my $self = shift;
    my $file = $self->{path};
    my $libdir = $self->{libdir};
    my $inode = "";

    $self->{lastpos} = (stat($file))[7];

    if (!$self->{save_position}) {
        return;
    }

    my $basename = do { $self->{path} =~ m!([^\\/]+)\z!; $1 };
    my $posfile = "$libdir/awesant-$basename.pos";

    if (-e $posfile) {
        $self->log->debug("read last position from $posfile");
        open my $fh, "<", $posfile or die "unable to open '$posfile' for reading - $!";
        my $line = <$fh>;
        my ($inode, $lastpos) = split /:/, $line;

        if (defined $inode && defined $lastpos && $inode =~ /^\d+\z/ && $lastpos =~ /^\d+\z/) {
            $inode =~ s/^0+//;
            $lastpos =~ s/^0+//;

            if ((stat($file))[1] eq $inode) {
                $self->{lastpos} = $lastpos;
            }
        }

        close $fh;
    }

    $self->log->debug("last position $self->{lastpos}");
    $self->log->debug("open '$posfile' for writing");
    sysopen my $fhpos, $posfile, O_CREAT | O_WRONLY
        or die "unable to open '$posfile' for writing - $!";

    # autoflush
    my $oldfh = select $fhpos;
    $| = $self->{autoflush};
    select $oldfh;

    # save the file handle for later usage
    $self->{fhpos} = $fhpos;
}

sub open_logfile {
    my $self = shift;
    my $file = $self->{path};
    my $fhlog = $self->{fhlog};

    if ($fhlog && $self->check_logfile) {
        return $fhlog;
    }

    $self->log->info("open '$file' for reading");

    open $fhlog, "<", $file or do {
        $self->log->error("unable to open logfile '$file' for reading - $!");
        return undef;
    };

    # Store the inode for the logfile to check
    # later if the inode changed because logrotate
    # moves the file.
    $self->{inode} = (stat($file))[1];
    $self->log->debug("stored inode $self->{inode} for file '$file'");

    # If fhlog is already set then we just reopen the next
    # file and jump to the start of the file, otherwise
    # a log file wasn't opened before and we jump to the
    # position of get_lastpos
    if ($self->{fhlog}) {
        $self->{lastpos} = 0;
    }

    $self->log->info("seek to position $self->{lastpos} of file '$file'");
    seek($fhlog, $self->{lastpos}, 0);
    $self->{fhlog} = $fhlog;
    return $fhlog;
}

sub check_logfile {
    my $self  = shift;
    my $file  = $self->{path};
    my $inode = $self->{inode};
    my $fhlog = $self->{fhlog};

    # If the logfile is rotated but not finished then the logfile
    # shouldn't be closed, otherwise we will miss some lines...
    if ($self->{reached_end_of_file} == 0) {
        #$self->log->debug("skip check logfile - reached_end_of_file=$self->{reached_end_of_file}");
        return 1;
    }

    # Clean up the eof marker
    $self->{reached_end_of_file} = 0;

    # Check if the logfile exists.
    if (!-e $file) {
        $self->log->debug("the log file '$file' does not exists any more");
        close $fhlog;
        return 0;
    }

    # Check if the inode has changed, because it's possible
    # that logrotate.d rotates the log file.
    if ($inode != (stat($file))[1]) {
        $self->log->debug("inode of file '$file' changed - closing file handle");
        close $fhlog;
        return 0;
    }

    # Check if the the current position where the log file was
    # read is higher than the file size. It's possible that
    # the logfile was flushed.
    if ((stat($file))[7] < $self->{lastpos}) {
        $self->log->debug("the size of file '$file' shrinks - seeking back");
        seek($fhlog, 0, 0);
        $self->{lastpos} = 0;
    } 

    return 1;
}

sub pull {
    my ($self, %opts) = @_;

    local $SIG{PIPE} = "IGNORE";

    my $max_lines = $opts{lines} || 1;
    my $lines = [ ];
    my $fhpos = $self->{fhpos};
    my $fhlog = $self->open_logfile or return $lines;

    while (my $line = <$fhlog>) {
        chomp $line;
        push @$lines, $line;

        if ($self->{fhpos}) {
            $self->{lastpos} = tell($fhlog);
            seek($fhpos, 0, 0);
            printf $fhpos "%014d:%014d", $self->{inode}, $self->{lastpos};
        }

        #$self->log->debug("read", length($line), "bytes from file");
        last unless --$max_lines;
    }

    # Store the last position
    $self->{lastpos} = tell($fhlog);

    # If EOF is reached then the logfile should be
    # checked if the file was rotated.
    if ($max_lines > 0) {
        $self->log->debug("reached end of file");
        $self->{reached_end_of_file} = 1;
    }

    return $lines;
}

sub validate {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        libdir => {
            type => Params::Validate::SCALAR,
            default => "/var/lib/awesant",
        },
        save_position => {
            type => Params::Validate::SCALAR,
            default => 0,
            regex => qr/^(?:yes|no|1|0)\z/,
        },
        path => {
            type => Params::Validate::SCALAR,
        },
    });

    if ($options{save_position} eq "no") {
        $options{save_position} = 0;
    }

    return \%options;
}

sub log {
    my $self = shift;

    return $self->{log};
}

1;
