package Mojo::UserAgent::Transactor;
use Mojo::Base -base;

use File::Basename 'basename';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::JSON;
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw(deprecated encode);

has generators => sub { {} };

sub new {
  my $self = shift->SUPER::new(@_);
  $self->add_generator(form => \&_form);
  $self->add_generator(json => \&_json);
  return $self;
}

sub add_generator {
  my ($self, $name, $cb) = @_;
  $self->generators->{$name} = $cb;
  return $self;
}

sub endpoint {
  my ($self, $tx) = @_;

  # Basic endpoint
  my $req   = $tx->req;
  my $url   = $req->url;
  my $proto = $url->protocol || 'http';
  my $host  = $url->ihost;
  my $port  = $url->port || ($proto eq 'https' ? 443 : 80);

  # Proxy for normal HTTP requests
  return $self->_proxy($tx, $proto, $host, $port)
    if $proto eq 'http' && lc(defined $req->headers->upgrade ? $req->headers->upgrade : '') ne 'websocket';

  return $proto, $host, $port;
}

# DEPRECATED in Rainbow!
sub form {
  deprecated 'Mojo::UserAgent::Transactor::form is DEPRECATED in favor of '
    . 'Mojo::UserAgent::Transactor::tx';
  my ($self, $url, $charset) = (shift, shift, shift);
  my $form = ref $charset ? $charset : shift;
  $charset = undef if ref $charset;
  return $self->tx(POST => $url, @_, form => $form, charset => $charset);
}

# DEPRECATED in Rainbow!
sub json {
  deprecated 'Mojo::UserAgent::Transactor::json is DEPRECATED in favor of '
    . 'Mojo::UserAgent::Transactor::tx';
  my ($self, $url, $data) = (shift, shift, shift);
  return $self->tx(POST => $url, @_, json => $data);
}

sub peer {
  my ($self, $tx) = @_;
  return $self->_proxy($tx, $self->endpoint($tx));
}

sub proxy_connect {
  my ($self, $old) = @_;

  # Already a CONNECT request
  my $req = $old->req;
  return undef if $req->method eq 'CONNECT';

  # No proxy
  return undef unless my $proxy = $req->proxy;

  # WebSocket and/or HTTPS
  my $url = $req->url;
  my $upgrade = lc(defined $req->headers->upgrade ? $req->headers->upgrade : '');
  return undef unless $upgrade eq 'websocket' || $url->protocol eq 'https';

  # CONNECT request
  my $new = $self->tx(CONNECT => $url->clone->userinfo(undef));
  $new->req->proxy($proxy);

  return $new;
}

sub redirect {
  my ($self, $old) = @_;

  # Commonly used codes
  my $res = $old->res;
  my $code = defined $res->code ? $res->code : '';
  return undef unless grep { $_ eq $code } 301, 302, 303, 307, 308;

  # Fix broken location without authority and/or scheme
  return unless my $location = $res->headers->location;
  $location = Mojo::URL->new($location);
  $location = $location->base($old->req->url)->to_abs unless $location->is_abs;

  # Clone request if necessary
  my $new    = Mojo::Transaction::HTTP->new;
  my $req    = $old->req;
  my $method = $req->method;
  if (grep { $_ eq $code } 301, 307, 308) {
    return undef unless my $req = $req->clone;
    $new->req($req);
    $req->headers->remove('Host')->remove('Cookie')->remove('Referer');
  }
  elsif ($method ne 'HEAD') { $method = 'GET' }
  $new->req->method($method)->url($location);
  return $new->previous($old);
}

sub tx {
  my $self = shift;

  # Method and URL
  my $tx  = Mojo::Transaction::HTTP->new;
  my $req = $tx->req->method(shift);
  my $url = shift;
  $url = "http://$url" unless $url =~ m!^/|://!;
  ref $url ? $req->url($url) : $req->url->parse($url);

  # Headers
  $req->headers->from_hash(shift) if ref $_[0] eq 'HASH';

  # Generator
  if (@_ > 1) {
    return $tx unless my $generator = $self->generators->{shift()};
    $self->$generator($tx, @_);
  }

  # Body
  elsif (@_) { $req->body(shift) }

  return $tx;
}

sub upgrade {
  my ($self, $tx) = @_;
  my $code = defined $tx->res->code ? $tx->res->code : '';
  return undef unless $tx->req->headers->upgrade && $code eq '101';
  my $ws = Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1);
  return $ws->client_challenge ? $ws : undef;
}

sub websocket {
  my $self = shift;

  # New WebSocket transaction
  my $tx    = $self->tx(GET => @_);
  my $url   = $tx->req->url;
  my $proto = $url->protocol;
  $url->scheme($proto eq 'wss' ? 'https' : 'http') if $proto;

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx)->client_handshake;

  return $tx;
}

sub _form {
  my ($self, $tx, $form, %options) = @_;

  # Check for uploads and force multipart if necessary
  my $multipart;
  for my $value (map { ref $_ eq 'ARRAY' ? @$_ : $_ } values %$form) {
    ++$multipart and last if ref $value eq 'HASH';
  }
  my $req     = $tx->req;
  my $headers = $req->headers;
  $headers->content_type('multipart/form-data') if $multipart;

  # Multipart
  if ((defined $headers->content_type ? $headers->content_type : '') eq 'multipart/form-data') {
    my $parts = $self->_multipart($options{charset}, $form);
    $req->content(
      Mojo::Content::MultiPart->new(headers => $headers, parts => $parts));
  }

  # Urlencoded
  else {
    $headers->content_type('application/x-www-form-urlencoded');
    my $p = Mojo::Parameters->new(map { $_ => $form->{$_} } sort keys %$form);
    $p->charset($options{charset}) if defined $options{charset};
    $req->body($p->to_string);
  }

  return $tx;
}

sub _json {
  my ($self, $tx, $data) = @_;
  $tx->req->body(Mojo::JSON->new->encode($data));
  my $headers = $tx->req->headers;
  $headers->content_type('application/json') unless $headers->content_type;
  return $tx;
}

sub _multipart {
  my ($self, $charset, $form) = @_;

  my @parts;
  for my $name (sort keys %$form) {
    my $values = $form->{$name};
    for my $value (ref $values eq 'ARRAY' ? @$values : ($values)) {
      push @parts, my $part = Mojo::Content::Single->new;

      # Upload
      my $filename;
      my $headers = $part->headers;
      if (ref $value eq 'HASH') {

        # File
        if (my $file = delete $value->{file}) {
          $file = Mojo::Asset::File->new(path => $file) unless ref $file;
          $part->asset($file);
          $value->{filename} ||= basename $file->path
            if $file->isa('Mojo::Asset::File');
        }

        # Memory
        elsif (defined(my $content = delete $value->{content})) {
          $part->asset(Mojo::Asset::Memory->new->add_chunk($content));
        }

        # Filename and headers
        $filename = delete $value->{filename} || $name;
        $filename = encode $charset, $filename if $charset;
        $headers->from_hash($value);
      }

      # Field
      else {
        $value = encode $charset, $value if $charset;
        $part->asset(Mojo::Asset::Memory->new->add_chunk($value));
      }

      # Content-Disposition
      $name = encode $charset, $name if $charset;
      my $disposition = qq{form-data; name="$name"};
      $disposition .= qq{; filename="$filename"} if $filename;
      $headers->content_disposition($disposition);
    }
  }

  return \@parts;
}

sub _proxy {
  my ($self, $tx, $proto, $host, $port) = @_;

  # Update with proxy information
  if (my $proxy = $tx->req->proxy) {
    $proto = $proxy->protocol;
    $host  = $proxy->ihost;
    $port  = $proxy->port || ($proto eq 'https' ? 443 : 80);
  }

  return $proto, $host, $port;
}

1;

=head1 NAME

Mojo::UserAgent::Transactor - User agent transactor

=head1 SYNOPSIS

  use Mojo::UserAgent::Transactor;

  # Simple GET request
  my $t = Mojo::UserAgent::Transactor->new;
  say $t->tx(GET => 'http://mojolicio.us')->req->to_string;

  # PATCH request with "Do Not Track" header and content
  say $t->tx(PATCH => 'mojolicio.us' => {DNT => 1} => 'Hi!')->req->to_string;

  # POST request with form data
  say $t->tx(POST => 'kraih.com' => form => {a => 'b'})->req->to_string;

  # PUT request with JSON data
  say $t->tx(PUT => 'http://kraih.com' => json => {a => 'b'})->req->to_string;

=head1 DESCRIPTION

L<Mojo::UserAgent::Transactor> is the transaction building and manipulation
framework used by L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::Transactor> implements the following attributes.

=head2 generators

  my $generators = $t->generators;
  $t             = $t->generators({foo => sub {...}});

Registered generators.

=head1 METHODS

L<Mojo::UserAgent::Transactor> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 new

  my $t = Mojo::UserAgent::Transactor->new;

Construct a new transactor and register C<form> and C<json> generators.

=head2 add_generator

  $t = $t->add_generator(foo => sub {...});

Register a new generator.

=head2 endpoint

  my ($proto, $host, $port) = $t->endpoint(Mojo::Transaction::HTTP->new);

Actual endpoint for transaction.

=head2 peer

  my ($proto, $host, $port) = $t->peer(Mojo::Transaction::HTTP->new);

Actual peer for transaction.

=head2 proxy_connect

  my $tx = $t->proxy_connect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> proxy connect request for transaction if
possible.

=head2 redirect

  my $tx = $t->redirect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> followup request for C<301>, C<302>, C<303>,
C<307> or C<308> redirect response if possible.

=head2 tx

  my $tx = $t->tx(GET  => 'kraih.com');
  my $tx = $t->tx(POST => 'http://kraih.com');
  my $tx = $t->tx(GET  => 'http://kraih.com' => {DNT => 1});
  my $tx = $t->tx(PUT  => 'http://kraih.com' => 'Hi!');
  my $tx = $t->tx(PUT  => 'http://kraih.com' => form => {a => 'b'});
  my $tx = $t->tx(PUT  => 'http://kraih.com' => json => {a => 'b'});
  my $tx = $t->tx(POST => 'http://kraih.com' => {DNT => 1} => 'Hi!');
  my $tx = $t->tx(
    PUT  => 'http://kraih.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $t->tx(
    PUT  => 'http://kraih.com' => {DNT => 1} => json => {a => 'b'});

Versatile general purpose L<Mojo::Transaction::HTTP> transaction builder for
requests, with support for generators.

  # Inspect generated request
  say $t->tx(GET => 'mojolicio.us' => {DNT => 1} => 'Bye!')->req->to_string;

  # Streaming response
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { say $_[1] });

  # Custom socket
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->connection($sock);

  # Use form generator with custom charset
  my $tx = $t->tx(
    PUT => 'http://kraih.com' => form => {a => 'b'} => charset => 'UTF-8');

  # Multiple form values with the same name
  my $tx = $t->tx(PUT => 'http://kraih.com' => form => {a => [qw(b c d)]});

  # Multipart upload streamed from file
  my $tx = $t->tx(
    PUT => 'http://kraih.com' => form => {mytext => {file => '/foo.txt'}});

  # Multipart upload with in-memory content
  my $tx = $t->tx(
    POST => 'http://kraih.com' => form => {mytext => {content => 'lalala'}});

  # Upload multiple files
  my $tx = $t->tx(POST => 'http://kraih.com' =>
    form => {mytext => [{content => 'first'}, {content => 'second'}]});

  # Customized upload with filename and header
  my $tx = $t->tx(POST => 'http://kraih.com' => form => {
    myzip => {
      file     => Mojo::Asset::Memory->new->add_chunk('lalala'),
      filename => 'foo.zip',
      DNT      => 1
    }
  });

While the "multipart/form-data" content type will be automatically used
instead of "application/x-www-form-urlencoded" when necessary, you can also
enforce it by setting the header manually.

=head2 upgrade

  my $tx = $t->upgrade(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::WebSocket> followup transaction for WebSocket
handshake if possible.

=head2 websocket

  my $tx = $t->websocket('ws://localhost:3000');
  my $tx = $t->websocket('ws://localhost:3000' => {DNT => 1});

Versatile L<Mojo::Transaction::HTTP> transaction builder for WebSocket
handshake requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
