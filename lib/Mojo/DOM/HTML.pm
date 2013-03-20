package Mojo::DOM::HTML;
use Mojo::Base -base;

use Mojo::Util qw(decode encode html_unescape xml_escape);
use Scalar::Util 'weaken';

has [qw(charset xml)];
has tree => sub { ['root'] };

my $ATTR_RE = qr/
  ([^=\s>]+)       # Key
  (?:
    \s*=\s*
    (?:
      "([^"]*?)"   # Quotation marks
    |
      '([^']*?)'   # Apostrophes
    |
      ([^>\s]*)    # Unquoted
    )
  )?
  \s*
/x;
my $END_RE   = qr!^\s*/\s*(.+)\s*!;
my $TOKEN_RE = qr/
  ([^<]*)                                           # Text
  (?:
    <\?(.*?)\?>                                     # Processing Instruction
  |
    <!--(.*?)--\s*>                                 # Comment
  |
    <!\[CDATA\[(.*?)\]\]>                           # CDATA
  |
    <!DOCTYPE(
      \s+\w+
      (?:(?:\s+\w+)?(?:\s+(?:"[^"]*"|'[^']*'))+)?   # External ID
      (?:\s+\[.+?\])?                               # Int Subset
      \s*
    )>
  |
    <(
      \s*
      [^>\s]+                                       # Tag
      \s*
      (?:$ATTR_RE)*                                 # Attributes
    )>
  )??
/xis;

# Optional HTML elements
my %OPTIONAL = map { $_ => 1 }
  qw(body colgroup dd head li optgroup option p rt rp tbody td tfoot th);

# Elements that break HTML paragraphs
my %PARAGRAPH = map { $_ => 1 } (
  qw(address article aside blockquote dir div dl fieldset footer form h1 h2),
  qw(h3 h4 h5 h6 header hgroup hr menu nav ol p pre section table ul)
);

# HTML table elements
my %TABLE = map { $_ => 1 } qw(col colgroup tbody td th thead tr);

# HTML void elements
my %VOID = map { $_ => 1 } (
  qw(area base br col command embed hr img input keygen link meta param),
  qw(source track wbr)
);

# HTML inline elements
my %INLINE = map { $_ => 1 } (
  qw(a abbr acronym applet b basefont bdo big br button cite code del dfn em),
  qw(font i iframe img ins input kbd label map object q s samp script select),
  qw(small span strike strong sub sup textarea tt u var)
);

sub parse {
  my ($self, $html) = @_;

  if (my $charset = $self->charset) {
    if (defined(my $chars = decode $charset, $html)) { $html = $chars }
    else                                             { $self->charset(undef) }
  }

  my $tree    = ['root'];
  my $current = $tree;
  while ($html =~ m/\G$TOKEN_RE/gcs) {
    my ($text, $pi, $comment, $cdata, $doctype, $tag)
      = ($1, $2, $3, $4, $5, $6);

    # Text
    if (length $text) {
      $text = html_unescape $text if (index $text, '&') >= 0;
      $self->_text($text, \$current);
    }

    # DOCTYPE
    if ($doctype) { $self->_doctype($doctype, \$current) }

    # Comment
    elsif ($comment) { $self->_comment($comment, \$current) }

    # CDATA
    elsif ($cdata) { $self->_cdata($cdata, \$current) }

    # Processing instruction
    elsif ($pi) { $self->_pi($pi, \$current) }

    # End
    next unless $tag;
    my $cs = $self->xml;
    if ($tag =~ $END_RE) { $self->_end($cs ? $1 : lc($1), \$current) }

    # Start
    elsif ($tag =~ m!([^\s/]+)([\s\S]*)!) {
      my ($start, $attr) = ($cs ? $1 : lc($1), $2);

      # Attributes
      my %attrs;
      while ($attr =~ /$ATTR_RE/g) {
        my $key = $cs ? $1 : lc($1);
        my $value = defined $2 ? $2 : defined $3 ? $3 : $4;

        # Empty tag
        next if $key eq '/';

        # Add unescaped value
        $value = html_unescape $value if $value && (index $value, '&') >= 0;
        $attrs{$key} = $value;
      }

      # Start
      $self->_start($start, \%attrs, \$current);

      # Empty element
      $self->_end($start, \$current)
        if (!$self->xml && $VOID{$start}) || $attr =~ m!/\s*$!;

      # Relaxed "script" or "style"
      if (grep { $_ eq $start } qw(script style)) {
        if ($html =~ m!\G(.*?)<\s*/\s*$start\s*>!gcsi) {
          $self->_raw($1, \$current);
          $self->_end($start, \$current);
        }
      }
    }
  }

  return $self->tree($tree);
}

sub render {
  my $self    = shift;
  my $content = $self->_render($self->tree);
  my $charset = $self->charset;
  return $charset ? encode($charset, $content) : $content;
}

sub _cdata {
  my ($self, $cdata, $current) = @_;
  push @$$current, ['cdata', $cdata];
}

sub _close {
  my ($self, $current, $tags, $stop) = @_;
  $tags ||= \%TABLE;
  $stop ||= 'table';

  # Check if parents need to be closed
  my $parent = $$current;
  while ($parent) {
    last if $parent->[0] eq 'root' || $parent->[1] eq $stop;

    # Close
    $tags->{$parent->[1]} and $self->_end($parent->[1], $current);

    # Try next
    $parent = $parent->[3];
  }
}

sub _comment {
  my ($self, $comment, $current) = @_;
  push @$$current, ['comment', $comment];
}

sub _doctype {
  my ($self, $doctype, $current) = @_;
  push @$$current, ['doctype', $doctype];
}

sub _end {
  my ($self, $end, $current) = @_;

  # Not a tag
  return if $$current->[0] eq 'root';

  # Search stack for start tag
  my $found = 0;
  my $next  = $$current;
  while ($next) {
    last if $next->[0] eq 'root';

    # Right tag
    ++$found and last if $next->[1] eq $end;

    # Inline elements can only cross other inline elements
    return if !$self->xml && $INLINE{$end} && !$INLINE{$next->[1]};

    # Parent
    $next = $next->[3];
  }

  # Ignore useless end tag
  return unless $found;

  # Walk backwards
  $next = $$current;
  while ($$current = $next) {
    last if $$current->[0] eq 'root';
    $next = $$current->[3];

    # Match
    if ($end eq $$current->[1]) { return $$current = $$current->[3] }

    # Optional elements
    elsif ($OPTIONAL{$$current->[1]}) {
      $self->_end($$current->[1], $current);
    }

    # Table
    elsif ($end eq 'table') { $self->_close($current) }

    # Missing end tag
    $self->_end($$current->[1], $current);
  }
}

# Try to detect XML from processing instructions
sub _pi {
  my ($self, $pi, $current) = @_;
  $self->xml(1) if !defined $self->xml && $pi =~ /xml/i;
  push @$$current, ['pi', $pi];
}

sub _raw {
  my ($self, $raw, $current) = @_;
  push @$$current, ['raw', $raw];
}

sub _render {
  my ($self, $tree) = @_;

  # Text (escaped)
  my $e = $tree->[0];
  return xml_escape $tree->[1] if $e eq 'text';

  # Raw text
  return $tree->[1] if $e eq 'raw';

  # DOCTYPE
  return "<!DOCTYPE" . $tree->[1] . ">" if $e eq 'doctype';

  # Comment
  return "<!--" . $tree->[1] . "-->" if $e eq 'comment';

  # CDATA
  return "<![CDATA[" . $tree->[1] . "]]>" if $e eq 'cdata';

  # Processing instruction
  return "<?" . $tree->[1] . "?>" if $e eq 'pi';

  # Start tag
  my $start = $e eq 'root' ? 1 : 2;
  my $content = '';
  if ($e eq 'tag') {
    $start = 4;

    # Open tag
    my $tag = $tree->[1];
    $content .= "<$tag";

    # Attributes
    my @attrs;
    for my $key (sort keys %{$tree->[2]}) {
      my $value = $tree->[2]{$key};

      # No value
      push @attrs, $key and next unless defined $value;

      # Key and value
      push @attrs, qq{$key="} . xml_escape($value) . '"';
    }
    my $attrs = join ' ', @attrs;
    $content .= " $attrs" if $attrs;

    # Empty tag
    return $self->xml || $VOID{$tag} ? "$content />" : "$content></$tag>"
      unless $tree->[4];

    # Close tag
    $content .= '>';
  }

  # Render whole tree
  $content .= $self->_render($tree->[$_]) for $start .. $#$tree;

  # End tag
  $content .= '</' . $tree->[1] . '>' if $e eq 'tag';

  return $content;
}

sub _start {
  my ($self, $start, $attrs, $current) = @_;

  # Autoclose optional HTML elements
  if (!$self->xml && $$current->[0] ne 'root') {

    # "<li>"
    if ($start eq 'li') { $self->_close($current, {li => 1}, 'ul') }

    # "<p>"
    elsif ($PARAGRAPH{$start}) { $self->_end('p', $current) }

    # "<head>"
    elsif ($start eq 'body') { $self->_end('head', $current) }

    # "<optgroup>"
    elsif ($start eq 'optgroup') { $self->_end('optgroup', $current) }

    # "<option>"
    elsif ($start eq 'option') { $self->_end('option', $current) }

    # "<colgroup>", "<thead>", "tbody" and "tfoot"
    elsif (grep { $_ eq $start } qw(colgroup thead tbody tfoot)) {
      $self->_close($current);
    }

    # "<tr>"
    elsif ($start eq 'tr') { $self->_close($current, {tr => 1}) }

    # "<th>" and "<td>"
    elsif (grep { $_ eq $start } qw(th td)) {
      $self->_close($current, {th => 1});
      $self->_close($current, {td => 1});
    }

    # "<dt>" and "<dd>"
    elsif (grep { $_ eq $start } qw(dt dd)) {
      $self->_end('dt', $current);
      $self->_end('dd', $current);
    }

    # "<rt>" and "<rp>"
    elsif (grep { $_ eq $start } qw(rt rp)) {
      $self->_end('rt', $current);
      $self->_end('rp', $current);
    }
  }

  # New tag
  my $new = ['tag', $start, $attrs, $$current];
  weaken $new->[3];
  push @$$current, $new;
  $$current = $new;
}

sub _text {
  my ($self, $text, $current) = @_;
  push @$$current, ['text', $text];
}

1;

=head1 NAME

Mojo::DOM::HTML - HTML/XML engine

=head1 SYNOPSIS

  use Mojo::DOM::HTML;

  # Turn HTML into DOM tree
  my $html = Mojo::DOM::HTML->new;
  $html->parse('<div><p id="a">A</p><p id="b">B</p></div>');
  my $tree = $html->tree;

=head1 DESCRIPTION

L<Mojo::DOM::HTML> is the HTML/XML engine used by L<Mojo::DOM>.

=head1 ATTRIBUTES

L<Mojo::DOM::HTML> implements the following attributes.

=head2 charset

  my $charset = $html->charset;
  $html       = $html->charset('UTF-8');

Charset used for decoding and encoding HTML/XML.

=head2 tree

  my $tree = $html->tree;
  $html    = $html->tree(['root', [qw(text lalala)]]);

Document Object Model.

=head2 xml

  my $xml = $html->xml;
  $html   = $html->xml(1);

Disable HTML semantics in parser and activate case sensitivity, defaults to
auto detection based on processing instructions.

=head1 METHODS

L<Mojo::DOM::HTML> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 parse

  $html = $html->parse('<foo bar="baz">test</foo>');

Parse HTML/XML document.

=head2 render

  my $xml = $html->render;

Render DOM to XML.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
