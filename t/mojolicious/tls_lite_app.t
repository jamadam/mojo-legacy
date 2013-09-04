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
use Mojo::UserAgent;
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('fatal');

# Secure sessions
app->sessions->secure(1);

get '/login' => sub {
  my $self = shift;
  my $name = $self->param('name') || 'anonymous';
  $self->session(name => $name);
  $self->render(text => "Welcome $name!");
};

get '/again' => sub {
  my $self = shift;
  my $name = $self->session('name') || 'anonymous';
  $self->render(text => "Welcome back $name!");
};

get '/logout' => sub {
  my $self = shift;
  $self->session(expires => 1);
  $self->redirect_to('login');
};

# Use HTTPS
my $t = Test::Mojo->new;
$t->ua->max_redirects(5);
$t->reset_session->ua->app_url('https');

# Login
$t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome sri!');
ok $t->tx->res->cookie('mojolicious')->expires, 'session cookie expires';
ok $t->tx->res->cookie('mojolicious')->secure,  'session cookie is secure';

# Return
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back sri!');

# Logout
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# Expired session
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back anonymous!');

# No session
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# Use HTTP
$t->reset_session->ua->app_url('http');

# Login again
$t->reset_session->get_ok('/login?name=sri')->status_is(200)
  ->content_is('Welcome sri!');

# Return
$t->get_ok('/again')->status_is(200)->content_is('Welcome back anonymous!');

# Use HTTPS again (without expiration)
$t->reset_session->ua->app_url('https');
app->sessions->default_expiration(0);

# Login again
$t->get_ok('/login?name=sri' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome sri!');
ok !$t->tx->res->cookie('mojolicious')->expires,
  'session cookie does not expire';
ok $t->tx->res->cookie('mojolicious')->secure, 'session cookie is secure';

# Return
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back sri!');

# Logout
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

# Expired session
$t->get_ok('/again' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome back anonymous!');

# No session
$t->get_ok('/logout' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_is('Welcome anonymous!');

done_testing();
