package Mojo::Cookie;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Carp 'croak';

has [qw(name value)];

sub parse     { croak 'Method "parse" not implemented by subclass' }
sub to_string { croak 'Method "to_string" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::Cookie - HTTP cookie base class

=head1 SYNOPSIS

  package Mojo::Cookie::MyCookie;
  use Mojo::Base 'Mojo::Cookie';

  sub parse     {...}
  sub to_string {...}

=head1 DESCRIPTION

L<Mojo::Cookie> is an abstract base class for HTTP cookies as described in RFC
6265.

=head1 ATTRIBUTES

L<Mojo::Cookie> implements the following attributes.

=head2 name

  my $name = $cookie->name;
  $cookie  = $cookie->name('foo');

Cookie name.

=head2 value

  my $value = $cookie->value;
  $cookie   = $cookie->value('/test');

Cookie value.

=head1 METHODS

L<Mojo::Cookie> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 parse

  my $cookies = $cookie->parse($str);

Parse cookies. Meant to be overloaded in a subclass.

=head2 to_string

  my $str = $cookie->to_string;
  my $str = "$cookie";

Render cookie. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
