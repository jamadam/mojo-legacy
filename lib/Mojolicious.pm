package Mojolicious;
use Mojo::Base 'Mojo';

# "Fry: Shut up and take my money!"
use Carp 'croak';
use Mojo::Exception;
use Mojo::Util 'decamelize';
use Mojolicious::Commands;
use Mojolicious::Controller;
use Mojolicious::Plugins;
use Mojolicious::Renderer;
use Mojolicious::Routes;
use Mojolicious::Sessions;
use Mojolicious::Static;
use Mojolicious::Types;
use Scalar::Util qw(blessed weaken);
use Time::HiRes 'gettimeofday';

has commands => sub {
  my $commands = Mojolicious::Commands->new(app => shift);
  weaken $commands->{app};
  return $commands;
};
has controller_class => 'Mojolicious::Controller';
has mode => sub { $ENV{MOJO_MODE} || $ENV{PLACK_ENV} || 'development' };
has moniker  => sub { decamelize ref shift };
has plugins  => sub { Mojolicious::Plugins->new };
has renderer => sub { Mojolicious::Renderer->new };
has routes   => sub { Mojolicious::Routes->new };
has secret   => sub {
  my $self = shift;

  # Warn developers about insecure default
  $self->log->debug('Your secret passphrase needs to be changed!!!');

  # Default to moniker
  return $self->moniker;
};
has sessions => sub { Mojolicious::Sessions->new };
has static   => sub { Mojolicious::Static->new };
has types    => sub { Mojolicious::Types->new };

our $CODENAME = 'Top Hat';
our $VERSION  = '4.30';

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)::(\w+)$/;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  # Call helper with fresh controller
  croak qq{Can't locate object method "$method" via package "$package"}
    unless my $helper = $self->renderer->helpers->{$method};
  return $self->controller_class->new(app => $self)->$helper(@_);
}

sub DESTROY { }

sub new {
  my $self = shift->SUPER::new(@_);

  my $home = $self->home;
  push @{$self->renderer->paths}, $home->rel_dir('templates');
  push @{$self->static->paths},   $home->rel_dir('public');

  # Default to application namespace
  my $r = $self->routes->namespaces([ref $self]);

  # Hide controller attributes/methods and "handler"
  $r->hide(qw(app continue cookie finish flash handler match on param));
  $r->hide(qw(redirect_to render render_exception render_later render_maybe));
  $r->hide(qw(render_not_found render_static rendered req res respond_to));
  $r->hide(qw(send session signed_cookie stash tx url_for write write_chunk));

  # Check if we have a log directory
  my $mode = $self->mode;
  $self->log->path($home->rel_file("log/$mode.log"))
    if -w $home->rel_file('log');

  $self->plugin($_)
    for qw(HeaderCondition DefaultHelpers TagHelpers EPLRenderer EPRenderer);

  # Exception handling should be first in chain
  $self->hook(around_dispatch => \&_exception);

  # Reduced log output outside of development mode
  $self->log->level('info') unless $mode eq 'development';

  # Run mode before startup
  if (my $sub = $self->can("${mode}_mode")) { $self->$sub(@_) }
  $self->startup(@_);

  return $self;
}

sub build_tx {
  my $self = shift;
  my $tx   = Mojo::Transaction::HTTP->new;
  $self->plugins->emit_hook(after_build_tx => $tx, $self);
  return $tx;
}

sub defaults { shift->_dict(defaults => @_) }

sub dispatch {
  my ($self, $c) = @_;

  # Prepare transaction
  my $tx = $c->tx;
  $tx->res->code(undef) if $tx->is_websocket;
  $self->sessions->load($c);
  my $plugins = $self->plugins->emit_hook(before_dispatch => $c);

  # Try to find a static file
  $self->static->dispatch($c) and $plugins->emit_hook(after_static => $c)
    unless $tx->res->code;

  # Start timer (ignore static files)
  my $stash = $c->stash;
  unless ($stash->{'mojo.static'} || $stash->{'mojo.started'}) {
    my $req    = $c->req;
    my $method = $req->method;
    my $path   = $req->url->path->to_abs_string;
    $self->log->debug(qq{$method "$path".});
    $stash->{'mojo.started'} = [gettimeofday];
  }

  # Routes
  $plugins->emit_hook(before_routes => $c);
  my $res = $tx->res;
  return if $res->code;
  if (my $code = ($tx->req->error)[1]) { $res->code($code) }
  elsif ($tx->is_websocket) { $res->code(426) }
  $c->render_not_found unless $self->routes->dispatch($c) || $tx->res->code;
}

sub handler {
  my ($self, $tx) = @_;

  # Embedded application
  my $stash = {};
  if (my $sub = $tx->can('stash')) { ($stash, $tx) = ($tx->$sub, $tx->tx) }
  $stash->{'mojo.secret'} = defined $stash->{'mojo.secret'} ? $stash->{'mojo.secret'} : $self->secret;

  # Build default controller
  my $defaults = $self->defaults;
  @{$stash}{keys %$defaults} = values %$defaults;
  my $c
    = $self->controller_class->new(app => $self, stash => $stash, tx => $tx);
  weaken $c->{$_} for qw(app tx);

  # Dispatcher has to be last in the chain
  ++$self->{dispatch}
    and $self->hook(around_action   => sub { $_[2]->($_[1]) })
    and $self->hook(around_dispatch => sub { $_[1]->app->dispatch($_[1]) })
    unless $self->{dispatch};

  # Process with chain
  $self->plugins->emit_chain(around_dispatch => $c);

  # Delayed response
  $self->log->debug('Nothing has been rendered, expecting delayed response.')
    unless $stash->{'mojo.rendered'} || $tx->is_writing;
}

sub helper {
  my ($self, $name, $cb) = @_;
  my $r = $self->renderer;
  $self->log->debug(qq{Helper "$name" already exists, replacing.})
    if exists $r->helpers->{$name};
  $r->add_helper($name => $cb);
}

sub hook { shift->plugins->on(@_) }

sub plugin {
  my $self = shift;
  $self->plugins->register_plugin(shift, $self, @_);
}

sub start { shift->commands->run(@_ ? @_ : @ARGV) }

sub startup { }

sub _exception {
  my ($next, $c) = @_;
  local $SIG{__DIE__}
    = sub { ref $_[0] ? CORE::die($_[0]) : Mojo::Exception->throw(@_) };
  $c->render_exception($@) unless eval { $next->(); 1 };
}

1;

=encoding utf8

=head1 NAME

Mojolicious - Real-time web framework

=head1 SYNOPSIS

  # Application
  package MyApp;
  use Mojo::Base 'Mojolicious';

  # Route
  sub startup {
    my $self = shift;
    $self->routes->get('/hello')->to('foo#hello');
  }

  # Controller
  package MyApp::Foo;
  use Mojo::Base 'Mojolicious::Controller';

  # Action
  sub hello {
    my $self = shift;
    $self->render(text => 'Hello World!');
  }

=head1 DESCRIPTION

Take a look at our excellent documentation in L<Mojolicious::Guides>!

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 commands

  my $commands = $app->commands;
  $app         = $app->commands(Mojolicious::Commands->new);

Command line interface for your application, defaults to a
L<Mojolicious::Commands> object.

  # Add another namespace to load commands from
  push @{$app->commands->namespaces}, 'MyApp::Command';

=head2 controller_class

  my $class = $app->controller_class;
  $app      = $app->controller_class('Mojolicious::Controller');

Class to be used for the default controller, defaults to
L<Mojolicious::Controller>.

=head2 mode

  my $mode = $app->mode;
  $app     = $app->mode('production');

The operating mode for your application, defaults to a value from the
MOJO_MODE and PLACK_ENV environment variables or C<development>. You can also
add per mode logic to your application by defining methods named
C<${mode}_mode> in the application class, which will be called right before
C<startup>.

  sub development_mode {
    my $self = shift;
    ...
  }

  sub production_mode {
    my $self = shift;
    ...
  }

Right before calling C<startup> and mode specific methods, L<Mojolicious>
will pick up the current mode, name the log file after it and raise the log
level from C<debug> to C<info> if it has a value other than C<development>.

=head2 moniker

  my $moniker = $app->moniker;
  $app        = $app->moniker('foo_bar');

Moniker of this application, often used as default filename for configuration
files and the like, defaults to decamelizing the application class with
L<Mojo::Util/"decamelize">.

=head2 plugins

  my $plugins = $app->plugins;
  $app        = $app->plugins(Mojolicious::Plugins->new);

The plugin manager, defaults to a L<Mojolicious::Plugins> object. See the
C<plugin> method below if you want to load a plugin.

  # Add another namespace to load plugins from
  push @{$app->plugins->namespaces}, 'MyApp::Plugin';

=head2 renderer

  my $renderer = $app->renderer;
  $app         = $app->renderer(Mojolicious::Renderer->new);

Used in your application to render content, defaults to a
L<Mojolicious::Renderer> object. The two main renderer plugins
L<Mojolicious::Plugin::EPRenderer> and L<Mojolicious::Plugin::EPLRenderer>
contain more information.

  # Add another "templates" directory
  push @{$app->renderer->paths}, '/home/sri/templates';

  # Add another class with templates in DATA section
  push @{$app->renderer->classes}, 'Mojolicious::Plugin::Fun';

=head2 routes

  my $routes = $app->routes;
  $app       = $app->routes(Mojolicious::Routes->new);

The router, defaults to a L<Mojolicious::Routes> object. You use this in your
startup method to define the url endpoints for your application.

  # Add routes
  my $r = $app->routes;
  $r->get('/foo/bar')->to('test#foo', title => 'Hello Mojo!');
  $r->post('/baz')->to('test#baz');

  # Add another namespace to load controllers from
  push @{$app->routes->namespaces}, 'MyApp::Controller';

=head2 secret

  my $secret = $app->secret;
  $app       = $app->secret('passw0rd');

A secret passphrase used for signed cookies and the like, defaults to the
C<moniker> of this application, which is not very secure, so you should change
it!!! As long as you are using the insecure default there will be debug
messages in the log file reminding you to change your passphrase.

=head2 sessions

  my $sessions = $app->sessions;
  $app         = $app->sessions(Mojolicious::Sessions->new);

Signed cookie based session manager, defaults to a L<Mojolicious::Sessions>
object. You can usually leave this alone, see
L<Mojolicious::Controller/"session"> for more information about working with
session data.

  # Change name of cookie used for all sessions
  $app->sessions->cookie_name('mysession');

=head2 static

  my $static = $app->static;
  $app       = $app->static(Mojolicious::Static->new);

For serving static files from your C<public> directories, defaults to a
L<Mojolicious::Static> object.

  # Add another "public" directory
  push @{$app->static->paths}, '/home/sri/public';

  # Add another class with static files in DATA section
  push @{$app->static->classes}, 'Mojolicious::Plugin::Fun';

=head2 types

  my $types = $app->types;
  $app      = $app->types(Mojolicious::Types->new);

Responsible for connecting file extensions with MIME types, defaults to a
L<Mojolicious::Types> object.

  # Add custom MIME type
  $app->types->type(twt => 'text/tweet');

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 new

  my $app = Mojolicious->new;

Construct a new L<Mojolicious> application, calling C<${mode}_mode> and
C<startup> in the process. Will automatically detect your home directory and
set up logging based on your current operating mode. Also sets up the
renderer, static file server, a default set of plugins and an
C<around_dispatch> hook with the default exception handling.

=head2 build_tx

  my $tx = $app->build_tx;

Transaction builder, defaults to building a L<Mojo::Transaction::HTTP>
object.

=head2 defaults

  my $hash = $app->defaults;
  my $foo  = $app->defaults('foo');
  $app     = $app->defaults({foo => 'bar'});
  $app     = $app->defaults(foo => 'bar');

Default values for L<Mojolicious::Controller/"stash">, assigned for every new
request.

  # Remove value
  my $foo = delete $app->defaults->{foo};

=head2 dispatch

  $app->dispatch(Mojolicious::Controller->new);

The heart of every Mojolicious application, calls the C<static> and C<routes>
dispatchers for every request and passes them a L<Mojolicious::Controller>
object.

=head2 handler

  $app->handler(Mojo::Transaction::HTTP->new);
  $app->handler(Mojolicious::Controller->new);

Sets up the default controller and calls process for every request.

=head2 helper

  $app->helper(foo => sub {...});

Add a new helper that will be available as a method of the controller object
and the application object, as well as a function in C<ep> templates.

  # Helper
  $app->helper(cache => sub { state $cache = {} });

  # Controller/Application
  $self->cache->{foo} = 'bar';
  my $result = $self->cache->{foo};

  # Template
  % cache->{foo} = 'bar';
  %= cache->{foo}

=head2 hook

  $app->hook(after_dispatch => sub {...});

Extend L<Mojolicious> with hooks, which allow code to be shared with all
requests indiscriminately.

  # Dispatchers will not run if there's already a response code defined
  $app->hook(before_dispatch => sub {
    my $c = shift;
    $c->render(text => 'Skipped static file server and router!')
      if $c->req->url->path->to_route =~ /do_not_dispatch/;
  });

These hooks are currently available and are emitted in the listed order:

=over 2

=item after_build_tx

Emitted right after the transaction is built and before the HTTP request gets
parsed.

  $app->hook(after_build_tx => sub {
    my ($tx, $app) = @_;
    ...
  });

This is a very powerful hook and should not be used lightly, it makes some
rather advanced features such as upload progress bars possible. Note that this
hook will not work for embedded applications. (Passed the transaction and
application object)

=item before_dispatch

Emitted right before the static file server and router start their work.

  $app->hook(before_dispatch => sub {
    my $c = shift;
    ...
  });

Very useful for rewriting incoming requests and other preprocessing tasks.
(Passed the default controller object)

=item after_static

Emitted after a static file response has been generated by the static file
server.

  $app->hook(after_static => sub {
    my $c = shift;
    ...
  });

Mostly used for post-processing static file responses. (Passed the default
controller object)

=item before_routes

Emitted after the static file server determined if a static file should be
served and before the router starts its work.

  $app->hook(before_routes => sub {
    my $c = shift;
    ...
  });

Mostly used for custom dispatchers and collecting metrics. (Passed the default
controller object)

=item around_action

Emitted right before an action gets invoked and wraps around it, so you have
to manually forward to the next hook if you want to continue the chain.
Default action dispatching is the last hook in the chain, yours will run
before it.

  $app->hook(around_action => sub {
    my ($next, $c, $action, $last) = @_;
    ...
    return $next->();
  });

This is a very powerful hook and should not be used lightly, it allows you for
example to pass additional arguments to actions or handle return values
differently. (Passed a callback leading to the next hook, the current
controller object, the action callback and a flag indicating if this action is
an endpoint)

=item after_render

Emitted after content has been generated by the renderer that is not partial.
Note that this hook can trigger out of order due to its dynamic nature, and
with embedded applications will only work for the application that is
rendering.

  $app->hook(after_render => sub {
    my ($c, $output, $format) = @_;
    ...
  });

Mostly used for post-processing dynamically generated content. (Passed the
current controller object, a reference to the content and the format)

=item after_dispatch

Emitted in reverse order after a response has been rendered. Note that this
hook can trigger out of order due to its dynamic nature, and with embedded
applications will only work for the application that is rendering.

  $app->hook(after_dispatch => sub {
    my $c = shift;
    ...
  });

Useful for rewriting outgoing responses and other post-processing tasks.
(Passed the current controller object)

=item around_dispatch

Emitted right before the C<before_dispatch> hook and wraps around the whole
dispatch process, so you have to manually forward to the next hook if you want
to continue the chain. Default exception handling with
L<Mojolicious::Controller/"render_exception"> is the first hook in the chain
and a call to C<dispatch> the last, yours will be in between.

  $app->hook(around_dispatch => sub {
    my ($next, $c) = @_;
    ...
    $next->();
    ...
  });

This is a very powerful hook and should not be used lightly, it allows you for
example to customize application wide exception handling, consider it the
sledgehammer in your toolbox. (Passed a callback leading to the next hook and
the default controller object)

=back

=head2 plugin

  $app->plugin('some_thing');
  $app->plugin('some_thing', foo => 23);
  $app->plugin('some_thing', {foo => 23});
  $app->plugin('SomeThing');
  $app->plugin('SomeThing', foo => 23);
  $app->plugin('SomeThing', {foo => 23});
  $app->plugin('MyApp::Plugin::SomeThing');
  $app->plugin('MyApp::Plugin::SomeThing', foo => 23);
  $app->plugin('MyApp::Plugin::SomeThing', {foo => 23});

Load a plugin, for a full list of example plugins included in the
L<Mojolicious> distribution see L<Mojolicious::Plugins/"PLUGINS">.

=head2 start

  $app->start;
  $app->start(@ARGV);

Start the command line interface for your application, for a full list of
commands available by default see L<Mojolicious::Commands/"COMMANDS">.

  # Always start daemon and ignore @ARGV
  $app->start('daemon', '-l', 'http://*:8080');

=head2 startup

  $app->startup;

This is your main hook into the application, it will be called at application
startup. Meant to be overloaded in a subclass.

  sub startup {
    my $self = shift;
    ...
  }

=head1 HELPERS

In addition to the attributes and methods above you can also call helpers on
L<Mojolicious> objects. This includes all helpers from
L<Mojolicious::Plugin::DefaultHelpers> and L<Mojolicious::Plugin::TagHelpers>.
Note that application helpers are always called with a new default controller
object, so they can't depend on or change controller state, which includes
request, response and stash.

  $app->log->debug($app->dumper({foo => 'bar'}));

=head1 BUNDLED FILES

The L<Mojolicious> distribution includes a few files with different licenses
that have been bundled for internal use.

=head2 Mojolicious Artwork

  Copyright (C) 2010-2013, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 jQuery

  Copyright (C) 2005, 2013 jQuery Foundation, Inc.

Licensed under the MIT License, L<http://creativecommons.org/licenses/MIT>.

=head2 prettify.js

  Copyright (C) 2006, 2013 Google Inc.

Licensed under the Apache License, Version 2.0
L<http://www.apache.org/licenses/LICENSE-2.0>.

=head1 CODE NAMES

Every major release of L<Mojolicious> has a code name, these are the ones that
have been used in the past.

4.0, C<Top Hat> (u1F3A9)

3.0, C<Rainbow> (u1F308)

2.0, C<Leaf Fluttering In Wind> (u1F343)

1.4, C<Smiling Face With Sunglasses> (u1F60E)

1.3, C<Tropical Drink> (u1F379)

1.1, C<Smiling Cat Face With Heart-Shaped Eyes> (u1F63B)

1.0, C<Snowflake> (u2744)

0.999930, C<Hot Beverage> (u2615)

0.999927, C<Comet> (u2604)

0.999920, C<Snowman> (u2603)

=head1 SPONSORS

Some of the work on this distribution has been sponsored by
L<The Perl Foundation|http://www.perlfoundation.org>, thank you!

=head1 PROJECT FOUNDER

Sebastian Riedel, C<sri@cpan.org>

=head1 CORE DEVELOPERS

Current members of the core team in alphabetical order:

=over 4

Abhijit Menon-Sen, C<ams@cpan.org>

Glen Hinkle, C<tempire@cpan.org>

Joel Berger, C<jberger@cpan.org>

Marcus Ramberg, C<mramberg@cpan.org>

=back

=head1 CREDITS

In alphabetical order:

=over 2

Adam Kennedy

Adriano Ferreira

Al Newkirk

Alex Salimon

Alexey Likhatskiy

Anatoly Sharifulin

Andre Vieth

Andreas Jaekel

Andreas Koenig

Andrew Fresh

Andrey Khozov

Andy Grundman

Aristotle Pagaltzis

Ashley Dev

Ask Bjoern Hansen

Audrey Tang

Ben van Staveren

Benjamin Erhart

Bernhard Graf

Breno G. de Oliveira

Brian Duggan

Burak Gursoy

Ch Lamprecht

Charlie Brady

Chas. J. Owens IV

Christian Hansen

chromatic

Curt Tilmes

Daniel Kimsey

Danijel Tasov

Danny Thomas

David Davis

David Webb

Diego Kuperman

Dmitriy Shalashov

Dmitry Konstantinov

Dominik Jarmulowicz

Dominique Dumont

Douglas Christopher Wilson

Eugene Toropov

Gisle Aas

Graham Barr

Henry Tang

Hideki Yamamura

Ilya Chesnokov

James Duncan

Jan Jona Javorsek

Jan Schmidt

Jaroslav Muhin

Jesse Vincent

Johannes Plunien

John Kingsley

Jonathan Yu

Josh Leder

Kazuhiro Shibuya

Kevin Old

Kitamura Akatsuki

Lars Balker Rasmussen

Leon Brocard

Magnus Holm

Maik Fischer

Mark Stosberg

Marty Tennison

Matthew Lineen

Maksym Komar

Maxim Vuets

Michael Harris

Mike Magowan

Mirko Westermeier

Mons Anderson

Moritz Lenz

Neil Watkiss

Nic Sandfield

Nils Diewald

Oleg Zhelo

Pascal Gaudette

Paul Evans

Paul Tomlin

Pavel Shaydo

Pedro Melo

Peter Edwards

Pierre-Yves Ritschard

Quentin Carbonneaux

Rafal Pocztarski

Randal Schwartz

Robert Hicks

Robin Lee

Roland Lammel

Ryan Jendoubi

Sascha Kiefer

Scott Wiersdorf

Sergey Zasenko

Simon Bertrang

Simone Tampieri

Shu Cho

Skye Shaw

Stanis Trendelenburg

Stephane Este-Gracias

Tatsuhiko Miyagawa

Terrence Brannon

Tomas Znamenacek

Ulrich Habel

Ulrich Kautz

Uwe Voelker

Viacheslav Tykhanovskyi

Victor Engmark

Viliam Pucik

Wes Cravens

Yaroslav Korshak

Yuki Kimoto

Zak B. Elep

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2013, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
