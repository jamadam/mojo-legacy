use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_PROXY}   = 0;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use ojo;

# Application
a('/' => sub { $_->render(data => $_->req->method . $_->req->body) })
  ->secret('foobarbaz');
is a->secret, 'foobarbaz', 'right secret';

# Requests
is g('/')->body, 'GET',     'right content';
is h('/')->body, '',        'no content';
is o('/')->body, 'OPTIONS', 'right content';
is t('/')->body, 'PATCH',   'right content';
is p('/')->body, 'POST',    'right content';
is u('/')->body, 'PUT',     'right content';
is d('/')->body, 'DELETE',  'right content';
is p('/' => form => {foo => 'bar'})->body, 'POSTfoo=bar', 'right content';
is p('/' => json => {foo => 'bar'})->body, 'POST{"foo":"bar"}',
  'right content';

# Parse XML
is x('<title>works</title>')->at('title')->text, 'works', 'right text';

# JSON
is j([1, 2]), '[1,2]', 'right result';
is_deeply j('[1,2]'), [1, 2], 'right structure';
is j({foo => 'bar'}), '{"foo":"bar"}', 'right result';
is_deeply j('{"foo":"bar"}'), {foo => 'bar'}, 'right structure';

# ByteStream
is b('<foo>')->url_escape, '%3Cfoo%3E', 'right result';

# Collection
is c(1, 2, 3)->join('-'), '1-2-3', 'right result';

# Dumper
is r([1, 2]), "[\n  1,\n  2\n]\n", 'right result';

done_testing();
