# Awesant::Output::Socket

## Options

### host

The hostname or ip address of the tcp server.

Default: 127.0.0.1

### port

The port number where the tcp server is listen on.

Default: no default

### timeout

The timeout in seconds to transport data to the tcp server.

Default: 10

### connect_timeout

The timeout in seconds to connect to the tcp server.

### proto

The protocol to use. At the moment only tcp is allowed.

Default: tcp

### response

If a response is excepted then you can set the excepted message here as a perl regular expression.

If the regular expression matched, then the transport of the message was successful.

Example:

    response ^(ok|yes|accept)$

Default: no default

### ssl_ca_file, ssl_cert_file, ssl_key_file

If you want to use ssl connections to the server you can set the path to your ca, certificate and key file.

This options are equivalent to the options of IO::Socket::SSL.

See cpan http://search.cpan.org/~sullr/IO-Socket-SSL/.

Default: no set

### ssl_passwd_cb

The password for the certificate, if one exists.

Default: no default

