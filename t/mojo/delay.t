use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Basic functionality
my $delay = Mojo::IOLoop::Delay->new;
my @results;
for my $i (1, 1) {
  my $end = $delay->begin;
  Mojo::IOLoop->timer(0 => sub { push @results, $i; $end->() });
}
my $end  = $delay->begin;
my $end2 = $delay->begin;
is $end->(),  3, 'three remaining';
is $end2->(), 2, 'two remaining';
is_deeply [$delay->wait], [], 'no return values';
is_deeply \@results, [1, 1], 'right results';

# Arguments
$delay = Mojo::IOLoop::Delay->new;
my $result;
$delay->on(finish => sub { shift; $result = [@_] });
for my $i (1, 2) {
  my $end = $delay->begin(0);
  Mojo::IOLoop->timer(0 => sub { $end->($i) });
}
is_deeply [$delay->wait], [1, 2], 'right return values';
is_deeply $result, [1, 2], 'right results';

# Scalar context
$delay = Mojo::IOLoop::Delay->new;
for my $i (1, 2) {
  my $end = $delay->begin(0);
  Mojo::IOLoop->timer(0 => sub { $end->($i) });
}
is scalar $delay->wait, 1, 'right return value';

# Steps
my $finished;
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub {
    my $delay = shift;
    my $end   = $delay->begin;
    $delay->begin->(3, 2, 1);
    Mojo::IOLoop->timer(0 => sub { $end->(1, 2, 3) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $end = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $end->(undef, @numbers, 4) });
  },
  sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
);
is_deeply [$delay->wait], [2, 3, 2, 1, 4], 'right return values';
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [2, 3, 2, 1, 4], 'right results';

# End chain after first step
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(sub { $result = 'success' }, sub { $result = 'fail' });
is_deeply [$delay->wait], [], 'no return values';
is $finished, 1,         'finish event has been emitted once';
is $result,   'success', 'right result';

# End chain after third step
my $remaining;
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub { Mojo::IOLoop->timer(0 => shift->begin) },
  sub {
    $result    = 'fail';
    $remaining = shift->begin->();
  },
  sub { $result = 'success' },
  sub { $result = 'fail' }
);
is_deeply [$delay->wait], [], 'no return values';
is $remaining, 0,         'none remaining';
is $finished,  1,         'finish event has been emitted once';
is $result,    'success', 'right result';

# End chain after second step
@results = ();
$delay   = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { shift; push @results, [@_] });
$delay->steps(
  sub { shift->begin(0)->(23) },
  sub { shift; push @results, [@_] },
  sub { push @results, 'fail' }
);
is_deeply [$delay->wait], [23], 'right return values';
is_deeply \@results, [[23], [23]], 'right results';

# Finish steps with event
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->on(
  finish => sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
);
$delay->steps(
  sub {
    my $delay = shift;
    my $end   = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $end->(1, 2, 3) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $end = $delay->begin;
    Mojo::IOLoop->timer(0 => sub { $end->(undef, @numbers, 4) });
  }
);
is_deeply [$delay->wait], [2, 3, 4], 'right return values';
is_deeply $result, [2, 3, 4], 'right results';

# Nested delays
($finished, $result) = ();
$delay = Mojo::IOLoop->delay(
  sub {
    my $first = shift;
    $first->on(finish => sub { $finished++ });
    my $second = Mojo::IOLoop->delay($first->begin);
    Mojo::IOLoop->timer(0 => $second->begin);
    Mojo::IOLoop->timer(0 => $first->begin);
    my $end = $second->begin(0);
    Mojo::IOLoop->timer(0 => sub { $end->(1, 2, 3) });
  },
  sub {
    my ($first, @numbers) = @_;
    $result = \@numbers;
    my $end = $first->begin;
    $first->begin->(3, 2, 1);
    my $end2 = $first->begin(0);
    my $end3 = $first->begin(0);
    $end2->(4);
    $end3->(5, 6);
    $end->(1, 2, 3);
    $first->begin(0)->(23);
  },
  sub {
    my ($first, @numbers) = @_;
    push @$result, @numbers;
  }
);
is_deeply [$delay->wait], [2, 3, 2, 1, 4, 5, 6, 23], 'right return values';
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [1, 2, 3, 2, 3, 2, 1, 4, 5, 6, 23], 'right results';

done_testing();
