# Awesant::Input::Socket

## Options

### host

The ip address to listen on.

Default: 127.0.0.1

### port

The port number to listen on.

Default: no default

### proto

The protocol to use. At the moment only tcp is allowed.

Default: tcp

### ssl_ca_file, ssl_cert_file, ssl_key_file

If you want to use ssl connections then you can set the path to your ca, certificate and key file.

This options are equivalent to the options of IO::Socket::SSL.

See cpan http://search.cpan.org/~sullr/IO-Socket-SSL/.

Default: no default

