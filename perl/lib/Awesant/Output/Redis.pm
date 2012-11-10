=head1 NAME

Awesant::Output::Redis - Send messages to a Redis database.

=head1 SYNOPSIS

    my $output = Awesant::Output::Redis->new(
        server => "127.0.0.1",
        port => 6379,
        timeout => 20,
        database => 0,
        password => "secret",
    );

    $output->push($line);

=head1 DESCRIPTION

This transport module connects to a Redis database and ships data via LPUSH.

=head1 METHODS

=head2 new

Create a new output object.

=head3 Options

=over 4

=item server

The hostname or ip address of the Redis server.

Default: 127.0.0.1

=item port

The port number where the Redis server is listen on.

Default: 6379

=item timeout

The timeout in seconds to connect and transport data to the Redis server.

Default: 10

=item database

The database to select.

Default: 0

=item password

The password to use for authentication.

Default: not set

=item key

The key is mandatory and is used to transport the data. This key is necessary
for logstash to pull the data from the Redis database.

=back

=head2 connect

Connect to the redis database.

=head2 push

Push data to redis via LPUSH command.

=head2 validate

Validate the configuration that is passed to the C<new> constructor.

=head2 log

Just a accessor to the logger.

=head1 PREREQUISITES

    IO::Socket::INET
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

package Awesant::Output::Redis;

use strict;
use warnings;
use IO::Socket::INET;
use Log::Handler;
use Params::Validate qw();

our $VERSION = "0.1";

sub new {
    my $class = shift;
    my $opts = $class->validate(@_);
    my $self = bless $opts, $class;

    $self->{select_database} = join("\r\n",
        '*2', # SELECT + db
        '$6',
        'SELECT',
        '$' . length($self->{database}),
        $self->{database} . "\r\n"
    );

    if ($self->{password}) {
        $self->{auth_client} = join("\r\n",
            '*2', # AUTH + password
            '$4',
            'AUTH',
            '$' . length($self->{password}),
            $self->{password},
        );
    }

    $self->{log} = Log::Handler->get_logger("awesant");

    return $self;
}

sub connect {
    my $self = shift;

    if ($self->{sock}) {
        return $self->{sock};
    }

    $self->log->notice("connect to $self->{server}:$self->{port}");

    $self->{sock} = IO::Socket::INET->new(
        PeerAddr => $self->{server},
        PeerPort => $self->{port},
        Proto    => "tcp",
    );

    if ($self->{sock}) {
        $self->{sock}->autoflush(1);

        $self->log->notice("connected to $self->{server}:$self->{port}");

        $self->_send($self->{select_database})
            or die "unable to select redis database";

        return $self->{sock};
    }

    $self->log->error("unable to create socket - $!");
    return undef;
}

sub push {
    my ($self, $line) = @_;
    my $timeout = $self->{timeout};
    my $ret = 0;

    $line = join("\r\n",
        '*3', # LPUSH + key + line
        '$5',
        'LPUSH',
        '$' . length $self->{key},
        $self->{key},
        '$' . length $line,
        $line . "\r\n"
    );

    $ret = $self->_send($line);

    return $ret;
}

sub validate {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        server => {
            type => Params::Validate::SCALAR,
            default => "127.0.0.1",
        },
        port => {
            type => Params::Validate::SCALAR,  
            default => 6379,
        },
        timeout => {  
            type => Params::Validate::SCALAR,  
            default => 10,
        },
        database => {  
            type => Params::Validate::SCALAR,  
            default => 0,
        },
        password => {  
            type => Params::Validate::SCALAR,  
            optional => 1,
        },
        key => {
            type => Params::Validate::SCALAR,
        },
    });

    return \%options;
}

sub log {
    my $self = shift;

    return $self->{log};
}

sub _send {
    my ($self, $data) = @_;

    my $sock = $self->connect
        or return undef;

    my $rest = length($data);
    my $offset = 0;

    if ($self->log->is_debug) {
        $self->log->debug("redis output: $data");
    }

    while ($rest) {
        my $written = syswrite $sock, $data, $rest, $offset;

        if (!defined $written) {
            $self->log->error("system write error: $!");
            $self->{sock} = undef;
            return undef;
        }

        $rest -= $written;
        $offset += $written;
    }

    my $response = <$sock>;

    if (!defined $response) {
        $self->log->error("lost connection to server $self->{server}:$self->{port}");
        $self->{sock} = undef;
        return undef;
    }

    if ($response !~ /^(:\d+|\+OK)\r\n/) {
        $self->log->error("unknown response from server: $response");
        $self->{sock} = undef;
        return undef;
    }

    return 1;
}

1;
