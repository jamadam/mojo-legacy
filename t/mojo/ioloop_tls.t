use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.75 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

# To regenerate all required certificates run these commands (18.04.2012)
# openssl genrsa -out ca.key 1024
# openssl req -new -key ca.key -out ca.csr -subj "/C=US/CN=ca"
# openssl req -x509 -days 7300 -key ca.key -in ca.csr -out ca.crt
#
# openssl genrsa -out server.key 1024
# openssl req -new -key server.key -out server.csr -subj "/C=US/CN=localhost"
# openssl x509 -req -days 7300 -in server.csr -out server.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out client.key 1024
# openssl req -new -key client.key -out client.csr -subj "/C=US/CN=localhost"
# openssl x509 -req -days 7300 -in client.csr -out client.crt -CA ca.crt \
#   -CAkey ca.key -CAcreateserial
#
# openssl genrsa -out badclient.key 1024
# openssl req -new -key badclient.key -out badclient.csr \
#   -subj "/C=US/CN=badclient"
# openssl req -x509 -days 7300 -key badclient.key -in badclient.csr \
#   -out badclient.crt
use Mojo::IOLoop;

# Built-in certificate
my $loop  = Mojo::IOLoop->new;
my $delay = $loop->delay;
my $port  = Mojo::IOLoop->generate_port;
my ($server, $client);
my $end = $delay->begin;
$loop->server(
  {address => '127.0.0.1', port => $port, tls => 1} => sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $stream->on(close => $end);
    $stream->on(read => sub { $server .= pop });
  }
);
my $end2 = $delay->begin;
$loop->client(
  {port => $port, tls => 1} => sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(close => $end2);
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server, 'tset123', 'right content';
is $client, 'test321', 'right content';

# Valid client certificate
$delay = Mojo::IOLoop->delay;
$port  = Mojo::IOLoop->generate_port;
($server, $client) = ();
my ($remove, $running, $timeout, $server_err, $server_close, $client_close);
Mojo::IOLoop->remove(Mojo::IOLoop->recurring(0 => sub { $remove++ }));
$end = $delay->begin;
Mojo::IOLoop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(
      close => sub {
        $server_close++;
        $end->();
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read => sub { $server .= pop });
    $stream->timeout(0.5);
  }
);
$end2 = $delay->begin;
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(
      close => sub {
        $client_close++;
        $end2->();
      }
    );
    $stream->on(read => sub { $client .= pop });
  }
);
$delay->wait;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,      'loop was running';
ok !$remove,     'event removed successfully';
ok !$server_err, 'no error';

# Invalid client certificate
my $client_err;
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
ok $client_err, 'has error';

# Missing client certificate
($server_err, $client_err) = ();
Mojo::IOLoop->client(
  {port => $port, tls => 1} => sub {
    shift->stop;
    $client_err = shift;
  }
);
Mojo::IOLoop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (server)
$loop = Mojo::IOLoop->new;
$port = Mojo::IOLoop->generate_port;
($server_err, $client_err) = ();
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 'no cert',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub { $server_err = 'accepted' }
);
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Valid client and server certificates
$delay = Mojo::IOLoop->delay;
$port  = Mojo::IOLoop->generate_port;
($running, $timeout, $server, $server_err, $server_close) = ();
($client, $client_close) = ();
$end = $delay->begin;
Mojo::IOLoop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub {
    my ($loop, $stream) = @_;
    $stream->write('test' => sub { shift->write('321') });
    $running = Mojo::IOLoop->is_running;
    $stream->on(
      close => sub {
        $server_close++;
        $end->();
      }
    );
    $stream->on(error => sub { $server_err = pop });
    $stream->on(read => sub { $server .= pop });
  }
);
$end2 = $delay->begin;
Mojo::IOLoop->client(
  port     => $port,
  tls      => 1,
  tls_ca   => 't/mojo/certs/ca.crt',
  tls_cert => 't/mojo/certs/client.crt',
  tls_key  => 't/mojo/certs/client.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->write('tset' => sub { shift->write('123') });
    $stream->on(timeout => sub { $timeout++ });
    $stream->on(
      close => sub {
        $client_close++;
        $end2->();
      }
    );
    $stream->on(read => sub { $client .= pop });
    $stream->timeout(0.5);
  }
);
$delay->wait;
is $server,       'tset123', 'right content';
is $client,       'test321', 'right content';
is $timeout,      1,         'server emitted timeout event once';
is $server_close, 1,         'server emitted close event once';
is $client_close, 1,         'client emitted close event once';
ok $running,      'loop was running';
ok !$server_err, 'no error';

# Invalid server certificate (unsigned)
$loop = Mojo::IOLoop->new;
$port = Mojo::IOLoop->generate_port;
($server_err, $client_err) = ();
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub { $server_err = 'accepted' }
);
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 't/mojo/certs/ca.crt',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid server certificate (hostname)
$loop = Mojo::IOLoop->new;
$port = Mojo::IOLoop->generate_port;
($server_err, $client_err) = ();
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/server.crt',
  tls_key  => 't/mojo/certs/server.key',
  sub { $server_err = 'accepted' }
);
$loop->client(
  address => '127.0.0.1',
  port    => $port,
  tls     => 1,
  tls_ca  => 't/mojo/certs/ca.crt',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Invalid certificate authority (client)
$loop = Mojo::IOLoop->new;
$port = Mojo::IOLoop->generate_port;
($server_err, $client_err) = ();
$loop->server(
  address  => '127.0.0.1',
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub { $server_err = 'accepted' }
);
$loop->client(
  port   => $port,
  tls    => 1,
  tls_ca => 'no cert',
  sub {
    shift->stop;
    $client_err = shift;
  }
);
$loop->start;
ok !$server_err, 'no error';
ok $client_err, 'has error';

# Ignore invalid client certificate
$loop = Mojo::IOLoop->new;
$port = Mojo::IOLoop->generate_port;
($server, $client, $client_err) = ();
$loop->server(
  address    => '127.0.0.1',
  port       => $port,
  tls        => 1,
  tls_ca     => 't/mojo/certs/ca.crt',
  tls_cert   => 't/mojo/certs/server.crt',
  tls_key    => 't/mojo/certs/server.key',
  tls_verify => 0x00,
  sub {
    my ($loop, $stream) = @_;
    $stream->on(close => sub { $loop->stop });
    $server = 'accepted';
  }
);
$loop->client(
  port     => $port,
  tls      => 1,
  tls_cert => 't/mojo/certs/badclient.crt',
  tls_key  => 't/mojo/certs/badclient.key',
  sub {
    my ($loop, $err, $stream) = @_;
    $stream->timeout(0.5);
    $client_err = $err;
    $client     = 'connected';
  }
);
$loop->start;
is $server, 'accepted',  'right result';
is $client, 'connected', 'right result';
ok !$client_err, 'no error';

done_testing();
