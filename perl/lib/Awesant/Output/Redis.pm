=head1 NAME

Awesant::Output::Redis - Send messages to a Redis database.

=head1 SYNOPSIS

    my $output = Awesant::Output::Redis->new(
        host => "127.0.0.1",
        port => 6379,
        timeout => 20,
        database => 0,
        password => "secret",
    );

    $output->push($line);

=head1 DESCRIPTION

This transport module connects to a Redis database and ships data via LPUSH.

=head1 OPTIONS

=head2 host

The hostname or ip address of the Redis server. It's possible to pass a comma separated list of hosts.

    redis {
        host active-server, failover-server-1, failover-server-2
        port 6379
    }

Default: 127.0.0.1

=head2 port

The port number where the Redis server is listen on.

Default: 6379

=head2 timeout

The timeout in seconds to connect and transport data to the Redis server.

Default: 10

=head2 database

The database to select.

Default: 0

=head2 password

The password to use for authentication.

Default: not set

=head2 key 

The key is mandatory and is used to transport the data. This key is necessary for logstash to pull the data from the Redis database.

Default: not set

=head1 METHODS

=head2 new

Create a new output object.

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
            $self->{password} . "\r\n"
        );
    }

    $self->{log} = Log::Handler->get_logger("awesant");

    $self->{__alarm_sub} = sub {
        alarm(0);
    };

    $self->{__timeout_sub} = sub {
        die join(" ",
            "connection to any redis server",
            "timed out after $self->{timeout} seconds",
        );
    };

    $self->log->notice("$class initialized");
    return $self;
}

sub connect {
    my $self = shift;

    if ($self->{sock}) {
        return $self->{sock};
    }

    my $hosts = $self->{hosts};
    my @order = @$hosts;

    while (my $host = shift @order) {
        push @$hosts, shift @$hosts;
        $self->{host} = $host;

        $self->log->notice("connect to redis server $host:$self->{port}");

        $self->{sock} = IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $self->{port},
            Proto    => "tcp",
        );

        if (!$self->{sock}) {
            $self->log->error("unable to connect to redis server $host:$self->{port} - $!");
            next;
        }

        $self->{sock}->autoflush(1);

        $self->log->notice("connected to redis server $host:$self->{port}");

        if ($self->{password}) {
            $self->log->notice("send auth to redis server $host:$self->{port}");

            $self->_send($self->{auth_client})
                or die "unable to auth at redis database";
        }

        $self->log->notice(
            "select database $self->{database} on",
            "redis server $host:$self->{port}"
        );

        $self->_send($self->{select_database})
            or die "unable to select redis database";

        $self->log->notice(
            "successfully selected database $self->{database}",
            "on redis server $host:$self->{port}",
        );

        return $self->{sock};
    }

    return undef;
}

sub push {
    my ($self, $line) = @_;
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
        host => {
            type => Params::Validate::SCALAR | Params::Validate::ARRAYREF,
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

    $options{host} =~ s/\s//g;
    $options{hosts} = [ split /,/, $options{host} ];

    return \%options;
}

sub log {
    my $self = shift;

    return $self->{log};
}

sub _send {
    my ($self, $data) = @_;

    my $timeout  = $self->{timeout};
    my $response = "";

    eval {
        local $SIG{ALRM} = $self->{__timeout_sub};
        local $SIG{__DIE__} = $self->{__alarm_sub};
        alarm($timeout);

        my $sock = $self->connect
            or die "unable to connect to any redis server";

        my $rest = length($data);
        my $offset = 0;

        if ($self->log->is_debug) {
            $self->log->debug("send to redis server $self->{host}:$self->{port}: $data");
        }

        while ($rest) {
            my $written = syswrite $sock, $data, $rest, $offset;

            if (!defined $written) {
                die "system write error: $!\n";
            }

            $rest -= $written;
            $offset += $written;
        }

        $response = <$sock>;
        alarm(0);
    };

    if (!$@ && defined $response && $response =~ /^(:\d+|\+OK)/) {
        return 1;
    }

    if ($@) {
        $self->log->error($@);
    } elsif (!defined $response) {
        $self->log->error("no response received from redis server $self->{host}:$self->{port}");
    } elsif ($response =~ /^\-ERR/) {
        $self->log->error("redis server returns an error: $response");
    } else {
        $self->log->error("unknown response from redis server: $response");
    }

    # Reset the complete connection.
    if ($self->{sock}) {
        close($self->{sock});
        $self->{sock} = undef;
    }

    return undef;
}

1;
