package Mojo::Cookie::Response;
use Mojo::Base 'Mojo::Cookie';

use Mojo::Date;
use Mojo::Util qw(quote split_header);

has [qw(domain httponly max_age path secure)];

sub expires {
  my $self = shift;

  # Upgrade
  my $e = $self->{expires};
  return $self->{expires} = defined $e && !ref $e ? Mojo::Date->new($e) : $e
    unless @_;
  $self->{expires} = shift;

  return $self;
}

sub parse {
  my ($self, $str) = @_;

  my @cookies;
  my $tree = split_header(defined $str ? $str : '');
  while (my $pairs = shift @$tree) {
    my $i = 0;
    while (@$pairs) {
      my ($name, $value) = (shift @$pairs, shift @$pairs);

      # "expires" is a special case, thank you Netscape...
      if ($name =~ /^expires$/i) {
        push @$pairs, @{ do { my $tmp = shift @$tree; defined $tmp ? $tmp : [] } };
        my $len = (defined $pairs->[0] ? $pairs->[0] : '') =~ /-/ ? 6 : 10;
        $value .= join ' ', ',', grep {defined} splice @$pairs, 0, $len;
      }

      # This will only run once
      push @cookies, $self->new(name => $name, value => defined $value ? $value : '') and next
        unless $i++;

      # Attributes (Netscape and RFC 6265)
      next unless $name =~ /^(expires|domain|path|secure|max-age|httponly)$/i;
      my $attr = lc $1;
      $attr = 'max_age' if $attr eq 'max-age';
      $cookies[-1]
        ->$attr($attr eq 'secure' || $attr eq 'httponly' ? 1 : $value);
    }
  }

  return \@cookies;
}

sub to_string {
  my $self = shift;

  # Name and value (Netscape)
  return '' unless my $name = $self->name;
  my $value = defined $self->value ? $self->value : '';
  $value = $value =~ /[,;" ]/ ? quote($value) : $value;
  my $cookie = "$name=$value";

  # "expires" (Netscape)
  if (defined(my $e = $self->expires)) { $cookie .= "; expires=$e" }

  # "domain" (Netscape)
  if (my $domain = $self->domain) { $cookie .= "; domain=$domain" }

  # "path" (Netscape)
  if (my $path = $self->path) { $cookie .= "; path=$path" }

  # "secure" (Netscape)
  if (my $secure = $self->secure) { $cookie .= "; secure" }

  # "Max-Age" (RFC 6265)
  if (defined(my $m = $self->max_age)) { $cookie .= "; Max-Age=$m" }

  # "HttpOnly" (RFC 6265)
  if (my $httponly = $self->httponly) { $cookie .= "; HttpOnly" }

  return $cookie;
}

1;

=encoding utf8

=head1 NAME

Mojo::Cookie::Response - HTTP response cookie

=head1 SYNOPSIS

  use Mojo::Cookie::Response;

  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('bar');
  say "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Response> is a container for HTTP response cookies as
described in RFC 6265.

=head1 ATTRIBUTES

L<Mojo::Cookie::Response> inherits all attributes from L<Mojo::Cookie> and
implements the following new ones.

=head2 domain

  my $domain = $cookie->domain;
  $cookie    = $cookie->domain('localhost');

Cookie domain.

=head2 httponly

  my $httponly = $cookie->httponly;
  $cookie      = $cookie->httponly(1);

HttpOnly flag, which can prevent client-side scripts from accessing this
cookie.

=head2 max_age

  my $max_age = $cookie->max_age;
  $cookie     = $cookie->max_age(60);

Max age for cookie.

=head2 path

  my $path = $cookie->path;
  $cookie  = $cookie->path('/test');

Cookie path.

=head2 secure

  my $secure = $cookie->secure;
  $cookie    = $cookie->secure(1);

Secure flag, which instructs browsers to only send this cookie over HTTPS
connections.

=head1 METHODS

L<Mojo::Cookie::Response> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 expires

  my $expires = $cookie->expires;
  $cookie     = $cookie->expires(time + 60);
  $cookie     = $cookie->expires(Mojo::Date->new(time + 60));

Expiration for cookie.

=head2 parse

  my $cookies = Mojo::Cookie::Response->parse('f=b; path=/');

Parse cookies.

=head2 to_string

  my $str = $cookie->to_string;

Render cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
