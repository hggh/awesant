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

=head2 queue_durable, queue_exclusive, queue_auto_delete

Value is boolean: true, 1, false, 0

All defaults to false.

=head2 exchange_durable, exchange_auto_delete

Value is boolean: true, 1, false, 0

All defaults to false.

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

=head1 CONFIGURATION

=head2 RabbitMQ

    rabbitmqctl add_user awesant secret
    rabbitmqctl set_permissions "awesant" ".*" ".*" ".*"

=head2 Awesant

    input {
        file {
            type test
            path /var/log/test/test.log
        }
    }

    output {
        rabbitmq {
            type test
            host 127.0.0.1
            user awesant
            password secret
            channel 1
            queue logstash
            queue_exclusive false
            queue_durable false
            queue_auto_delete false
            exchange logstash
            exchange_type direct
            exchange_durable false
            exchange_auto_delete false
        }
    }

=head2 Logstash

    input {
        rabbitmq {
            type => "test"
            user => "awesant"
            password => "secret"
            host => "127.0.0.1"
            queue => "logstash"
            exchange => "logstash"
            exclusive => false
            durable => false
            auto_delete => false
            format => "json_event"
        }
    }

    output {
        file {
            type => "test"
            path => "/var/log/logstash/test.log"
        }
    }

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
        alarm($self->{options}->{timeout} || 10);

        $self->log->notice("connect to rabbitmq $self->{host}:$self->{options}->{port}");

        $self->rmq->connect(
            $self->{host},
            $self->{options}
        );

        $self->log->notice("open channel $self->{channel}");

        $self->rmq->channel_open(
            $self->{channel}
        );

        $self->log->notice(
            "declare exchange $self->{exchange}",
            "type $self->{exchange_type}",
            "durable $self->{exchange_durable}",
            "auto_delete $self->{exchange_auto_delete}",
            "on channel $self->{channel}"
         );

        $self->rmq->exchange_declare(
            $self->{channel},
            $self->{exchange},
            {
                exchange_type => $self->{exchange_type},
                durable => $self->{exchange_durable},
                auto_delete => $self->{exchange_auto_delete}
            }
        );

        $self->log->notice(
            "declare queue $self->{queue}",
            "exclusive $self->{queue_exclusive}",
            "durable $self->{queue_durable}",
            "auto_delete $self->{queue_auto_delete}",
            "on channel $self->{channel}"
        );

        $self->rmq->queue_declare(
            $self->{channel},
            $self->{queue},
            {
                exclusive => $self->{queue_exclusive},
                durable => $self->{queue_durable},
                auto_delete => $self->{queue_auto_delete}
            }
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
            $self->disconnect;
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
        queue_durable => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 0,
        },
        queue_exclusive => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 0,
        },
        queue_auto_delete => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 0,
        },
        exchange => {
            type => Params::Validate::SCALAR,
            default => "logstash"
        },
        exchange_type => {
            type => Params::Validate::SCALAR,
            default => "direct"
        },
        exchange_durable => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 0,
        },
        exchange_auto_delete => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 0,
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

    my %opts = map { $_ => 0 } qw(
        host channel
        queue queue_durable queue_exclusive queue_auto_delete
        exchange exchange_type exchange_durable exchange_auto_delete
    );

    foreach my $key (keys %opts) {
        $opts{$key} = delete $options{$key};
    }

    $opts{options} = \%options;

    foreach my $key (qw/queue_durable queue_exclusive queue_auto_delete exchange_durable exchange_auto_delete/) {
        if ($opts{$key} eq "false") {
            $opts{$key} = 0;
        } elsif ($opts{$key} eq "true") {
            $opts{$key} = 1;
        }
    }

    return \%opts;
}

1;
