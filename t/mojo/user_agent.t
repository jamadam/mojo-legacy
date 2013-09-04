use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_NO_TLS} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use IO::Compress::Gzip 'gzip';
use Mojo::IOLoop;
use Mojo::Message::Request;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

my $timeout = undef;
get '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->stream($self->tx->connection)
    ->timeout($self->param('timeout'));
  $self->on(finish => sub { $timeout = 1 });
  $self->render_later;
};

get '/no_length' => sub {
  my $self = shift;
  $self->finish('works too!');
  $self->rendered(200);
};

get '/no_content' => {text => 'fail!', status => 204};

get '/echo' => sub {
  my $self = shift;
  gzip \(my $uncompressed = $self->req->body), \my $compressed;
  $self->res->headers->content_encoding($self->req->headers->accept_encoding);
  $self->render(data => $compressed);
};

post '/echo' => sub {
  my $self = shift;
  $self->render(data => $self->req->body);
};

# Proxy detection
{
  my $ua = Mojo::UserAgent->new;
  local $ENV{HTTP_PROXY}  = 'http://127.0.0.1';
  local $ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
  local $ENV{NO_PROXY}    = 'mojolicio.us';
  $ua->detect_proxy;
  is $ua->http_proxy,  'http://127.0.0.1',      'right proxy';
  is $ua->https_proxy, 'http://127.0.0.1:8080', 'right proxy';
  $ua->http_proxy(undef);
  $ua->https_proxy(undef);
  is $ua->http_proxy,  undef, 'right proxy';
  is $ua->https_proxy, undef, 'right proxy';
  ok !$ua->need_proxy('dummy.mojolicio.us'), 'no proxy needed';
  ok $ua->need_proxy('icio.us'),   'proxy needed';
  ok $ua->need_proxy('localhost'), 'proxy needed';
  ($ENV{HTTP_PROXY}, $ENV{HTTPS_PROXY}, $ENV{NO_PROXY}) = ();
  local $ENV{http_proxy}  = 'proxy.example.com';
  local $ENV{https_proxy} = 'tunnel.example.com';
  local $ENV{no_proxy}    = 'localhost,localdomain,foo.com,example.com';
  $ua->detect_proxy;
  is $ua->http_proxy,  'proxy.example.com',  'right proxy';
  is $ua->https_proxy, 'tunnel.example.com', 'right proxy';
  ok $ua->need_proxy('dummy.mojolicio.us'), 'proxy needed';
  ok $ua->need_proxy('icio.us'),            'proxy needed';
  ok !$ua->need_proxy('localhost'),             'proxy needed';
  ok !$ua->need_proxy('localhost.localdomain'), 'no proxy needed';
  ok !$ua->need_proxy('foo.com'),               'no proxy needed';
  ok !$ua->need_proxy('example.com'),           'no proxy needed';
  ok !$ua->need_proxy('www.example.com'),       'no proxy needed';
  ok $ua->need_proxy('www.example.com.com'), 'proxy needed';
}

# Max redirects
{
  local $ENV{MOJO_MAX_REDIRECTS} = 25;
  is(Mojo::UserAgent->new->max_redirects, 25, 'right value');
  $ENV{MOJO_MAX_REDIRECTS} = 0;
  is(Mojo::UserAgent->new->max_redirects, 0, 'right value');
}

# Timeouts
{
  is(Mojo::UserAgent->new->connect_timeout, 10, 'right value');
  local $ENV{MOJO_CONNECT_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->connect_timeout,    25, 'right value');
  is(Mojo::UserAgent->new->inactivity_timeout, 20, 'right value');
  local $ENV{MOJO_INACTIVITY_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->inactivity_timeout, 25, 'right value');
  $ENV{MOJO_INACTIVITY_TIMEOUT} = 0;
  is(Mojo::UserAgent->new->inactivity_timeout, 0, 'right value');
  is(Mojo::UserAgent->new->request_timeout,    0, 'right value');
  local $ENV{MOJO_REQUEST_TIMEOUT} = 25;
  is(Mojo::UserAgent->new->request_timeout, 25, 'right value');
  $ENV{MOJO_REQUEST_TIMEOUT} = 0;
  is(Mojo::UserAgent->new->request_timeout, 0, 'right value');
}

# Default application
is(Mojo::UserAgent->app,      app, 'applications are equal');
is(Mojo::UserAgent->new->app, app, 'applications are equal');
Mojo::UserAgent->app(app);
is(Mojo::UserAgent->app, app, 'applications are equal');
my $dummy = Mojolicious::Lite->new;
isnt(Mojo::UserAgent->new->app($dummy)->app, app,
  'applications are not equal');
is(Mojo::UserAgent->app, app, 'applications are still equal');
Mojo::UserAgent->app($dummy);
isnt(Mojo::UserAgent->app, app, 'applications are not equal');
is(Mojo::UserAgent->app, $dummy, 'application are equal');
Mojo::UserAgent->app(app);
is(Mojo::UserAgent->app, app, 'applications are equal again');

# Clean up non-blocking requests
my $ua = Mojo::UserAgent->new;
my $get = my $post = '';
$ua->get('/' => sub { $get = pop->error });
$ua->post('/' => sub { $post = pop->error });
undef $ua;
is $get,  'Premature connection close', 'right error';
is $post, 'Premature connection close', 'right error';

# The poll reactor stops when there are no events being watched anymore
my $time = time;
Mojo::IOLoop->start;
ok time < ($time + 10), 'stopped automatically';

# Non-blocking
$ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my ($success, $code, $body);
$ua->get(
  '/' => sub {
    my ($ua, $tx) = @_;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
eval { $ua->get('/') };
like $@, qr/^Non-blocking requests in progress/, 'right error';
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works!', 'right content';

# Error in callback is logged
app->ua->once(error => sub { Mojo::IOLoop->stop });
ok app->ua->has_subscribers('error'), 'has subscribers';
my $err;
my $msg = app->log->on(message => sub { $err .= pop });
app->ua->get('/' => sub { die 'error event works' });
Mojo::IOLoop->start;
app->log->unsubscribe(message => $msg);
like $err, qr/error event works/, 'right error';

# HTTPS request without TLS support
my $tx = $ua->get($ua->app_url->scheme('https'));
ok $tx->error, 'has error';

# Blocking
$tx = $ua->get('/');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Again
$tx = $ua->get('/');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Events
my ($finished_req, $finished_tx, $finished_res);
$tx = $ua->build_tx(GET => '/');
ok !$tx->is_finished, 'transaction is not finished';
$ua->once(
  start => sub {
    my ($self, $tx) = @_;
    $tx->req->on(finish => sub { $finished_req++ });
    $tx->on(finish => sub { $finished_tx++ });
    $tx->res->on(finish => sub { $finished_res++ });
  }
);
$tx = $ua->start($tx);
ok $tx->success, 'successful';
is $finished_req, 1, 'finish event has been emitted once';
is $finished_tx,  1, 'finish event has been emitted once';
is $finished_res, 1, 'finish event has been emitted once';
ok $tx->req->is_finished, 'request is finished';
ok $tx->is_finished, 'transaction is finished';
ok $tx->res->is_finished, 'response is finished';
is $tx->res->code,        200, 'right status';
is $tx->res->body,        'works!', 'right content';

# Missing Content-Length header
($finished_req, $finished_tx, $finished_res) = ();
$tx = $ua->build_tx(GET => '/no_length');
ok !$tx->is_finished, 'transaction is not finished';
$ua->once(
  start => sub {
    my ($self, $tx) = @_;
    $tx->req->on(finish => sub { $finished_req++ });
    $tx->on(finish => sub { $finished_tx++ });
    $tx->res->on(finish => sub { $finished_res++ });
  }
);
$tx = $ua->start($tx);
ok $tx->success, 'successful';
is $finished_req, 1, 'finish event has been emitted once';
is $finished_tx,  1, 'finish event has been emitted once';
is $finished_res, 1, 'finish event has been emitted once';
ok $tx->req->is_finished, 'request is finished';
ok $tx->is_finished, 'transaction is finished';
ok $tx->res->is_finished, 'response is finished';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok !$tx->keep_alive, 'keep connection not alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# 204 No Content
$tx = $ua->get('/no_content');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 204, 'right status';
ok $tx->is_empty, 'transaction is empty';
is $tx->res->body, '', 'no content';

# Connection was kept alive
$tx = $ua->get('/');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200, 'right status';
ok !$tx->is_empty, 'transaction is not empty';
is $tx->res->body, 'works!', 'right content';

# Non-blocking form
($success, $code, $body) = ();
$ua->post(
  '/echo' => form => {hello => 'world'} => sub {
    my ($self, $tx) = @_;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'hello=world', 'right content';

# Non-blocking JSON
($success, $code, $body) = ();
$ua->post(
  '/echo' => json => {hello => 'world'} => sub {
    my ($self, $tx) = @_;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    '{"hello":"world"}', 'right content';

# Built-in web server times out
my $log = '';
$msg = app->log->on(message => sub { $log .= pop });
$tx = $ua->get('/timeout?timeout=0.25');
app->log->unsubscribe(message => $msg);
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close', 'right error';
is $timeout, 1, 'finish event has been emitted';
like $log, qr/Inactivity timeout\./, 'right log message';

# Client times out
$ua->once(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        Mojo::IOLoop->stream($connection)->timeout(0.25);
      }
    );
  }
);
$tx = $ua->get('/timeout?timeout=5');
ok !$tx->success, 'not successful';
is $tx->error, 'Inactivity timeout', 'right error';

# Response exceeding message size limit
$ua->once(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->res->max_message_size(12);
  }
);
$tx = $ua->get('/echo' => 'Hello World!');
ok !$tx->success, 'not successful';
is(($tx->error)[0], 'Maximum message size exceeded', 'right error');
is(($tx->error)[1], undef, 'no status');
ok $tx->res->is_limit_exceeded, 'limit is exceeded';

# 404 response
$tx = $ua->get('/does_not_exist');
ok !$tx->success, 'not successful';
is(($tx->error)[0], 'Not Found', 'right error');
is(($tx->error)[1], 404,         'right status');

# Fork safety
$tx = $ua->get('/');
is $tx->res->body, 'works!', 'right content';
my $last = $tx->connection;
my $port = $ua->app_url->port;
$tx = $ua->get('/');
is $tx->res->body, 'works!', 'right content';
is $tx->connection, $last, 'same connection';
is $ua->app_url->port, $port, 'same port';
{
  local $$ = -23;
  $tx = $ua->get('/');
  is $tx->res->body, 'works!', 'right content';
  isnt $tx->connection, $last, 'new connection';
  isnt $ua->app_url->port, $port, 'new port';
  $port = $ua->app_url->port;
  $last = $tx->connection;
  $tx   = $ua->get('/');
  is $tx->res->body, 'works!', 'right content';
  is $tx->connection, $last, 'same connection';
  is $ua->app_url->port, $port, 'same port';
}

# Introspect
my $req = my $res = '';
my $start = $ua->on(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        my $stream = Mojo::IOLoop->stream($connection);
        my $read   = $stream->on(
          read => sub {
            my ($stream, $chunk) = @_;
            $res .= $chunk;
          }
        );
        my $write = $stream->on(
          write => sub {
            my ($stream, $chunk) = @_;
            $req .= $chunk;
          }
        );
        $tx->on(
          finish => sub {
            $stream->unsubscribe(read  => $read);
            $stream->unsubscribe(write => $write);
          }
        );
      }
    );
  }
);
$tx = $ua->get('/', 'whatever');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('write')}, 0,
  'unsubscribed successfully';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('read')}, 1,
  'unsubscribed successfully';
like $req, qr!^GET / .*whatever$!s,      'right request';
like $res, qr|^HTTP/.*200 OK.*works!$|s, 'right response';
$ua->unsubscribe(start => $start);
ok !$ua->has_subscribers('start'), 'unsubscribed successfully';

# Stream with drain callback and compressed response
$tx = $ua->build_tx(GET => '/echo');
my $i = 0;
my ($stream, $drain);
$drain = sub {
  my $content = shift;
  return $ua->ioloop->timer(
    0.25 => sub {
      $content->write_chunk('');
      $tx->resume;
      $stream
        += @{Mojo::IOLoop->stream($tx->connection)->subscribers('drain')};
    }
  ) if $i >= 10;
  $content->write_chunk($i++, $drain);
  $tx->resume;
  return unless my $id = $tx->connection;
  $stream += @{Mojo::IOLoop->stream($id)->subscribers('drain')};
};
$tx->req->content->$drain;
$ua->start($tx);
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, '0123456789', 'right content';
is $stream, 1, 'no leaking subscribers';

# Nested non-blocking requests after blocking one, with custom URL
my @kept_alive;
$ua->get(
  $ua->app_url => sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      '/' => sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          $ua->app_url => sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# Simple nested non-blocking requests with timers
@kept_alive = ();
$ua->get(
  '/' => sub {
    push @kept_alive, pop->kept_alive;
    Mojo::IOLoop->timer(
      0 => sub {
        $ua->get(
          '/' => sub {
            push @kept_alive, pop->kept_alive;
            Mojo::IOLoop->timer(0 => sub { Mojo::IOLoop->stop });
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';

# Blocking request after non-blocking one, with custom URL
$tx = $ua->get($ua->app_url);
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Unexpected 1xx responses
$port = Mojo::IOLoop->generate_port;
$req  = Mojo::Message::Request->new;
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $port} => sub {
    my ($loop, $stream) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        $stream->write("HTTP/1.1 100 Continue\x0d\x0a"
            . "X-Foo: Bar\x0d\x0a\x0d\x0a"
            . "HTTP/1.1 101 Switching Protocols\x0d\x0a\x0d\x0a"
            . "HTTP/1.1 200 OK\x0d\x0a"
            . "Content-Length: 3\x0d\x0a\x0d\x0a" . 'Hi!')
          if $req->parse($chunk)->is_finished;
      }
    );
  }
);
$tx = $ua->build_tx(GET => "http://localhost:$port/");
my @unexpected;
$tx->on(unexpected => sub { push @unexpected, pop });
$tx = $ua->start($tx);
is $unexpected[0]->code, 100, 'right status';
is $unexpected[0]->headers->header('X-Foo'), 'Bar', 'right "X-Foo" value';
is $unexpected[1]->code, 101, 'right status';
ok $tx->success, 'successful';
is $tx->res->code, 200,   'right status';
is $tx->res->body, 'Hi!', 'right content';

# Premature connection close
$port = Mojo::IOLoop->generate_port;
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $port} => sub { Mojo::IOLoop->remove(pop) }
);
$tx = $ua->get("http://localhost:$port/");
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close', 'right error';

done_testing();
