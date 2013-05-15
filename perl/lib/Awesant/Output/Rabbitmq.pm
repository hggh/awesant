=head1 NAME

Awesant::Output::Rabbitmq - Send messages to a RabbitMQ server.

=head1 SYNOPSIS

    my $output = Awesant::Output::Rabbitmq->new(
        host => "127.0.0.1",
        user => "logstash",
        password => "secret",
        channel => 1,
        queue => "logstash"
    );

    $output->push($line);

=head1 DESCRIPTION

This transport module connects and shipts log data to RabbitMQ.

=head1 OPTIONS

=head2 host

The hostname or ip address of the RabbitMQ server.

Default: 127.0.0.1

=head2 port

The port number where the RabbitMQ server is listen on.

Default: 5672

=head2 timeout

The timeout in seconds to connect and transport data to the RabbitMQ server.

Default: 10

=head2 user, password

The username and password to use for authentication.

Default: guest/guest

=head2 queue

The queue to transport the data.

Default: logstash

=head2 channel

channel is a positive integer describing the channel you which to open.

Default: 1

=head2 vhost

See http://www.rabbitmq.com/uri-spec.html for more information.

Default: /

=head2 heartbeat, frame_max, channel_max

See http://search.cpan.org/~jesus/Net--RabbitMQ/RabbitMQ.pm and
http://www.rabbitmq.com/ for more information.

Default: defaults from http://search.cpan.org/~jesus/Net--RabbitMQ/RabbitMQ.pm

=head1 METHODS

=head2 new

Create a new output object.

=head2 connect

Connect to the RabbitMQ server.

=head2 push

Push data to redis via LPUSH command.

=head2 validate

Validate the configuration that is passed to the C<new> constructor.

=head2 log

Just a accessor to the logger.

=head1 PREREQUISITES

    Net::RabbitMQ
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

package Awesant::Output::Rabbitmq;

use strict;
use warnings;
use Log::Handler;
use Net::RabbitMQ;
use Params::Validate qw();
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw/log rmq/);

sub new {
    my $class = shift;
    my $opts = $class->validate(@_);
    my $self = bless $opts, $class;

    $self->{log} = Log::Handler->get_logger("awesant");
    $self->{rmq} = Net::RabbitMQ->new();

    $self->{__alarm_sub} = sub {
        alarm(0);
    };

    $self->{__timeout_sub} = sub {
        die join(" ",
            "connection to rabbitmq",
            "$self->{host}:$self->{options}->{port}",
            "timed out after $self->{options}->{timeout} seconds",
        );
    };

    $self->log->notice("$class initialized");
    return $self;
}

sub connect {
    my $self = shift;

    if ($self->{connected}) {
        return $self->{rmq};
    }

    eval {
        local $SIG{ALRM} = $self->{__timeout_sub};
        local $SIG{__DIE__} = $self->{__alarm_sub};
        alarm($timeout);

        $self->rmq->connect(
            $self->{host},
            $self->{options}
        );

        $self->rmq->open_channel(
            $self->{channel}
        );

        alarm(0);
    };

    if ($@) {
        $self->log->error($@);
        return undef;
    }

    $self->{connected} = 1;
    return 1;
}

sub push {
    my ($self, $line) = @_;
    my $channel = $self->{channel};
    my $queue = $self->{queue};
    my $options = $self->{options};
    my $timeout = $options->{timeout} || 10;

    $self->connect
        or return undef;

    eval {
        local $SIG{ALRM} = $self->{__timeout_sub};
        local $SIG{__DIE__} = $self->{__alarm_sub};
        alarm($timeout);
        $self->rmq->publish($channel, $queue, $line);
        alarm(0);
    };

    if ($@) {
        # Unfortunately it's not possible to determine why the
        # message couldn't be send to rabbitmq. For this reason
        # the connection is marked as lost.
        $self->{connected} = 0;
        $self->log->error(
            "unable to publish message to rabbitmq",
            "$self->{host}:$self->{options}->{port}"
        );
        eval {
            local $SIG{ALRM} = sub { die "disconnect timeout" };
            local $SIG{__DIE__} = sub { alarm(0) };
            alarm(3);
            $self->disconnect
            alarm(0);
        };
        return undef;
    }

    return 1;
}

sub validate {
    my $class = shift;

    my %options = Params::Validate::validate(@_, {
        host => {
            type => Params::Validate::SCALAR,
            default => "127.0.0.1",
        },
        port => {
            type => Params::Validate::SCALAR,
            default => 5672,
        },
        timeout => {
            type => Params::Validate::SCALAR,
            default => 10,
            regex => qr/^[1-9]\d*\z/,
        },
        user => {
            type => Params::Validate::SCALAR,
            default => "guest",
        },
        password => {
            type => Params::Validate::SCALAR,
            default => "guest",
        },
        channel => {
            type => Params::Validate::SCALAR,
            default => 1,
            regex => qr/^\d+\z/,
        },
        queue => {
            type => Params::Validate::SCALAR,
            default => "logstash"
        },
        vhost => {
            type => Params::Validate::SCALAR,
            default => "/",
        },
        heartbeat => {
            type => Params::Validate::SCALAR,
            optional => 1,
            regex => qr/^\d+\z/,
        },
        frame_max => {
            type => Params::Validate::SCALAR,
            optional => 1,
            regex => qr/^\d+\z/,
        },
        channel_max => {
            type => Params::Validate::SCALAR,
            optional => 1,
            regex => qr/^\d+\z/,
        },
    });

    my $host = delete $options{host};
    my $channel = delete $options{channel};
    my $queue = delete $options{queue};

    return {
        host => $host,
        channel => $channel,
        queue => $queue,
        options => \%options
    };
}

1;
