use 5.008007;

use strict;
use warnings;

use ExtUtils::MakeMaker;

# Pod::Simple 3.09 first shipped with Perl 5.11.2
# Time::Local 1.2 first shipped with Perl 5.13.9
WriteMakefile(
  NAME         => 'Mojolicious',
  VERSION_FROM => 'lib/Mojolicious.pm',
  ABSTRACT     => 'Real-time web framework',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    requires  => {perl => '5.008007'},
    resources => {
      license    => 'http://www.opensource.org/licenses/artistic-license-2.0',
      homepage   => 'http://mojolicio.us',
      bugtracker => 'https://github.com/kraih/mojo/issues',
      repository => 'https://github.com/kraih/mojo.git',
      x_IRC      => 'irc://irc.perl.org/#mojo'
    },
    no_index => {directory => ['t']}
  },
  PREREQ_PM    => {
    'Pod::Simple'             => '3.09',
    'Time::Local'             => '1.2',
    'Digest::SHA'             => '0',
    'Socket'                  => '1.81',
    'IO::Socket'              => '1.31',
    'Test::More'              => '0.98',
    !(eval 'use Hash::Util::FieldHash; 1')
                                      ? ('Hash::FieldHash' => '0') : (),
  },
  EXE_FILES => ['script/hypnotoad', 'script/mojo', 'script/morbo'],
  test => {TESTS => 't/*.t t/*/*.t'}
);
