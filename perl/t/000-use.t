use strict;
use warnings;
use Test::More tests => 1;
use Awesant::Agent;
use Awesant::Input::Socket;
use Awesant::Input::File;
use Awesant::Output::Socket;
use Awesant::Output::Screen;
use Awesant::Output::Redis;

eval "Net::RabbitMQ";

if (!$@) {
    require Awesant::Output::Rabbitmq;
}

ok(1, "use");
