use Mojo::Base -strict;

use Test::More;
use Mojo::JSON;
use Mojo::Server::PSGI;
use Mojolicious::Command::psgi;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

under sub {
  shift->on(finish => sub { $ENV{MOJO_HELLO} = 'world' });
};

get '/' => {text => 'Your Mojo is working!'};

get '/cookies' => sub {
  my $self   = shift;
  my $params = $self->req->params->to_hash;
  for my $key (sort keys %$params) { $self->cookie($key, $params->{$key}) }
  $self->render(text => 'nomnomnom');
};

post '/params' => sub {
  my $self = shift;
  $self->render(json => $self->req->params->to_hash);
};

# Binding
my $app = Mojo::Server::PSGI->new(app => app)->to_psgi_app;
my $content = 'hello=world';
open my $body, '<', \$content;
my $env = {
  CONTENT_LENGTH      => 11,
  CONTENT_TYPE        => 'application/x-www-form-urlencoded',
  PATH_INFO           => '/params',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'POST',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.0',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => $body,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
my $res = $app->($env);
is $res->[0], 200, 'right status';
my %headers = @{$res->[1]};
ok keys(%headers) >= 3, 'enough headers';
ok $headers{Date}, 'has "Date" value';
is $headers{'Content-Length'}, 43, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
my $params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
$res->[2]->close;
is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
$params = Mojo::JSON->new->decode($params);
is_deeply $params, {bar => 'baz', hello => 'world', lalala => 23},
  'right structure';

# Command
$content = 'world=hello';
open $body, '<', \$content;
$env = {
  CONTENT_LENGTH      => 11,
  CONTENT_TYPE        => 'application/x-www-form-urlencoded',
  PATH_INFO           => '/params',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'POST',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.0',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => $body,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
$app = Mojolicious::Command::psgi->new(app => app)->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
%headers = @{$res->[1]};
ok keys(%headers) >= 3, 'enough headers';
ok $headers{Date}, 'has "Date" value';
is $headers{'Content-Length'}, 43, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'application/json', 'right "Content-Type" value';
$params = '';
while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
$res->[2]->close;
is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
$params = Mojo::JSON->new->decode($params);
is_deeply $params, {bar => 'baz', world => 'hello', lalala => 23},
  'right structure';

# Simple
$env = {
  CONTENT_LENGTH      => 0,
  PATH_INFO           => '/',
  REQUEST_METHOD      => 'GET',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.1',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => *STDIN,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
$app = Mojolicious::Command::psgi->new(app => app)->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
%headers = @{$res->[1]};
is $headers{'Content-Length'}, 21, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
$body = '';
while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
is $body, 'Your Mojo is working!', 'right content';
is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
$res->[2]->close;
is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';

# HEAD request
$env = {
  CONTENT_LENGTH      => 0,
  PATH_INFO           => '/',
  REQUEST_METHOD      => 'HEAD',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.1',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => *STDIN,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
$app = Mojolicious::Command::psgi->new(app => app)->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
%headers = @{$res->[1]};
is $headers{'Content-Length'}, 21, 'right "Content-Length" value';
is $headers{'Content-Type'}, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
$body = '';
while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
is $body, '', 'no content';
is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
$res->[2]->close;
is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';

# Cookies
$env = {
  CONTENT_LENGTH      => 0,
  PATH_INFO           => '/cookies',
  QUERY_STRING        => 'lalala=23&bar=baz',
  REQUEST_METHOD      => 'GET',
  SCRIPT_NAME         => '/',
  HTTP_HOST           => 'localhost:8080',
  SERVER_PROTOCOL     => 'HTTP/1.1',
  'psgi.version'      => [1, 0],
  'psgi.url_scheme'   => 'http',
  'psgi.input'        => *STDIN,
  'psgi.errors'       => *STDERR,
  'psgi.multithread'  => 0,
  'psgi.multiprocess' => 1,
  'psgi.run_once'     => 0
};
$app = Mojolicious::Command::psgi->new(app => app)->run;
$res = $app->($env);
is $res->[0], 200, 'right status';
ok scalar @{$res->[1]} >= 10, 'enough headers';
my $i = 0;
for my $header (@{$res->[1]}) { $i++ if $header eq 'Set-Cookie' }
is $i, 2, 'right number of "Set-Cookie" headers';

done_testing();
