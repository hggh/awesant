=head1 NAME

Awesant::Output::Screen - Send messages to the screen.

=head1 SYNOPSIS

    my $log = Awesant::Format::Screen->new(
        send_to => "stdout"
    );

=head1 DESCRIPTION

=head1 OPTIONS

=head2 send_to

Where to send the output.

Possible:

    stderr
    stdout
    null (means /dev/null)

Default: null

=head1 METHODS

=head2 new

Create a new input object.

=head2 push

Push data to STDOUT, STDERR or to C</dev/null>.

=head2 validate

Validate the configuration that is passed to the C<new> constructor.

=head2 log

Just a accessor to the logger.

=head1 PREREQUISITES

    Log::Handler
    Params::Validate

=head1 EXPORTS

No exports.

=head1 REPORT BUGS

Please report all bugs to <support(at)bloonix.de>.

=head1 AUTHOR

Jonny Schulz <support(at)bloonix.de>.

=head1 COPYRIGHT

Copyright (C) 2012 by Jonny Schulz. All rights reserved.

=cut

package Awesant::Output::Screen;

use strict;
use warnings;
use Log::Handler;
use Params::Validate qw();

our $VERSION = "0.2";

sub new {
    my $class = shift;
    my $opts = @_ > 1 ? {@_} : shift;
    my $self = bless $opts, $class;

    if ($self->{send_to} eq "stderr") {
        $self->{fh} = \*STDERR;
    } elsif ($self->{send_to} eq "stdout") {
        $self->{fh} = \*STDOUT;
    } else {
        open my $fh, ">>", "/dev/null";
        $self->{fh} = $fh;
    }

    $self->{log} = Log::Handler->get_logger("awesant");

    return $self;
}

sub push {
    my ($self, $line) = @_;
    my $fh = $self->{fh};

    if ($self->log->is_debug) {
        $self->log->debug("screen output: $line");
    }

    print $fh "$line\n";
}

sub validate {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        send_to => {
            type => Params::Validate::SCALAR,
            default => "null",
            regex => qr/^(?:stdout|stderr|null)\z/,
        },
    });

    return \%options;
}

sub log {
    my $self = shift;

    return $self->{log};
}

1;
