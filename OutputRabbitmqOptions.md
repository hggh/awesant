# Awesant::Output::Rabbitmq

## Description

This transport module connects and shipts log data to RabbitMQ.

## Options

### host

The hostname or ip address of the RabbitMQ server.

Default: 127.0.0.1

### port

The port number where the RabbitMQ server is listen on.

Default: 5672

### timeout

The timeout in seconds to connect and transport data to the RabbitMQ server.

Default: 10

### user, password

The username and password to use for authentication.

Default: guest/guest

### queue

The queue to transport the data.

Default: logstash

### queue_durable, queue_exclusive, queue_auto_delete

Value is boolean: true, 1, false, 0

All defaults to false.

### exchange_durable, exchange_auto_delete

Value is boolean: true, 1, false, 0

All defaults to false.

### channel

channel is a positive integer describing the channel you which to open.

Default: 1

### vhost

See http://www.rabbitmq.com/uri-spec.html for more information.

Default: /

### heartbeat, frame_max, channel_max

See http://search.cpan.org/~jesus/Net--RabbitMQ/RabbitMQ.pm and
http://www.rabbitmq.com/ for more information.

Default: defaults from http://search.cpan.org/~jesus/Net--RabbitMQ/RabbitMQ.pm

## CONFIGURATION

### RabbitMQ

    rabbitmqctl add_user awesant secret
    rabbitmqctl set_permissions "awesant" ".*" ".*" ".*"

### Awesant

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

### Logstash

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

