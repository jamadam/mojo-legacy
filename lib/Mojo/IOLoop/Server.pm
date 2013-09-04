package Mojo::IOLoop::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use IO::Socket::INET;
use Scalar::Util 'weaken';
use Socket qw(IPPROTO_TCP TCP_NODELAY);

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.16 (); 1';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS} ? 0
  : eval(IPV6 ? 'use IO::Socket::SSL 1.75 (); 1'
  : 'use IO::Socket::SSL 1.75 "inet4"; 1');
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# To regenerate the certificate run this command (18.04.2012)
# openssl req -new -x509 -keyout server.key -out server.crt -nodes -days 7300
my $CERT = catfile dirname(__FILE__), 'server.crt';
my $KEY  = catfile dirname(__FILE__), 'server.key';

has multi_accept => 50;
has reactor      => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->reactor;
};

sub DESTROY {
  my $self = shift;
  if (my $port = $self->{port}) { $ENV{MOJO_REUSE} =~ s/(?:^|\,)${port}:\d+// }
  return unless my $reactor = $self->reactor;
  $self->stop if $self->{handle};
  $reactor->remove($_) for values %{$self->{handles}};
}

sub listen {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Look for reusable file descriptor
  my $reuse = my $port = $self->{port} = $args->{port} || 3000;
  $ENV{MOJO_REUSE} ||= '';
  my $fd;
  if ($ENV{MOJO_REUSE} =~ /(?:^|\,)${reuse}:(\d+)/) { $fd = $1 }

  # Allow file descriptor inheritance
  local $^F = 1000;

  # Reuse file descriptor
  my $handle;
  my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
  if (defined $fd) {
    $handle = $class->new_from_fd($fd, 'r')
      or croak "Can't open file descriptor $fd: $!";
  }

  # New socket
  else {
    my %options = (
      Listen => defined $args->{backlog} ? $args->{backlog} : SOMAXCONN,
      LocalAddr => $args->{address} || '0.0.0.0',
      LocalPort => $port,
      Proto     => 'tcp',
      ReuseAddr => 1,
      ReusePort => $args->{reuse},
      Type      => SOCK_STREAM
    );
    $options{LocalAddr} =~ s/[\[\]]//g;
    $handle = $class->new(%options) or croak "Can't create listen socket: $@";
    $fd = fileno $handle;
    $ENV{MOJO_REUSE} .= length $ENV{MOJO_REUSE} ? ",$reuse:$fd" : "$reuse:$fd";
  }
  $handle->blocking(0);
  $self->{handle} = $handle;

  return unless $args->{tls};
  croak "IO::Socket::SSL 1.75 required for TLS support" unless TLS;

  # Prioritize RC4 to mitigate BEAST attack and use Perfect Forward Secrecy
  my $options = $self->{tls} = {
    SSL_cert_file => $args->{tls_cert} || $CERT,
    SSL_cipher_list =>
      'ECDHE-RSA-AES128-SHA256:AES128-GCM-SHA256:RC4:HIGH:!MD5:!aNULL:!EDH',
    SSL_honor_cipher_order => 1,
    SSL_key_file           => $args->{tls_key} || $KEY,
    SSL_startHandshake     => 0,
    SSL_verify_mode        => 0x00
  };
  return unless $args->{tls_ca};
  $options->{SSL_ca_file} = -T $args->{tls_ca} ? $args->{tls_ca} : undef;
  $options->{SSL_verify_mode}
    = defined $args->{tls_verify} ? $args->{tls_verify} : 0x03;
}

sub generate_port {
  IO::Socket::INET->new(Listen => 5, LocalAddr => '127.0.0.1', Proto => 'tcp')
    ->sockport;
}

sub handle { shift->{handle} }

sub start {
  my $self = shift;
  weaken $self;
  $self->reactor->io(
    $self->{handle} => sub { $self->_accept for 1 .. $self->multi_accept });
}

sub stop { $_[0]->reactor->remove($_[0]{handle}) }

sub _accept {
  my $self = shift;

  return unless my $handle = $self->{handle}->accept;
  $handle->blocking(0);

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  # Start TLS handshake
  return $self->emit_safe(accept => $handle) unless my $tls = $self->{tls};
  weaken $self;
  $tls->{SSL_error_trap} = sub {
    return unless my $handle = delete $self->{handles}{shift()};
    $self->reactor->remove($handle);
    close $handle;
  };
  return unless $handle = IO::Socket::SSL->start_SSL($handle, %$tls);
  $self->reactor->io($handle => sub { $self->_tls($handle) });
  $self->{handles}{$handle} = $handle;
}

sub _tls {
  my ($self, $handle) = @_;

  # Accepted
  if ($handle->accept_SSL) {
    $self->reactor->remove($handle);
    return $self->emit_safe(accept => delete $self->{handles}{$handle});
  }

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Server - Non-blocking TCP server

=head1 SYNOPSIS

  use Mojo::IOLoop::Server;

  # Create listen socket
  my $server = Mojo::IOLoop::Server->new;
  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });
  $server->listen(port => 3000);

  # Start and stop accepting connections
  $server->start;
  $server->stop;

  # Start reactor if necessary
  $server->reactor->start unless $server->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Server> accepts TCP connections for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Server> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 accept

  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });

Emitted safely for each accepted connection.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Server> implements the following attributes.

=head2 multi_accept

  my $multi = $server->multi_accept;
  $server   = $server->multi_accept(100);

Number of connections to accept at once, defaults to C<50>.

=head2 reactor

  my $reactor = $server->reactor;
  $server     = $server->reactor(Mojo::Reactor::Poll->new);

Low level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Server> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 listen

  $server->listen(port => 3000);

Create a new listen socket. Note that TLS support depends on
L<IO::Socket::SSL> (1.75+) and IPv6 support on L<IO::Socket::IP> (0.16+).

These options are currently available:

=over 2

=item address

  address => '127.0.0.1'

Local address to listen on, defaults to all.

=item backlog

  backlog => 128

Maximum backlog size, defaults to C<SOMAXCONN>.

=item port

  port => 80

Port to listen on.

=item reuse

  reuse => 1

Allow multiple servers to use the same port with the C<SO_REUSEPORT> socket
option.

=item tls

  tls => 1

Enable TLS.

=item tls_ca

  tls_ca => '/etc/tls/ca.crt'

Path to TLS certificate authority file.

=item tls_cert

  tls_cert => '/etc/tls/server.crt'

Path to the TLS cert file, defaults to a built-in test certificate.

=item tls_key

  tls_key => '/etc/tls/server.key'

Path to the TLS key file, defaults to a built-in test key.

=item tls_verify

  tls_verify => 0x00

TLS verification mode, defaults to C<0x03>.

=back

=head2 generate_port

  my $port = $server->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 handle

  my $handle = $server->handle;

Get handle for server.

=head2 start

  $server->start;

Start accepting connections.

=head2 stop

  $server->stop;

Stop accepting connections.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
