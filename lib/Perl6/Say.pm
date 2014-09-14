package Perl6::Say;
use strict;
use warnings;
require 5.006_002;
our $VERSION = '0.16';
use IO::Handle;
use Scalar::Util 'openhandle';
use Carp;

sub say {
    my $currfh = select();
    my $handle;
    {
        no strict 'refs';
        $handle = openhandle($_[0]) ? shift : \*$currfh;
        use strict 'refs';
    }
    @_ = $_ unless @_;
    my $warning;
    local $SIG{__WARN__} = sub { $warning = join q{}, @_ };
    my $res = print {$handle} @_, "\n";
    return $res if $res;
    $warning =~ s/[ ]at[ ].*//xms;
    croak $warning;
}

# Handle direct calls...

no strict 'refs';
sub import { *{caller() . '::say'} = \&say; }
use strict 'refs';

# Handle OO calls:

*IO::Handle::say = \&say if ! defined &IO::Handle::say;

1;

#################### DOCUMENTATION #################### 

=head1 NAME

Perl6::Say - C<print()>, but no newline needed

=head1 SYNOPSIS

    # Perl 5 code...

    use Perl6::Say;

    say 'boo';             # same as:  print 'boo', "\n"

    say STDERR 'boo';      # same as:  print STDERR 'boo', "\n"

    STDERR->say('boo');    # same as:  print STDERR 'boo', \n"

    $fh->say('boo');       # same as:  print $fh 'boo', "\n";

    say();                 # same as:  print "$_\n";

    say undef;             # same as:  print "\n";

=head1 DESCRIPTION

=head2 Note for Users of Perl 5.10

You don't need this module.  The Perl 6 C<say> function is available in Perl
5.10 by saying C<use feature 'say';>.  Hence, this module is of interest only
to users of Perl 5.6 and 5.8.

If you have Perl 5.10 installed, see the F<510/> directory in this
distribution for some elementary examples of C<say> taken from C<perldoc
feature>.

=head2 General

Implements a close simulation of the C<say> function in Perl 6,
which acts like C<print> but automatically appends a newline.

Use it just like C<print> (except that it only supports the indirect object
syntax when the stream is a bareword). That is, assuming the relevant
filehandles are open for output, you can use any of these:

    say @data;
    say FH @data;
    FH->say(@data);
    *FH->say(@data);
    (\*FH)->say(@data);
    say $fh, @data;
    $fh->say(@data);

but not any of these:

    say {FH} @data;
    say {*FH} @data;
    say {\*FH} @data;
    say $fh @data;
    say {$fh} @data;

=head2 Additional Permitted Usages

As demonstrated in the test suite accompanying this distribution,
C<Perl6::Say::say()> can be used in all the following situations.

    $string = q{};
    open FH, ">", \$string;
    say FH qq{Hello World};            # print to a string
    close FH;                          # requires Perl 5.8.0 or later

    use FileHandle;
    $fh = FileHandle->new($file, 'w');
    if (defined $fh) {
        say $fh, qq{Hello World};
        $fh->close;
    }

    use IO::File;
    $fh = IO::File->new($file, 'w');
    if (defined $fh) {
        say $fh, qq{Hello World};
        $fh->close;
    }

    $string = q{};
    open FH, ">", \$string;             # requires Perl 5.8.0 or later
    select(FH);
    say qq{Hello World};
    close FH;

=head2 Interaction with Output Record Separator

In Perl 6, S<C<say @stuff>> is exactly equivalent to
S<C<Core::print @stuff, "\n">>.

That means that a call to C<say> appends any output record separator (ORS)
I<after> the added newline (though in Perl 6, the ORS is an attribute of
the filehandle being used, rather than a global C<$/> variable).

=head2 C<IO::Handle::say()>

IO::Handle version 1.27 or later (which, confusingly, is
found in IO distribution 1.23 and later) also implements a C<say>
method.   Perl6::Say provides its own C<say> method to IO::Handle
if C<IO::Handle::say> is not available.

=head2 Usage with Older Perls

As noted above, some aspects of C<Perl6::Say::say()> will not work with
versions of Perl earlier than 5.8.0.  This is not due to any problem with this
module; it is simply that Perl did not support printing to an in-memory file
(C<print \$string, "\n";>) prior to that point.  (Thanks to a CPAN testers
report from David Cantrell for identifying this limitation.)

=head1 WARNING

The syntax and semantics of Perl 6 is still being finalized
and consequently is at any time subject to change. That means the
same caveat applies to this module.

=head1 DEPENDENCIES

No dependencies other than on modules included with the Perl core as of
version 5.8.0.

Some of the files in the test suite accompanying this distribution use
non-core CPAN module IO::Capture::Stdout.  Tests calling IO::Capture::Stdout
methods are enclosed in C<SKIP> blocks and so should pose no obstacle to
installation of the distribution on systems lacking IO::Capture.  (However,
the maintainer strongly recommends IO::Capture for developers who write a lot
of test code.  So please consider installing it!)

=head1 AUTHOR and MAINTAINER

=head2 AUTHOR

Damian Conway (damian@conway.org).

=head2 MAINTAINER

Alexandr Ciornii (alexchorny@gmail.com)

=head1 ACKNOWLEDGMENTS

Thanks to Damian Conway for dreaming this up.  Thanks to David A Golden for a
close review of the documentation.  Thanks to CPAN tester Jost Krieger for
reporting an error in my SKIP block count in one test file.

=head1 BUGS AND IRRITATIONS

As far as we can determine, Perl 5 doesn't allow us to create a subroutine
that truly acts like C<print>. That is, one that can simultaneously be
used like so:

    say @data;

and like so:

    say {$fh} @data;

Comments, suggestions, and patches welcome.

=head1 COPYRIGHT

Copyright (c) 2004, Damian Conway. All Rights Reserved.
This module is free software. It may be used, redistributed
and/or modified under the same terms as Perl itself.

=cut
