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

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

# Web server with valid certificates
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  ioloop => Mojo::IOLoop->singleton,
  silent => 1
);
my $port = Mojo::IOLoop->new->generate_port;
my $listen
  = "https://127.0.0.1:$port"
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt';
$daemon->listen([$listen])->start;

# No certificate
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my $tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';
$tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Valid certificates
$ua->ca('t/mojo/certs/ca.crt')->cert('t/mojo/certs/client.crt')
  ->key('t/mojo/certs/client.key');
$tx = $ua->get("https://localhost:$port");
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Valid certificates (using an already prepared socket)
my $sock;
$ua->ioloop->client(
  {
    address  => 'localhost',
    port     => $port,
    tls      => 1,
    tls_ca   => 't/mojo/certs/ca.crt',
    tls_cert => 't/mojo/certs/client.crt',
    tls_key  => 't/mojo/certs/client.key'
  } => sub {
    my ($loop, $err, $stream) = @_;
    $sock = $stream->steal_handle;
    $loop->stop;
  }
);
$ua->ioloop->start;
$tx = $ua->build_tx(GET => 'https://lalala/');
$tx->connection($sock);
$ua->start($tx);
ok $tx->success, 'successful';
is $tx->req->method, 'GET',             'right method';
is $tx->req->url,    'https://lalala/', 'right url';
is $tx->res->code,   200,               'right status';
is $tx->res->body,   'works!',          'right content';

# Valid certificates (env)
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
{
  local $ENV{MOJO_CA_FILE}   = 't/mojo/certs/ca.crt';
  local $ENV{MOJO_CERT_FILE} = 't/mojo/certs/client.crt';
  local $ENV{MOJO_KEY_FILE}  = 't/mojo/certs/client.key';
  $tx = $ua->get("https://localhost:$port");
  is $ua->ca,   't/mojo/certs/ca.crt',     'right path';
  is $ua->cert, 't/mojo/certs/client.crt', 'right path';
  is $ua->key,  't/mojo/certs/client.key', 'right path';
  ok $tx->success, 'successful';
  is $tx->res->code, 200,      'right status';
  is $tx->res->body, 'works!', 'right content';
}

# Empty certificate authority
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->ca('t/mojo/certs/empty.crt')->cert('t/mojo/certs/client.crt')
  ->key('t/mojo/certs/client.key');
$tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Invalid certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->cert('t/mojo/certs/badclient.crt')->key('t/mojo/certs/badclient.key');
$tx = $ua->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Empty certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$tx = $ua->cert('t/mojo/certs/empty.crt')->key('t/mojo/certs/empty.crt')
  ->get("https://localhost:$port");
ok !$tx->success, 'not successful';
ok $tx->error, 'has error';

# Web server with valid certificates and no verification
$daemon = Mojo::Server::Daemon->new(
  app    => app,
  ioloop => Mojo::IOLoop->singleton,
  silent => 1
);
$listen
  = "https://127.0.0.1:$port"
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt'
  . '&verify=0x00';
$daemon->listen([$listen])->start;

# Invalid certificate
$ua = Mojo::UserAgent->new(ioloop => $ua->ioloop);
$ua->cert('t/mojo/certs/badclient.crt')->key('t/mojo/certs/badclient.key');
$tx = $ua->get("https://localhost:$port");
ok $tx->success, 'successful';
ok !$tx->error, 'no error';

done_testing();
