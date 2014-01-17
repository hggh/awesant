# Global options

### hostname

Set the hostname.

Default: set by Sys::Hostname

### benchmark

Print some benchmark statistics to the log file.

Default: no

### milliseconds

Add milliseconds to @timestamp. Usually the timestamp looks like

    2013-11-15 17:46:13+0200

Enabling this parameter would generate a timestamp with milliseconds:

    2013-11-15 17:46:13.234+0200

Default: no

### poll

How often to poll inputs for new events.

Default: 500

### lines

How many lines to request from the inputs by each poll.

Default: 100

## How does the options 'poll' and 'lines' work in combination?

If 100 lines could be read then the agent tries to read the next 100 lines.
If less than 100 lines could be read then the end of the log file was reached
and the agent waits 500 ms before the agent tries to read the next lines.

### oldlogstashjson

Use the old or new logstash json schema.

By default awesant uses the new json format.

Default: no

# Global input and output options

## Global output options

### type

Label to bind the output to inputs.

Value: STRING

## Global input options

### type

Label to bind the input to outputs.

Value: STRING

It is possible to set a comma separated list of types.

Since v0.11 it is possible to use '*' to match all types.

### format

This option is equivalent to the option 'format' of logstash inputs.

Possible values: "plain", "json_event"

If the format is a json_event, then all necessary key-value pairs should exists.

    Example for a file input (/var/log/httpd/access.log):

    @version     =>  the version number
    @timestamp   =>  a well formatted timestamp!
    source       =>  file://hostname/var/log/httpd/access.log
    source_host  =>  hostname
    source_path  =>  /var/log/httpd/access.log
    type         =>  any_type
    tags         =>  [ "some", "tags" ]
    message      =>  "the message"

If 'type' is set, then it overwrites the type of the input, otherwise the type is used from the configuration.

Default: plain

### workers

How many processes to fork for this input.

Note that only 1 worker is possible for file inputs.

Example:

    file {
        type apache-access-log
        path /var/log/httpd/foo-access.log, /var/log/httpd/bar-access.log
        workers 1
    }
    file {
        type apache-error-log
        path /var/log/httpd/foo-error.log, /var/log/httpd/bar-error.log
        workers 1
    }
    file {
        type myapp
        path /var/log/myapp/*.log
        workers 1
    }
    socket {
        type logstash
        host 127.0.0.1
        port 4711
        format json_event
        workers 20
    }


In this case

* 1 process is forked to process foo-access.log and bar-access.log.
* 1 process is forked to process foo-error.log and bar-error.log.
* 1 process is forked to process all *.log files in /var/log/myapp and watching for new files.
* 20 processes are forked to process incoming request on host 127.0.0.1 port 4711

By default 1 process will be forked to process all inputs that has no "workers" configured.

### tags

Add any number of arbitrary tags to your event.

Value: STRING (a comma separated list)

### add_field

Add a field to an event.

Value: STRING (a comma separated list) or a HASH

#### Extended add_field feature

You can do cool things with the add_field parameter if you want.

As example you have a bunch of logfiles:

    /var/log/apache2/mydomain1.example/foo/error.log
    /var/log/apache2/mydomain2.example/bar/error.log
    /var/log/apache2/mydomain3.example/baz/error.log
    /var/log/apache2/mydomain1.example/foo/error.log
    /var/log/apache2/mydomain2.example/bar/error.log
    /var/log/apache2/mydomain3.example/baz/error.log

In this case you do not want to create a input configuration for each single log file:

    input {
        file {
            type apache-error-log
            path /var/log/apache2/mydomain1.example/foo/error.log
            add_field domain, foo.mydomain1.example
        }
        file {
            type apache-error-log
            path /var/log/apache2/mydomain1.example/bar/error.log
            add_field domain, bar.mydomain1.example
        }
        ... and so on - that would be bloated

Instead to create a input configuration for each log file, you can create one configuration
and fetch the domain name from the source_path:

    input {
        type apache-error-log
        path /var/log/apache2/*/*/error.log
        add_field {
            domain {                                    # The new field to add.
                                                        # Format: A-Za-z_
               field source_path                        # The field to use for the regexp.
               match ([a-z]+\.[a-z]+)/([a-z]+)/[^/]+$   # The perl regular expression.
                                                        # Format: no limitation
               concat $2.$1                             # Concatenate the matches with $1, $2, $3 ...
                                                        # Format: double quotes are not allowed
               default common                           # Set a default value if the regexp does not match.
                                                        # The parameter "default" is optional.
                                                        # Format: single quotes are not allowed
            }
        }
    }

As you can see two wildcards are used to match all error log files of each domain.
All what you have to do now is to create a regexp that matches the domain and subdomain
from the field source_path and to concatenate the matches to a string.

