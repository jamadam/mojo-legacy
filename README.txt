This is a modified version of mojo to run on Perl-5.8.7 environment.
The API is expected to be compatible with Mojolicious v3.41.

The code is experimental and might not work in all cases.

Notes;

Some tests may fail. You better test first and make sure the 
failing tests are not critical for you.

To test it, you should upgrade Test::More to latest version.
Please do the following command.

$ cpanm Test::More

To use morbo with it, you must at least upgrade Socket module to 
version 1.81 or higher. Please do the following command.

$ cpanm Socket
