This is a modified version of mojo to run on Perl-5.8.7 environment.
The API is expected to be compatible with Mojolicious v5.01.

The code is experimental and might not work in all cases.

Notes;

Some tests may fail. You better test first and make sure the 
failing tests are not critical for you.

Since mojo v4.95 it depends on Hash::Util::FieldHash which released for
Perl core since perl-5.9.4. If you use older version of Perl, install
following modules as a substitute.

$ cpanm parent
$ cpanm MRO::Compat
$ cpanm Hash::FieldHash

I recommend the installation though mojo-legacy works without the modules.
*::FieldHash looks to me like a cure of memory leaks so
if you're aiming at non-persistent environment like CGI, it may not a must.

To test it, you should upgrade Test::More to latest version.
Please do the following command.

$ cpanm Test::More

To use morbo with it, you must at least upgrade Socket module to 
version 1.81 or higher. Please do the following command.

$ cpanm Socket

To use websocket, you must at least install Digest::SHA.

$ cpanm Digest::SHA

If Compress::Raw::Zlib is not found, some tests may fail. However I guess
this works without the module in real world use case.
