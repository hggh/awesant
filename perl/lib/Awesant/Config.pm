=head1 NAME

Awesant::Config - Configuration file parser.

=head1 SYNOPSIS

    my $config = Awesant::Config->parse($file);

=head1 DESCRIPTION

This module is just for internal usage.

=head1 CONFIGURATION FORMAT

=head2 SELF-EXPLANATORY

The configuration format is very simple:

    param1 value
    param2 value
    param3 " value value value "
    param4 ' value value value '
    param5 multiline \
           value
    param6 " multiline values " \
           " with whitespaces "

    section1 {
        param1 value
        param2 value

        subsection1 {
            param1 value
            param2 value
        }
    }

=head2 COMMENTS

Add comments to the configuration to explain parameter:

    # Comment
    param1 value # comment
    param2 value#value # comment
    param3 'value \# value' # comment
    param4 multiline \ # comment
           value
    param5 " multiline values " \ # comment
           " with whitespaces " # comment

=head2 HASHES VS ARRRAYS

Please not that if a hash key exists that the values will be pushed into an array:

    param1 value
    param2 value1
    param2 value2

    section1 {
        param value
    }
    section2 {
        param value
    }
    section2 {
        param value
    }

is

    param1 => "value",
    param2 => [ "value1", "value2" ],
    section1 => { param => "value" },
    section2 => [
        { param => "value" },
        { param => "value" }
    ]

=head2 INCLUDE

It's possible to include configuration files.

    param1 value
    param2 value
    include /etc/myapp/another-config.conf
    param3 value

=head1 FUNCTIONS

=head2 C<parse>

Pass the configuration file as argument and a hash reference with the
parsed configuration will be returned.

=head1 AUTHOR

Jonny Schulz <support(at)bloonix.de>.

=head1 COPYRIGHT

Copyright (C) 2014 by Jonny Schulz. All rights reserved.

=cut

package Awesant::Config;

use strict;
use warnings;
use constant IS_WIN32 => $^O =~ /Win32/i ? 1 : 0;
use constant DIRDELIM => IS_WIN32 ? "\\" : "/";

sub parse {
    my ($class, $file, $enc) = @_;

    # Safe the path to the file. The path is
    # used to include further configuration files.
    my $path = $file;
    $path =~ s![^/\\]+$!!;

    # Create the object.
    my $self = bless { path => $path }, $class;

    # The $config will be returned as a hash reference.
    my $config = { };

    # Go go go ...
    $self->_include_config($file, $config, $enc);

    return $config;
}

sub _include_config {
    my ($self, $file, $config, $enc) = @_;
    my $d = $enc ? "<:$enc" : "<";

    open my $fh, $d, $file
        or die "Unable to open file '$file' for reading - $!";

    $self->_parse_config($fh, $config);

    close $fh;
}

sub _parse_config {
    my ($self, $fh, $config) = @_;
    my ($key, $value, @multiline, $is_multiline);

    while (my $line = <$fh>) {
        # Prepare the line and cut newline, comments
        # and whitespaces from the begin and the end
        # of each line.
        $line =~ s/[\r\n]+\z//;
        $line =~ s/\s+#.+//;
        $line =~ s/^\s*#.*//;
        $line =~ s/\\#/#/g;
        $line =~ s/^\s*//;
        $line =~ s/\s*\z//;

        # Comments and whitespaces was removed.
        # Empty lines will be ignored.
        if (!length $line) {
            next;
        }

        # The end of a section ends with "}"
        if ($line =~ /^\s*\}/) {
            return;
        }

        # If the parameter was marked as multiline parameter
        # then the raw line will be stored as value.
        if ($is_multiline) {
            $value = $line;

        # If a line begins with "keyword {" then it's a sub-section.
        } elsif ($line =~ /^([^\s]+)\s*\{/) {
            ($key, $value) = ($1, { });
            $self->_add_key_value($config, $key, $value);
            $self->_parse_config($fh, $value);
            next;

        # A key value pair. The value can be an empty string.
        } elsif ($line =~ /^([^\s]+)\s*(.*)/) {
            ($key, $value) = ($1, $2);
        }

        # Look if the end of the line is marked as multiline.
        $is_multiline = $value =~ s/\s*\\\z//;

        # Remove the quotes of quoted values.
        if ($value =~ /^'(.*)'\z/ || $value =~ /^"(.*)"\z/) {
            $value = $1;
        }

        # If the line is marked as multiline, then just
        # push the value into a temporary array.
        if ($is_multiline) {
            push @multiline, $value;
            next;
        }

        # If the last parsed parameter was a multine parameter,
        # then the array @multiline contains the values.
        if (@multiline) {
            $value = join(" ", @multiline, $value);
            @multiline = ();
        }

        # Add the key value pair to the config.
        $self->_add_key_value($config, $key, $value);
    }
}

sub _add_key_value {
    my ($self, $config, $key, $value) = @_;

    if ($key eq "include") {
        if ($self->{path} && $value !~ m!^(/|[a-z]:\\)!i) {
            $value = join(DIRDELIM, $self->{path}, $value);
        }
        $self->_include_config($value, $config);
    } elsif (!exists $config->{$key}) {
        $config->{$key} = $value;
    } elsif (ref $config->{$key} eq "ARRAY") {
        push @{$config->{$key}}, $value;
    } else {
        $config->{$key} = [ $config->{$key}, $value ];
    }
}

1;
