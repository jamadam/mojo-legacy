use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# POD renderer plugin
plugin('PODRenderer')->name('perldoc');
ok app->routes->find('perldoc'), 'route found';

# Default layout
app->defaults(layout => 'gray');

get '/' => sub {
  my $self = shift;
  $self->render('simple', handler => 'pod');
};

post '/' => 'index';

post '/block' => 'block';

get '/empty' => {inline => '', handler => 'pod'};

my $t = Test::Mojo->new;

# Simple POD template
$t->get_ok('/')->status_is(200)
  ->content_like(qr|<h1>Test123</h1>\s+<p>It <code>works</code>!</p>|);

# POD helper
$t->post_ok('/')->status_is(200)
  ->content_like(qr!test123\s+<h1>A</h1>\s+<h1>B</h1>!)
  ->content_like(qr!\s+<p><code>test</code></p>!)->content_like(qr/Gray/);

# POD filter
$t->post_ok('/block')->status_is(200)
  ->content_like(qr!test321\s+<h2>lalala</h2>\s+<p><code>test</code></p>!)
  ->content_like(qr/Gray/);

# Empty
$t->get_ok('/empty')->status_is(200)->content_is('');

# Perldoc browser (Welcome)
$t->get_ok('/perldoc')->status_is(200)->text_is('h1 a[id="NAME"]', 'NAME')
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')->content_like(qr/galaxy/);

# Perldoc browser (Welcome with slash)
$t->get_ok('/perldoc/')->status_is(200)->text_is('h1 a[id="NAME"]', 'NAME')
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')->content_like(qr/galaxy/)
  ->content_unlike(qr/Gray/);

# Perldoc browser (Mojolicious)
$t->get_ok('/perldoc/Mojolicious')->status_is(200)
  ->text_is('h1 a[id="NAME"]', 'NAME')->text_is('a[id="handler"]', 'handler')
  ->text_like('p', qr/Mojolicious/)->content_like(qr/Sebastian Riedel/);

done_testing();

__DATA__

@@ layouts/gray.html.ep
Gray <%= content %>

@@ index.html.ep
test123<%= pod_to_html "=head1 A\n\n=head1 B\n\nC<test>"%>

@@ block.html.ep
test321<%= pod_to_html begin %>=head2 lalala

C<test><% end %>
