use Mojo::Base -strict;

# Disable libev and proxy detection
BEGIN {
  $ENV{MOJO_PROXY}   = 0;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan skip_all => 'IO::Socket::IP 0.16 required for this test!'
  unless Mojo::IOLoop::Server::IPV6;
plan skip_all => 'IO::Socket::SSL 1.75 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojolicious::Lite;
use ojo;

get '/remote_address' => sub {
  my $self = shift;
  $self->render(text => $self->tx->remote_address);
};

# Make sure user agents dont taint the ioloop
my $loop = Mojo::IOLoop->singleton;
my $ua   = Mojo::UserAgent->new;
my ($id, $code);
$ua->get(
  'http://metacpan.org' => sub {
    my $tx = pop;
    $id   = $tx->connection;
    $code = $tx->res->code;
    $loop->stop;
  }
);
$loop->start;
$ua = undef;
$loop->timer(0.25 => sub { shift->stop });
$loop->start;
ok !$loop->stream($id), 'loop not tainted';
is $code, 301, 'right status';

# Fresh user agent
$ua = Mojo::UserAgent->new;

# Local address
$ua->app(app);
my $sock = IO::Socket::INET->new(
  PeerAddr => 'mojolicio.us',
  PeerPort => 80,
  Proto    => 'tcp'
);
my $address = $sock->sockhost;
isnt $address, '127.0.0.1', 'different address';
$ua->local_address('127.0.0.1')->max_connections(0);
is $ua->get('/remote_address')->res->body, '127.0.0.1', 'right address';
$ua->local_address($address);
is $ua->get('/remote_address')->res->body, $address, 'right address';

# Fresh user agent
$ua = Mojo::UserAgent->new;

# Connection refused
my $port = Mojo::IOLoop->generate_port;
my $tx = $ua->build_tx(GET => "http://localhost:$port");
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
ok $tx->error,       'has error';

# Connection refused (IPv4)
$tx = $ua->build_tx(GET => "http://127.0.0.1:$port");
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
ok $tx->error,       'has error';

# Connection refused (IPv6)
$tx = $ua->build_tx(GET => "http://[::1]:$port");
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
ok $tx->error,       'has error';

# Host does not exist
$tx = $ua->build_tx(GET => 'http://cdeabcdeffoobarnonexisting.com');
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
is $tx->error, "Couldn't connect", 'right error';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Keep alive
$ua->get('http://mojolicio.us' => sub { Mojo::IOLoop->singleton->stop });
Mojo::IOLoop->singleton->start;
my $kept_alive;
$ua->get(
  'http://mojolicio.us' => sub {
    my $tx = pop;
    Mojo::IOLoop->singleton->stop;
    $kept_alive = $tx->kept_alive;
  }
);
Mojo::IOLoop->singleton->start;
ok $kept_alive, 'connection was kept alive';

# Nested keep alive
my @kept_alive;
$ua->get(
  'http://mojolicio.us' => sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      'http://mojolicio.us' => sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          'http://mojolicio.us' => sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->singleton->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->singleton->start;
is_deeply \@kept_alive, [1, 1, 1], 'connections kept alive';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Custom non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://metacpan.org');
$tx->req->headers->connection('close');
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 301, 'right status';
like $tx->res->headers->connection, qr/close/i, 'right "Connection" header';

# Oneliner
is g('mojolicio.us')->code,          200, 'right status';
is h('mojolicio.us')->code,          200, 'right status';
is h('mojolicio.us')->body,          '',  'no content';
is p('mojolicio.us/lalalala')->code, 404, 'right status';
is g('http://mojolicio.us')->code,   200, 'right status';
is p('http://mojolicio.us')->code,   404, 'right status';
my $res = p('search.cpan.org/search' => form => {query => 'mojolicious'});
like $res->body, qr/Mojolicious/, 'right content';
is $res->code,   200,             'right status';

# Simple requests
$tx = $ua->get('metacpan.org');
is $tx->req->method, 'GET',                 'right method';
is $tx->req->url,    'http://metacpan.org', 'right url';
is $tx->res->code,   301,                   'right status';
$tx = $ua->get('http://google.com');
is $tx->req->method, 'GET',               'right method';
is $tx->req->url,    'http://google.com', 'right url';
is $tx->res->code,   301,                 'right status';

# Simple keep alive requests
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->req->body,   '',                         'no content';
is $tx->res->code,   200,                        'right status';
ok $tx->keep_alive, 'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->res->code,   200,                        'right status';
ok $tx->keep_alive, 'connection will be kept alive';
ok $tx->kept_alive, 'connection was kept alive';
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->res->code,   200,                        'right status';
ok $tx->keep_alive, 'connection will be kept alive';
ok $tx->kept_alive, 'connection was kept alive';

# Request that requires IPv6
$tx = $ua->get('http://ipv6.google.com');
is $tx->req->method, 'GET',                    'right method';
is $tx->req->url,    'http://ipv6.google.com', 'right url';
is $tx->res->code,   200,                      'right status';

# Simple HTTPS request
$tx = $ua->get('https://metacpan.org');
is $tx->req->method, 'GET',                  'right method';
is $tx->req->url,    'https://metacpan.org', 'right url';
is $tx->res->code,   200,                    'right status';

# HTTPS request that requires IPv6
$tx = $ua->get('https://ipv6.google.com');
is $tx->req->method, 'GET',                     'right method';
is $tx->req->url,    'https://ipv6.google.com', 'right url';
is $tx->res->code,   200,                       'right status';

# HTTPS request that requires SNI
$tx = $ua->get('https://google.de');
like $ua->ioloop->stream($tx->connection)
  ->handle->peer_certificate('commonName'), qr/google\.de/, 'right name';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Simple keep alive form POST
$tx = $ua->post(
  'http://search.cpan.org/search' => form => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';
ok $tx->keep_alive, 'connection will be kept alive';
$tx = $ua->post(
  'http://search.cpan.org/search' => form => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';
ok $tx->kept_alive, 'connection was kept alive';

# Simple request with redirect
$ua->max_redirects(3);
$tx = $ua->get('http://wikipedia.org/wiki/Perl');
$ua->max_redirects(0);
is $tx->req->method, 'GET',                               'right method';
is $tx->req->url,    'http://en.wikipedia.org/wiki/Perl', 'right url';
is $tx->res->code,   200,                                 'right status';
is $tx->previous->req->method, 'GET', 'right method';
is $tx->previous->req->url, 'http://www.wikipedia.org/wiki/Perl', 'right url';
is $tx->previous->res->code, 301, 'right status';

# Custom chunked request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.google.com');
$tx->req->headers->transfer_encoding('chunked');
$tx->req->write_chunk(
  'hello world!' => sub {
    shift->write_chunk('hello world2!' => sub { shift->write_chunk('') });
  }
);
$ua->start($tx);
is_deeply [$tx->error],      ['Bad Request', 400], 'right error';
is_deeply [$tx->res->error], ['Bad Request', 400], 'right error';
ok $tx->local_address, 'has local address';
ok $tx->local_port > 0, 'has local port';
ok $tx->remote_address, 'has local address';
ok $tx->remote_port > 0, 'has local port';

# Connect timeout (non-routable address)
$tx = $ua->connect_timeout(0.5)->get('192.0.2.1');
ok $tx->is_finished, 'transaction is finished';
is $tx->error, 'Connect timeout', 'right error';
$ua->connect_timeout(3);

# Request timeout (non-routable address)
$tx = $ua->request_timeout(0.5)->get('192.0.2.1');
ok $tx->is_finished, 'transaction is finished';
is $tx->error, 'Request timeout', 'right error';

done_testing();
