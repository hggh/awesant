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

## Installation

Just download the project and execute

    perl Configure.PL
    make
    make install

Or create a RPM with

    rpm -ta awesant-$version.tar.gz
    rpm -i rpmbuild/RPMS/noarch/awesant...

## HowTo

### Start and stop Awesant

    /etc/init.d/logstash-agent [ start | stop | restart ]

### Configuration

The main configuration file of the Awesant agent is

    /etc/awesant/agent.conf

The configuration style is very simple. You can define inputs and outputs.

Inputs are the log files you want to ship. Outputs are the transports you want to use to ship the log files.

Only files are currently supported as input and only redis and screen are currently supported for outputs.

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
            server 127.0.0.1
            port 6379
            database 0
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
            format => "json_event"
        }
    }

