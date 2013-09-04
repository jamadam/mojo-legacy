package Mojolicious::Command::generate::makefile;
use Mojo::Base 'Mojolicious::Command';

use Mojolicious;

has description => qq{Generate "Makefile.PL".\n};
has usage       => "usage: $0 generate makefile\n";

sub run { shift->render_to_rel_file('makefile', 'Makefile.PL') }

1;
__DATA__

@@ makefile
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.01',
  PREREQ_PM => {'Mojolicious' => '<%= $Mojolicious::VERSION %>'},
  test      => {TESTS => 't/*.t'}
);

__END__

=encoding utf8

=head1 NAME

Mojolicious::Command::generate::makefile - Makefile generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::makefile;

  my $makefile = Mojolicious::Command::generate::makefile->new;
  $makefile->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::makefile> generates C<Makefile.PL> files for
applications.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::makefile> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $makefile->description;
  $makefile       = $makefile->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $makefile->usage;
  $makefile = $makefile->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::makefile> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $makefile->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
