# Awesant

Awesant is a simple log shipper for logstash. It ships logs from multiple inputs to multiple outputs.

## Pre-installation

Awesant is written in Perl. So you have to install some Perl packages at first
to run Awesant on your machine. Let us have a look on what you need to install:

    Log::Handler
    Params::Validate
    IO::Socket
    Sys::Hostname
    Time::HiRes
    JSON

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

    rpmbuild -ta awesant-$version.tar.gz
    rpm -i rpmbuild/RPMS/noarch/awesant...

## HowTo

### Start and stop Awesant

    /etc/init.d/awesant-agent [ start | stop | restart ]

### Configuration

The main configuration file of the Awesant agent is

    /etc/awesant/agent.conf

The configuration style is very simple. You can define inputs, outputs and a logger configuration.

Inputs are the log files you want to ship. Outputs are the transports you want to use to ship the log files.

Currently supported inputs:

    file

Currently supported outputs:

    redis
    screen

Example configuration:

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
            db => 0
            key => "syslog"
            type => "syslog"
            format => "json_event"
        }
    }

### Extended input and output configuration

* It is possible to set a comma separated list of types for outputs.
* It is possible to set wildcards for file inputs.

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

# Configuration options

See the *Options.md files.

Or you can look into the manpages

    man Awesant::Output::Redis
    man Awesant::Output::Screen
    man Awesant::Input::File

