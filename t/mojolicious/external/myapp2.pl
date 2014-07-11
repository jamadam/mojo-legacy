#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::IOLoop;

# Default for config file tests
app->defaults(secret => 'Insecure too!');

# Helpers sharing the same name in different embedded applications
helper same_name => sub {'myapp2'};

# Caching helper for state variable test
our %cache;
helper my_cache => sub { my $app = $_[0]->app; $cache{$app} = defined $cache{$app} ? $cache{$app} : shift->param('cache') };

# Delay dispatching
hook around_dispatch => sub {
  my ($next, $c) = @_;
  Mojo::IOLoop->next_tick(sub { $next->() });
};

get '/' => sub {
  my $c = shift;
  $c->render(
    text => $c->render_to_string('menubar') . app->defaults->{secret});
};

get '/cached' => sub {
  my $c = shift;
  $c->render(text => $c->my_cache);
};

app->start;
__DATA__

@@ menubar.html.ep
%= same_name
%= stash('message') || 'works 4!'
