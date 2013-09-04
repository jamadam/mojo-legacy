package Mojolicious::Command::daemon;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Server::Daemon;

has description => "Start application with HTTP and WebSocket server.\n";
has usage       => <<EOF;
usage: $0 daemon [OPTIONS]

These options are available:
  -b, --backlog <size>         Listen backlog size, defaults to SOMAXCONN.
  -c, --clients <number>       Maximum number of concurrent clients, defaults
                               to 1000.
  -g, --group <name>           Group name for process.
  -i, --inactivity <seconds>   Inactivity timeout, defaults to the value of
                               MOJO_INACTIVITY_TIMEOUT or 15.
  -l, --listen <location>      One or more locations you want to listen on,
                               defaults to the value of MOJO_LISTEN or
                               "http://*:3000".
  -p, --proxy                  Activate reverse proxy support, defaults to
                               the value of MOJO_REVERSE_PROXY.
  -r, --requests <number>      Maximum number of requests per keep-alive
                               connection, defaults to 25.
  -u, --user <name>            Username for process.
EOF

sub run {
  my ($self, @args) = @_;

  my $daemon = Mojo::Server::Daemon->new(app => $self->app);
  GetOptionsFromArray \@args,
    'b|backlog=i'    => sub { $daemon->backlog($_[1]) },
    'c|clients=i'    => sub { $daemon->max_clients($_[1]) },
    'g|group=s'      => sub { $daemon->group($_[1]) },
    'i|inactivity=i' => sub { $daemon->inactivity_timeout($_[1]) },
    'l|listen=s'     => \my @listen,
    'p|proxy' => sub { $ENV{MOJO_REVERSE_PROXY} = 1 },
    'r|requests=i' => sub { $daemon->max_requests($_[1]) },
    'u|user=s'     => sub { $daemon->user($_[1]) };

  $daemon->listen(\@listen) if @listen;
  $daemon->run;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::daemon - Daemon command

=head1 SYNOPSIS

  use Mojolicious::Command::daemon;

  my $daemon = Mojolicious::Command::daemon->new;
  $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::daemon> starts applications with
L<Mojo::Server::Daemon> backend.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::daemon> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $daemon->description;
  $daemon         = $daemon->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $daemon->usage;
  $daemon   = $daemon->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::daemon> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $daemon->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
