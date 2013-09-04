use Mojo::Base -strict;

use Test::More;
use Mojo::ByteStream 'b';
use Mojolicious::Routes::Pattern;

# Normal pattern with text, placeholders and a default value
my $pattern = Mojolicious::Routes::Pattern->new('/test/(controller)/:action');
$pattern->defaults({action => 'index'});
is_deeply $pattern->match('/test/foo/bar', 1),
  {controller => 'foo', action => 'bar'}, 'right structure';
is_deeply $pattern->match('/test/foo'),
  {controller => 'foo', action => 'index'}, 'right structure';
is_deeply $pattern->match('/test/foo/'),
  {controller => 'foo', action => 'index'}, 'right structure';
ok !$pattern->match('/test/'), 'no result';
is $pattern->render({controller => 'foo'}), '/test/foo', 'right result';

# Root
$pattern = Mojolicious::Routes::Pattern->new('/');
$pattern->defaults({action => 'index'});
ok !$pattern->match('/test/foo/bar'), 'no result';
is_deeply $pattern->match('/'), {action => 'index'}, 'right structure';
is $pattern->render, '/', 'right result';

# Regex in pattern
$pattern = Mojolicious::Routes::Pattern->new('/test/(controller)/:action/(id)',
  id => '\d+');
$pattern->defaults({action => 'index', id => 1});
is_deeply $pattern->match('/test/foo/bar/203'),
  {controller => 'foo', action => 'bar', id => 203}, 'right structure';
ok !$pattern->match('/test/foo/bar/baz'), 'no result';
is $pattern->render({controller => 'zzz', action => 'index', id => 13}),
  '/test/zzz/index/13', 'right result';
is $pattern->render({controller => 'zzz'}), '/test/zzz', 'right result';

# Quoted placeholders
$pattern = Mojolicious::Routes::Pattern->new('/(:controller)test/(action)');
$pattern->defaults({action => 'index'});
is_deeply $pattern->match('/footest/bar'),
  {controller => 'foo', action => 'bar'}, 'right structure';
is $pattern->render({controller => 'zzz', action => 'lala'}), '/zzztest/lala',
  'right result';
ok !$pattern->match('/test/lala'), 'no result';

# Relaxed
$pattern = Mojolicious::Routes::Pattern->new('/test/#controller/:action');
is_deeply $pattern->match('/test/foo.bar/baz'),
  {controller => 'foo.bar', action => 'baz'}, 'right structure';
is $pattern->render({controller => 'foo.bar', action => 'baz'}),
  '/test/foo.bar/baz', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/test/(#groovy)');
is_deeply $pattern->match('/test/foo.bar'), {groovy => 'foo.bar'},
  'right structure';
is $pattern->defaults->{format}, undef, 'no value';
is $pattern->render({groovy => 'foo.bar'}), '/test/foo.bar', 'right result';

# Wildcard
$pattern = Mojolicious::Routes::Pattern->new('/test/(:controller)/(*action)');
is_deeply $pattern->match('/test/foo/bar.baz/yada'),
  {controller => 'foo', action => 'bar.baz/yada'}, 'right structure';
is $pattern->render({controller => 'foo', action => 'bar.baz/yada'}),
  '/test/foo/bar.baz/yada', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/tset/:controller/*action');
is_deeply $pattern->match('/tset/foo/bar.baz/yada'),
  {controller => 'foo', action => 'bar.baz/yada'}, 'right structure';
is $pattern->render({controller => 'foo', action => 'bar.baz/yada'}),
  '/tset/foo/bar.baz/yada', 'right result';

# Render false value
$pattern = Mojolicious::Routes::Pattern->new('/:id');
is $pattern->render({id => 0}), '/0', 'right result';

# Regex in path
$pattern = Mojolicious::Routes::Pattern->new('/:test');
is_deeply $pattern->match('/test(test)(\Qtest\E)('),
  {test => 'test(test)(\Qtest\E)('}, 'right structure';
is $pattern->render({test => '23'}), '/23', 'right result';

# Regex in pattern
$pattern = Mojolicious::Routes::Pattern->new('/.+(:test)');
is_deeply $pattern->match('/.+test'), {test => 'test'}, 'right structure';
is $pattern->render({test => '23'}), '/.+23', 'right result';

# Unusual values
$pattern = Mojolicious::Routes::Pattern->new('/:test');
my $value = b('abc%E4cba')->url_unescape->to_string;
is_deeply $pattern->match("/$value"), {test => $value}, 'right structure';
is $pattern->render({test => $value}), "/$value", 'right result';
$value = b('abc%FCcba')->url_unescape->to_string;
is_deeply $pattern->match("/$value"), {test => $value}, 'right structure';
is $pattern->render({test => $value}), "/$value", 'right result';
$value = b('abc%DFcba')->url_unescape->to_string;
is_deeply $pattern->match("/$value"), {test => $value}, 'right structure';
is $pattern->render({test => $value}), "/$value", 'right result';
$value = b('abc%24cba')->url_unescape->to_string;
is_deeply $pattern->match("/$value"), {test => $value}, 'right structure';
is $pattern->render({test => $value}), "/$value", 'right result';
$value = b('abc%20cba')->url_unescape->to_string;
is_deeply $pattern->match("/$value"), {test => $value}, 'right structure';
is $pattern->render({test => $value}), "/$value", 'right result';

# Format detection
$pattern = Mojolicious::Routes::Pattern->new('/test');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
is_deeply $pattern->match('/test.xml', 1),
  {action => 'index', format => 'xml'}, 'right structure';
ok $pattern->regex,        'regex has been compiled on demand';
ok $pattern->format_regex, 'format regex has been compiled on demand';
$pattern = Mojolicious::Routes::Pattern->new('/test.json');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
is_deeply $pattern->match('/test.json'), {action => 'index'},
  'right structure';
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
is_deeply $pattern->match('/test.json', 1), {action => 'index'},
  'right structure';
ok !$pattern->match('/test.xml'), 'no result';
ok !$pattern->match('/test'),     'no result';

# Formats without detection
$pattern = Mojolicious::Routes::Pattern->new('/test');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
ok !$pattern->match('/test.xml'), 'no result';
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
is_deeply $pattern->match('/test'), {action => 'index'}, 'right structure';

# Format detection disabled
$pattern = Mojolicious::Routes::Pattern->new('/test', format => 0);
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
is_deeply $pattern->match('/test', 1), {action => 'index'}, 'right structure';
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
ok !$pattern->match('/test.xml', 1), 'no result';

# Special pattern for disabling format detection
$pattern = Mojolicious::Routes::Pattern->new(format => 0);
is $pattern->constraints->{format}, 0, 'right value';
$pattern->defaults({action => 'index'});
is_deeply $pattern->match('/', 1), {action => 'index'}, 'right structure';
ok !$pattern->match('/.xml', 1), 'no result';

# Versioned pattern
$pattern = Mojolicious::Routes::Pattern->new('/:test/v1.0');
$pattern->defaults({action => 'index', format => 'html'});
my $result = $pattern->match('/foo/v1.0', 1);
is_deeply $result, {test => 'foo', action => 'index', format => 'html'},
  'right structure';
is $pattern->render($result), '/foo/v1.0', 'right result';
is $pattern->render($result, 1), '/foo/v1.0.html', 'right result';
is $pattern->render({%$result, format => undef}, 1), '/foo/v1.0',
  'right result';
$result = $pattern->match('/foo/v1.0.txt', 1);
is_deeply $result, {test => 'foo', action => 'index', format => 'txt'},
  'right structure';
is $pattern->render($result), '/foo/v1.0', 'right result';
is $pattern->render($result, 1), '/foo/v1.0.txt', 'right result';
ok !$pattern->match('/foo/v2.0', 1), 'no result';

# Special placeholder names
$pattern = Mojolicious::Routes::Pattern->new('/:');
$result = $pattern->match('/foo', 1);
is_deeply $result, {'' => 'foo'}, 'right structure';
is $pattern->render($result, 1), '/foo', 'right result';
is $pattern->render({'' => 'bar'}, 1), '/bar', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/#');
$result = $pattern->match('/foo.bar', 1);
is_deeply $result, {'' => 'foo.bar'}, 'right structure';
is $pattern->render($result, 1), '/foo.bar', 'right result';
is $pattern->render({'' => 'bar.baz'}, 1), '/bar.baz', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/*');
$result = $pattern->match('/foo/bar', 1);
is_deeply $result, {'' => 'foo/bar'}, 'right structure';
is $pattern->render($result, 1), '/foo/bar', 'right result';
is $pattern->render({'' => 'bar/baz'}, 1), '/bar/baz', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/:/:0');
$result = $pattern->match('/foo/bar', 1);
is_deeply $result, {'' => 'foo', '0' => 'bar'}, 'right structure';
is $pattern->render($result, 1), '/foo/bar', 'right result';
is $pattern->render({'' => 'bar', '0' => 'baz'}, 1), '/bar/baz',
  'right result';
$pattern = Mojolicious::Routes::Pattern->new('/(:)test/(0)');
$result = $pattern->match('/footest/bar', 1);
is_deeply $result, {'' => 'foo', '0' => 'bar'}, 'right structure';
is $pattern->render($result, 1), '/footest/bar', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/()test');
$result = $pattern->match('/footest', 1);
is_deeply $result, {'' => 'foo'}, 'right structure';
is $pattern->render($result, 1), '/footest', 'right result';

# Unicode
$pattern = Mojolicious::Routes::Pattern->new('/(one)♥(two)');
$result  = $pattern->match('/i♥mojolicious');
is_deeply $result, {one => 'i', two => 'mojolicious'}, 'right structure';
is $pattern->render($result, 1), '/i♥mojolicious', 'right result';

done_testing();
