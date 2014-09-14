This is a modified version of mojo to run on Perl-5.8.7 environment.
The API is expected to be compatible with Mojolicious v5.32.

The code is experimental and might not work in all cases.

To test it, you should upgrade Test::More to latest version.
Please do the following command.

$ cpanm Test::More

Since mojo-legacy v5.03 some tests are skipped unless the environment variable
TEST_ORIGINAL_CASES set to true as following.

$ export TEST_ORIGINAL_CASES=1

You better check which tests are failing on this backport project
and make sure the use cases are not critical for you.

Since upstream mojo v4.95 it depends on Hash::Util::FieldHash which released for
Perl core since perl-5.9.4. If you use older version of perls, install
Hash::FieldHash as a substitute.

$ cpanm Hash::FieldHash

I recommend the installation though mojo-legacy works without the modules.
*::FieldHash looks to me like a cure of memory leaks so
if you're aiming at non-persistent environment like CGI, it may not a must.

To use Mojolicious::Plugin::PODRenderer, you need Pod::Simple 3.09 or higher
which first shipped with perl-5.11.2. If you use older perls, just do
the following command.

$ cpanm Pod::Simple

To use morbo with it, you must at least upgrade Socket module to 
version 1.81 or higher. Please do the following command.

$ cpanm Socket

To use websocket, you must at least install Digest::SHA.

$ cpanm Digest::SHA

If Compress::Raw::Zlib is not found, some tests may fail. However I guess
this works without the module in real world use case.
