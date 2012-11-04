use 5.008007;

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious',
  VERSION_FROM => 'lib/Mojolicious.pm',
  ABSTRACT     => 'Real-time web framework',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',
  LICENSE      => 'artistic_2',
  PREREQ_PM    => {
    'Pod::Simple::HTML'       => '0',
    'Pod::Simple::Search'     => '0',
    'Digest::SHA'             => '0',
    'Socket'                  => '1.81',
    'Test::More'              => '0.98',
  },
  META_MERGE   => {
    requires  => {perl => '5.008007'},
    resources => {
      homepage    => 'http://mojolicio.us',
      license     => 'http://www.opensource.org/licenses/artistic-license-2.0',
      MailingList => 'http://groups.google.com/group/mojolicious',
      repository  => 'http://github.com/kraih/mojo',
      bugtracker  => 'http://github.com/kraih/mojo/issues'
    },
    no_index => {directory => ['t']}
  },
  EXE_FILES => ['script/hypnotoad', 'script/mojo', 'script/morbo'],
  test => {TESTS => 't/*.t t/*/*.t'}
);
