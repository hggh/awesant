use strict;
use warnings;
use Test::More;
eval "use Test::Pod::Coverage";

if ($@) {
    plan skip_all => "Test::Pod::Coverage required for testing pod coverage";
    exit 0;
}

my @modules = qw(
    Awesant::Input::File
    Awesant::Input::Socket
    Awesant::Output::Socket
    Awesant::Output::Screen
    Awesant::Output::Redis
    Awesant::Agent
    Awesant::Config
);

eval "Net::RabbitMQ";

if (!$@) {
    push @modules, "Awesant::Output::Rabbitmq";
}

plan tests => scalar @modules;

foreach my $mod (@modules) {
    pod_coverage_ok($mod, "$mod is covered");
}
