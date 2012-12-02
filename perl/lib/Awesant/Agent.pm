=head1 NAME

Awesant::Agent - Ships log files for logstash.

=head1 SYNOPSIS

    Awesant::Agent->run(
        config  => $path_to_configuration,
        pidfile => $path_to_pid_file,
    );

=head1 DESCRIPTION

Awesant is a simple log file shipper for logstash.

It ships log files and sends the data to different transports.

All what you have to do is to call the method C<run> with its expected options.

=head1 METHODS

=head2 run

Start the shipping machine.

Nothing more is there for you to do. That means that you shouldn't touch the
other methods in this module.

=head2 load_output

Load the output modules that are used by configuration.

As example if C<redis> is defined as transport in the output section

    output {
        redis {
            ...
        }
    }

then Awesant is looking for a module called C<Awesant::Output::Redis>.
If you would define a section call C<foo>, then Awesant would try to
C<require> the module C<Awesant::Output::Foo>.

=head2 load_input

The method C<load_input> does in the first step the same like C<load_output>.
It looks for input modules. As example if the input C<file> is configured,
then it tries to load the module C<Awesant::Input::File>.

As next each output module that was pre-loaded is bound to the inputs.
This is done using the parameter C<type>.

=head2 load_module

This method just includes the input and output modules and is called by
C<load_output> and C<load_input>. The process to load the modules is really
simple.

As example if the following sections are configured:

    output {
        redis {
            ...
        }
    }

then the module is loaded as follows:

    my $input_or_output = "output"; # output is the first section
    my $transport = "redis";        # redis is the configured transport

    my $module = join("::",
        "Awesant",
        ucfirst($input_or_output),
        ucfirst($transport)
    );

    require $module;

All clear? :-)

=head2 daemonize

Start the endless loop and calls C<run_agent> in an eval block.

=head2 run_agent

The main logic of the Awesant agent. It requests the inputs for data to
forward the data to the outputs.

=head2 prepare_message

Each log line is passed to C<prepare_message> and a nice formatted
JSON string is returned, ready for Logstash.

=head2 get_config

Load the configuration from a file.

=head2 write_pidfile

Writes the PID file.

=head2 remove_pidfile

Removes the PID file.

=head2 create_logger

Create the logger object. As logger C<Log::Handler> is used.

=head2 validate_config, validate_agent_config, validate_add_field_match

Validate the configuration.

=head2 config

Just an accessor to the configuration.

=head2 log

Just an accessor to the logger.

=head1 PREREQUISITES

    Log::Handler
    Params::Validate
    JSON
    POSIX
    Sys::Hostname
    Time::HiRes

=head1 EXPORTS

No exports.

=head1 REPORT BUGS

Please report all bugs to <support(at)bloonix.de>.

=head1 AUTHOR

Jonny Schulz <support(at)bloonix.de>.

=head1 COPYRIGHT

Copyright (C) 2012 by Jonny Schulz. All rights reserved.

=cut

package Awesant::Agent;

use strict;
use warnings;
use Log::Handler;
use Params::Validate qw();
use JSON;
use POSIX qw();
use Sys::Hostname;
use Time::HiRes qw();
use Awesant::Config;

our $VERSION = "0.4";

sub run {
    my ($class, %args) = @_;

    my $self = bless {
        done => 0,
        args => \%args,
        json => JSON->new(),
        hostname => Sys::Hostname::hostname(),
    }, $class;

    $self->get_config;
    $self->write_pidfile;
    $self->create_logger;
    $self->load_output;
    $self->load_input;
    $self->daemonize;
    $self->remove_pidfile;
}

sub load_output {
    my $self = shift;
    my $outputs = $self->config->{output};

    foreach my $output (keys %$outputs) {
        my $module = $self->load_module(output => $output);

        foreach my $config (@{$outputs->{$output}}) {
            my $types = delete $config->{type};

            if (!defined $types || $types !~ /\w/) {
                die "missing mandatory parameter 'type' for output '$types'";
            }

            my $object = $module->new($config);

            foreach my $type (split /,/, $types) {
                $type =~ s/^\s+//;
                $type =~ s/\s+\z//;
                push @{$self->{output}->{$type}}, $object;
            }
        }
    }
}

sub load_input {
    my $self = shift;
    my $inputs = $self->config->{input};

    foreach my $input (keys %$inputs) {
        my $module = $self->load_module(input => $input);

        foreach my $config (@{$inputs->{$input}}) {
            my %agent_config;

            foreach my $param (qw/type tags add_field/) {
                if (exists $config->{$param}) {
                    $agent_config{$param} = delete $config->{$param};
                }
            }

            foreach my $field (keys %{$agent_config{add_field}}) {
                if (ref $agent_config{add_field}{$field} eq "HASH") {
                    $agent_config{__add_field}{$field} = delete $agent_config{add_field}{$field};
                }
            }

            $agent_config{path} = $config->{path} || "/";

            if ($input eq "file") {
                foreach my $path (split /,/, $config->{path}) {
                    $path =~ s/^\s+//;
                    $path =~ s/\s+\z//;
                    while (my $file = glob $path) {
                        my %c = %$config;
                        my %a = %agent_config;
                        $a{path} = $c{path} = $file;
                        push @{$self->{input}}, {
                            time   => scalar Time::HiRes::gettimeofday(),
                            object => $module->new(\%c),
                            config => $self->validate_agent_config(\%a),
                        };
                    }
                }
            } else {
                push @{$self->{input}}, {
                    time   => scalar Time::HiRes::gettimeofday(),
                    object => $module->new($config),
                    config => $self->validate_agent_config(\%agent_config),
                };
            }
        }
    }
}

sub load_module {
    my ($self, $io, $type) = @_;

    my $module = join("::",
        "Awesant",
        ucfirst($io),
        ucfirst($type),
    );

    eval "require $module";
    die $@ if $@;
    return $module;
}

sub daemonize {
    my $self = shift;

    # This is the best way to determine dirty code :)
    $SIG{__WARN__} = sub {
        $self->log->warning(@_);
    };

    # A full backtrace if someone calls die()
    $SIG{__DIE__} = sub {
        if ($_[0] !~ /^signal TERM received/) {
            $self->log->trace(error => @_);
        }
    };

    $SIG{HUP} = "IGNORE";
    $SIG{TERM} = sub { $self->{done} = 1 };

    while ($self->{done} == 0) {
        eval { $self->run_agent };

        if ($self->{done} == 0) {
            sleep 3;
        }
    }
}

sub run_agent {
    my $self = shift;
    my $poll = $self->config->{poll} / 1000;
    my $inputs = $self->{input};
    my $max_lines = $self->config->{lines};
    my $messurement = Time::HiRes::gettimeofday();
    my $count_lines = 0;
    my $count_bytes = 0;
    my $benchmark = $self->config->{benchmark};
    my %error = ();

    while ($self->{done} == 0) {
        my $time = Time::HiRes::gettimeofday() + $poll;

        foreach my $input (@$inputs) {
            if ($input->{time} - Time::HiRes::gettimeofday() > 0) {
                next;
            }

            my $config = $input->{config};
            my $type = $config->{type};

            if ($error{$type}) {
                while (my $ref = shift @{$error{$type}}) {
                    my $output = $ref->{output};
                    my $count  = 0;
                    my $bytes  = 0;

                    while (my $line = shift @{$ref->{lines}}) {
                        my $json = $self->prepare_message($config, $line);

                        if (!$output->push($json)) {
                            unshift @{$ref->{lines}}, $line;
                            last;
                        }

                        $count += 1;
                        $bytes += length($line);
                    }

                    if (@{$ref->{lines}}) {
                        unshift @{$error{$type}}, $ref;
                        last;
                    }

                    $self->log->notice(
                        "output $type is reachable again -",
                        "flushed $count lines with $bytes bytes"
                    );
                }

                if (!@{$error{$type}}) {
                    delete $error{$type};
                }

                # next input
                next;
            }

            my $lines = $input->{object}->pull(lines => 100);
            my $outputs = $self->{output}->{$type};

            if (!defined $lines || !@$lines) {
                $input->{time} = Time::HiRes::gettimeofday() + $poll;
                next;
            }

            $time = Time::HiRes::gettimeofday();

            if ($benchmark) {
                $count_lines += scalar @$lines;
                $count_bytes += length(join("", @$lines));

                if ($count_lines >= 10000) {
                    $messurement = sprintf("%.6f", Time::HiRes::gettimeofday() - $messurement);
                    $count_bytes = sprintf("%.3fM", $count_bytes > 0 ? $count_bytes / 1_048_576 : 0);
                    $self->log->info("processed $count_lines lines / $count_bytes bytes in $messurement seconds");
                    $messurement = Time::HiRes::gettimeofday();
                    $count_lines = 0;
                    $count_bytes = 0;
                }
            }

            my @prepared;

            foreach my $line (@$lines) {
                my $json = $self->prepare_message($config, $line);
                push @prepared, $json;
            }

            foreach my $output (@$outputs) {
                for (my $i=0; $i <= $#prepared; $i++) {
                    if (!$output->push($prepared[$i])) {
                        my $stash = [ @{$lines}[$i..$#{$lines}] ];
                        my $count = scalar @$stash;
                        my $bytes = length( join("", @$stash) );
                        push @{$error{$type}}, {
                            output => $output,
                            lines  => [ @{$lines}[$i..$#{$lines}] ],
                            count  => $count,
                            bytes  => $bytes,
                        };
                        $self->log->error(
                            "output $type returns an error -",
                            "stashing $count lines with $bytes bytes"
                        );
                        last;
                    }
                }
            }
        }

        $time -= Time::HiRes::gettimeofday();

        if ($time > 0 && $self->{done} == 0) {
            $self->log->debug(sprintf("sleep for %.6f seconds", $time));
            Time::HiRes::usleep($time * 1_000_000);
        }
    }
}

sub prepare_message {
    my ($self, $input, $line) = @_;
    my $json = $self->{json};

    my $timestamp = POSIX::strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $timestamp =~ s/(\d{2})(\d{2})\z/$1:$2/;

    my $logstash = {
        '@timestamp'   => $timestamp,
        '@source'      => "file://" . $self->{hostname} . $input->{path},
        '@source_host' => $self->{hostname},
        '@source_path' => $input->{path},
        '@type'        => $input->{type},
        '@tags'        => $input->{tags},
        '@fields'      => $input->{add_field},
        '@message'     => $line,
    };

    if ($input->{__add_field}) {
        foreach my $code (@{$input->{__add_field_code}}) {
            &$code($logstash);
        }
    }

    return $json->encode($logstash);
}

sub get_config {
    my $self = shift;

    my $config = Awesant::Config->parse(
        $self->{args}->{config}
    );

    $self->{config} = $self->validate_config($config);
}

sub write_pidfile {
    my $self = shift;                                                                                                               
    open my $fh, ">", $self->{args}->{pidfile}
        or die "unable to write pid file - $!";
    print $fh $$;
    close $fh;
}

sub remove_pidfile {
    my $self = shift;

    if (-f $self->{args}->{pidfile}) {
        unlink($self->{args}->{pidfile});
            # "or die" is not necessaray because
            # awesant stop running
    }
}

sub create_logger {
    my $self = shift;

    $self->{log} = Log::Handler->create_logger("awesant");

    if ($self->config->{logger}) {
        $self->{log}->config(config => $self->config->{logger});
    }
}

sub validate_config {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        poll => {
            type => Params::Validate::SCALAR,
            regex => qr/^(?:1000|[1-9][0-9][0-9])\z/,
            default => 500,
        },
        lines => {
            type => Params::Validate::SCALAR,
            default => 100,
        },
        output => {
            type => Params::Validate::HASHREF,
        },
        input => {
            type => Params::Validate::HASHREF,
        },
        logger => {
            type => Params::Validate::HASHREF,
            optional => 1,
        },
        benchmark => {
            type => Params::Validate::SCALAR,
            regex => qr/^(?:yes|no|0|1)\z/,
            default => 0,
        },
    });

    if ($options{benchmark} eq "no") {
        $options{benchmark} = 0;
    }

    foreach my $key (qw/output input/) {
        my $ref = $options{$key};
        foreach my $type (keys %$ref) {
            if (ref $ref->{$type} eq "HASH") {
                $ref->{$type} = [ $ref->{$type} ];
            }
        }
    }

    return \%options;
}

sub validate_agent_config {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        type => {
            type => Params::Validate::SCALAR,
        },
        tags => {
            type => Params::Validate::SCALAR
                    | Params::Validate::ARRAYREF,
            default => [ ],
        },
        add_field => {
            type => Params::Validate::SCALAR
                    | Params::Validate::HASHREF
                    | Params::Validate::ARRAYREF,
            default => { },
        },
        __add_field => {
            type => Params::Validate::HASHREF,
            optional => 1,
        },
        path => {
            type => Params::Validate::SCALAR,
            default => "/",
        },
    });

    # add_field => {
    #     domain => {
    #         key    => '@source_path',
    #         match  => "([a-z]+\.[a-z]+)/([a-z]+)/[^/]+$",
    #         concat => "$2.$1",
    #     }
    # }

    if (defined $options{add_field}) {
        if (ref $options{add_field} eq "ARRAY") {
            $options{add_field} = { @{$options{add_field}} };
        } elsif (ref $options{add_field} ne "HASH") {
            my @fields;
            foreach my $field (split /,/, $options{add_field}) {
                $field =~ s/^\s+//;
                $field =~ s/\s+\z//;
                push @fields, $field;
            }
            $options{add_field} = { @fields };
        }
    }

    if (defined $options{__add_field}) {
        foreach my $field (keys %{$options{__add_field}}) {
            my $ref = $options{__add_field}{$field};

            # The code generation. I'm sorry that it's a bit unreadable.
            my $func = "sub { my (\$e) = \@_; if (\$e->{'$ref->{field}'} =~ m!$ref->{match}!) { ";
            $func .= "\$e->{'\@fields'}->{'$field'} = \"$ref->{concat}\"; }";
            if (defined $ref->{default}) {
                $func .= " else { \$e->{'\@fields'}->{'$field'} = '$ref->{default}'; } ";
            }
            $func .= "}";

            # Eval the code.
            my $code = eval $func;
            push @{$options{__add_field_func}}, $func;
            push @{$options{__add_field_code}}, $code;
        }
    }

    if (defined $options{tags} && ref $options{tags} ne "ARRAY") {
        my $tags = $options{tags};
        $options{tags} = [ ];
        foreach my $tag (split /,/, $tags) {
            $tag =~ s/^\s+//;
            $tag =~ s/\s+\z//;
            push @{$options{tags}}, $tag;
        }
    }

    return \%options;
}

sub validate_add_field_match {
    my $self = shift;

    my %options = Params::Validate::validate(@_, {
        field => {
            type => Params::Validate::SCALAR,
            regex => qr/^\w+\z/,
        },
        match => {
            type => Params::Validate::SCALAR,
        },
        concat => {
            type => Params::Validate::SCALAR,
            regex => qr/^[^"]+\z/,
        },
        default => {
            type => Params::Validate::SCALAR,
            regex => qr/^[^']+\z/,
            optional => 1,
        },
    });

    return \%options;
}

sub config {
    my $self = shift;

    return $self->{config};
}

sub log {
    my $self = shift;

    return $self->{log};
}

1;
