=head1 NAME

Awesant::Output::Gelf - Send messages GELF messages to Graylog2 server.

=head1 SYNOPSIS

    my $output = Awesant::Output::Gelf->new(
        host => "127.0.0.1",
        port => 12201,
        timeout => 10,
    );

    $output->push($line);

=head1 DESCRIPTION

This transport module connects to a Graylog2 server and send messages via udp.

=head1 OPTIONS

=head2 host

The hostname or ip address of the Graylog2 server.

    gelf {
        host graylog2-server
        port 12201
    }

Default: 127.0.0.1

=head2 port

The port number where the Graylog2 server GELF input is listen on.

Default: 12201

=head2 gzip

If gzip is set to false, GELF messages are not compressed before sending.

Default: true

=head2 source

Override default hostname from Awesant with the one.

Default: not set

=head2 facility

Facility for send to Graylog2

Default: syslog

=head2 timeout

The timeout in seconds to connect and transport data to the Graylog2 server.

Default: 10

=head1 METHODS

=head2 new

Create a new output object.

=head2 connect

Connect to the Graylog2 server.

=head2 push

Push data to Graylog2.

=head2 validate

Validate the configuration that is passed to the C<new> constructor.

=head2 log

Just a accessor to the logger.

=head1 PREREQUISITES

    IO::Socket::INET
    IO::Compress::Gzip
    Log::Handler
    Params::Validate
    JSON

=head1 EXPORTS

No exports.

=head1 REPORT BUGS

Please report all bugs to <jonas@brachium-system.net>.

=head1 AUTHOR

Jonas Genannt <jonas@brachium-system.net>.

=head1 COPYRIGHT

Copyright (C) 2014 by Jonas Genannt. All rights reserved.

=cut

package Awesant::Output::Gelf;

use strict;
use warnings;
use bytes;
use IO::Socket::INET;
use IO::Compress::Gzip qw( gzip $GzipError );
use Log::Handler;
use JSON;
use Params::Validate qw();

sub new {
    my $class = shift;
    my $opts = $class->validate(@_);
    my $self = bless $opts, $class;

    $self->{log}  = Log::Handler->get_logger("awesant");

    $self->{__alarm_sub} = sub {
        alarm(0);
    };

    $self->{__timeout_sub} = sub {
        die join(" ",
            "connection Graylog2 server",
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

    $self->{sock} = IO::Socket::INET->new(
            PeerAddr => $self->{host},
            PeerPort => $self->{port},
            Proto    => "udp",
    );
    $self->{sock}->autoflush(1);

    if (!$self->{sock}) {
      $self->log->error("unable to connect to Graylog2 server $self->{host}:$self->{port} - $!");
    }
    else {
      return $self->{sock};
    }
    return undef;
}

sub push {
    my ($self, $line) = @_;
    my $ret = 0;
    my $json = JSON->new->utf8();
    my $data = $json->decode($line);
    my $source = $data->{'source_host'};
    
    if ($self->{source} ne "") {
      $source = $self->{source};
    }
    my $gelf_event = {
      'version' => '1.1',
      'host'    => $source,
      'short_message' => $data->{'message'},
      'level' => '1',
      'facility' => $self->{facility},
      
      
    };

    my $gelf_json = $json->encode($gelf_event);
    undef($gelf_event);
    undef($source);
    if ($self->{gzip}) {
      my $gzip_gelf;
      gzip \$gelf_json =>  \$gzip_gelf;
      $gelf_json = $gzip_gelf;
      undef($gzip_gelf)
    }

    if ( bytes::length($gelf_json) > 8192) {
      $self->log->error("GELF messages is greater then 8192 bytes. use gzip or add chunk support.");
      return 1;
    }
   
    $ret = $self->_send($gelf_json);
    undef($gelf_json);
   
    return 1;
}

sub validate {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        host => {
            type => Params::Validate::SCALAR,
            default => "127.0.0.1",
        },
        port => {
            type => Params::Validate::SCALAR,  
            default => 12201,
        },
        timeout => {  
            type => Params::Validate::SCALAR,  
            default => 10,
        },
        gzip => {
            type => Params::Validate::SCALAR,
            regex => qr/^(0|1|true|false)\z/,
            default => 1,
        },
        facility => {
            type => Params::Validate::SCALAR,
            default => "syslog",
        },
        source => {
            type => Params::Validate::SCALAR,
            default => "",
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

    my $timeout  = $self->{timeout};
    my $response = "";

    eval {
        local $SIG{ALRM} = $self->{__timeout_sub};
        local $SIG{__DIE__} = $self->{__alarm_sub};
        alarm($timeout);

        my $sock = $self->connect
            or die "unable to connect to any Graylog2 server";

        my $rest = length($data);
        my $offset = 0;

        if ($self->log->is_debug) {
            $self->log->debug("send to Graylog2 server $self->{host}:$self->{port}: $data");
        }

        $response = $sock->send($data);
        alarm(0);
    };

    # Reset the complete connection.
    if ($self->{sock}) {
        close($self->{sock});
        $self->{sock} = undef;
    }

    return undef;
}

1;
