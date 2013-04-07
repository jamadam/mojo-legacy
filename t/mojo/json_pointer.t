use Mojo::Base -strict;

use Test::More;
use Mojo::JSON::Pointer;

# "contains" (hash)
my $pointer = Mojo::JSON::Pointer->new;
ok $pointer->contains({foo => 23}, ''),     'contains ""';
ok $pointer->contains({foo => 23}, '/foo'), 'contains "/foo"';
ok !$pointer->contains({foo => 23}, '/bar'), 'does not contains "/bar"';
ok $pointer->contains({foo => {bar => undef}}, '/foo/bar'),
  'contains "/foo/bar"';

# "contains" (mixed)
ok $pointer->contains({foo => [0, 1, 2]}, ''),       'contains ""';
ok $pointer->contains({foo => [0, 1, 2]}, '/foo/0'), 'contains "/foo/0"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/foo/9'),
  'does not contain "/foo/9"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/foo/bar'),
  'does not contain "/foo/bar"';
ok !$pointer->contains({foo => [0, 1, 2]}, '/0'), 'does not contain "/0"';

# "get" (hash)
is_deeply $pointer->get({foo => 'bar'}, ''), {foo => 'bar'},
  '"" is "{foo => "bar"}"';
is $pointer->get({foo => 'bar'}, '/foo'), 'bar', '"/foo" is "bar"';
is $pointer->get({foo => {bar => 42}}, '/foo/bar'), 42, '"/foo/bar" is "42"';
is_deeply $pointer->get({foo => {23 => {baz => 0}}}, '/foo/23'), {baz => 0},
  '"/foo/23" is "{baz => 0}"';

# "get" (mixed)
is_deeply $pointer->get({foo => {bar => [1, 2, 3]}}, '/foo/bar'), [1, 2, 3],
  '"/foo/bar" is "[1, 2, 3]"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/0'), 0,
  '"/foo/bar/0" is "0"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/1'), undef,
  '"/foo/bar/1" is "undef"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/2'), 3,
  '"/foo/bar/2" is "3"';
is $pointer->get({foo => {bar => [0, undef, 3]}}, '/foo/bar/6'), undef,
  '"/foo/bar/6" is "undef"';

# "get" (encoded)
is $pointer->get([{'foo/bar' => 'bar'}], '/0/foo~1bar'), 'bar',
  '"/0/foo~1bar" is "bar"';
is $pointer->get([{'foo/bar/baz' => 'yada'}], '/0/foo~1bar~1baz'), 'yada',
  '"/0/foo~1bar~1baz" is "yada"';
is $pointer->get([{'foo~/bar' => 'bar'}], '/0/foo~0~1bar'), 'bar',
  '"/0/foo~0~1bar" is "bar"';
is $pointer->get(
  [{'f~o~o~/b~' => {'a~' => {'r' => 'baz'}}}] => '/0/f~0o~0o~0~1b~0/a~0/r'),
  'baz', '"/0/f~0o~0o~0~1b~0/a~0/r" is "baz"';

# Unicode
is $pointer->get({'☃' => 'snowman'}, '/☃'), 'snowman', 'found the snowman';
is $pointer->get({'☃' => ['snowman']}, '/☃/0'), 'snowman',
  'found the snowman';

# RFC 6901
my $hash = {
  foo    => ['bar', 'baz'],
  ''     => 0,
  'a/b'  => 1,
  'c%d'  => 2,
  'e^f'  => 3,
  'g|h'  => 4,
  'i\\j' => 5,
  'k"l'  => 6,
  ' '    => 7,
  'm~n'  => 8
};
is_deeply $pointer->get($hash, ''), $hash, 'empty pointer is whole document';
is_deeply $pointer->get($hash, '/foo'), ['bar', 'baz'],
  '"/foo" is "["bar", "baz"]"';
is $pointer->get($hash, '/foo/0'), 'bar', '"/foo/0" is "bar"';
is $pointer->get($hash, '/'),      0,     '"/" is 0';
is $pointer->get($hash, '/a~1b'),  1,     '"/a~1b" is 1';
is $pointer->get($hash, '/c%d'),   2,     '"/c%d" is 2';
is $pointer->get($hash, '/e^f'),   3,     '"/e^f" is 3';
is $pointer->get($hash, '/g|h'),   4,     '"/g|h" is 4';
is $pointer->get($hash, '/i\\j'),  5,     '"/i\\\\j" is 5';
is $pointer->get($hash, '/k"l'),   6,     '"/k\\"l" is 6';
is $pointer->get($hash, '/ '),     7,     '"/ " is 7';
is $pointer->get($hash, '/m~0n'),  8,     '"/m~0n" is 8';

done_testing();
