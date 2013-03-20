use Mojo::Base -strict;

use Test::More;
use Mojo::DOM;
use Mojo::Util 'encode';

# Simple (basics)
my $dom = Mojo::DOM->new->parse(
  '<div><div FOO="0" id="a">A</div><div id="b">B</div></div>');
is $dom->at('#b')->text, 'B', 'right text';
my @div;
push @div, $dom->find('div[id]')->pluck('text')->each;
is_deeply \@div, [qw(A B)], 'found all div elements with id';
@div = ();
$dom->find('div[id]')->each(sub { push @div, $_->text });
is_deeply \@div, [qw(A B)], 'found all div elements with id';
is $dom->at('#a')->attrs('foo'), 0, 'right attribute';
is $dom->at('#a')->attrs->{foo}, 0, 'right attribute';
is "$dom", '<div><div foo="0" id="a">A</div><div id="b">B</div></div>',
  'right result';

# Simple nesting with healing (tree structure)
$dom = Mojo::DOM->new->parse(<<EOF);
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</bar>works</foo>
EOF
is $dom->tree->[0], 'root', 'right element';
is $dom->tree->[1][0], 'tag', 'right element';
is $dom->tree->[1][1], 'foo', 'right tag';
is_deeply $dom->tree->[1][2], {}, 'empty attributes';
is $dom->tree->[1][3], $dom->tree, 'right parent';
is $dom->tree->[1][4][0], 'tag', 'right element';
is $dom->tree->[1][4][1], 'bar', 'right tag';
is_deeply $dom->tree->[1][4][2], {a => 'b<c'}, 'right attributes';
is $dom->tree->[1][4][3], $dom->tree->[1], 'right parent';
is $dom->tree->[1][4][4][0], 'text', 'right element';
is $dom->tree->[1][4][4][1], 'ju',   'right text';
is $dom->tree->[1][4][5][0], 'tag',  'right element';
is $dom->tree->[1][4][5][1], 'baz',  'right tag';
is_deeply $dom->tree->[1][4][5][2], {a23 => undef}, 'right attributes';
is $dom->tree->[1][4][5][3], $dom->tree->[1][4], 'right parent';
is $dom->tree->[1][4][5][4][0], 'text', 'right element';
is $dom->tree->[1][4][5][4][1], 's',    'right text';
is $dom->tree->[1][4][5][5][0], 'tag',  'right element';
is $dom->tree->[1][4][5][5][1], 'bazz', 'right tag';
is_deeply $dom->tree->[1][4][5][5][2], {}, 'empty attributes';
is $dom->tree->[1][4][5][5][3], $dom->tree->[1][4][5], 'right parent';
is $dom->tree->[1][4][5][6][0], 'text', 'right element';
is $dom->tree->[1][4][5][6][1], 't',    'right text';
is $dom->tree->[1][5][0], 'text',  'right element';
is $dom->tree->[1][5][1], 'works', 'right text';
is "$dom", <<EOF, 'right result';
<foo><bar a="b&lt;c">ju<baz a23>s<bazz></bazz>t</baz></bar>works</foo>
EOF

# Select based on parent
$dom = Mojo::DOM->new->parse(<<EOF);
<body>
  <div>test1</div>
  <div><div>test2</div></div>
<body>
EOF
is $dom->find('body > div')->[0]->text, 'test1', 'right text';
is $dom->find('body > div')->[1]->text, '',      'no content';
is $dom->find('body > div')->[2], undef, 'no result';
is $dom->find('body > div')->size, 2, 'right number of elements';
is $dom->find('body > div > div')->[0]->text, 'test2', 'right text';
is $dom->find('body > div > div')->[1], undef, 'no result';
is $dom->find('body > div > div')->size, 1, 'right number of elements';

# A bit of everything (basic navigation)
$dom = Mojo::DOM->new->parse(<<EOF);
<!doctype foo>
<foo bar="ba&lt;z">
  test
  <simple class="working">easy</simple>
  <test foo="bar" id="test" />
  <!-- lala -->
  works well
  <![CDATA[ yada yada]]>
  <?boom lalalala ?>
  <a little bit broken>
  < very broken
  <br />
  more text
</foo>
EOF
is $dom->xml,  undef, 'xml mode not detected';
is $dom->type, '',    'no type';
is $dom->attrs('foo'), '', 'no attribute';
is $dom->attrs(foo => 'bar')->attrs('foo'), '', 'no attribute';
is $dom->tree->[1][0], 'doctype', 'right element';
is $dom->tree->[1][1], ' foo',    'right doctype';
is "$dom", <<EOF, 'right result';
<!DOCTYPE foo>
<foo bar="ba&lt;z">
  test
  <simple class="working">easy</simple>
  <test foo="bar" id="test"></test>
  <!-- lala -->
  works well
  <![CDATA[ yada yada]]>
  <?boom lalalala ?>
  <a bit broken little>
  <very <br broken></very>
  more text
</a></foo>
EOF
my $simple = $dom->at('foo simple.working[class^="wor"]');
is $simple->parent->all_text, 'test easy works well yada yada more text',
  'right text';
is $simple->type, 'simple', 'right type';
is $simple->attrs('class'), 'working', 'right class attribute';
is $simple->text, 'easy', 'right text';
is $simple->parent->type, 'foo', 'right parent type';
is $simple->parent->attrs->{bar}, 'ba<z', 'right parent attribute';
is $simple->parent->children->[1]->type, 'test', 'right sibling';
is $simple->to_xml, '<simple class="working">easy</simple>',
  'stringified right';
$simple->parent->attrs(bar => 'baz')->attrs({this => 'works', too => 'yea'});
is $simple->parent->attrs('bar'),  'baz',   'right parent attribute';
is $simple->parent->attrs('this'), 'works', 'right parent attribute';
is $simple->parent->attrs('too'),  'yea',   'right parent attribute';
is $dom->at('test#test')->type,         'test',   'right type';
is $dom->at('[class$="ing"]')->type,    'simple', 'right type';
is $dom->at('[class="working"]')->type, 'simple', 'right type';
is $dom->at('[class$=ing]')->type,      'simple', 'right type';
is $dom->at('[class=working]')->type,   'simple', 'right type';
is $dom->at('foo > simple')->next->type, 'test', 'right type';
is $dom->at('foo > simple')->next->next->type, 'a', 'right type';
is $dom->at('foo > test')->previous->type, 'simple', 'right type';
is $dom->next,     undef, 'no siblings';
is $dom->previous, undef, 'no siblings';
is $dom->at('foo > a')->next,          undef, 'no next sibling';
is $dom->at('foo > simple')->previous, undef, 'no previous sibling';

# Class and ID
$dom = Mojo::DOM->new->parse('<div id="id" class="class">a</div>');
is $dom->at('div#id.class')->text, 'a', 'right text';

# Deep nesting (parent combinator)
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <title>Foo</title>
  </head>
  <body>
    <div id="container">
      <div id="header">
        <div id="logo">Hello World</div>
        <div id="buttons">
          <p id="foo">Foo</p>
        </div>
      </div>
      <form>
        <div id="buttons">
          <p id="bar">Bar</p>
        </div>
      </form>
      <div id="content">More stuff</div>
    </div>
  </body>
</html>
EOF
my $p = $dom->find('body > #container > div p[id]');
is $p->[0]->attrs('id'), 'foo', 'right id attribute';
is $p->[1], undef, 'no second result';
is $p->size, 1, 'right number of elements';
my @p;
@div = ();
$dom->find('div')->each(sub { push @div, $_->attrs('id') });
$dom->find('p')->each(sub { push @p, $_->attrs('id') });
is_deeply \@p, [qw(foo bar)], 'found all p elements';
my $ids = [qw(container header logo buttons buttons content)];
is_deeply \@div, $ids, 'found all div elements';

# Script tag
$dom = Mojo::DOM->new->parse(<<EOF);
<script charset="utf-8">alert('lalala');</script>
EOF
is $dom->at('script')->text, "alert('lalala');", 'right script content';

# HTML5 (unquoted values)
$dom = Mojo::DOM->new->parse(
  qq{<div id = test foo ="bar" class=tset>works</div>});
is $dom->at('#test')->text,       'works', 'right text';
is $dom->at('div')->text,         'works', 'right text';
is $dom->at('[foo="bar"]')->text, 'works', 'right text';
is $dom->at('[foo="ba"]'), undef, 'no result';
is $dom->at('[foo=bar]')->text, 'works', 'right text';
is $dom->at('[foo=ba]'), undef, 'no result';
is $dom->at('.tset')->text, 'works', 'right text';

# HTML1 (single quotes, upper case tags and whitespace in attributes)
$dom = Mojo::DOM->new->parse(
  qq{<DIV id = 'test' foo ='bar' class= "tset">works</DIV>});
is $dom->at('#test')->text,       'works', 'right text';
is $dom->at('div')->text,         'works', 'right text';
is $dom->at('[foo="bar"]')->text, 'works', 'right text';
is $dom->at('[foo="ba"]'), undef, 'no result';
is $dom->at('[foo=bar]')->text, 'works', 'right text';
is $dom->at('[foo=ba]'), undef, 'no result';
is $dom->at('.tset')->text, 'works', 'right text';

# Already decoded Unicode snowman and quotes in selector
$dom = Mojo::DOM->new->parse('<div id="snowm&quot;an">☃</div>');
is $dom->at('[id="snowm\"an"]')->text,      '☃', 'right text';
is $dom->at('[id="snowm\22 an"]')->text,    '☃', 'right text';
is $dom->at('[id="snowm\000022an"]')->text, '☃', 'right text';
is $dom->at('[id="snowm\22an"]'),      undef, 'no result';
is $dom->at('[id="snowm\21 an"]'),     undef, 'no result';
is $dom->at('[id="snowm\000021an"]'),  undef, 'no result';
is $dom->at('[id="snowm\000021 an"]'), undef, 'no result';

# Unicode and escaped selectors
my $chars
  = qq{<html><div id="☃x">Snowman</div><div class="x ♥">Heart</div></html>};
my $bytes = encode 'UTF-8', $chars;
$dom = Mojo::DOM->new->charset('UTF-8');
$dom->parse($bytes);
is $dom->at("#\\\n\\002603x")->text,                  'Snowman', 'right text';
is $dom->at('#\\2603 x')->text,                       'Snowman', 'right text';
is $dom->at("#\\\n\\2603 x")->text,                   'Snowman', 'right text';
is $dom->at(qq{[id="\\\n\\2603 x"]})->text,           'Snowman', 'right text';
is $dom->at(qq{[id="\\\n\\002603x"]})->text,          'Snowman', 'right text';
is $dom->at(qq{[id="\\\\2603 x"]})->text,             'Snowman', 'right text';
is $dom->at("html #\\\n\\002603x")->text,             'Snowman', 'right text';
is $dom->at('html #\\2603 x')->text,                  'Snowman', 'right text';
is $dom->at("html #\\\n\\2603 x")->text,              'Snowman', 'right text';
is $dom->at(qq{html [id="\\\n\\2603 x"]})->text,      'Snowman', 'right text';
is $dom->at(qq{html [id="\\\n\\002603x"]})->text,     'Snowman', 'right text';
is $dom->at(qq{html [id="\\\\2603 x"]})->text,        'Snowman', 'right text';
is $dom->at('#☃x')->text,                           'Snowman', 'right text';
is $dom->at('div#☃x')->text,                        'Snowman', 'right text';
is $dom->at('html div#☃x')->text,                   'Snowman', 'right text';
is $dom->at('[id^="☃"]')->text,                     'Snowman', 'right text';
is $dom->at('div[id^="☃"]')->text,                  'Snowman', 'right text';
is $dom->at('html div[id^="☃"]')->text,             'Snowman', 'right text';
is $dom->at('html > div[id^="☃"]')->text,           'Snowman', 'right text';
is $dom->at('[id^=☃]')->text,                       'Snowman', 'right text';
is $dom->at('div[id^=☃]')->text,                    'Snowman', 'right text';
is $dom->at('html div[id^=☃]')->text,               'Snowman', 'right text';
is $dom->at('html > div[id^=☃]')->text,             'Snowman', 'right text';
is $dom->at(".\\\n\\002665")->text,                   'Heart',   'right text';
is $dom->at('.\\2665')->text,                         'Heart',   'right text';
is $dom->at("html .\\\n\\002665")->text,              'Heart',   'right text';
is $dom->at('html .\\2665')->text,                    'Heart',   'right text';
is $dom->at(qq{html [class\$="\\\n\\002665"]})->text, 'Heart',   'right text';
is $dom->at(qq{html [class\$="\\2665"]})->text,       'Heart',   'right text';
is $dom->at(qq{[class\$="\\\n\\002665"]})->text,      'Heart',   'right text';
is $dom->at(qq{[class\$="\\2665"]})->text,            'Heart',   'right text';
is $dom->at('.x')->text,                              'Heart',   'right text';
is $dom->at('html .x')->text,                         'Heart',   'right text';
is $dom->at('.♥')->text,                            'Heart',   'right text';
is $dom->at('html .♥')->text,                       'Heart',   'right text';
is $dom->at('div.♥')->text,                         'Heart',   'right text';
is $dom->at('html div.♥')->text,                    'Heart',   'right text';
is $dom->at('[class$="♥"]')->text,                  'Heart',   'right text';
is $dom->at('div[class$="♥"]')->text,               'Heart',   'right text';
is $dom->at('html div[class$="♥"]')->text,          'Heart',   'right text';
is $dom->at('html > div[class$="♥"]')->text,        'Heart',   'right text';
is $dom->at('[class$=♥]')->text,                    'Heart',   'right text';
is $dom->at('div[class$=♥]')->text,                 'Heart',   'right text';
is $dom->at('html div[class$=♥]')->text,            'Heart',   'right text';
is $dom->at('html > div[class$=♥]')->text,          'Heart',   'right text';
is $dom->at('[class~="♥"]')->text,                  'Heart',   'right text';
is $dom->at('div[class~="♥"]')->text,               'Heart',   'right text';
is $dom->at('html div[class~="♥"]')->text,          'Heart',   'right text';
is $dom->at('html > div[class~="♥"]')->text,        'Heart',   'right text';
is $dom->at('[class~=♥]')->text,                    'Heart',   'right text';
is $dom->at('div[class~=♥]')->text,                 'Heart',   'right text';
is $dom->at('html div[class~=♥]')->text,            'Heart',   'right text';
is $dom->at('html > div[class~=♥]')->text,          'Heart',   'right text';
is $dom->at('[class~="x"]')->text,                    'Heart',   'right text';
is $dom->at('div[class~="x"]')->text,                 'Heart',   'right text';
is $dom->at('html div[class~="x"]')->text,            'Heart',   'right text';
is $dom->at('html > div[class~="x"]')->text,          'Heart',   'right text';
is $dom->at('[class~=x]')->text,                      'Heart',   'right text';
is $dom->at('div[class~=x]')->text,                   'Heart',   'right text';
is $dom->at('html div[class~=x]')->text,              'Heart',   'right text';
is $dom->at('html > div[class~=x]')->text,            'Heart',   'right text';
is $dom->to_xml,      $bytes, 'XML is encoded';
is $dom->content_xml, $bytes, 'XML is encoded';
$dom->charset(undef);
is $dom->to_xml,      $chars, 'XML is not encoded';
is $dom->content_xml, $chars, 'XML is not encoded';

# Looks remotely like HTML
$dom = Mojo::DOM->new->parse(
  '<!DOCTYPE H "-/W/D HT 4/E">☃<title class=test>♥</title>☃');
is $dom->at('title')->text, '♥', 'right text';
is $dom->at('*')->text,     '♥', 'right text';
is $dom->at('.test')->text, '♥', 'right text';

# Replace elements
$dom = Mojo::DOM->new->parse('<div>foo<p>lalala</p>bar</div>');
is $dom->at('p')->replace('<foo>bar</foo>'), '<p>lalala</p>', 'right result';
is "$dom", '<div>foo<foo>bar</foo>bar</div>', 'right result';
$dom->at('foo')->replace(Mojo::DOM->new->parse('text'));
is "$dom", '<div>footextbar</div>', 'right result';
$dom = Mojo::DOM->new->parse('<div>foo</div><div>bar</div>');
$dom->find('div')->each(sub { shift->replace('<p>test</p>') });
is "$dom", '<p>test</p><p>test</p>', 'right result';
$dom = Mojo::DOM->new->parse('<div>foo<p>lalala</p>bar</div>');
is $dom->replace('♥'), '♥', 'right result';
is "$dom", '♥', 'right result';
$dom->replace('<div>foo<p>lalala</p>bar</div>');
is "$dom", '<div>foo<p>lalala</p>bar</div>', 'right result';
is $dom->at('p')->replace(''), '<p>lalala</p>', 'right result';
is "$dom", '<div>foobar</div>', 'right result';
is $dom->replace(''), '', 'right result';
is "$dom", '', 'right result';
$dom->replace('<div>foo<p>lalala</p>bar</div>');
is "$dom", '<div>foo<p>lalala</p>bar</div>', 'right result';
$dom->find('p')->pluck(replace => '');
is "$dom", '<div>foobar</div>', 'right result';
$dom = Mojo::DOM->new->parse('<div>♥</div>');
$dom->at('div')->replace_content('☃');
is "$dom", '<div>☃</div>', 'right result';
$dom = Mojo::DOM->new->parse('<div>♥</div>');
$dom->at('div')->replace_content("\x{2603}");
is $dom->to_xml, '<div>☃</div>', 'right result';
is $dom->at('div')->replace('<p>♥</p>')->root, '<p>♥</p>', 'right result';
is $dom->to_xml, '<p>♥</p>', 'right result';
is $dom->replace('<b>whatever</b>')->root, '<b>whatever</b>', 'right result';
is $dom->to_xml, '<b>whatever</b>', 'right result';
$dom->at('b')->prepend('<p>foo</p>')->append('<p>bar</p>');
is "$dom", '<p>foo</p><b>whatever</b><p>bar</p>', 'right result';
is $dom->find('p')->pluck('remove')->first->root->at('b')->text, 'whatever',
  'right result';
is "$dom", '<b>whatever</b>', 'right result';
$dom->remove;
is "$dom", '', 'right result';

# Replace element content
$dom = Mojo::DOM->new->parse('<div>foo<p>lalala</p>bar</div>');
is $dom->at('p')->replace_content('bar'), '<p>bar</p>', 'right result';
is "$dom", '<div>foo<p>bar</p>bar</div>', 'right result';
$dom->at('p')->replace_content(Mojo::DOM->new->parse('text'));
is "$dom", '<div>foo<p>text</p>bar</div>', 'right result';
$dom = Mojo::DOM->new->parse('<div>foo</div><div>bar</div>');
$dom->find('div')->each(sub { shift->replace_content('<p>test</p>') });
is "$dom", '<div><p>test</p></div><div><p>test</p></div>', 'right result';
$dom->find('p')->each(sub { shift->replace_content('') });
is "$dom", '<div><p></p></div><div><p></p></div>', 'right result';
$dom = Mojo::DOM->new->parse('<div><p id="☃" /></div>');
$dom->at('#☃')->replace_content('♥');
is "$dom", '<div><p id="☃">♥</p></div>', 'right result';
$dom = Mojo::DOM->new->parse('<div>foo<p>lalala</p>bar</div>');
$dom->replace_content('♥');
is "$dom", '♥', 'right result';
is $dom->replace_content('<div>foo<p>lalala</p>bar</div>'),
  '<div>foo<p>lalala</p>bar</div>', 'right result';
is "$dom", '<div>foo<p>lalala</p>bar</div>', 'right result';
is $dom->replace_content(''), '', 'right result';
is "$dom", '', 'right result';
$dom->replace_content('<div>foo<p>lalala</p>bar</div>');
is "$dom", '<div>foo<p>lalala</p>bar</div>', 'right result';
is $dom->at('p')->replace_content(''), '<p></p>', 'right result';

# Mixed search and tree walk
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
  <tr>
    <td>text1</td>
    <td>text2</td>
  </tr>
</table>
EOF
my @data;
for my $tr ($dom->find('table tr')->each) {
  for my $td (@{$tr->children}) {
    push @data, $td->type, $td->all_text;
  }
}
is $data[0], 'td',    'right tag';
is $data[1], 'text1', 'right text';
is $data[2], 'td',    'right tag';
is $data[3], 'text2', 'right text';
is $data[4], undef,   'no tag';

# RSS
$dom = Mojo::DOM->new->parse(<<EOF);
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
  <channel>
    <title>Test Blog</title>
    <link>http://blog.kraih.com</link>
    <description>lalala</description>
    <generator>Mojolicious</generator>
    <item>
      <pubDate>Mon, 12 Jul 2010 20:42:00</pubDate>
      <title>Works!</title>
      <link>http://blog.kraih.com/test</link>
      <guid>http://blog.kraih.com/test</guid>
      <description>
        <![CDATA[<p>trololololo>]]>
      </description>
      <my:extension foo:id="works">
        <![CDATA[
          [awesome]]
        ]]>
      </my:extension>
    </item>
  </channel>
</rss>
EOF
is $dom->xml, 1, 'xml mode detected';
is $dom->find('rss')->[0]->attrs('version'), '2.0', 'right version';
is $dom->at('extension')->attrs('foo:id'), 'works', 'right id';
like $dom->at('#works')->text,       qr/\[awesome\]\]/, 'right text';
like $dom->at('[id="works"]')->text, qr/\[awesome\]\]/, 'right text';
is $dom->find('description')->[1]->text, '<p>trololololo>', 'right text';
is $dom->at('pubDate')->text,        'Mon, 12 Jul 2010 20:42:00', 'right text';
like $dom->at('[id*="ork"]')->text,  qr/\[awesome\]\]/,           'right text';
like $dom->at('[id*="orks"]')->text, qr/\[awesome\]\]/,           'right text';
like $dom->at('[id*="work"]')->text, qr/\[awesome\]\]/,           'right text';
like $dom->at('[id*="or"]')->text,   qr/\[awesome\]\]/,           'right text';

# Namespace
$dom = Mojo::DOM->new->parse(<<EOF);
<?xml version="1.0"?>
<bk:book xmlns='uri:default-ns'
         xmlns:bk='uri:book-ns'
         xmlns:isbn='uri:isbn-ns'>
  <bk:title>Programming Perl</bk:title>
  <comment>rocks!</comment>
  <nons xmlns=''>
    <section>Nothing</section>
  </nons>
  <meta xmlns='uri:meta-ns'>
    <isbn:number>978-0596000271</isbn:number>
  </meta>
</bk:book>
EOF
is $dom->xml,       1,  'xml mode detected';
is $dom->namespace, '', 'no namespace';
is $dom->at('book comment')->namespace, 'uri:default-ns', 'right namespace';
is $dom->at('book comment')->text,      'rocks!',         'right text';
is $dom->at('book nons section')->namespace, '',            'no namespace';
is $dom->at('book nons section')->text,      'Nothing',     'right text';
is $dom->at('book meta number')->namespace,  'uri:isbn-ns', 'right namespace';
is $dom->at('book meta number')->text, '978-0596000271', 'right text';
is $dom->children('bk:book')->first->{xmlns}, 'uri:default-ns',
  'right attribute';
is $dom->children('k:book')->first, undef, 'no result';
is $dom->children('book')->first,   undef, 'no result';
is $dom->children('ook')->first,    undef, 'no result';
is $dom->at('k\:book'), undef, 'no result';
is $dom->at('ook'),     undef, 'no result';
is $dom->at('[xmlns\:bk]')->{'xmlns:bk'}, 'uri:book-ns', 'right attribute';
is $dom->at('[bk]')->{'xmlns:bk'},        'uri:book-ns', 'right attribute';
is $dom->at('[bk]')->attrs('xmlns:bk'), 'uri:book-ns', 'right attribute';
is $dom->at('[bk]')->attrs('s:bk'),     '',            'no attribute';
is $dom->at('[bk]')->attrs('bk'),       '',            'no attribute';
is $dom->at('[bk]')->attrs('k'),        '',            'no attribute';
is $dom->at('[s\:bk]'), undef, 'no result';
is $dom->at('[k]'),     undef, 'no result';

# Namespace with dot
$dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0"?>
<foo xmlns:foo.bar="uri:first">
  <bar xmlns:fooxbar="uri:second">
    <foo.bar:baz>First</fooxbar:baz>
    <fooxbar:yada>Second</foo.bar:yada>
  </bar>
</foo>
EOF
is $dom->at('foo bar baz')->text,  'First',      'right text';
is $dom->at('baz')->namespace,     'uri:first',  'right namespace';
is $dom->at('foo bar yada')->text, 'Second',     'right text';
is $dom->at('yada')->namespace,    'uri:second', 'right namespace';
is $dom->at('foo')->namespace,     '',           'no namespace';

# Yadis
$dom = Mojo::DOM->new->parse(<<'EOF');
<?xml version="1.0" encoding="UTF-8"?>
<XRDS xmlns="xri://$xrds">
  <XRD xmlns="xri://$xrd*($v*2.0)">
    <Service>
      <Type>http://o.r.g/sso/2.0</Type>
    </Service>
    <Service>
      <Type>http://o.r.g/sso/1.0</Type>
    </Service>
  </XRD>
</XRDS>
EOF
is $dom->xml, 1, 'xml mode detected';
is $dom->at('XRDS')->namespace, 'xri://$xrds',         'right namespace';
is $dom->at('XRD')->namespace,  'xri://$xrd*($v*2.0)', 'right namespace';
my $s = $dom->find('XRDS XRD Service');
is $s->[0]->at('Type')->text, 'http://o.r.g/sso/2.0', 'right text';
is $s->[0]->namespace, 'xri://$xrd*($v*2.0)', 'right namespace';
is $s->[1]->at('Type')->text, 'http://o.r.g/sso/1.0', 'right text';
is $s->[1]->namespace, 'xri://$xrd*($v*2.0)', 'right namespace';
is $s->[2], undef, 'no result';
is $s->size, 2, 'right number of elements';

# Yadis (roundtrip with namespace)
my $yadis = <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<xrds:XRDS xmlns="xri://$xrd*($v*2.0)" xmlns:xrds="xri://$xrds">
  <XRD>
    <Service>
      <Type>http://o.r.g/sso/3.0</Type>
    </Service>
    <xrds:Service>
      <Type>http://o.r.g/sso/4.0</Type>
    </xrds:Service>
  </XRD>
  <XRD>
    <Service>
      <Type test="23">http://o.r.g/sso/2.0</Type>
    </Service>
    <Service>
      <Type Test="23" test="24">http://o.r.g/sso/1.0</Type>
    </Service>
  </XRD>
</xrds:XRDS>
EOF
$dom = Mojo::DOM->new->parse($yadis);
is $dom->xml, 1, 'xml mode detected';
is $dom->at('XRDS')->namespace, 'xri://$xrds',         'right namespace';
is $dom->at('XRD')->namespace,  'xri://$xrd*($v*2.0)', 'right namespace';
$s = $dom->find('XRDS XRD Service');
is $s->[0]->at('Type')->text, 'http://o.r.g/sso/3.0', 'right text';
is $s->[0]->namespace, 'xri://$xrd*($v*2.0)', 'right namespace';
is $s->[1]->at('Type')->text, 'http://o.r.g/sso/4.0', 'right text';
is $s->[1]->namespace, 'xri://$xrds', 'right namespace';
is $s->[2]->at('Type')->text, 'http://o.r.g/sso/2.0', 'right text';
is $s->[2]->namespace, 'xri://$xrd*($v*2.0)', 'right namespace';
is $s->[3]->at('Type')->text, 'http://o.r.g/sso/1.0', 'right text';
is $s->[3]->namespace, 'xri://$xrd*($v*2.0)', 'right namespace';
is $s->[4], undef, 'no result';
is $s->size, 4, 'right number of elements';
is $dom->at('[Test="23"]')->text, 'http://o.r.g/sso/1.0', 'right text';
is $dom->at('[test="23"]')->text, 'http://o.r.g/sso/2.0', 'right text';
is $dom->find('xrds\:Service > Type')->[0]->text, 'http://o.r.g/sso/4.0',
  'right text';
is $dom->find('xrds\:Service > Type')->[1], undef, 'no result';
is $dom->find('xrds\3AService > Type')->[0]->text, 'http://o.r.g/sso/4.0',
  'right text';
is $dom->find('xrds\3AService > Type')->[1], undef, 'no result';
is $dom->find('xrds\3A Service > Type')->[0]->text, 'http://o.r.g/sso/4.0',
  'right text';
is $dom->find('xrds\3A Service > Type')->[1], undef, 'no result';
is $dom->find('xrds\00003AService > Type')->[0]->text, 'http://o.r.g/sso/4.0',
  'right text';
is $dom->find('xrds\00003AService > Type')->[1], undef, 'no result';
is $dom->find('xrds\00003A Service > Type')->[0]->text,
  'http://o.r.g/sso/4.0', 'right text';
is $dom->find('xrds\00003A Service > Type')->[1], undef, 'no result';
is "$dom", $yadis, 'successful roundtrip';

# Result and iterator order
$dom = Mojo::DOM->new->parse('<a><b>1</b></a><b>2</b><b>3</b>');
my @numbers;
$dom->find('b')->each(sub { push @numbers, pop, shift->text });
is_deeply \@numbers, [1, 1, 2, 2, 3, 3], 'right order';

# Attributes on multiple lines
$dom = Mojo::DOM->new->parse("<div test=23 id='a' \n class='x' foo=bar />");
is $dom->at('div.x')->attrs('test'),        23,  'right attribute';
is $dom->at('[foo="bar"]')->attrs('class'), 'x', 'right attribute';

# Markup characters in attribute values
$dom = Mojo::DOM->new->parse(
  qq{<div id="<a>" \n test='='>Test<div id='><' /></div>});
is $dom->at('div[id="<a>"]')->attrs->{test}, '=', 'right attribute';
is $dom->at('[id="<a>"]')->text, 'Test', 'right text';
is $dom->at('[id="><"]')->attrs->{id}, '><', 'right attribute';

# Empty attributes
$dom = Mojo::DOM->new->parse(qq{<div test="" test2='' />});
is $dom->at('div')->attrs->{test},  '', 'empty attribute value';
is $dom->at('div')->attrs->{test2}, '', 'empty attribute value';

# Whitespaces before closing bracket
$dom = Mojo::DOM->new->parse(qq{<div >content</div>});
ok $dom->at('div'), 'tag found';
is $dom->at('div')->text,        'content', 'right text';
is $dom->at('div')->content_xml, 'content', 'right text';

# Class with hyphen
$dom
  = Mojo::DOM->new->parse(qq{<div class="a">A</div><div class="a-1">A1</div>});
@div = ();
$dom->find('.a')->each(sub { push @div, shift->text });
is_deeply \@div, ['A'], 'found first element only';
@div = ();
$dom->find('.a-1')->each(sub { push @div, shift->text });
is_deeply \@div, ['A1'], 'found last element only';

# Defined but false text
$dom = Mojo::DOM->new->parse(
  '<div><div id="a">A</div><div id="b">B</div></div><div id="0">0</div>');
@div = ();
$dom->find('div[id]')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A B 0)], 'found all div elements with id';

# Empty tags
$dom = Mojo::DOM->new->parse('<hr /><br/><br id="br"/><br />');
is "$dom", '<hr /><br /><br id="br" /><br />', 'right result';
is $dom->at('br')->content_xml, '', 'empty result';

# Inner XML
$dom = Mojo::DOM->new->parse('<a>xxx<x>x</x>xxx</a>');
is $dom->at('a')->content_xml, 'xxx<x>x</x>xxx', 'right result';
is $dom->content_xml, '<a>xxx<x>x</x>xxx</a>', 'right result';

# Multiple selectors
$dom = Mojo::DOM->new->parse(
  '<div id="a">A</div><div id="b">B</div><div id="c">C</div>');
@div = ();
$dom->find('#a, #c')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
@div = ();
$dom->find('div#a, div#b')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A B)], 'found all div elements with the right ids';
@div = ();
$dom->find('div[id="a"], div[id="c"]')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
$dom = Mojo::DOM->new->parse(
  '<div id="☃">A</div><div id="b">B</div><div id="♥x">C</div>');
@div = ();
$dom->find('#☃, #♥x')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
@div = ();
$dom->find('div#☃, div#b')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A B)], 'found all div elements with the right ids';
@div = ();
$dom->find('div[id="☃"], div[id="♥x"]')
  ->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';

# Multiple attributes
$dom = Mojo::DOM->new->parse(<<EOF);
<div foo="bar" bar="baz">A</div>
<div foo="bar">B</div>
<div foo="bar" bar="baz">C</div>
<div foo="baz" bar="baz">D</div>
EOF
@div = ();
$dom->find('div[foo="bar"][bar="baz"]')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A C)], 'found all div elements with the right atributes';
@div = ();
$dom->find('div[foo^="b"][foo$="r"]')->each(sub { push @div, shift->text });
is_deeply \@div, [qw(A B C)],
  'found all div elements with the right atributes';
is $dom->at('[foo="bar"]')->previous, undef, 'no previous sibling';
is $dom->at('[foo="bar"]')->next->text, 'B', 'right text';
is $dom->at('[foo="bar"]')->next->previous->text, 'A', 'right text';
is $dom->at('[foo="bar"]')->next->next->next->next, undef, 'no next sibling';

# Pseudo classes
$dom = Mojo::DOM->new->parse(<<EOF);
<form action="/foo">
    <input type="text" name="user" value="test" />
    <input type="checkbox" checked="checked" name="groovy">
    <select name="a">
        <option value="b">b</option>
        <optgroup label="c">
            <option value="d">d</option>
            <option selected="selected" value="e">E</option>
            <option value="f">f</option>
        </optgroup>
        <option value="g">g</option>
        <option selected value="h">H</option>
    </select>
    <input type="submit" value="Ok!" />
    <input type="checkbox" checked name="I">
</form>
EOF
is $dom->find(':root')->[0]->type,     'form', 'right type';
is $dom->find('*:root')->[0]->type,    'form', 'right type';
is $dom->find('form:root')->[0]->type, 'form', 'right type';
is $dom->find(':root')->[1], undef, 'no result';
is $dom->find(':checked')->[0]->attrs->{name},        'groovy', 'right name';
is $dom->find('option:checked')->[0]->attrs->{value}, 'e',      'right value';
is $dom->find(':checked')->[1]->text,  'E', 'right text';
is $dom->find('*:checked')->[1]->text, 'E', 'right text';
is $dom->find(':checked')->[2]->text,  'H', 'right name';
is $dom->find(':checked')->[3]->attrs->{name}, 'I', 'right name';
is $dom->find(':checked')->[4], undef, 'no result';
is $dom->find('option[selected]')->[0]->attrs->{value}, 'e', 'right value';
is $dom->find('option[selected]')->[1]->text, 'H', 'right text';
is $dom->find('option[selected]')->[2], undef, 'no result';
is $dom->find(':checked[value="e"]')->[0]->text,       'E', 'right text';
is $dom->find('*:checked[value="e"]')->[0]->text,      'E', 'right text';
is $dom->find('option:checked[value="e"]')->[0]->text, 'E', 'right text';
is $dom->at('optgroup option:checked[value="e"]')->text, 'E', 'right text';
is $dom->at('select option:checked[value="e"]')->text,   'E', 'right text';
is $dom->at('select :checked[value="e"]')->text,         'E', 'right text';
is $dom->at('optgroup > :checked[value="e"]')->text,     'E', 'right text';
is $dom->at('select *:checked[value="e"]')->text,        'E', 'right text';
is $dom->at('optgroup > *:checked[value="e"]')->text,    'E', 'right text';
is $dom->find(':checked[value="e"]')->[1], undef, 'no result';
is $dom->find(':empty')->[0]->attrs->{name},      'user', 'right name';
is $dom->find('input:empty')->[0]->attrs->{name}, 'user', 'right name';
is $dom->at(':empty[type^="ch"]')->attrs->{name}, 'groovy', 'right name';

# More pseudo classes
$dom = Mojo::DOM->new->parse(<<EOF);
<ul>
    <li>A</li>
    <li>B</li>
    <li>C</li>
    <li>D</li>
    <li>E</li>
    <li>F</li>
    <li>G</li>
    <li>H</li>
</ul>
EOF
my @li;
$dom->find('li:nth-child(odd)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
@li = ();
$dom->find('li:NTH-CHILD(ODD)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
@li = ();
$dom->find('li:nth-last-child(odd)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all odd li elements';
is $dom->find(':nth-child(odd)')->[0]->type,       'ul', 'right type';
is $dom->find(':nth-child(odd)')->[1]->text,       'A',  'right text';
is $dom->find(':nth-child(1)')->[0]->type,         'ul', 'right type';
is $dom->find(':nth-child(1)')->[1]->text,         'A',  'right text';
is $dom->find(':nth-last-child(odd)')->[0]->type,  'ul', 'right type';
is $dom->find(':nth-last-child(odd)')->[-1]->text, 'H',  'right text';
is $dom->find(':nth-last-child(1)')->[0]->type,    'ul', 'right type';
is $dom->find(':nth-last-child(1)')->[1]->text,    'H',  'right text';
@li = ();
$dom->find('li:nth-child(2n+1)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
@li = ();
$dom->find('li:nth-child(2n + 1)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
@li = ();
$dom->find('li:nth-last-child(2n+1)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all odd li elements';
@li = ();
$dom->find('li:nth-child(even)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all even li elements';
@li = ();
$dom->find('li:NTH-CHILD(EVEN)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all even li elements';
@li = ();
$dom->find('li:nth-last-child(even)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all even li elements';
@li = ();
$dom->find('li:nth-child(2n+2)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all even li elements';
@li = ();
$dom->find('li:nTh-chILd(2N+2)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all even li elements';
@li = ();
$dom->find('li:nth-child( 2n + 2 )')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(B D F H)], 'found all even li elements';
@li = ();
$dom->find('li:nth-last-child(2n+2)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A C E G)], 'found all even li elements';
@li = ();
$dom->find('li:nth-child(4n+1)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A E)], 'found the right li elements';
@li = ();
$dom->find('li:nth-last-child(4n+1)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(D H)], 'found the right li elements';
@li = ();
$dom->find('li:nth-child(4n+4)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(D H)], 'found the right li element';
@li = ();
$dom->find('li:nth-last-child(4n+4)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A E)], 'found the right li element';
@li = ();
$dom->find('li:nth-child(4n)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(D H)], 'found the right li element';
@li = ();
$dom->find('li:nth-child( 4n )')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(D H)], 'found the right li element';
@li = ();
$dom->find('li:nth-last-child(4n)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A E)], 'found the right li element';
@li = ();
$dom->find('li:nth-child(5n-2)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C H)], 'found the right li element';
@li = ();
$dom->find('li:nth-child( 5n - 2 )')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C H)], 'found the right li element';
@li = ();
$dom->find('li:nth-last-child(5n-2)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A F)], 'found the right li element';
@li = ();
$dom->find('li:nth-child(-n+3)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C)], 'found first three li elements';
@li = ();
$dom->find('li:nth-child( -n + 3 )')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C)], 'found first three li elements';
@li = ();
$dom->find('li:nth-last-child(-n+3)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(F G H)], 'found last three li elements';
@li = ();
$dom->find('li:nth-child(-1n+3)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C)], 'found first three li elements';
@li = ();
$dom->find('li:nth-last-child(-1n+3)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(F G H)], 'found first three li elements';
@li = ();
$dom->find('li:nth-child(3n)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C F)], 'found every third li elements';
@li = ();
$dom->find('li:nth-last-child(3n)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C F)], 'found every third li elements';
@li = ();
$dom->find('li:NTH-LAST-CHILD(3N)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C F)], 'found every third li elements';
@li = ();
$dom->find('li:Nth-Last-Child(3N)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(C F)], 'found every third li elements';
@li = ();
$dom->find('li:nth-child(3)')->each(sub { push @li, shift->text });
is_deeply \@li, ['C'], 'found third li element';
@li = ();
$dom->find('li:nth-last-child(3)')->each(sub { push @li, shift->text });
is_deeply \@li, ['F'], 'found third last li element';
@li = ();
$dom->find('li:nth-child(1n+0)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C D E F G)], 'found first three li elements';
@li = ();
$dom->find('li:nth-child(n+0)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C D E F G)], 'found first three li elements';
@li = ();
$dom->find('li:NTH-CHILD(N+0)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C D E F G)], 'found first three li elements';
@li = ();
$dom->find('li:Nth-Child(N+0)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C D E F G)], 'found first three li elements';
@li = ();
$dom->find('li:nth-child(n)')->each(sub { push @li, shift->text });
is_deeply \@li, [qw(A B C D E F G)], 'found first three li elements';

# Even more pseudo classes
$dom = Mojo::DOM->new->parse(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li class="test ♥">C</li>
    <p>D</p>
    <li>E</li>
    <li>F</li>
    <p>G</p>
    <li>H</li>
    <li>I</li>
</ul>
<div>
    <div class="☃">J</div>
</div>
<div>
    <a href="http://mojolicio.us">Mojo!</a>
    <div class="☃">K</div>
    <a href="http://mojolicio.us">Mojolicious!</a>
</div>
EOF
my @e;
$dom->find('ul :nth-child(odd)')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A C E G I)], 'found all odd elements';
@e = ();
$dom->find('li:nth-of-type(odd)')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A E H)], 'found all odd li elements';
@e = ();
$dom->find('li:nth-last-of-type(odd)')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(C F I)], 'found all odd li elements';
@e = ();
$dom->find('p:nth-of-type(odd)')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(B G)], 'found all odd p elements';
@e = ();
$dom->find('p:nth-last-of-type(odd)')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(B G)], 'found all odd li elements';
@e = ();
$dom->find('ul :nth-child(1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['A'], 'found first child';
@e = ();
$dom->find('ul :first-child')->each(sub { push @e, shift->text });
is_deeply \@e, ['A'], 'found first child';
@e = ();
$dom->find('p:nth-of-type(1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['B'], 'found first child';
@e = ();
$dom->find('p:first-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, ['B'], 'found first child';
@e = ();
$dom->find('li:nth-of-type(1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['A'], 'found first child';
@e = ();
$dom->find('li:first-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, ['A'], 'found first child';
@e = ();
$dom->find('ul :nth-last-child(-n+1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['I'], 'found last child';
@e = ();
$dom->find('ul :last-child')->each(sub { push @e, shift->text });
is_deeply \@e, ['I'], 'found last child';
@e = ();
$dom->find('p:nth-last-of-type(-n+1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['G'], 'found last child';
@e = ();
$dom->find('p:last-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, ['G'], 'found last child';
@e = ();
$dom->find('li:nth-last-of-type(-n+1)')->each(sub { push @e, shift->text });
is_deeply \@e, ['I'], 'found last child';
@e = ();
$dom->find('li:last-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, ['I'], 'found last child';
@e = ();
$dom->find('ul :nth-child(-n+3):not(li)')->each(sub { push @e, shift->text });
is_deeply \@e, ['B'], 'found first p element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(:first-child)')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(B C)], 'found second and third element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(.♥)')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A B)], 'found first and second element';
@e = ();
$dom->find('ul :nth-child(-n+3):not([class$="♥"])')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A B)], 'found first and second element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(li[class$="♥"])')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A B)], 'found first and second element';
@e = ();
$dom->find('ul :nth-child(-n+3):not([class$="♥"][class^="test"])')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A B)], 'found first and second element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(*[class$="♥"])')
  ->each(sub { push @e, shift->text });
is_deeply \@e, [qw(A B)], 'found first and second element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(:nth-child(-n+2))')
  ->each(sub { push @e, shift->text });
is_deeply \@e, ['C'], 'found third element';
@e = ();
$dom->find('ul :nth-child(-n+3):not(:nth-child(1)):not(:nth-child(2))')
  ->each(sub { push @e, shift->text });
is_deeply \@e, ['C'], 'found third element';
@e = ();
$dom->find(':only-child')->each(sub { push @e, shift->text });
is_deeply \@e, ['J'], 'found only child';
@e = ();
$dom->find('div :only-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(J K)], 'found only child';
@e = ();
$dom->find('div:only-child')->each(sub { push @e, shift->text });
is_deeply \@e, ['J'], 'found only child';
@e = ();
$dom->find('div div:only-of-type')->each(sub { push @e, shift->text });
is_deeply \@e, [qw(J K)], 'found only child';

# Sibling combinator
$dom = Mojo::DOM->new->parse(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<h1>D</h1>
<p id="♥">E</p>
<p id="☃">F</p>
<div>G</div>
EOF
is $dom->at('li ~ p')->text,       'B', 'right text';
is $dom->at('li + p')->text,       'B', 'right text';
is $dom->at('h1 ~ p ~ p')->text,   'F', 'right text';
is $dom->at('h1 + p ~ p')->text,   'F', 'right text';
is $dom->at('h1 ~ p + p')->text,   'F', 'right text';
is $dom->at('h1 + p + p')->text,   'F', 'right text';
is $dom->at('ul > li ~ li')->text, 'C', 'right text';
is $dom->at('ul li ~ li')->text,   'C', 'right text';
is $dom->at('ul li li'),     undef, 'no result';
is $dom->at('ul ~ li ~ li'), undef, 'no result';
is $dom->at('ul + li ~ li'), undef, 'no result';
is $dom->at('ul > li + li'), undef, 'no result';
is $dom->at('h1 ~ div')->text, 'G', 'right text';
is $dom->at('h1 + div'), undef, 'no result';
is $dom->at('p + div')->text,               'G', 'right text';
is $dom->at('ul + h1 + p + p + div')->text, 'G', 'right text';
is $dom->at('ul + h1 ~ p + div')->text,     'G', 'right text';
is $dom->at('h1 ~ #♥')->text,             'E', 'right text';
is $dom->at('h1 + #♥')->text,             'E', 'right text';
is $dom->at('#♥ ~ #☃')->text,           'F', 'right text';
is $dom->at('#♥ + #☃')->text,           'F', 'right text';
is $dom->at('#♥ > #☃'), undef, 'no result';
is $dom->at('#♥ #☃'),   undef, 'no result';
is $dom->at('#♥ + #☃ + :nth-last-child(1)')->text,  'G', 'right text';
is $dom->at('#♥ ~ #☃ + :nth-last-child(1)')->text,  'G', 'right text';
is $dom->at('#♥ + #☃ ~ :nth-last-child(1)')->text,  'G', 'right text';
is $dom->at('#♥ ~ #☃ ~ :nth-last-child(1)')->text,  'G', 'right text';
is $dom->at('#♥ + :nth-last-child(2)')->text,         'F', 'right text';
is $dom->at('#♥ ~ :nth-last-child(2)')->text,         'F', 'right text';
is $dom->at('#♥ + #☃ + *:nth-last-child(1)')->text, 'G', 'right text';
is $dom->at('#♥ ~ #☃ + *:nth-last-child(1)')->text, 'G', 'right text';
is $dom->at('#♥ + #☃ ~ *:nth-last-child(1)')->text, 'G', 'right text';
is $dom->at('#♥ ~ #☃ ~ *:nth-last-child(1)')->text, 'G', 'right text';
is $dom->at('#♥ + *:nth-last-child(2)')->text,        'F', 'right text';
is $dom->at('#♥ ~ *:nth-last-child(2)')->text,        'F', 'right text';

# Adding nodes
$dom = Mojo::DOM->new->parse(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$dom->at('li')->append('<p>A1</p>23');
is "$dom", <<EOF, 'right result';
<ul>
    <li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$dom->at('li')->prepend('24')->prepend('<div>A-1</div>25');
is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
is $dom->at('div')->text, 'A-1', 'right text';
is $dom->at('iv'), undef, 'no result';
$dom->prepend('l')->prepend('alal')->prepend('a');
is "$dom", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$dom->append('lalala');
is "$dom", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$dom->find('div')->each(sub { shift->append('works') });
is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$dom->at('li')->prepend_content('A3<p>A2</p>')->prepend_content('A4');
is $dom->at('li')->text, 'A4 A3 A', 'right text';
is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$dom->find('li')->[1]->append_content('<p>C2</p>C3')->append_content('C4');
is $dom->find('li')->[1]->text, 'C C3 C4', 'right text';
is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C<p>C2</p>C3C4</li>
</ul>
<div>D</div>works
EOF

# Optional "head" and "body" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <title>foo</title>
  <body>bar
EOF
is $dom->at('html > head > title')->text, 'foo', 'right text';
is $dom->at('html > body')->text,         'bar', 'right text';

# Optional "li" tag
$dom = Mojo::DOM->new->parse(<<EOF);
<ul>
  <li>A</li>
  <LI>B
  <li>C</li>
  <li>D
  <li>E
</ul>
EOF
is $dom->find('ul > li')->[0]->text, 'A', 'right text';
is $dom->find('ul > li')->[1]->text, 'B', 'right text';
is $dom->find('ul > li')->[2]->text, 'C', 'right text';
is $dom->find('ul > li')->[3]->text, 'D', 'right text';
is $dom->find('ul > li')->[4]->text, 'E', 'right text';

# Optional "p" tag
$dom = Mojo::DOM->new->parse(<<EOF);
<div>
  <p>A</p>
  <P>B
  <p>C</p>
  <p>D<div>X</div>
  <p>E<img src="foo.png">
  <p>F<br>G
  <p>H
</div>
EOF
is $dom->find('div > p')->[0]->text, 'A',   'right text';
is $dom->find('div > p')->[1]->text, 'B',   'right text';
is $dom->find('div > p')->[2]->text, 'C',   'right text';
is $dom->find('div > p')->[3]->text, 'D',   'right text';
is $dom->find('div > p')->[4]->text, 'E',   'right text';
is $dom->find('div > p')->[5]->text, 'F G', 'right text';
is $dom->find('div > p')->[6]->text, 'H',   'right text';
is $dom->find('div > p > p')->[0], undef, 'no results';
is $dom->at('div > p > img')->attrs->{src}, 'foo.png', 'right attribute';
is $dom->at('div > div')->text, 'X', 'right text';

# Optional "dt" and "dd" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<dl>
  <dt>A</dt>
  <DD>B
  <dt>C</dt>
  <dd>D
  <dt>E
  <dd>F
</dl>
EOF
is $dom->find('dl > dt')->[0]->text, 'A', 'right text';
is $dom->find('dl > dd')->[0]->text, 'B', 'right text';
is $dom->find('dl > dt')->[1]->text, 'C', 'right text';
is $dom->find('dl > dd')->[1]->text, 'D', 'right text';
is $dom->find('dl > dt')->[2]->text, 'E', 'right text';
is $dom->find('dl > dd')->[2]->text, 'F', 'right text';

# Optional "rp" and "rt" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<ruby>
  <rp>A</rp>
  <RT>B
  <rp>C</rp>
  <rt>D
  <rp>E
  <rt>F
</ruby>
EOF
is $dom->find('ruby > rp')->[0]->text, 'A', 'right text';
is $dom->find('ruby > rt')->[0]->text, 'B', 'right text';
is $dom->find('ruby > rp')->[1]->text, 'C', 'right text';
is $dom->find('ruby > rt')->[1]->text, 'D', 'right text';
is $dom->find('ruby > rp')->[2]->text, 'E', 'right text';
is $dom->find('ruby > rt')->[2]->text, 'F', 'right text';

# Optional "optgroup" and "option" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<div>
  <optgroup>A
    <option id="foo">B
    <option>C</option>
    <option>D
  <OPTGROUP>E
    <option>F
  <optgroup>G
    <option>H
</div>
EOF
is $dom->find('div > optgroup')->[0]->text,          'A', 'right text';
is $dom->find('div > optgroup > #foo')->[0]->text,   'B', 'right text';
is $dom->find('div > optgroup > option')->[1]->text, 'C', 'right text';
is $dom->find('div > optgroup > option')->[2]->text, 'D', 'right text';
is $dom->find('div > optgroup')->[1]->text,          'E', 'right text';
is $dom->find('div > optgroup > option')->[3]->text, 'F', 'right text';
is $dom->find('div > optgroup')->[2]->text,          'G', 'right text';
is $dom->find('div > optgroup > option')->[4]->text, 'H', 'right text';

# Optional "colgroup" tag
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
  <col id=morefail>
  <col id=fail>
  <colgroup>
    <col id=foo>
    <col class=foo>
  <colgroup>
    <col id=bar>
</table>
EOF
is $dom->find('table > col')->[0]->attrs->{id}, 'morefail', 'right attribute';
is $dom->find('table > col')->[1]->attrs->{id}, 'fail',     'right attribute';
is $dom->find('table > colgroup > col')->[0]->attrs->{id}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[1]->attrs->{class}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[2]->attrs->{id}, 'bar',
  'right attribute';

# Optional "thead", "tbody", "tfoot", "tr", "th" and "td" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
  <thead>
    <tr>
      <th>A</th>
      <th>D
  <tbody>
    <tr>
      <td>B
  <tfoot>
    <tr>
      <td>C
</table>
EOF
is $dom->at('table > thead > tr > th')->text, 'A', 'right text';
is $dom->find('table > thead > tr > th')->[1]->text, 'D', 'right text';
is $dom->at('table > tbody > tr > td')->text, 'B', 'right text';
is $dom->at('table > tfoot > tr > td')->text, 'C', 'right text';

# Optional "colgroup", "thead", "tbody", "tr", "th" and "td" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
  <col id=morefail>
  <col id=fail>
  <colgroup>
    <col id=foo />
    <col class=foo>
  <colgroup>
    <col id=bar>
  </colgroup>
  <thead>
    <tr>
      <th>A</th>
      <th>D
  <tbody>
    <tr>
      <td>B
</table>
EOF
is $dom->find('table > col')->[0]->attrs->{id}, 'morefail', 'right attribute';
is $dom->find('table > col')->[1]->attrs->{id}, 'fail',     'right attribute';
is $dom->find('table > colgroup > col')->[0]->attrs->{id}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[1]->attrs->{class}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[2]->attrs->{id}, 'bar',
  'right attribute';
is $dom->at('table > thead > tr > th')->text, 'A', 'right text';
is $dom->find('table > thead > tr > th')->[1]->text, 'D', 'right text';
is $dom->at('table > tbody > tr > td')->text, 'B', 'right text';

# Optional "colgroup", "tbody", "tr", "th" and "td" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
  <colgroup>
    <col id=foo />
    <col class=foo>
  <colgroup>
    <col id=bar>
  </colgroup>
  <tbody>
    <tr>
      <td>B
</table>
EOF
is $dom->find('table > colgroup > col')->[0]->attrs->{id}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[1]->attrs->{class}, 'foo',
  'right attribute';
is $dom->find('table > colgroup > col')->[2]->attrs->{id}, 'bar',
  'right attribute';
is $dom->at('table > tbody > tr > td')->text, 'B', 'right text';

# Optional "tr" and "td" tags
$dom = Mojo::DOM->new->parse(<<EOF);
<table>
    <tr>
      <td>A
      <td>B</td>
    <tr>
      <td>C
    </tr>
    <tr>
      <td>D
</table>
EOF
is $dom->find('table > tr > td')->[0]->text, 'A', 'right text';
is $dom->find('table > tr > td')->[1]->text, 'B', 'right text';
is $dom->find('table > tr > td')->[2]->text, 'C', 'right text';
is $dom->find('table > tr > td')->[3]->text, 'D', 'right text';

# Real world table
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <p>Just a test
    <table class=RealWorld>
      <thead>
        <tr>
          <th class=one>One
          <th class=two>Two
          <th class=three>Three
          <th class=four>Four
      <tbody>
        <tr>
          <td class=alpha>Alpha
          <td class=beta>Beta
          <td class=gamma><a href="#gamma">Gamma</a>
          <td class=delta>Delta
        <tr>
          <td class=alpha>Alpha Two
          <td class=beta>Beta Two
          <td class=gamma><a href="#gamma-two">Gamma Two</a>
          <td class=delta>Delta Two
    </table>
EOF
is $dom->find('html > head > title')->[0]->text, 'Real World!', 'right text';
is $dom->find('html > body > p')->[0]->text,     'Just a test', 'right text';
is $dom->find('p')->[0]->text,                   'Just a test', 'right text';
is $dom->find('thead > tr > .three')->[0]->text, 'Three',       'right text';
is $dom->find('thead > tr > .four')->[0]->text,  'Four',        'right text';
is $dom->find('tbody > tr > .beta')->[0]->text,  'Beta',        'right text';
is $dom->find('tbody > tr > .gamma')->[0]->text, '',            'no text';
is $dom->find('tbody > tr > .gamma > a')->[0]->text, 'Gamma',     'right text';
is $dom->find('tbody > tr > .alpha')->[1]->text,     'Alpha Two', 'right text';
is $dom->find('tbody > tr > .gamma > a')->[1]->text, 'Gamma Two', 'right text';

# Real world list
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <ul>
      <li>
        Test
        <br>
        123
        <p>

      <li>
        Test
        <br>
        321
        <p>
      <li>
        Test
        3
        2
        1
        <p>
    </ul>
EOF
is $dom->find('html > head > title')->[0]->text, 'Real World!', 'right text';
is $dom->find('body > ul > li')->[0]->text,      'Test 123',    'right text';
is $dom->find('body > ul > li > p')->[0]->text,  '',            'no text';
is $dom->find('body > ul > li')->[1]->text,      'Test 321',    'right text';
is $dom->find('body > ul > li > p')->[1]->text,  '',            'no text';
is $dom->find('body > ul > li')->[1]->all_text,  'Test 321',    'right text';
is $dom->find('body > ul > li > p')->[1]->all_text, '',           'no text';
is $dom->find('body > ul > li')->[2]->text,         'Test 3 2 1', 'right text';
is $dom->find('body > ul > li > p')->[2]->text,     '',           'no text';
is $dom->find('body > ul > li')->[2]->all_text,     'Test 3 2 1', 'right text';
is $dom->find('body > ul > li > p')->[2]->all_text, '',           'no text';

# Advanced whitespace trimming (punctuation)
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <div>foo <strong>bar</strong>.</div>
    <div>foo<strong>, bar</strong>baz<strong>; yada</strong>.</div>
    <div>foo<strong>: bar</strong>baz<strong>? yada</strong>!</div>
EOF
is $dom->find('html > head > title')->[0]->text, 'Real World!', 'right text';
is $dom->find('body > div')->[0]->all_text,      'foo bar.',    'right text';
is $dom->find('body > div')->[1]->all_text, 'foo, bar baz; yada.',
  'right text';
is $dom->find('body > div')->[1]->text, 'foo baz.', 'right text';
is $dom->find('body > div')->[2]->all_text, 'foo: bar baz? yada!',
  'right text';
is $dom->find('body > div')->[2]->text, 'foo baz!', 'right text';

# Real world JavaScript and CSS
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head>
    <style test=works>#style { foo: style('<test>'); }</style>
    <script>
      if (a < b) {
        alert('<123>');
      }
    </script>
    < sCriPt two="23" >if (b > c) { alert('&<ohoh>') }< / scRiPt >
  <body>Foo!</body>
EOF
is $dom->find('html > body')->[0]->text, 'Foo!', 'right text';
is $dom->find('html > head > style')->[0]->text,
  "#style { foo: style('<test>'); }", 'right text';
is $dom->find('html > head > script')->[0]->text,
  "\n      if (a < b) {\n        alert('<123>');\n      }\n    ", 'right text';
is $dom->find('html > head > script')->[1]->text,
  "if (b > c) { alert('&<ohoh>') }", 'right text';

# More real world JavaScript
$dom = Mojo::DOM->new->parse(<<EOF);
<!DOCTYPE html>
<html>
  <head>
    <title>Foo</title>
    <script src="/js/one.js"></script>
    <script src="/js/two.js"></script>
    <script src="/js/three.js"></script>
  </head>
  <body>Bar</body>
</html>
EOF
is $dom->at('title')->text, 'Foo', 'right text';
is $dom->find('html > head > script')->[0]->attrs('src'), '/js/one.js',
  'right attribute';
is $dom->find('html > head > script')->[1]->attrs('src'), '/js/two.js',
  'right attribute';
is $dom->find('html > head > script')->[2]->attrs('src'), '/js/three.js',
  'right attribute';
is $dom->find('html > head > script')->[2]->text, '', 'no text';
is $dom->at('html > body')->text, 'Bar', 'right text';

# Even more real world JavaScript
$dom = Mojo::DOM->new->parse(<<EOF);
<!DOCTYPE html>
<html>
  <head>
    <title>Foo</title>
    <script src="/js/one.js"></script>
    <script src="/js/two.js"></script>
    <script src="/js/three.js">
  </head>
  <body>Bar</body>
</html>
EOF
is $dom->at('title')->text, 'Foo', 'right text';
is $dom->find('html > head > script')->[0]->attrs('src'), '/js/one.js',
  'right attribute';
is $dom->find('html > head > script')->[1]->attrs('src'), '/js/two.js',
  'right attribute';
is $dom->find('html > head > script')->[2]->attrs('src'), '/js/three.js',
  'right attribute';
is $dom->find('html > head > script')->[2]->text, '', 'no text';
is $dom->at('html > body')->text, 'Bar', 'right text';

# Inline DTD
$dom = Mojo::DOM->new->parse(<<EOF);
<?xml version="1.0"?>
<!-- This is a Test! -->
<!DOCTYPE root [
  <!ELEMENT root (#PCDATA)>
  <!ATTLIST root att CDATA #REQUIRED>
]>
<root att="test">
  <![CDATA[<hello>world</hello>]]>
</root>
EOF
is $dom->xml, 1, 'xml mode detected';
is $dom->at('root')->attrs('att'), 'test', 'right attribute';
is $dom->tree->[5][1], ' root [
  <!ELEMENT root (#PCDATA)>
  <!ATTLIST root att CDATA #REQUIRED>
]', 'right doctype';
is $dom->at('root')->text, '<hello>world</hello>', 'right text';
$dom = Mojo::DOM->new->parse(<<EOF);
<!doctype book
SYSTEM "usr.dtd"
[
  <!ENTITY test "yeah">
]>
<foo />
EOF
is $dom->tree->[1][1], ' book
SYSTEM "usr.dtd"
[
  <!ENTITY test "yeah">
]', 'right doctype';
is $dom->xml, undef, 'xml mode not detected';
is $dom->at('foo'), '<foo></foo>', 'right element';
$dom = Mojo::DOM->new->parse(<<EOF);
<?xml version="1.0" encoding = 'utf-8'?>
<!DOCTYPE foo [
  <!ELEMENT foo ANY>
  <!ATTLIST foo xml:lang CDATA #IMPLIED>
  <!ENTITY % e SYSTEM "myentities.ent">
  %myentities;
]  >
<foo xml:lang="de">Check!</fOo>
EOF
is $dom->xml, 1, 'xml mode detected';
is $dom->tree->[3][1], ' foo [
  <!ELEMENT foo ANY>
  <!ATTLIST foo xml:lang CDATA #IMPLIED>
  <!ENTITY % e SYSTEM "myentities.ent">
  %myentities;
]  ', 'right doctype';
is $dom->at('foo')->attrs->{'xml:lang'}, 'de', 'right attribute';
is $dom->at('foo')->text, 'Check!', 'right text';
$dom = Mojo::DOM->new->parse(<<EOF);
<!DOCTYPE TESTSUITE PUBLIC "my.dtd" 'mhhh' [
  <!ELEMENT foo ANY>
  <!ATTLIST foo bar ENTITY 'true'>
  <!ENTITY system_entities SYSTEM 'systems.xml'>
  <!ENTITY leertaste '&#32;'>
  <!-- This is a comment -->
  <!NOTATION hmmm SYSTEM "hmmm">
]   >
<?check for-nothing?>
<foo bar='false'>&leertaste;!!!</foo>
EOF
is $dom->tree->[1][1], ' TESTSUITE PUBLIC "my.dtd" \'mhhh\' [
  <!ELEMENT foo ANY>
  <!ATTLIST foo bar ENTITY \'true\'>
  <!ENTITY system_entities SYSTEM \'systems.xml\'>
  <!ENTITY leertaste \'&#32;\'>
  <!-- This is a comment -->
  <!NOTATION hmmm SYSTEM "hmmm">
]   ', 'right doctype';
is $dom->at('foo')->attrs('bar'), 'false', 'right attribute';

# Broken "font" block and useless end tags
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr><td><font>test</td></font></tr>
      </tr>
    </table>
  </body>
</html>
EOF
is $dom->at('html > head > title')->text,          'Test', 'right text';
is $dom->at('html body table tr td > font')->text, 'test', 'right text';

# Different broken "font" block
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <font>
    <table>
      <tr>
        <td>test1<br></td></font>
        <td>test2<br>
    </table>
  </body>
</html>
EOF
is $dom->at('html > head > title')->text, 'Test', 'right text';
is $dom->find('html > body > font > table > tr > td')->[0]->text, 'test1',
  'right text';
is $dom->find('html > body > font > table > tr > td')->[1]->text, 'test2',
  'right text';

# Broken "font" and "div" blocks
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <font>
    <div>test1<br>
      <div>test2<br></font>
    </div>
  </body>
</html>
EOF
is $dom->at('html head title')->text,            'Test',  'right text';
is $dom->at('html body font > div')->text,       'test1', 'right text';
is $dom->at('html body font > div > div')->text, 'test2', 'right text';

# Broken "div" blocks
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <div>
    <table>
      <tr><td><div>test</td></div></tr>
      </div>
    </table>
  </body>
</html>
EOF
is $dom->at('html head title')->text,                 'Test', 'right text';
is $dom->at('html body div table tr td > div')->text, 'test', 'right text';

# And another broken "font" block
$dom = Mojo::DOM->new->parse(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr>
        <td><font><br>te<br>st<br>1</td></font>
        <td>x1<td><img>tes<br>t2</td>
        <td>x2<td><font>t<br>est3</font></td>
      </tr>
    </table>
  </body>
</html>
EOF
is $dom->at('html > head > title')->text, 'Test', 'right text';
is $dom->find('html body table tr > td > font')->[0]->text, 'te st 1',
  'right text';
is $dom->find('html body table tr > td')->[1]->text, 'x1',     'right text';
is $dom->find('html body table tr > td')->[2]->text, 'tes t2', 'right text';
is $dom->find('html body table tr > td')->[3]->text, 'x2',     'right text';
is $dom->find('html body table tr > td')->[5], undef, 'no result';
is $dom->find('html body table tr > td')->size, 5, 'right number of elements';
is $dom->find('html body table tr > td > font')->[1]->text, 't est3',
  'right text';
is $dom->find('html body table tr > td > font')->[2], undef, 'no result';
is $dom->find('html body table tr > td > font')->size, 2,
  'right number of elements';
is $dom, <<EOF, 'right result';
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr>
        <td><font><br />te<br />st<br />1</font></td>
        <td>x1</td><td><img />tes<br />t2</td>
        <td>x2</td><td><font>t<br />est3</font></td>
      </tr>
    </table>
  </body>
</html>
EOF

# A collection of wonderful screwups
$dom = Mojo::DOM->new->parse(<<'EOF');
<!DOCTYPE html>
<html lang="en">
  <head><title>Wonderful Screwups</title></head>
  <body id="screw-up">
    <div>
      <div class="ewww">
        <a href="/test" target='_blank'><img src="/test.png"></a>
        <a href='/real bad' screwup: http://localhost/bad' target='_blank'>
          <img src="/test2.png">
      </div>
      </mt:If>
    </div>
    <b>lalala</b>
  </body>
</html>
EOF
is $dom->at('#screw-up > b')->text, 'lalala', 'right text';
is $dom->at('#screw-up .ewww > a > img')->attrs('src'), '/test.png',
  'right attribute';
is $dom->find('#screw-up .ewww > a > img')->[1]->attrs('src'), '/test2.png',
  'right attribute';
is $dom->find('#screw-up .ewww > a > img')->[2], undef, 'no result';
is $dom->find('#screw-up .ewww > a > img')->size, 2,
  'right number of elements';

# Modifying an XML document
$dom = Mojo::DOM->new->parse(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest />
EOF
is $dom->xml, 1, 'xml mode detected';
$dom->at('XMLTest')->replace_content('<Element />');
my $element = $dom->at('Element');
is $element->type, 'Element', 'right type';
is $element->xml,  1,         'xml mode detected';
$element = $dom->at('XMLTest')->children->[0];
is $element->type, 'Element', 'right child';
is $element->parent->type, 'XMLTest', 'right parent';
is $element->root->xml,    1,         'xml mode detected';
$dom->replace('<XMLTest2 />');
is $dom->xml, undef, 'xml mode not detected';
is $dom->children->[0], '<xmltest2></xmltest2>', 'right result';
$dom->replace(<<EOF);
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest3 />
EOF
is $dom->xml, 1, 'xml mode detected';
is $dom->children->[0], '<XMLTest3 />', 'right result';

# Ensure XML semantics
$dom = Mojo::DOM->new->parse(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<table>
  <td>
    <tr><thead>foo<thead></tr>
  </td>
  <td>
    <tr><thead>bar<thead></tr>
  </td>
</table>
EOF
is $dom->find('table > td > tr > thead')->[0]->text, 'foo', 'right text';
is $dom->find('table > td > tr > thead')->[1]->text, 'bar', 'right text';
is $dom->find('table > td > tr > thead')->[2], undef, 'no result';
is $dom->find('table > td > tr > thead')->size, 2, 'right number of elements';

# Ensure XML semantics again
$dom = Mojo::DOM->new->xml(1)->parse(<<'EOF');
<table>
  <td>
    <tr><thead>foo<thead></tr>
  </td>
  <td>
    <tr><thead>bar<thead></tr>
  </td>
</table>
EOF
is $dom->find('table > td > tr > thead')->[0]->text, 'foo', 'right text';
is $dom->find('table > td > tr > thead')->[1]->text, 'bar', 'right text';
is $dom->find('table > td > tr > thead')->[2], undef, 'no result';
is $dom->find('table > td > tr > thead')->size, 2, 'right number of elements';

# Nested tables
$dom = Mojo::DOM->new->parse(<<'EOF');
<table id="foo">
  <tr>
    <td>
      <table id="bar">
        <tr>
          <td>baz</td>
        </tr>
      </table>
    </td>
  </tr>
</table>
EOF
is $dom->find('#foo > tr > td > #bar > tr >td')->[0]->text, 'baz',
  'right text';
is $dom->find('table > tr > td > table > tr >td')->[0]->text, 'baz',
  'right text';

# Nested find
$dom->parse(<<EOF);
<c>
  <a>foo</a>
  <b>
    <a>bar</a>
    <c>
      <a>baz</a>
      <d>
        <a>yada</a>
      </d>
    </c>
  </b>
</c>
EOF
my @results;
$dom->find('b')->each(
  sub {
    $_->find('a')->each(sub { push @results, $_->text });
  }
);
is_deeply \@results, [qw(bar baz yada)], 'right results';
@results = ();
$dom->find('a')->each(sub { push @results, $_->text });
is_deeply \@results, [qw(foo bar baz yada)], 'right results';
@results = ();
$dom->find('b')->each(
  sub {
    $_->find('c a')->each(sub { push @results, $_->text });
  }
);
is_deeply \@results, [qw(baz yada)], 'right results';

# Autoload children in XML mode
$dom = Mojo::DOM->new->xml(1)->parse(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $dom->xml, 1, 'xml mode enabled';
is $dom->a->B->text, 'foo', 'right text';
is $dom->a->B->c->[0]->text, 'bar', 'right text';
is $dom->a->B->c->[1]->text, 'baz', 'right text';
is $dom->a->B->c->[2], undef, 'no result';
is $dom->a->B->c->size, 2, 'right number of elements';

# Autoload children in HTML mode
$dom = Mojo::DOM->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $dom->xml, undef, 'xml mode disabled';
is $dom->a->b->text, 'foo', 'right text';
is $dom->a->b->c->[0]->text, 'bar', 'right text';
is $dom->a->b->c->[1]->text, 'baz', 'right text';
is $dom->a->b->c->[2], undef, 'no result';
is $dom->a->b->c->size, 2, 'right number of elements';

# Direct hash access to attributes in XML mode
$dom = Mojo::DOM->new->xml(1)->parse(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $dom->xml, 1, 'xml mode enabled';
is $dom->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$dom->a}], ['id'], 'right attributes';
is $dom->a->B->text, 'foo', 'right text';
is $dom->at('a')->B->text, 'foo', 'right text';
is $dom->find('a')->[0]->B->text, 'foo', 'right text';
is $dom->a->B->{class}, 'two', 'right attribute';
is $dom->at('a')->B->{class}, 'two', 'right attribute';
is $dom->find('a')->[0]->B->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$dom->a->B}], [qw(class test)], 'right attributes';
is $dom->a->B->c->[0]->text, 'bar', 'right text';
is $dom->a->B->c->[0]{id}, 'three', 'right attribute';
is_deeply [sort keys %{$dom->a->B->c->[0]}], ['id'], 'right attributes';
is $dom->a->B->c->[1]->text, 'baz', 'right text';
is $dom->a->B->c->[1]{ID}, 'four', 'right attribute';
is_deeply [sort keys %{$dom->a->B->c->[1]}], ['ID'], 'right attributes';
is $dom->a->B->c->[2], undef, 'no result';
is $dom->a->B->c->size, 2, 'right number of elements';
@results = ();
$dom->a->B->c->each(sub { push @results, $_->text });
is_deeply \@results, [qw(bar baz)], 'right results';
is $dom->a->B->c, qq{<c id="three">bar</c>\n<c ID="four">baz</c>},
  'right result';
is_deeply [keys %$dom], [], 'root has no attributes';
is $dom->find('#nothing'), '', 'no result';

# Direct hash access to attributes in HTML mode
$dom = Mojo::DOM->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $dom->xml, undef, 'xml mode disabled';
is $dom->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$dom->a}], ['id'], 'right attributes';
is $dom->a->b->text, 'foo', 'right text';
is $dom->at('a')->b->text, 'foo', 'right text';
is $dom->find('a')->[0]->b->text, 'foo', 'right text';
is $dom->a->b->{class}, 'two', 'right attribute';
is $dom->at('a')->b->{class}, 'two', 'right attribute';
is $dom->find('a')->[0]->b->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$dom->a->b}], [qw(class test)], 'right attributes';
is $dom->a->b->c->[0]->text, 'bar', 'right text';
is $dom->a->b->c->[0]{id}, 'three', 'right attribute';
is_deeply [sort keys %{$dom->a->b->c->[0]}], ['id'], 'right attributes';
is $dom->a->b->c->[1]->text, 'baz', 'right text';
is $dom->a->b->c->[1]{id}, 'four', 'right attribute';
is_deeply [sort keys %{$dom->a->b->c->[1]}], ['id'], 'right attributes';
is $dom->a->b->c->[2], undef, 'no result';
is $dom->a->b->c->size, 2, 'right number of elements';
@results = ();
$dom->a->b->c->each(sub { push @results, $_->text });
is_deeply \@results, [qw(bar baz)], 'right results';
is $dom->a->b->c, qq{<c id="three">bar</c>\n<c id="four">baz</c>},
  'right result';
is_deeply [keys %$dom], [], 'root has no attributes';
is $dom->find('#nothing'), '', 'no result';

# Append and prepend content
$dom = Mojo::DOM->new('<a><b>Test<c /></b></a>');
$dom->at('b')->append_content('<d />');
is $dom->children->[0]->type, 'a', 'right element';
is $dom->all_text, 'Test', 'right text';
is $dom->at('c')->parent->type, 'b', 'right element';
is $dom->at('d')->parent->type, 'b', 'right element';
$dom->at('b')->prepend_content('<e>Mojo</e>');
is $dom->at('e')->parent->type, 'b', 'right element';
is $dom->all_text, 'Mojo Test', 'right text';

# Broken "div" in "td"
$dom = Mojo::DOM->new(<<EOF);
<table>
  <tr>
    <td><div id="A"></td>
    <td><div id="B"></td>
  </tr>
</table>
EOF
is $dom->table->tr->td->[0]->div->{id}, 'A', 'right attribute';
is $dom->table->tr->td->[1]->div->{id}, 'B', 'right attribute';
is $dom->table->tr->td->[2], undef, 'no result';
is $dom->table->tr->td->size, 2, 'right number of elements';
is "$dom", <<EOF, 'right result';
<table>
  <tr>
    <td><div id="A"></div></td>
    <td><div id="B"></div></td>
  </tr>
</table>
EOF

# Preformatted text
$dom = Mojo::DOM->new(<<EOF);
<div>
  looks
  <pre><code>like
  it
    really</code>
  </pre>
  works
</div>
EOF
is $dom->text, '', 'right text';
is $dom->text(0), "\n", 'right text';
is $dom->all_text, "looks like\n  it\n    really\n  works", 'right text';
is $dom->all_text(0), "\n  looks\n  like\n  it\n    really\n  \n  works\n\n",
  'right text';
is $dom->text_before, '', 'no text';
is $dom->text_after,  '', 'no text';
is $dom->div->text, 'looks works', 'right text';
is $dom->div->text(0), "\n  looks\n  \n  works\n", 'right text';
is $dom->div->all_text, "looks like\n  it\n    really\n  works", 'right text';
is $dom->div->all_text(0),
  "\n  looks\n  like\n  it\n    really\n  \n  works\n", 'right text';
is $dom->div->pre->text, "\n  ", 'right text';
is $dom->div->pre->text(0), "\n  ", 'right text';
is $dom->div->pre->all_text, "like\n  it\n    really\n  ", 'right text';
is $dom->div->pre->all_text(0), "like\n  it\n    really\n  ", 'right text';
is $dom->div->pre->code->text, "like\n  it\n    really", 'right text';
is $dom->div->pre->code->text(0), "like\n  it\n    really", 'right text';
is $dom->div->pre->code->all_text, "like\n  it\n    really", 'right text';
is $dom->div->pre->code->all_text(0), "like\n  it\n    really", 'right text';
is $dom->div->pre->text_before, 'looks', 'right text';
is $dom->div->pre->text_after,  'works', 'right text';

# Text siblings
$dom = Mojo::DOM->new(<<EOF);
ok
<div>
  looks<p>like</p>
  thi<![CDATA[s]]>
  <p>might</p><p>really</p>
  <p>
    just
  </p>work
</div>
wow
EOF
is $dom->text_before, '', 'right text';
is $dom->text_before(0), '', 'right text';
is $dom->div->text_before, 'ok', 'right text';
is $dom->div->text_before(0), "ok\n", 'right text';
is $dom->div->p->[0]->text_before, 'looks', 'right text';
is $dom->div->p->[0]->text_before(0), "\n  looks", 'right text';
is $dom->div->p->[1]->text_before, 'thi s', 'right text';
is $dom->div->p->[1]->text_before(0), "\n  thi s\n  ", 'right text';
is $dom->div->p->[2]->text_before, '', 'right text';
is $dom->div->p->[2]->text_before(0), '', 'right text';
is $dom->div->p->[3]->text_before, '', 'right text';
is $dom->div->p->[3]->text_before(0), "\n  ", 'right text';
is $dom->text_after, '', 'right text';
is $dom->text_after(0), '', 'right text';
is $dom->div->text_after, 'wow', 'right text';
is $dom->div->text_after(0), "\nwow\n", 'right text';
is $dom->div->p->[0]->text_after, 'thi s', 'right text';
is $dom->div->p->[0]->text_after(0), "\n  thi s\n  ", 'right text';
is $dom->div->p->[1]->text_after, '', 'right text';
is $dom->div->p->[1]->text_after(0), '', 'right text';
is $dom->div->p->[2]->text_after, '', 'right text';
is $dom->div->p->[2]->text_after(0), "\n  ", 'right text';
is $dom->div->p->[3]->text_after, 'work', 'right text';
is $dom->div->p->[3]->text_after(0), "work\n", 'right text';

# PoCo example with whitespace sensitive text
$dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0" encoding="UTF-8"?>
<response>
  <entry>
    <id>1286823</id>
    <displayName>Homer Simpson</displayName>
    <addresses>
      <type>home</type>
      <formatted><![CDATA[742 Evergreen Terrace
Springfield, VT 12345 USA]]></formatted>
    </addresses>
  </entry>
  <entry>
    <id>1286822</id>
    <displayName>Marge Simpson</displayName>
    <addresses>
      <type>home</type>
      <formatted>742 Evergreen Terrace
Springfield, VT 12345 USA</formatted>
    </addresses>
  </entry>
</response>
EOF
is $dom->find('entry')->[0]->displayName->text, 'Homer Simpson', 'right text';
is $dom->find('entry')->[0]->id->text,          '1286823',       'right text';
is $dom->find('entry')->[0]->addresses->children('type')->[0]->text, 'home',
  'right text';
is $dom->find('entry')->[0]->addresses->formatted->text,
  "742 Evergreen Terrace\nSpringfield, VT 12345 USA", 'right text';
is $dom->find('entry')->[0]->addresses->formatted->text(0),
  "742 Evergreen Terrace\nSpringfield, VT 12345 USA", 'right text';
is $dom->find('entry')->[1]->displayName->text, 'Marge Simpson', 'right text';
is $dom->find('entry')->[1]->id->text,          '1286822',       'right text';
is $dom->find('entry')->[1]->addresses->children('type')->[0]->text, 'home',
  'right text';
is $dom->find('entry')->[1]->addresses->formatted->text,
  '742 Evergreen Terrace Springfield, VT 12345 USA', 'right text';
is $dom->find('entry')->[1]->addresses->formatted->text(0),
  "742 Evergreen Terrace\nSpringfield, VT 12345 USA", 'right text';
is $dom->find('entry')->[2], undef, 'no result';
is $dom->find('entry')->size, 2, 'right number of elements';

# Find attribute with hyphen in name and value
$dom = Mojo::DOM->new(<<EOF);
<html>
  <head><meta http-equiv="content-type" content="text/html"></head>
</html>
EOF
is $dom->find('[http-equiv]')->[0]{content}, 'text/html', 'right attribute';
is $dom->find('[http-equiv]')->[1], undef, 'no result';
is $dom->find('[http-equiv="content-type"]')->[0]{content}, 'text/html',
  'right attribute';
is $dom->find('[http-equiv="content-type"]')->[1], undef, 'no result';
is $dom->find('[http-equiv^="content-"]')->[0]{content}, 'text/html',
  'right attribute';
is $dom->find('[http-equiv^="content-"]')->[1], undef, 'no result';
is $dom->find('head > [http-equiv$="-type"]')->[0]{content}, 'text/html',
  'right attribute';
is $dom->find('head > [http-equiv$="-type"]')->[1], undef, 'no result';

# Find "0" attribute value and unescape relaxed entity
$dom = Mojo::DOM->new(<<EOF);
<a accesskey="0">Zero</a>
<a accesskey="1">O&gTn&gte</a>
EOF
is $dom->find('a[accesskey]')->[0]->text, 'Zero',    'right text';
is $dom->find('a[accesskey]')->[1]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey]')->[2], undef, 'no result';
is $dom->find('a[accesskey="0"]')->[0]->text, 'Zero', 'right text';
is $dom->find('a[accesskey="0"]')->[1], undef, 'no result';
is $dom->find('a[accesskey^="0"]')->[0]->text, 'Zero', 'right text';
is $dom->find('a[accesskey^="0"]')->[1], undef, 'no result';
is $dom->find('a[accesskey$="0"]')->[0]->text, 'Zero', 'right text';
is $dom->find('a[accesskey$="0]')->[1], undef, 'no result';
is $dom->find('a[accesskey~="0"]')->[0]->text, 'Zero', 'right text';
is $dom->find('a[accesskey~="0]')->[1], undef, 'no result';
is $dom->find('a[accesskey*="0"]')->[0]->text, 'Zero', 'right text';
is $dom->find('a[accesskey*="0]')->[1], undef, 'no result';
is $dom->find('a[accesskey="1"]')->[0]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey="1"]')->[1], undef, 'no result';
is $dom->find('a[accesskey^="1"]')->[0]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey^="1"]')->[1], undef, 'no result';
is $dom->find('a[accesskey$="1"]')->[0]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey$="1]')->[1], undef, 'no result';
is $dom->find('a[accesskey~="1"]')->[0]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey~="1]')->[1], undef, 'no result';
is $dom->find('a[accesskey*="1"]')->[0]->text, 'O&gTn>e', 'right text';
is $dom->find('a[accesskey*="1]')->[1], undef, 'no result';

# Empty attribute value
$dom = Mojo::DOM->new->parse(<<EOF);
<foo bar=>
  test
</foo>
<bar>after</bar>
EOF
is $dom->tree->[0], 'root', 'right element';
is $dom->tree->[1][0], 'tag', 'right element';
is $dom->tree->[1][1], 'foo', 'right tag';
is_deeply $dom->tree->[1][2], {bar => ''}, 'right attributes';
is $dom->tree->[1][4][0], 'text',       'right element';
is $dom->tree->[1][4][1], "\n  test\n", 'right text';
is $dom->tree->[3][0], 'tag', 'right element';
is $dom->tree->[3][1], 'bar', 'right tag';
is $dom->tree->[3][4][0], 'text',  'right element';
is $dom->tree->[3][4][1], 'after', 'right text';
is "$dom", <<EOF, 'right result';
<foo bar="">
  test
</foo>
<bar>after</bar>
EOF

# Nested lists
$dom = Mojo::DOM->new(<<EOF);
<div>
  <ul>
    <li>
      A
      <ul>
        <li>B</li>
        C
      </ul>
    </li>
  </ul>
</div>
EOF
is $dom->find('div > ul > li')->[0]->text, 'A', 'right text';
is $dom->find('div > ul > li')->[1], undef, 'no result';
is $dom->find('div > ul li')->[0]->text, 'A', 'right text';
is $dom->find('div > ul li')->[1]->text, 'B', 'right text';
is $dom->find('div > ul li')->[2], undef, 'no result';
is $dom->find('div > ul ul')->[0]->text, 'C', 'right text';
is $dom->find('div > ul ul')->[1], undef, 'no result';

# Extra whitespace
$dom = Mojo::DOM->new('< span>a< /span><b >b</b><span >c</ span>');
is $dom->at('span')->text,     'a', 'right text';
is $dom->at('span + b')->text, 'b', 'right text';
is $dom->at('b + span')->text, 'c', 'right text';
is "$dom", '<span>a</span><b>b</b><span>c</span>', 'right result';

# Bad charset
$dom = Mojo::DOM->new->charset('doesnotexist');
$dom->parse('<html><div id="a">A</div></html>');
is $dom->charset, undef, 'no charset';
is $dom->at('#a')->text, 'A', 'right text';
is "$dom", '<html><div id="a">A</div></html>', 'right result';
$dom = Mojo::DOM->new->charset('UTF-8');
$dom->parse(qq{<div id="invalid">\x89</div>});
is $dom->charset, undef, 'no charset';
is $dom->at('#invalid')->text, "\x89", 'right text';
is "$dom", qq{<div id="invalid">\x89</div>}, 'right result';

# "0" with charset
$dom = Mojo::DOM->new->charset('UTF-8');
$dom->parse('0');
is $dom->charset, 'UTF-8', 'right charset';
is "$dom", '0', 'right result';
$dom->append_content('☃');
is "$dom", encode('UTF-8', '0☃'), 'right result';

# Comments
$dom = Mojo::DOM->new(<<EOF);
<!-- HTML5 -->
<!-- bad idea -- HTML5 -->
<!-- HTML4 -- >
<!-- bad idea -- HTML4 -- >
EOF
is $dom->tree->[1][1], ' HTML5 ',             'right comment';
is $dom->tree->[3][1], ' bad idea -- HTML5 ', 'right comment';
is $dom->tree->[5][1], ' HTML4 ',             'right comment';
is $dom->tree->[7][1], ' bad idea -- HTML4 ', 'right comment';

done_testing();
