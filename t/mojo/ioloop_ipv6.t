use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_IPV6 to enable this test (developer only!)'
  unless $ENV{TEST_IPV6};
plan skip_all => 'IO::Socket::IP 0.16 required for this test!'
  unless Mojo::IOLoop::Server::IPV6;

use Mojo::IOLoop;

# IPv6 roundtrip
my $delay = Mojo::IOLoop->delay;
my $port  = Mojo::IOLoop->generate_port;
my ($server, $client);
my $end = $delay->begin;
Mojo::IOLoop->server(
  {address => '[::1]', port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $stream->on(close => $end);
    $stream->on(read => sub { $server .= pop });
  }
);
my $end2 = $delay->begin;
Mojo::IOLoop->client(
  {address => '[::1]', port => $port} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(close => $end);
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server, 'tset123', 'right content';
is $client, 'test321', 'right content';

done_testing();
