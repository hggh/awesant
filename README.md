# Awesant

Awesant is a simple log shipper for logstash. It ships logs from multiple inputs to multiple outputs.

## Plugins and Options

Global Options for each plugin:

* <https://github.com/bloonix/awesant/blob/master/GlobalOptions.md>

Currently supported inputs:

* File: <https://github.com/bloonix/awesant/blob/master/InputFileOptions.md>
* Socket: <https://github.com/bloonix/awesant/blob/master/InputSocketOptions.md>

Currently supported outputs:

* Redis: <https://github.com/bloonix/awesant/blob/master/OutputRedisOptions.md>
* RabbitMQ: <https://github.com/bloonix/awesant/blob/master/OutputRabbitmqOptions.md>
* Screen: <https://github.com/bloonix/awesant/blob/master/OutputScreenOptions.md>
* Socket: <https://github.com/bloonix/awesant/blob/master/OutputSocketOptions.md>

## Pre-installation

Awesant is written in Perl. So you have to install some Perl packages at first
to run Awesant on your machine. Let us have a look on what you need to install:

    Log::Handler
    Params::Validate
    IO::Socket
    IO::Select
    Sys::Hostname
    Time::HiRes
    JSON

If you want to transport logs via SSL and the Socket output then you need to install IO::Socket::SSL.

If you want to transport logs to RabbitMQ you need to install Net::RabbitMQ.

You can install the packages with your favorite package manager or with cpan tool.

    cpan -i Log::Handler
    cpan -i Params::Validate
    cpan -i ...

## Installation

Just download the project and execute

    perl Configure.PL
    make
    make install

Or create a RPM with

    git clone https://github.com/bloonix/awesant.git awesant-$version
    tar -czf awesant-$version.tar.gz awesant-$version
    rpmbuild -ta awesant-$version.tar.gz
    rpm -i rpmbuild/RPMS/noarch/awesant...

Or create a deb-package with

    git clone https://github.com/bloonix/awesant.git awesant-$version
    cd awesant-$version
    dpkg-buildpackage

## Install Awesant from a repository

You can install Awesant from the Bloonix repository if you like.
The packages are available for Debian and CentOS like distributions.
Just look into the INSTALL files on http://download.bloonix.de/.

## HowTo

### Start and stop Awesant

    /etc/init.d/awesant-agent [ start | stop | restart ]

### Configuration

The main configuration file of the Awesant agent is

    /etc/awesant/agent.conf

The configuration style is very simple. You can define inputs, outputs, a logger and some global configuration parameter.

Inputs are the log files you want to ship. Outputs are the transports you want to use to ship the log files.

Example configuration:

    # How often to poll inputs for new events.
    # Default: 500 (ms)
    poll 500

    # How much lines to request from the inputs by each poll.
    # Default: 100 (count)
    lines 100

    input {
        file {
            type syslog
            path /var/log/messages
            tags tag1, tag2
            add_field key1, value1, key2, value2
            # add_field {
            #    key1 value1
            #    key2 value2
            # }
        }
    }

    output {
        redis {
            type syslog
            key syslog
            host 127.0.0.1
            port 6379
            database 0
            timeout 10
            password foobared
        }
        screen {
            type syslog
            send_to stdout
        }
    }

    logger {
        file {
            filename /var/log/awesant/agent.log
            maxlevel info
        }
    }

With this agent configuration your logstash should be configured as follows:

    input {
        redis {
            host => "127.0.0.1"
            port => 6379
            data_type => "list"
            db => 0
            key => "syslog"
            type => "redis"
            format => "json_event"
        }
    }

### Extended input and output configuration

* It is possible to set a comma separated list of types for outputs.
* It is possible to set wildcards for file inputs.
* If a wildcard is used then Awesant is watching the path for new files. If a new file is created then Awesant tails the new file automatically, so you do not need to restart Awesant.

As example if you has different inputs, such as

    input {
        file {
            type apache-access-log
            path /var/log/httpd/*access*log
        }
        file {
            type syslog
            path /var/log/messages
        }
    }

then you can use one output for multiple inputs:

    output {
        redis {
            type apache-access-log, syslog
            key logstash
            host 127.0.0.1
        }
    }

In this case the redis-output is bound to the inputs 'apache-access-log'
and 'syslog', but if the log events are pushed to the output then the
type of the input is used for the json event. That means that '@type' is
set to the type of the input, not of the output.

# SSL and authentication support

Do you want to ship your logs via SSL and via password authentication? That should not be a problem.

The scenario could looks like

    Awesant output socket -> Awesant input socket -> Redis -> Logstash

You can use the script 'awesant-create-cert' to create a cert bundle for Awesant.

    awesant-create-cert /etc/awesant 4096 10000

## Awesant output socket

Create the following configuration on the machines with the log files you want to ship.

    input {
        file {
            type foologs
            path /var/log/foo/*.log
        }
        file {
            type barlogs
            path /var/log/bar/*.log
        }
    }

    output {
        socket {
            type foologs, barlogs
            host redis-machine-remote-addr
            port 25801
            auth your-very-very-very-long-password
            ssl_cert_file /etc/awesant/certs/ssl.crt
            ssl_key_file  /etc/awesant/certs/ssl.key
        }
    }

## Awesant input socket

Create the following configuration on the machine where the redis instance is running
or on any host to transfer the logs to redis.

    input {
        socket {
            type logstash
            host redis-machine-local-addr
            port 25801
            auth your-very-very-very-long-password
            ssl_cert_file /etc/awesant/certs/ssl.crt
            ssl_key_file  /etc/awesant/certs/ssl.key
            format json_event
            workers 10
        }
    }

    output {
        redis {
            type foologs, barlogs
            host 127.0.0.1
            port 6379
            database 0
            key logstash
        }
    }

