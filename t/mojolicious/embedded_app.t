use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# Custom secret
app->secret('very secr3t!');

# Mount full external application a few times
use FindBin;
my $external = "$FindBin::Bin/external/script/my_app";
plugin Mount => {'/x/1' => $external};
plugin(Mount => ('/x/♥' => $external));
plugin Mount => {'MOJOLICIO.US/' => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external));

get '/hello' => 'works';

get '/primary' => sub {
  my $self = shift;
  $self->render(text => ++$self->session->{primary});
};

my $t = Test::Mojo->new;

# Normal request
$t->get_ok('/hello')->status_is(200)->content_is("Hello from the main app!\n");

# Session
$t->get_ok('/primary')->status_is(200)->content_is(1);

# Session again
$t->get_ok('/primary')->status_is(200)->content_is(2);

# Session in external app
$t->get_ok('/x/1/secondary')->status_is(200)->content_is(1);

# Session again
$t->get_ok('/primary')->status_is(200)->content_is(3);

# Session in external app again
$t->get_ok('/x/1/secondary')->status_is(200)->content_is(2);

# External app
$t->get_ok('/x/1')->status_is(200)->content_is('too%21');

# Static file from external app
$t->get_ok('/x/1/index.html')->status_is(200)
  ->content_is("External static file!\n");

# External app with different prefix
$t->get_ok('/x/1/test')->status_is(200)->content_is('works%21');

# External app with unicode prefix
$t->get_ok('/x/♥')->status_is(200)->content_is('too%21');

# Static file from external app with unicode prefix
$t->get_ok('/x/♥/index.html')->status_is(200)
  ->content_is("External static file!\n");

# External app with unicode prefix again
$t->get_ok('/x/♥/test')->status_is(200)->content_is('works%21');

# External app with domain
$t->get_ok('/' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is('too%21');

# Static file from external app with domain
$t->get_ok('/index.html' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is("External static file!\n");

# External app with domain again
$t->get_ok('/test' => {Host => 'mojolicio.us'})->status_is(200)
  ->content_is('works%21');

# External app with a bit of everything
$t->get_ok('/♥/123/' => {Host => 'test.foo-bar.de'})->status_is(200)
  ->content_is('too%21');

# Static file from external app with a bit of everything
$t->get_ok('/♥/123/index.html' => {Host => 'test.foo-bar.de'})
  ->status_is(200)->content_is("External static file!\n");

# External app with a bit of everything again
$t->get_ok('/♥/123/test' => {Host => 'test.foo-bar.de'})->status_is(200)
  ->content_is('works%21');

done_testing();

__DATA__

@@ works.html.ep
Hello from the main app!
