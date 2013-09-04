use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD};

use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::Util qw(slurp spurt);

# Prepare script
my $dir = tempdir CLEANUP => 1;
my $script = catdir $dir, 'myapp.pl';
my $log    = catdir $dir, 'mojo.log';
my $port1  = Mojo::IOLoop->generate_port;
my $port2  = Mojo::IOLoop->generate_port;
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => {text => 'Hello Hypnotoad!'};

app->start;
EOF

# Start
my $prefix = "$FindBin::Bin/../../script";
open my $start, '-|', $^X, "$prefix/hypnotoad", $script;
sleep 3;
sleep 1
  while !IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => '127.0.0.1',
  PeerPort => $port2
  );
my $old = _pid();

my $ua = Mojo::UserAgent->new;

# Application is alive
my $tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Application is alive (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script
spurt <<EOF, $script;
use Mojolicious::Lite;

app->log->path('$log');

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      workers => 1
    }
  }
};

app->log->level('debug');

get '/hello' => {text => 'Hello World!'};

app->start;
EOF
open my $hot_deploy, '-|', $^X, "$prefix/hypnotoad", $script;

# Connection did not get lost
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Connection did not get lost (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Remove keep-alive connections
$ua = Mojo::UserAgent->new;

# Wait for hot deployment to finish
while (1) {
  sleep 1;
  next unless my $new = _pid();
  last if $new ne $old;
}

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Application has been reloaded (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Same result (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200,            'right status';
is $tx->res->body, 'Hello World!', 'right content';

# Stop
open my $stop, '-|', $^X, "$prefix/hypnotoad", $script, '-s';
sleep 1
  while IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => '127.0.0.1',
  PeerPort => $port2
  );

# Check log
$log = slurp $log;
like $log, qr/Worker \d+ started\./,                      'right message';
like $log, qr/Starting zero downtime software upgrade\./, 'right message';
like $log, qr/Upgrade successful, stopping $old\./,       'right message';

sub _pid {
  return undef unless open my $file, '<', catdir($dir, 'hypnotoad.pid');
  my $pid = <$file>;
  chomp $pid;
  return $pid;
}

done_testing();
