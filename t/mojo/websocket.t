use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use IO::Socket::INET;
use Mojo::ByteStream 'b';
use Mojo::IOLoop;
use Mojo::Transaction::WebSocket;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Max WebSocket size
{
  local $ENV{MOJO_MAX_WEBSOCKET_SIZE} = 1024;
  is(Mojo::Transaction::WebSocket->new->max_websocket_size,
    1024, 'right value');
}

# Silence
app->log->level('fatal');

# Avoid exception template
app->renderer->paths->[0] = app->home->rel_dir('public');

get '/link' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('index')->to_abs);
};

my $server;
websocket '/' => sub {
  my $self = shift;
  $self->on(finish => sub { $server += 2 });
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      my $url = $self->url_for->to_abs;
      $self->send("${msg}test2$url");
      $server = 1;
    }
  );
} => 'index';

get '/something/else' => sub {
  my $self = shift;
  my $timeout
    = Mojo::IOLoop->singleton->stream($self->tx->connection)->timeout;
  $self->render(text => "${timeout}failed!");
};

websocket '/socket' => sub {
  my $self = shift;
  $self->send(
    $self->req->headers->host => sub {
      my $self = shift;
      $self->send(Mojo::IOLoop->stream($self->tx->connection)->timeout);
      $self->finish;
    }
  );
};

websocket '/early_start' => sub {
  my $self = shift;
  $self->send('test1');
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("${msg}test2")->finish;
    }
  );
};

my ($handshake, $denied);
websocket '/denied' => sub {
  my $self = shift;
  $self->tx->handshake->on(finish => sub { $handshake += 1 });
  $self->on(finish => sub { $denied += 1 });
  $self->render(text => 'denied', status => 403);
};

my $subreq;
websocket '/subreq' => sub {
  my $self = shift;
  $self->ua->websocket(
    '/echo' => sub {
      my ($ua, $tx) = @_;
      $tx->on(
        message => sub {
          my ($tx, $msg) = @_;
          $self->send($msg);
          $tx->finish;
          $self->finish;
        }
      );
      $tx->send('test1');
    }
  );
  $self->send('test0');
  $self->on(finish => sub { $subreq += 1 });
};

websocket '/echo' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send($msg);
    }
  );
};

my $buffer = '';
websocket '/double_echo' => sub {
  shift->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send($msg => sub { shift->send($msg) });
    }
  );
};

websocket '/squish' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send(b($msg)->squish);
    }
  );
};

websocket '/dead' => sub { die 'i see dead processes' };

websocket '/foo' =>
  sub { shift->rendered->res->code('403')->message("i'm a teapot") };

websocket '/deadcallback' => sub {
  my $self = shift;
  $self->on(message => sub { die 'i see dead callbacks' });
};

my $timeout;
websocket '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->stream($self->tx->connection)->timeout(0.25);
  $self->on(finish => sub { $timeout = 'works!' });
};

my $ua  = app->ua;
my $res = $ua->get('/link')->success;
is $res->code, 200, 'right status';
like $res->body, qr!ws://localhost:\d+/!, 'right content';

# Plain HTTP request
$res = $ua->get('/socket')->res;
is $res->code, 404, 'right status';
like $res->body, qr/Page not found/, 'right content';

# Plain WebSocket
my $result;
$ua->websocket(
  '/' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
        $tx->finish;
      }
    );
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
like $result, qr!test1test2ws://localhost:\d+/!, 'right result';

# Failed WebSocket connection
my ($code, $body, $ws);
$ua->websocket(
  '/something/else' => sub {
    my ($ua, $tx) = @_;
    $ws   = $tx->is_websocket;
    $code = $tx->res->code;
    $body = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$ws, 'not a WebSocket';
is $code, 426, 'right code';
ok $body =~ /^(\d+)failed!$/, 'right content';
is $1, 15, 'right timeout';

# Using an already prepared socket
my $port = $ua->app_url->port;
my $tx   = $ua->build_websocket_tx('ws://lalala/socket');
my $finished;
$tx->on(finish => sub { $finished++ });
my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);
$sock->blocking(0);
$tx->connection($sock);
$result = '';
my ($local, $early);
$ua->start(
  $tx => sub {
    my ($ua, $tx) = @_;
    $early = $finished;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $tx->finish if length $result;
        $result .= $msg;
      }
    );
    $local = Mojo::IOLoop->stream($tx->connection)->handle->sockport;
  }
);
Mojo::IOLoop->start;
is $finished, 1, 'finish event has been emitted';
is $early,    1, 'finish event has been emitted at the right time';
ok $result =~ /^lalala(\d+)$/, 'right result';
is $1, 15, 'right timeout';
ok $local, 'local port';
is(Mojo::IOLoop->stream($tx->connection)->handle, $sock,
  'right connection id');

# Server directly sends a message
$result = undef;
my $client;
$ua->websocket(
  '/early_start' => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      finish => sub {
        $client += 2;
        Mojo::IOLoop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
        $tx->send('test3');
        $client = 1;
      }
    );
  }
);
Mojo::IOLoop->start;
is $result, 'test3test2', 'right result';
is $client, 3,            'finish event has been emitted';

# Connection denied
($code, $ws) = ();
$ua->websocket(
  '/denied' => sub {
    my ($ua, $tx) = @_;
    $ws   = $tx->is_websocket;
    $code = $tx->res->code;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$ws, 'not a WebSocket';
is $code,      403, 'right status';
is $handshake, 1,   'finished handshake';
is $denied,    1,   'finished websocket';

# Subrequests
$finished = 0;
($code, $result) = ();
$ua->websocket(
  '/subreq' => sub {
    my ($ua, $tx) = @_;
    $code = $tx->res->code;
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result .= $msg;
        $tx->finish if $msg eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 4;
        Mojo::IOLoop->stop;
      }
    );
  }
);
Mojo::IOLoop->start;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $finished, 4,            'finished client websocket';
is $subreq,   1,            'finished server websocket';

# Parallel subrequests
my $delay = Mojo::IOLoop->delay;
$finished = 0;
($code, $result) = ();
my ($code2, $result2);
my $end = $delay->begin;
$ua->websocket(
  '/subreq' => sub {
    my ($ua, $tx) = @_;
    $code = $tx->res->code;
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result .= $msg;
        $tx->finish if $msg eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 1;
        $end->();
      }
    );
  }
);
my $end2 = $delay->begin;
$ua->websocket(
  '/subreq' => sub {
    my ($ua, $tx) = @_;
    $code2 = $tx->res->code;
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result2 .= $msg;
        $tx->finish if $msg eq 'test1';
      }
    );
    $tx->on(
      finish => sub {
        $finished += 2;
        $end2->();
      }
    );
  }
);
$delay->wait;
is $code,     101,          'right status';
is $result,   'test0test1', 'right result';
is $code2,    101,          'right status';
is $result2,  'test0test1', 'right result';
is $finished, 3,            'finished client websocket';
is $subreq,   3,            'finished server websocket';

# Client-side drain callback
$result = '';
$client = 0;
my ($drain, $counter);
$ua->websocket(
  '/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      finish => sub {
        $client += 2;
        Mojo::IOLoop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result .= $msg;
        $tx->finish if ++$counter == 2;
      }
    );
    $client = 1;
    $tx->send(
      'hi!' => sub {
        shift->send('there!');
        $drain
          += @{Mojo::IOLoop->stream($tx->connection)->subscribers('drain')};
      }
    );
  }
);
Mojo::IOLoop->start;
is $result, 'hi!there!', 'right result';
is $client, 3,           'finish event has been emitted';
is $drain,  1,           'no leaking subscribers';

# Server-side drain callback
$result = '';
$counter = $client = 0;
$ua->websocket(
  '/double_echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      finish => sub {
        $client += 2;
        Mojo::IOLoop->stop;
      }
    );
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result .= $msg;
        $tx->finish if ++$counter == 2;
      }
    );
    $client = 1;
    $tx->send('hi!');
  }
);
Mojo::IOLoop->start;
is $result, 'hi!hi!', 'right result';
is $client, 3,        'finish event has been emitted';

# Sending objects
$result = undef;
$ua->websocket(
  '/squish' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
        $tx->finish;
      }
    );
    $tx->send(b(' foo bar '));
  }
);
Mojo::IOLoop->start;
is $result, 'foo bar', 'right result';

# Dies
($finished, $code) = ();
my ($websocket, $msg);
$ua->websocket(
  '/dead' => sub {
    my ($ua, $tx) = @_;
    $finished  = $tx->is_finished;
    $websocket = $tx->is_websocket;
    $code      = $tx->res->code;
    $msg       = $tx->res->message;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $finished, 'transaction is finished';
ok !$websocket, 'no websocket';
is $code, 500, 'right status';
is $msg, 'Internal Server Error', 'right message';

# Forbidden
($websocket, $code, $msg) = ();
$ua->websocket(
  '/foo' => sub {
    my ($ua, $tx) = @_;
    $websocket = $tx->is_websocket;
    $code      = $tx->res->code;
    $msg       = $tx->res->message;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$websocket, 'no websocket';
is $code, 403,            'right status';
is $msg,  "i'm a teapot", 'right message';

# Dies in callback
$ua->websocket(
  '/deadcallback' => sub {
    pop->send('test1');
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;

# 16bit length
$result = undef;
$ua->websocket(
  '/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
        $tx->finish;
      }
    );
    $tx->send('hi!' x 100);
  }
);
Mojo::IOLoop->start;
is $result, 'hi!' x 100, 'right result';

# Timeout
my $log = '';
$msg = app->log->on(message => sub { $log .= pop });
$ua->websocket(
  '/timeout' => sub {
    pop->on(finish => sub { Mojo::IOLoop->stop });
  }
);
Mojo::IOLoop->start;
app->log->unsubscribe(message => $msg);
is $timeout, 'works!', 'finish event has been emitted';
like $log, qr/Inactivity timeout\./, 'right log message';

# Ping/pong
my $pong;
$ua->websocket(
  '/echo' => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      frame => sub {
        my ($tx, $frame) = @_;
        $pong = $frame->[5] if $frame->[4] == 10;
        Mojo::IOLoop->stop;
      }
    );
    $tx->send([1, 0, 0, 0, 9, 'test']);
  }
);
Mojo::IOLoop->start;
is $pong, 'test', 'received pong with payload';

# The "finish" event has been emitted on the server side too
is $server, 3, 'finish event has been emitted';

done_testing();
