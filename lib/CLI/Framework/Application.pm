package CLI::Framework::Application;

use strict;
use warnings;
use warnings::register;
use Carp;

our $VERSION = 0.02;

use Getopt::Long::Descriptive;
use Class::Inspector;
use File::Spec;

use CLI::Framework::Exceptions;
use CLI::Framework::Command;

# Certain built-in commands are required:
use constant REQUIRED_BUILTINS              => qw( help );
# Certain built-in commands are required only in interactive mode:
use constant REQUIRED_BUILTINS_INTERACTIVE  => qw( menu );

#-------

sub new {
    my ($class, %args) = @_;

    my $interactive                 = $args{ interactive };              # boolean: interactive mode?

#FIXME-TODO:$builtins, $noninteractive_commands, etc. -- consider supporting
#passing these as constructor args to allow a CLIF app to be generated without
#overriding classes (could make a second constructor for this)

#    my $builtins                    = $args{ builtins };                 # built-in commands to include
#    my $noninteractive_commands     = $args{ noninteractive_commands };  # commands to disallow in interactive mode
#
#    $noninteractive_commands && do{
#        ref $noninteractive_commands eq 'ARRAY'
#            or croak "'noninteractive_commands' must be an ARRAY ref'" };
#
#    $builtins && do{
#        ref $builtins eq 'ARRAY'
#            or croak "'builtins' must be an ARRAY ref'" }; 

    my $app = {
        _commands                   => undef,           # (k,v)=(cmd pkg name,cmd obj) for all registered commands
        _default_command            => 'help',          # name of default command
        _current_command            => undef,           # name of current (or last) command to run
        _interactive                => $interactive,    # boolean: interactive state
        _session                    => undef,           # storage for global app data during running session
    };
    bless $app, $class;

    return $app;
}

###############################
#
#   COMMAND INTROSPECTION & REGISTRATION
#
###############################

sub is_valid_command {
    my ($app, $command_name) = @_;
    return 0 unless $command_name;
    my @valid = ( $app->valid_commands(), REQUIRED_BUILTINS );
    push @valid, REQUIRED_BUILTINS_INTERACTIVE if $app->is_interactive();
    return grep { $command_name eq $_ } ( @valid );
}

sub command_search_path {
    my ($app) = @_;

    # Start with the relative path to the application package file...
    my $app_rel_path = Class::Inspector->filename(ref $app);
    substr( $app_rel_path, -3, 3 ) = ''; # trim trailing '.pm'
    # ...transform to represent the expected path for command package files...
    my $command_search_path = File::Spec->catfile( $app_rel_path, 'Command' );

    return $command_search_path;
}

sub get_registered_command_names {
    my ($app) = @_;

    map { $_->name() } values %{ $app->{_commands} };
}

sub get_registered_command {
    my ($app, $command_name) = @_;

    return unless $command_name;

    my $command_obj = $app->{_commands}->{$command_name};
    return $command_obj;
}

sub register_command {
    my ($app, $cmd) = @_;

    return unless $cmd;

    if( ref $cmd && $app->is_valid_command($cmd->name()) ) {
        # Register command given object reference...
        return unless $cmd->isa( 'CLI::Framework::Command' );
        $app->{_commands}->{ $cmd->name() } = $cmd;
    }
    elsif( $app->is_valid_command( $cmd ) ) {
        # Attempt to manufacture and register user-defined command by the given name...

#FIXME:consider re-implementing this -- instead of trying to load user-defined
#command and then falling back to built-in, have command_search_path() return
#a LIST of paths to search sequentially, in order of preference.

        my $command_search_path = $app->command_search_path();
        my $cmd_obj = eval {
            CLI::Framework::Command->manufacture(
                command_search_path => $command_search_path,
                command             => $cmd
            )
        };
        my $user_def_err = $@;
        # ...if we could not manufacture user-defined command then attempt to
        # construct built-in command by the given name...
        unless( $cmd_obj && $cmd_obj->isa('CLI::Framework::Command') ) {
            my $class;
            eval {
                $cmd =~ s/^(\w)(.*)/\u$1\L$2/; # normalize command name
                $class = "CLI::Framework::Command::$cmd";
                eval "require $class"
                    or croak "failed to require() built-in command ",
                    "class '$class': $@";
                $cmd_obj = $class->new()
                    or croak "failed to instantiate built-in command ",
                    "class '$class'";
            };
        }
        unless( $cmd_obj ) {
            my $err = "Error: cannot create command '$cmd'";
            $err .= "; failed attempt to create user-defined command: $user_def_err" if $user_def_err;
            $err .= "; failed attempt to create built-in command: $@" if $@;
            croak $err;
        }
        $app->{_commands}->{ $cmd_obj->name() } = $cmd_obj;
        $cmd = $cmd_obj;
    }
    else {
        croak "Error: failed attempt to register invalid command";
    }
    # Metacommands should be app-aware...
    $cmd->set_app( $app ) if $cmd->isa( 'CLI::Framework::Command::Meta' );

    return $cmd;
}

###############################
#
#   PARSING & RUNNING COMMAND
#
###############################

sub get_default_command { $_[0]->{_default_command} }
sub set_default_command { $_[0]->{_default_command} = $_[1] }

sub get_current_command  { $_[0]->{_current_command} }
sub set_current_command { $_[0]->{_current_command} = $_[1] }

sub get_default_usage { $_[0]->{_default_usage} }
sub set_default_usage { $_[0]->{_default_usage} = $_[1] }

sub usage {
    my ($app, $command_name, @args) = @_;

    # Allow aliases in place of command name...
    $app->_canonicalize_cmd( $command_name );

    my $usage_text;
    if( $command_name && $app->is_valid_command($command_name) ) {
        # Get usage from Command object...
        my $cmd = $app->get_registered_command( $command_name )
            || $app->register_command( $command_name );
        $usage_text = $cmd->usage(@args);
    }
    else {
        # Get usage from Application object...
        $usage_text = $app->usage_text();
    }
    # Finally, fall back to default application usage message...
    $usage_text ||= $app->get_default_usage();
    return $usage_text;
}

#-------

sub session {
    my ($app, $k, $v) = @_;

    if( defined $k && defined $v ) {
        # Set session element...
        $app->{_session}->{$k} = $v;
    }
    elsif( defined $k ) {
        # Get session element...
        return $app->{_session}->{$k};
    }
    else {
        # Get entire session...
        return $app->{_session};
    }
}

#-------

sub _canonicalize_cmd {
    my ($self, $input) = @_;

    # Translate shorthand aliases for commands to full names...

    return unless $input;

    my $aliases = $self->command_alias();
    return unless $aliases;

    my $command_name = $aliases->{$input} || $input;
    $_[1] = $command_name;
}

#-------

sub _handle_global_app_options {
    my ($app) = @_;

    # Process the [app-opts] prefix of the command request...

    # preconditions:
    #   - tail of @ARGV has been parsed and removed, leaving only the
    #   [app-opts] portion ofthe request
    # postconditions:
    #   - application options have been parsed and any application-specific
    #     validation and initialization that is defined has been performed
    #   - invalid tokens after [app-opts] and before <cmd> are detected and
    #     handled

    # Parse [app-opts], consuming them from @ARGV...
    my ($app_options, $app_usage);
    eval { ($app_options, $app_usage) = describe_options( '%c %o ...', $app->option_spec() ) };
    if( my $e = Exception::Class->caught() ) {
        # (failed application options parsing)
        ref $e ? $e->rethrow :
            CLI::Framework::Exception::AppOptsParsingException->throw( error => $e );
    }
    $app->set_default_usage( $app_usage->text() );

    # Detect invalid tokens in the [app-opts] part of the request
    # (@ARGV should be empty unless such invalid tokens exist because <cmd> has
    # been removed and any valid options have been processed)...
    if( @ARGV ) {
        my $err = @ARGV > 1 ? 'Unrecognized options: ' : 'Unrecognized option: ';
        $err .= join(' ', @ARGV ) . "\n";
        CLI::Framework::Exception::AppOptsParsingException->throw( error => $err );
    }
    # --- VALIDATE APP OPTIONS ---
    eval { $app->validate_options($app_options) };
    if( my $e = Exception::Class->caught() ) { # (application failed options validation)
        ref $e ? $e->rethrow :
        CLI::Framework::Exception::AppOptsValidationException->throw( error => $e."\n".$app->usage() );
    }
    # --- INITIALIZE APP ---
    eval{ $app->init($app_options) };
    if( my $e = Exception::Class->caught() ) { # (application failed initialization)
        ref $e ? $e->rethrow() :
        CLI::Framework::Exception::AppInitException->throw( error => $e );
    }
}

sub _parse_request {
    my ($app, %param) = @_;

    # Parse options/arguments from a command request and set the name of the
    # current command...

    # If in non-interactive mode, perform validation and initialization of
    # the application.  Application validation/initialization is NOT done
    # here if we are in interactive mode because it should only be done once
    # for the application, not every time a command is run.

    #
    # ARGV_Format
    #
    # non-interactive case:     @ARGV:      [app-opts]  <cmd> [cmd-opts] [cmd-args]
    # interactive case:         @ARGV:                  <cmd> [cmd-opts] [cmd-args]
    #

    my $initialize_app = $param{initialize};

    # Parse options/arguments for the application and the command from @ARGV...
    my ($command_name, @command_opts_and_args);
    for my $i ( 0..$#ARGV ) {
        # Find first valid command name in @ARGV...
        $app->_canonicalize_cmd( $ARGV[$i] );
        if( $app->is_valid_command($ARGV[$i]) ) {
            # Extract and store '<cmd> [cmd-opts] [cmd-args]', leaving
            # preceding contents (potentially '[app-opts]') in @ARGV...
            ($command_name, @command_opts_and_args) = @ARGV[$i..@ARGV-1];
            splice @ARGV, $i;
            last;
        }
    }
    unless( defined $command_name ) {
        # If no valid command, fall back to default, ignoring any args...
        $command_name = $app->get_default_command();
        @command_opts_and_args = ();

        # If no valid command then any non-option tokens are invalid args...
        my @invalid_args = grep { substr($_, 0, 1) ne '-' } @ARGV;
        if( @invalid_args ) {
            my $err = @invalid_args > 1 ? 'Invalid arguments: ' : 'Invalid argument: ';
            $err .= join(' ', @invalid_args );
            CLI::Framework::Exception::AppArgumentException->throw( error => $err );
        }
    }
    # Set internal current command name...
    $app->set_current_command( $command_name );

    # If requested, parse [app-opts] and initialize application...
    # (this is optional because, in interactive mode, it should not be done
    # for every request)
    $app->_handle_global_app_options() if $initialize_app;

    # Leave '[cmd-opts] [cmd-args]' in @ARGV...
    @ARGV = @command_opts_and_args;

    return 1;
}

sub run {
    my ($app) = @_;

    # Auto-instantiate if necessary...
    unless( ref $app ) {
        my $class = $app;
        $app = $class->new();
    }
    my $do_init = not $app->is_interactive(); # (skip init in interactive mode)

    # Parse request; perform initialization...
    eval { $app->_parse_request( initialize => $do_init ) };
    if( my $e = CLI::Framework::Exception->caught() ) {
        $app->render( $e->error() );
        return;
    }
    elsif( $e = Exception::Class->caught() ) {
        ref $e ? $e->rethrow : die $e;
    }
    my $command_name = $app->get_current_command();

    # Lazy registration of commands...
    my $command = $app->get_registered_command( $command_name )
        || $app->register_command( $command_name );

    # Parse command options and auto-generate minimal usage message...
    my ($cmd_options, $cmd_usage);
    my $format = "$command_name %o ...";                    # Getopt::Long::Descriptive format string
    $format = '%c '.$format unless $app->is_interactive();  # (%c is command name -- irrelevant in interactive mode)
    # (configure Getop::Long to stop consuming tokens when first non-option is
    # encountered on input stream)
    my $getopt_configuration = { getopt_conf => [qw(require_order)] };
    eval { ($cmd_options, $cmd_usage) =
        describe_options( $format, $command->option_spec(), $getopt_configuration ) };
    if( my $e = Exception::Class->caught() ) {
        # (failed command options parsing)
        ref $e ? $e->rethrow :
        CLI::Framework::Exception::CmdOptsParsingException->throw( error => $e );
    }
    $command->set_default_usage( $cmd_usage->text() );

    # "metacommands" need to be app-aware...
    $command->set_app( $app ) if $command->isa( "CLI::Framework::Command::Meta" );

    # Share session data with command...
    # (init() method may have populated global session data for use by all commands)
    $command->set_session( $app->session() );

    # --- APP HOOK: COMMAND PRE-DISPATCH ---
    $app->pre_dispatch( $command );

    # --- RUN COMMAND ---
    my $output;
    eval { $output = $command->dispatch( $cmd_options, @ARGV ) };
    if( my $e = Exception::Class->caught() ) {
        if( ref $e ) { $app->render( $e->error() ) }
        else{ $app->render( $e ) }
        return;
    }
    # Display output of command, if any...
    $app->render( $output )
        if defined $output;
}

###############################
#
#   INTERACTIVITY
#
###############################

sub is_interactive { $_[0]->{_interactive} }

sub set_interactivity_mode { $_[0]->{_interactive} = $_[1] }

sub is_interactive_command {
    my ($app, $command_name) = @_;

    my @noninteractive_commands = $app->noninteractive_commands();

    # Command must be valid...
    return 0 unless $app->is_valid_command( $command_name );

    # Command must NOT be non-interactive...
    return 1 unless grep { $command_name eq $_ } @noninteractive_commands;

    return 0;
}

sub get_interactive_commands {
    my ($app) = @_;

    my @valid_commands = $app->valid_commands();

    # All valid commands are enabled in non-interactive mode...
    return @valid_commands unless( $app->is_interactive() );

    # ...otherwise, in interactive mode, include only interactive commands...
    my @command_names;
    for my $c ( @valid_commands ) {
        push @command_names, $c if $app->is_interactive_command( $c );
    }
    return @command_names;
}

sub run_interactive {
    my ($app, %param) = @_;

    # Auto-instantiate if necessary...
    unless( ref $app ) {
        my $class = $app;
        $app = $class->new();
    }
    $app->set_interactivity_mode(1);

    # If default command is non-interactive, reset it, remembering default...
    my $orig_default_command = $app->get_default_command();
    if( grep { $orig_default_command eq $_ } $app->noninteractive_commands() ) {
        $app->set_default_command( 'help' );
    }
    # If initialization indicated, run init() and handle existing input...
    eval { $app->_parse_request( initialize => $param{initialize} )
        if $param{initialize}
    };
    if( my $e = CLI::Framework::Exception->caught() ) {
        $app->render( $e->error() );
        return;
    }
    # Find how many prompts to display in sequence between displaying menu...
    my $menu_cmd = $app->get_registered_command('menu')
        || $app->register_command('menu')
        || croak "Error: unable to register 'menu' command (required for interactive mode)";
    $menu_cmd->isa( 'CLI::Framework::Command::Menu' )
        or croak "Menu command must be a subtype of CLI::Framework::Command::Menu";

    my $invalid_request_threshold = $param{invalid_request_threshold}
        || $menu_cmd->line_count(); # num empty prompts b4 re-displaying menu

    $app->render( $menu_cmd->run() );
    my ($cmd_succeeded, $invalid_request_count, $done) = (0,0,0);
    until( $done ) {
        if( $invalid_request_count >= $invalid_request_threshold ) {
            # Reached threshold for invalid cmd requests => re-display menu...
            $invalid_request_count = 0;
            $app->render( $menu_cmd->run() );
        }
        elsif( $cmd_succeeded ) {
            # Last command request was successful => re-display menu...
            $app->render( $menu_cmd->run() );
            $cmd_succeeded = $invalid_request_count = 0;
        }
        # Read a command request...
        $app->read_cmd();

        if( @ARGV ) {
            # Recognize quit requests...
            if( $app->is_quit_signal($ARGV[0]) ) {
                $done = 1;
                undef @ARGV;
                last;
            }
            $app->_canonicalize_cmd($ARGV[0]); # translate cmd aliases
            if( $app->is_valid_command( $ARGV[0] ) &&
                $app->is_interactive_command( $ARGV[0] ) ) {

                eval { $app->run() };
                if( my $e = CLI::Framework::Exception->caught() ) {
                    warn "[from command '", $app->get_current_command(), "'] ", $e->error
                        if warnings::enabled();
                    $cmd_succeeded = 0;
                }
                elsif( $e = Exception::Class->caught() ) {
                    ref $e ? $e->rethrow : warn $e if warnings::enabled();
                }
                else { $cmd_succeeded = 1 }
            }
            else {
                $app->render( 'unrecognized command request: ' . join(' ',@ARGV) . "\n");
                $invalid_request_count++
            }
        }
        else { $invalid_request_count++ }
    }
    # Restore original default command...
    $app->set_default_command( $orig_default_command );
}

sub read_cmd {
    my ($app) = @_;

    require Text::ParseWords;

    # Retreive or cache Term::ReadLine object (this is necessary to save
    # command-line history in persistent object)...
    my $term = $app->{_readline};
    unless( $term ) {
        require Term::ReadLine;
        $term = Term::ReadLine->new('CLIF Application');
        select $term->OUT;
        $app->{_readline} = $term;
    }
    # Prompt for the name of a command and read input from STDIN.
    # Store, in @ARGV, the individual tokens that are read.
    my $command_request = $term->readline('> ');
    if( defined $command_request ) {
        @ARGV = Text::ParseWords::shellwords( $command_request ); # prepare command for usual parsing
        $term->addhistory( $command_request );
    }
    return 1;
}

sub render {
    my ($app, $output) = @_;

#FIXME: consider built-in features to help simplify associating templates
#with commands (each command would probably have its own template for its
#output)
    print $output;
}

sub is_quit_signal {
    my ($app, $command_name) = @_;

    my @quit_signals = $app->quit_signals();
    return grep { $command_name eq  $_ } @quit_signals;
}

###############################
#
#   APPLICATION SUBCLASS HOOKS
#
###############################

#FIXME:application name -- is this useful enough to include?
#sub name { }

#FIXME: consider making default implementation of init():
#       $app->set_current_command('help') if $opts->{help}
sub init { 1 }

sub pre_dispatch { }

sub usage_text { }

sub option_spec { ( ) }

sub validate_options { 1 }

sub command_alias { ( ) }

sub valid_commands { qw( help console menu list dump tree app ) }

sub noninteractive_commands { qw( console menu ) }

sub quit_signals { qw( q quit exit ) }

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Application - Build standardized, flexible, testable command-line applications

=head1 SYNOPSIS

    #---- CLIF Application class -- lib/My/Journal.pm
    package My::Journal;
    use base qw( CLI::Framework::Application );

    sub init {
        my ($self, $opts) = @_;
        # ...connect to DB, getting DB handle $dbh...
        $self->session('dbh' => $dbh); # (store $dbh in shared session slot)
    }
    1;

    #---- CLIF Command class -- lib/My/Journal/Command/Entry.pm
    package My::Journal::Command::Entry;
    use base qw( CLI::Framework::Command );
    
    sub run { ... }
    1;

    #---- CLIF (sub)Command Class -- can be defined inline in master command
    # package file for My::Journal::Command::Entry or in dedicated package
    # file lib/My/Journal/Command/Entry/Add.pm
    package My::Journal::Command::Entry::Add;
    use base qw( My::Journal::Command::Entry );

    sub run { ... }
    1;

    #---- ...<more similar class definitions for 'entry' subcommands>...

    #---- CLIF Command Class -- lib/My/Journal/Command/Publish.pm
    package My::Journal::Command::Publish;
    use base qw( CLI::Framework::Command );

    sub run { ... }
    1;

    #---- CLIF executable script: journal
    use My::Journal;
    My::Journal->run();

    #---- Command-line
    $ journal entry add 'today I wrote some POD'
    $ journal entry search --regex='perl'
    $ journal entry print 1 2 3
    $ journal publish --format=pdf --template=my-journal --out=~/notes/journal-20090314.txt

=head1 OVERVIEW

CLI::Framework (nickname "CLIF") provides a framework and conceptual pattern
for building full-featured command line applications.  It intends to make this
process easy and consistent.  It assumes responsibility for common details
that are application-independent, making it possible for new CLI applications
to be built without concern for these recurring aspects (which are otherwise
very tedious to implement).

For instance, the Journal application example in the L<SYNOPSIS|/SYNOPSIS>
is an example of a CLIF application for a personal journal.  The application
has both commands and subcommands.  Since the application class, My::Journal, is a
subclass of CLI::Framework::Application, the Journal application is free to
focus on implementation of its individual commands with minimum concern for
the many details involved in building an interface around those commands.  The
application is composed of concise, understandable code in packages that are
easy to test and maintain.  This methodology for building CLI apps can be
adopted as a standardized convention.

=head1 UNDERSTANDING CLIF: RECOMMENDATIONS

"Quickstart" and "Tutorial" guides are currently being prepared for the next
CLIF release.  However, this early version has the necessary content.
See especially L<CLI::Framework::Application> and L<CLI::Framework::Command>.
Also, there are example CLIF applications (demonstrating both simple and
advanced usage) included with the tests for this distribution.

=head1 MOTIVATION

There are a few other distributions on CPAN intended to simplify building
modular command line applications.  None of them met my requirements, which
are documented in L<DESIGN GOALS|\DESIGN GOALS>.

=head1 DESIGN GOALS/FEATURES

CLIF was designed to offer the following features...

=over

=item *

A clear conceptual pattern for creating CLI apps

=item *

Guiding documentation and examples

=item *

Convenience for simple cases, flexibility for complex cases

=item *

Support for both non-interactive and interactive modes (without extra work)

=item *

Separation of Concerns to decouple data model, control flow, and presentation

=item *

The possibility to share some components with MVC web apps

=item *

Commands that can be shared between apps (and uploaded to CPAN)

=item *

Validation of app options

=item *

Validation of per-command options and arguments

=item *

A model that encourages easily-testable applications

=item *

Flexible way to provide usage/help information for the application as a whole
and for individual commands

=item *

Support for subcommands that work just like commands

=item *

Support for recursively-defined subcommands (sub-sub-...commands to any level
of depth)

=item *

Support aliases for commands and subcommands

=item *

Allow subcommand package declarations to be defined inline in the same file as
their parent command or in separate files per usual Perl package file
hierarchy organization

=item *

Support the concept of a default command for the application

=back

=head1 CONCEPTS AND DEFINITIONS

=over

=item *

Application Script - The wrapper program that invokes the CLIF Application's
L<run|/run> method.

=item *

Valid Commands - The set of command names available to a running
CLIF-derived application.  This set contains the client-programmer-defined
commands and all registered built-in commands.

=item *

Metacommand - An application-aware command.  Metacommands are subclasses of
C<CLI::Framework::Command::Meta>.  They are identical to regular commands except
they hold a reference to the application within which they are running.  This
means they are able to "know about" and affect the application.  For example,
the built-in command 'Menu' is a Metacommand because it needs to produce a
list of the other commands in its application.

In general, your commands should be designed to operate independently of the
application, so they should simply inherit from C<CLI::Framework::Command>.
The Metacommand facility is useful but should only be used when necessary.

=item *

Non-interactive Command - In interactive mode, some commands need to be disabled.  For
instance, the built-in 'console' command should not be presented as a menu
option in interactive mode because it is already running.  You can designate
which commands are non-interactive by overriding the
C<noninteractive_commands> method.

=item *

Options hash - A Perl hash that is created by the framework based on user
input.  The hash keys are option names (from among the valid options defined
in an application's L<option_spec|/option_spec> method) and the values are
the scalars passed by the user via the command line.

=item *

Command names - The official name of each CLIF command is defined by the value
returned by its C<name> method.  Names are handled case-sensitively throughout
CLIF.

=item *

Registration of commands - The CLIF Commands within an application must be
registered with the application.  The names of commands registered within an
application must be unique.

=back

=head1 APPLICATION RUN SEQUENCE

When a command of the form:

    $ app [app-opts] <cmd> [cmd-opts] { <cmd> [cmd-opts] {...} } [cmd-args]

...causes your application script, <app>, to invoke the C< run() >> method in
your application class, CLI::Framework::Application performs the following
actions:

=over

=item 1

Parse the application options C<< [app-opts] >>, command name C<< <cmd> >>,
command options C<< [cmd-opts] >>, and the remaining part of the command line
(which includes command arguments C<< [cmd-args] >> for the last command and
may include multiple subcommands; everything between the C<< { ... } >>
represents recursive subcommand processing).

If the command request is not well-formed, it is replaced with the default
command and any arguments present are ignored.  Generally, the default command
prints a help or usage message.

=item 2

Validate application options.

=item 3

Initialize application.

=item 4

Invoke command pre-run hook.

=item 5

Dispatch command.

=back

These steps are explained in more detail below...

=head2 Validation of application options

Your application class can optionally define the
L<validate_options|/validate_options> method.

If your application class does not override this method, validation is
effectively skipped -- any received options are considered to be valid.

=head2 Application initialization

Your application class can optionally override the L<init|/init> method.
This is an optional hook that can be used to perform any application-wide
initialization that needs to be done independent of individual commands.  For
example, your application may use the L<init|/init> method to connect to a
database and store a connection handle which is needed by most of the commands
in the application.

=head2 Command pre-run

Your application class can optionally have a L<pre_dispatch|/pre_dispatch>
method that is called with one parameter: the Command object that is about to
be dispatched.  This hook is called in void context.  Its purpose is to allow
applications to do whatever may be necessary to prepare for running the
command.  For example, the L<pre_dispatch|/pre_dispatch> method could set a
database handle in all command objects so that every command has access to the
database.  As another example, a log entry could be inserted as a record of
the command being run.

=head2 Dispatching a command

CLIF uses the L<dispatch|CLI::Framework::Command/dispatch> method to actually
dispatch a specific command.  That method is responsible for running the
command or delegating responsibility to a subcommand, if applicable.

See L<dispatch|CLI::Framework::Command/dispatch> for the specifics.

=head1 INTERACTIVITY

After building your CLIF-based application, in addition to basic
non-interactive functionality, you will instantly benefit from the ability to
(optionally) run your application in interactive mode.  A readline-enabled
application command console with an event loop, a command menu, and built-in
debugging commands is provided by default.

=head1 BUILT-IN COMMANDS INCLUDED IN THIS DISTRIBUTION

This distribution comes with some default built-in commands, and more
CLIF built-ins can be installed as they become available on CPAN.

Use of the built-ins is optional in most cases, but certain features require
specific built-in commands (e.g. the Help command is a fundamental feature and
the Menu command is required in interactive mode).  You can override any of
the built-ins.

The existing built-ins and their corresponding packages are as follows (for
more information on each, see the respective documentation):

=over

=item help

CLI::Framework::Comand::Help

NOTE: This command is registered automatically.  It can be overridden, but a
'help' command is mandatory.

=item list

CLI::Framework::Comand::List

=item dump

CLI::Framework::Comand::Dump

=item tree

CLI::Framework::Comand::Tree

=item console

CLI::Framework::Comand::Console

=item menu

CLI::Framework::Comand::Menu

NOTE: This command may be overridden, but the overriding command class MUST
inherit from this one, conforming to its interface.

=back

=head1 METHODS: OBJECT CONSTRUCTION

=head2 new

    My::Application->new( interactive => 1 );

Construct a new CLIF Application object.

=head1 METHODS: COMMAND INTROSPECTION & REGISTRATION

=head2 is_valid_command

    $app->is_valid_command( 'foo' );

Returns a true value if the specified command name is valid within the running
application.  Returns a false value otherwise.

=head2 command_search_path

    $path = $app->command_search_path();

This method returns the path that should be searched for command class package
files.  If not overridden, the directory will be named 'Command' and will be
under a sibling directory of your application class package named after the
application class (e.g. if your application class is lib/My/App.pm, the
default command search path will be lib/My/App/Command/).

=head2 get_registered_command_names

    @registered_commands = $app->get_registered_command_names();

Returns a list of the names of all registered commands.

=head2 get_registered_command

    my $command_object = $app->get_registered_command( $command_name );

Given the name of a registered command, returns the corresponding
CLI::Framework::Command object.  If the command is not registered, returns
undef.

=head2 register_command

    # Register by name...
    $command_object = $app->register_command( $command_name );
    # ...or register by object reference...
    $command_object = CLI::Framework::Command->new( ... );
    $app->register_command( $command_object );

Register a command to be recognized by the application.  This method accepts
either the name of a command or a reference to a CLI::Framework::Command
object.

If a CLI::Framework::Command object is given and it is one of the commands
specified to be valid, the command is registered and returned.

For registration by command name, an attempt is made to find the command with
the given name.  Preference is given to user-defined commands over built-ins,
allowing user-defined versions to override built-in commands of the same name.
If a user-defined command cannot be created, an attempt is made to register a
built-in command by the given name.  If neither attempt succeeds, an exception
is thrown.

NOTE that registration of a command with the same name as one that is already
registered will cause the existing command to be replaced by the new one.  The
commands registered within an application must be unique.

=head1 METHODS: PARSING & RUNNING COMMANDS

=head2 get_default_command

    my $default = $app->get_default_command();

Retrieve the name of the default command.

=head2 set_default_command

    $app->set_default_command( 'fly' );

Given a command name, makes it the default command for the application.

=head2 get_current_command

    $status = $app->run();
    print 'The command named: ', $app->get_current_command(), ' has completed';

Returns the name of the current command (or the one that was most recently
run).

=head2 set_current_command

    $app->set_current_command( 'roll' );

Given a command name, forward execution to that command.  This might be useful
(for example) in an application's init() method to redirect to another command.

=head2 get_default_usage

    $usage_msg = $app->get_default_usage();

Get the default usage message for the application.  This message is used as a
last resort when usage information is unavailable by other means.  See
F<usage|/usage>.

=head2 set_default_usage

    $app->set_default_usage( $usage_message );

Set the default usage message for the application.  This message is used as a
last resort when usage information is unavailable by other means.  See
F<usage|/usage>.

=head2 usage

    # Application usage...
    print $app->usage();

    # Command-specific usage...
    print $app->usage( $command_name, @subcommand_chain );

Returns a usage message for the application or a specific command.

If a command name is given, returns a usage message string for that command.
If no command name is given or if no usage message is defined for the
specified command, returns a general usage message for the application.

Logically, here is how the usage message is produced:

=over

=item *

If a valid command name is given, attempt to get usage message from the
command; if no usage message is defined for the command, use the application
usage message instead.

=item *

If the application object has defined L<usage_text|/usage_text>, use its
return value as the usage message.

=item *

Finally, fall back to using the default usage message returned by
L<get_default_usage|/get_default_usage>.

=back

=head2 session

    # Get the entire session hash...
    $app->session();
    
    # Get the value of an item from the session...
    $app->session( 'key' );

    # Set the value of an item in the session...
    $app->session( 'key' => $value );

CLIF Applications may have a need for global data shared between all
components (individual CLIF Commands and the Application object itself).
C<session> provides a way for this data to be stored, retreived, and shared
between components.

=head2 run

    MyApp->run();
    # ...or...
    $app->run();

This method controls the request processing and dispatching of a single
command.  It takes its input from @ARGV (which may be populated by a
script running non-interactively on the command line) and dispatches the
indicated command, capturing its return value.  The command's return value
should represent the output produced by the command.  It is a scalar that is
passed to L<render|render> for final display.

=head1 METHODS: INTERACTIVITY

=head2 is_interactive

    if( $app->is_interactive() ) {
        print "running interactively";
    }

Accessor for the interactivity state of the application.

=head2 set_interactivity_mode

    $app->set_interactivity_mode(1);

Set the interactivity state of the application.  One parameter is accepted: a
true or false value for whether the application state should be interactive or
non-interactive, respectively.

=head2 is_interactive_command

    $help_command_is_interactive = $app->is_interactive_command( 'help' );

Determine if the command with the specified name is an interactive command
(i.e. whether or not the command is enabled in interactive mode).  Returns a
true value if it is; returns a false value otherwise.

=head2 get_interactive_commands

    my @interactive_commands = $app->get_interactive_commands();

Return a list of all commands that are to be shown in interactive mode
("interactive commands").

=head2 run_interactive

    MyApp->run_interactive();
    # ...or...
    $app->run_interactive();

Wrap the L<run|/run> method to create an event processing loop to prompt for
and run commands in sequence.  It uses the built-in command C<menu> (or a
user-defined menu-command, if one exists) to display available command
selections.

Within this loop, valid input is the same as in non-interactive mode except
that application options are not accepted (any application options should be
handled before the interactive B<command> loop is entered -- see the
C<initialize> parameter below).

The following parameters are recognized:

C<initialize>: cause any options that are present in C<@ARGV> to be
procesed.  One example of how this may be used: allow C<run_interactive()> to
process/validate application options and to run L<init|init> prior to
entering the interactive event loop to recognize commands.

C<invalid_request_threshold>: the number of unrecognized command requests the
user can enter before the menu is re-displayed.

=head2 read_cmd

    $app->read_cmd();

This method is responsible for retreiving a command request and placing the
tokens composing the request into C<@ARGV>.  It is called in void context.

The default implementation uses Term::ReadLine to prompt the user and read a
command request, supporting command history.

Subclasses are encouraged to override this method if a different means of
accepting user input is needed.  This makes it possible to read command
selections without assuming that the console is being used for I/O.

=head2 render

    $app->render( $output );

This method is responsible for presentation of the result from a command.
The default implementation simply attempts to print the C<$output> scalar,
assuming that it is a string.

Subclasses are encouraged to override this method to provide more
sophisticated behavior such as processing the <$output> scalar through a
templating system, if desired.

=head2 is_quit_signal

    until( $app->is_quit_signal( $string_read_from_user ) ) { ... }

Given a string, return a true value if it is a quit signal (indicating that
the application should exit) and a false value otherwise.
L<quit_signals|/quit_signals> is an application subclass hook that
defines what strings signify that the interactive session should exit.

=head1 METHODS: SUBCLASS HOOKS

There are several hooks that allow CLIF applications to influence the command
execution process.  This makes customizing the critical aspects of an
application as easy as overriding methods.  Subclasses can (and must, in some
cases, as noted) override the following methods:

=head2 init

Overriding this hook is optional.  It is called as follows:

    $app->init( $app_options );

C<$app_options> is a hash of pre-validated application options received and
parsed from the command line.  The option hash has already been checked
against the options defined to be accepted by the application in
L<option_spec|/option_spec>.

This method allows CLIF applications to perform any common
global initialization tasks that are necessary regardless of which command is
to be run.  Some examples of this include connecting to a database and storing
a connection handle in the shared L<session|/session> slot for use by
individual commands, setting up a logging facility that can be used by each
command, or initializing settings from a configuration file.

=head2 pre_dispatch

Overriding this hook is optional.  It is called as follows:

    $app->pre_dispatch( $command_object );

This method allows applications to perform actions after each command object
has been prepared for dispatch but before the command dispatch actually takes
place.

=head2 option_spec

Overriding this hook is optional.  An example of its definition is as
follows:

    sub option_spec {
        (
            [ 'verbose|v'   => 'be verbose'         ],
            [ 'logfile=s'   => 'path to log file'   ],
        )
    }

This method should return an option specification as expected by the
Getopt::Long::Descriptive function C<describe_options>.  The option
specification defines what options are allowed and recognized by the
application.

=head2 validate_options

This hook is optional.  It is provided so that applications can perform
validation of received options.  It is called as follows:

    $app->validate_options( $app_options );

C<$app_options> is an options hash for the application.

This method should throw an exception (e.g. with die()) if the options are
invalid.

NOTE that Getop::Long::Descriptive, which is used internally for part of the
options processing, will perform some validation of its own based on the
L<option_spec|/option_spec>.  However, the C<validate_options> hook allows
additional flexibility (if needed) in validating application options.

=head2 command_alias

Overriding this hook is optioal.  It allows aliases for commands to be
specified.  The aliases will be recognized in place of the actual command
names.  This is useful for setting up shortcuts to longer command names.

An example of its definition:

    sub command_alias {
    {
        h   => 'help',
        l   => 'list',
        ls  => 'list',
        sh  => 'console',
        c   => 'console',
    }
}

=head2 valid_commands

Overriding this hook is optional.  An example of its definition is as
follows:

    sub valid_commands { qw( console list my-custom-command ... ) }

The hook should return a list of the names of each command that is to be
supported by the application.  If not overridden by the application subclass,
the application will be very generic and have only the default commands.

Command names must be the same as the values returned by the C<name> method of
the corresponding Command class.

=head2 noninteractive_commands

Overriding this hook is optional.

Certain commands do not make sense to run interactively (e.g. the "console"
command, which starts interactive mode).  This method should return a list of
their names.  These commands will be disabled during interactive mode.  By
default, all commands are interactive commands except for C<console> and C<menu>.

=head2 quit_signals

Overriding this hook is optional.

    sub quit_signals { qw( q quit exit ) }

An application can specify exactly what input represents a request to end an
interactive session.  By default, the three strings above are used.

=head2 usage_text

To provide application usage information, this method may be defined.  It
should return a string containing a useful help message for the overall
application.

=head1 CLIF ERROR HANDLING POLICY

CLIF aims to make things simple for CLIF-derived applications.  OO Exceptions
are used internally, but CLIF apps are free to handle errors using any desired
strategy.

The main implication is that Application and Command class hooks such as
CLI::Framework::Application::validate_options() and
CLI::Framework::Command::validate() are expected to indicate success or
failure by throwing exceptions.  The exceptions can be plain calls to die() or
can be Exception::Class objects.

=head1 DIAGNOSTICS

Details will be provided pending finalizing error handling policies

=head1 CONFIGURATION & ENVIRONMENT

For interactive usage, Term::ReadLine is used.  Depending on which readline
libraries are available on your system, your interactive experience will vary
(for example, systems with GNU readline can benefit from a command history
buffer).

=head1 DEPENDENCIES

Carp

Getopt::Long::Descriptive

Class::Inspector

File::Spec

Text::ParseWords (only for interactive use)

Term::ReadLine (only for interactive use)

CLI::Framework::Exceptions

CLI::Framework::Command

=head1 DEFECTS AND LIMITATIONS

The CLIF distribution (CLI::Framework::*) is a work in progress!  The current
release is already quite effective, but there are several aspects that I
plan to improve.

The following areas are currently targeted for improvement:

=over

=item *

Interface -- Be aware that the interface may change.  Most likely, the changes
will be small.

=item *

Session handling -- Session handling is currently implemented in a temporary
manner.  Better session support is forthcoming.

=item *

Error handling -- Exception objects are being used successfully, but more
thorough planning needs to be done to finalize error handling policies.

=item *

Feature set -- Possible additional features being considered include: enhanced
support for using templates to render output of commands (including output
from error handlers); an optional constructor with an interface that will
allow the application and its commands to be defined inline, making it
possible to generate an application without creating separate files to inherit
from the base framework classes; a "web console" that will make the
interactive mode available over the web.

=item *

Documentation -- "Quickstart" and "Tutorial" guides are being written.

=back

I plan another release soon that will offer some or all of these improvements.
Suggestions and comments are welcome.

=head1 ACKNOWLEDGEMENTS

Many thanks to my colleagues at Informatics Corporation of America who have
assisted by providing ideas and bug reports, especially Allen May.

=head1 SEE ALSO

CLI::Framework::Command

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009 Karl Erisman (karl.erisman@icainformatics.com), Informatics
Corporation of America. All rights reserved.

This is free software; you can redistribute it and/or modify it under the same
terms as Perl itself. See perlartistic.

=head1 AUTHOR

Karl Erisman (karl.erisman@icainformatics.com)

=cut
