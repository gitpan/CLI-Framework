package CLI::Framework::Application;

use strict;
use warnings;

our $VERSION = '0.04_01';

use Getopt::Long::Descriptive;
use Exception::Class::TryCatch;

use CLI::Framework::Exceptions qw( :all );
use CLI::Framework::Command;

# Certain built-in commands are required:
use constant REQUIRED_BUILTINS => qw(
    CLI::Framework::Command::Help
);
# Certain built-in commands are required only in interactive mode:
use constant REQUIRED_BUILTINS_INTERACTIVE => qw(
    CLI::Framework::Command::Menu
);

#FIXME-TODO-CLASS_GENERATION:
#sub import {
#    my ($class, $app_pkg, $app_def) = @_;
#
#    # If caller has supplied import args, CLIF's "inline form" is being used;
#    # we need to generate the application class dynamically...
#
#}

#-------

sub new {
    my ($class, %args) = @_;

    my $interactive = $args{ interactive };             # boolean: interactive mode?

    my $cache = CLI::Framework::Cache->new();

    my $app = {
        _registered_command_objects => undef,           # (k,v)=(cmd pkg name,cmd obj) for all registered commands
        _default_command            => 'help',          # name of default command
        _current_command            => undef,           # name of current (or last) command to run
        _interactive                => $interactive,    # boolean: interactive state
        _cache                      => $cache,          # storage for data shared between app and cmd
        _initialized                => 0,               # initialization status
    };
    bless $app, $class;

    # Validate some hook methods so we can assume that they behave properly...
    $app->_validate_hooks();

    return $app;
}

sub _validate_hooks {
    my ($app) = @_;

    # Ensure that hook methods return expected data structure types according
    # to their preconditions...

    my $class = ref $app;

    # Ensure that command_map() returns a hashref...
    my $h;
    eval { $h = $app->command_map() };
    if( catch my $e ) {
        throw_app_hook_exception(
            error   => "method 'command_map' in class '$class' fails" );
    }
    elsif( ref $h ne 'HASH' ) {
        throw_app_hook_exception(
            error   => "method 'command_map' in class '$class' should return a HASH ref" );
    }
    # Ensure that command_alias() returns value appropriate for hash...
    my @aliases;
    eval { @aliases = $app->command_alias() };
    if( catch my $e ) {
        throw_app_hook_exception(
            error   => "method 'command_alias' in class '$class' fails" );
    }
    elsif( @aliases % 2 != 0 ) {
        throw_app_hook_exception(
            error   => "method 'command_alias' in class '$class' should return a hash or even-sized list" );
    }
}

sub cache { $_[0]->{_cache} }

###############################
#
#   COMMAND INTROSPECTION & REGISTRATION
#
###############################

sub is_valid_command_pkg {
    my ($app, $cmd_pkg) = @_;
    return unless $cmd_pkg;

    my @valid_pkgs = ( values %{ $app->command_map() }, REQUIRED_BUILTINS );
    push @valid_pkgs, REQUIRED_BUILTINS_INTERACTIVE
        if $app->get_interactivity_mode();

    return grep { $cmd_pkg eq $_ } @valid_pkgs;
}

sub is_valid_command_name {
    my ($app, $cmd_name) = @_;
    return unless $cmd_name;

    my @valid_aliases = ( keys %{ $app->command_map() } );
    push @valid_aliases, 'help';
    push @valid_aliases, 'menu' if $app->get_interactivity_mode();

    return grep { $cmd_name eq $_ } @valid_aliases;
}

sub registered_command_names {
    my ($app) = @_;

    # For each registered command package...
    my @names;
    for my $cmd_pkg (keys %{ $app->{_registered_command_objects} }) {
        # Find the command names that this command package was registered
        # under...
        push @names, grep { $_ } map {
            $_ if $app->command_map->{$_} eq $cmd_pkg
        } keys %{ $app->command_map }
    }
    return @names;
}

sub registered_command_object {
    my ($app, $cmd_name) = @_;
    return unless $cmd_name;

    my $cmd_pkg = $app->command_map->{$cmd_name};

    return unless $cmd_pkg
        && exists $app->{_registered_command_objects}
        && exists $app->{_registered_command_objects}->{$cmd_pkg};

    return $app->{_registered_command_objects}->{$cmd_pkg};
}

sub register_command {
    my ($app, $cmd) = @_;
    return unless $cmd;

    if( ref $cmd && $app->is_valid_command_pkg(ref $cmd) ) {
        # Register by reference...
        return unless $cmd->isa( 'CLI::Framework::Command' );
        $app->{_registered_command_objects}->{ref $cmd} = $cmd;
    }
    elsif( $app->is_valid_command_pkg($app->command_map->{$cmd}) ) {
        # Register by command name...
        my $pkg = $app->command_map->{$cmd};
        $cmd = CLI::Framework::Command->manufacture( $pkg );
        $app->{_registered_command_objects}->{ref $cmd} = $cmd;
    }
    elsif( $cmd eq 'help' ) {
        # Required built-in is always valid...
        $cmd = CLI::Framework::Command->manufacture( 'CLI::Framework::Command::Help' );
        $app->{_registered_command_objects}->{'CLI::Framework::Command::Help'} = $cmd;
    }
    elsif( $app->get_interactivity_mode() && $cmd eq 'menu' ) {
        # Required built-in for interactive usage is always valid...
        $cmd = CLI::Framework::Command->manufacture( 'CLI::Framework::Command::Menu' );
        $app->{_registered_command_objects}->{'CLI::Framework::Command::Menu'} = $cmd;
    }
    else {
        throw_cmd_registration_exception(
            error => "Error: failed attempt to register invalid command '$cmd'" );
    }
    # Metacommands should be app-aware...
    $cmd->set_app( $app ) if $cmd->isa( 'CLI::Framework::Command::Meta' );

    return $cmd;
}

sub get_default_command { $_[0]->{_default_command} }
sub set_default_command { $_[0]->{_default_command} = $_[1] }

sub get_current_command { $_[0]->{_current_command} }
sub set_current_command { $_[0]->{_current_command} = $_[1] }

sub get_default_usage { $_[0]->{_default_usage} }
sub set_default_usage { $_[0]->{_default_usage} = $_[1] }

###############################
#
#   PARSING & RUNNING COMMANDS
#
###############################

sub usage {
    my ($app, $command_name, @args) = @_;

    # Allow aliases in place of command name...
    $app->_canonicalize_cmd( $command_name );

    my $usage_text;
    if( $command_name && $app->is_valid_command_name($command_name) ) {
        # Get usage from Command object...
        my $cmd = $app->registered_command_object( $command_name )
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

sub _canonicalize_cmd {
    my ($self, $input) = @_;

    # Translate shorthand aliases for commands to full names...

    return unless $input;

    # Allow caller to define command_alias() to return either a hash or a
    # hashref...
    my $command_name;
    if( ref $self->command_alias() eq 'HASH' ) {
        my $aliases = $self->command_alias();
        return unless $aliases;
        $command_name = $aliases->{$input} || $input;
    }
    else {
        my %aliases = $self->command_alias();
        return unless %aliases;
        $command_name = $aliases{$input} || $input;
    }
    $_[1] = $command_name;
}

sub _handle_global_app_options {
    my ($app) = @_;

    # Process the [app-opts] prefix of the command request...

    # preconditions:
    #   - tail of @ARGV has been parsed and removed, leaving only the
    #   [app-opts] portion of the request
    # postconditions:
    #   - application options have been parsed and any application-specific
    #     validation and initialization that is defined has been performed
    #   - invalid tokens after [app-opts] and before <cmd> are detected and
    #     handled

    # Parse [app-opts], consuming them from @ARGV...
    my ($app_options, $app_usage);
    eval { ($app_options, $app_usage) = describe_options( '%c %o ...', $app->option_spec ) };
    if( catch my $e ) { # (failed application options parsing)
        throw_app_opts_parse_exception( error => $e );
    }
    $app->set_default_usage( $app_usage->text );

    # Detect invalid tokens in the [app-opts] part of the request
    # (@ARGV should be empty unless such invalid tokens exist because <cmd> has
    # been removed and any valid options have been processed)...
    if( @ARGV ) {
        my $err = @ARGV > 1 ? 'Unrecognized options: ' : 'Unrecognized option: ';
        $err .= join(' ', @ARGV ) . "\n";
        throw_app_opts_parse_exception( error => $err );
    }
    # --- VALIDATE APP OPTIONS ---
    eval { $app->validate_options($app_options) };
    if( catch my $e ) { # (failed application options validation)
        $e->isa( 'CLI::Framework::Exception' ) && do{ $e->rethrow() };
        throw_app_opts_validation_exception( error => $e . "\n" . $app->usage );
    }
    # --- INITIALIZE APP ---
    eval{ $app->init($app_options) };
    if( catch my $e ) { # (application failed initialization)
        $e->isa( 'CLI::Framework::Exception' ) && do{ $e->rethrow() };
        throw_app_init_exception( error => $e );
    }
    $app->{_initialized} = 1;

    return 1;
}

sub _parse_request {
    my ($app, %param) = @_;

    # Parse options/arguments from a command request and set the name of the
    # current command...

    # If requested, perform validation and initialization of the application.
    # NOTE: Application validation/initialization should NOT be performed here
    # in interactive mode for each command request because it should only be
    # done once for the application, not every time a command is run.

    #~~~~~~~~~~~~~~~~~~~~~~~
    # ARGV_Format
    #
    # non-interactive case:     @ARGV:      [app-opts]  <cmd> [cmd-opts] [cmd-args]
    # interactive case:         @ARGV:                  <cmd> [cmd-opts] [cmd-args]
    #~~~~~~~~~~~~~~~~~~~~~~~

    my $initialize_app = $param{initialize};

    # Parse options/arguments for the application and the command from @ARGV...
    my ($command_name, @command_opts_and_args);
    for my $i ( 0..$#ARGV ) {
        # Find first valid command name in @ARGV...
        $app->_canonicalize_cmd( $ARGV[$i] );
        if( $app->is_valid_command_name($ARGV[$i]) ) {
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
            throw_invalid_cmd_exception( error => $err );
        }
    }
    # Set internal current command name...
    $app->set_current_command( $command_name );

    # If requested, parse [app-opts] and initialize application...
    # (this is an optional step because in interactive mode, it should not be
    # done for every request)
    $app->_handle_global_app_options() if $initialize_app;

    # Leave '[cmd-opts] [cmd-args]' in @ARGV...
    @ARGV = @command_opts_and_args;

    return 1;
}

sub run {
    my ($app, %param) = @_;

    # Auto-instantiate if necessary...
    unless( ref $app ) {
        my $class = $app;
        $app = $class->new();
    }
    # Determine whether to do initialization -- if not explicitly indicated,
    # default to doing initialization only if it has not yet been done...
    my $initialize = $param{initialize};
    $initialize = not $app->{_initialized} unless defined $initialize;

    # Parse request; perform initialization...
    eval { $app->_parse_request( initialize => $initialize ) };
    if( catch my $e ) { $app->handle_exception($e); return }

    my $command_name = $app->get_current_command();

    # Lazy registration of commands...
    my $command = $app->registered_command_object( $command_name )
        || $app->register_command( $command_name );

    # Parse command options and auto-generate minimal usage message...
    my ($cmd_options, $cmd_usage);
    my $currently_interactive = $app->get_interactivity_mode();
    my $format = "$command_name %o ...";                            # Getopt::Long::Descriptive format string
    $format = '%c '.$format unless $currently_interactive;          # (%c is command name -- irrelevant in interactive mode)

    # (configure Getopt::Long to stop consuming tokens when first non-option is
    # encountered on input stream)
    my $getopt_configuration = { getopt_conf => [qw(require_order)] };
    eval { ($cmd_options, $cmd_usage) =
        describe_options( $format, $command->option_spec, $getopt_configuration )
    };
    # (handle failed command options parsing)
    if( catch my $e ) {
        if( $e->isa('CLI::Framework::Exception') ) {
            $app->handle_exception($e);
            return;
        }
        eval{ throw_cmd_opts_parse_exception( error => $e ) };
        if( catch my $e ) { $app->handle_exception( $e ); return }
    }
    $command->set_default_usage( $cmd_usage->text );

    # Share session data with command...
    # (init() method may have populated shared session data in cache for use by all commands)
    $command->set_cache( $app->cache );

    # --- APP HOOK: COMMAND PRE-DISPATCH ---
    $app->pre_dispatch( $command );

    # --- RUN COMMAND ---
    my $output;
    eval { $output = $command->dispatch( $cmd_options, @ARGV ) };
    if( catch my $e ) { $app->handle_exception($e); return }

    # Display output of command, if any...
    $app->render( $output ) if defined $output;

    return 1;
}

###############################
#
#   INTERACTIVITY
#
###############################

sub get_interactivity_mode { $_[0]->{_interactive} }
sub set_interactivity_mode { $_[0]->{_interactive} = $_[1] }

sub is_interactive_command {
    my ($app, $command_name) = @_;

    my @noninteractive_commands = $app->noninteractive_commands();

    # Command must be valid...
    return 0 unless $app->is_valid_command_name( $command_name );

    # Command must NOT be non-interactive...
    return 1 unless grep { $command_name eq $_ } @noninteractive_commands;

    return 0;
}

sub get_interactive_commands {
    my ($app) = @_;

    my @valid_commands = keys %{ $app->command_map };

    # All valid commands are enabled in non-interactive mode...
    return @valid_commands unless( $app->get_interactivity_mode() );

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
    if( catch my $e ) { $app->handle_exception($e); return }

    # Find how many prompts to display in sequence between displaying menu...
    my $menu_cmd = $app->registered_command_object('menu')
        || $app->register_command( 'menu' );
    $menu_cmd->isa( 'CLI::Framework::Command::Menu' )
        or throw_type_exception(
            error => "Menu command must be a subtype of " .
                     "CLI::Framework::Command::Menu" );

    my $invalid_request_threshold = $param{invalid_request_threshold}
        || $menu_cmd->line_count(); # num empty prompts b4 re-displaying menu

    $app->_run_cmd_processing_loop(
        menu_cmd                    => $menu_cmd,
        invalid_request_threshold   => $invalid_request_threshold
    );
    # Restore original default command...
    $app->set_default_command( $orig_default_command );
}

sub _run_cmd_processing_loop {
    my ($app, %param) = @_;

    my $menu_cmd                    = $param{menu_cmd};
    my $invalid_request_threshold   = $param{invalid_request_threshold};

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
                undef @ARGV;
                last;
            }
            $app->_canonicalize_cmd($ARGV[0]); # translate cmd aliases

            if( $app->is_interactive_command($ARGV[0]) ) {
                if( $app->run() ) {
                    $cmd_succeeded = 1;
                }
                else { $invalid_request_count++ }
            }
            else {
                $app->render( 'unrecognized command request: ' . join(' ',@ARGV) . "\n");
                $invalid_request_count++;
            }
        }
        else { $invalid_request_count++ }
    }
}

sub read_cmd {
    my ($app) = @_;

    require Text::ParseWords;

    # Retrieve or cache Term::ReadLine object (this is necessary to save
    # command-line history in persistent object)...
    my $term = $app->{_readline};
    unless( $term ) {
        require Term::ReadLine;
        $term = Term::ReadLine->new('CLIF Application');
        select $term->OUT;
        $app->{_readline} = $term;

#FIXME-TODO-CMDLINE_COMPLETION:
#        # Arrange for command-line completion...
#        my $attribs = $term->Attribs;
#        $attribs->{completion_function} = $app->_cmd_request_completions();
    }
    # Prompt for the name of a command and read input from STDIN.
    # Store the individual tokens that are read in @ARGV.
    my $command_request = $term->readline('> ');
    if( defined $command_request ) {
        @ARGV = Text::ParseWords::shellwords( $command_request ); # prepare command for usual parsing
        $term->addhistory( $command_request );
    }
    return 1;
}

##FIXME-TODO-CMDLINE_COMPLETION:this should only return interactive commands; it should pay attention
##to its text/line/start args, ...; also: make it work with subcommands
##  --see Term::Readline::Gnu
#sub _cmd_request_completions {
#    my ($app) = @_;
#    return sub {
#        my ($text, $line, $start) = @_;
#        return keys %{ $app->command_map() };
#    }
#}

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

#XXX-CONSIDER: consider making default implementation of init():
#       $app->set_current_command('help') if $opts->{help}
sub init { 1 }

sub pre_dispatch { }

sub usage_text { }

sub option_spec { }

sub validate_options { 1 }

sub command_map {
    {
        help        => 'CLI::Framework::Command::Help',
        console     => 'CLI::Framework::Command::Console',
        menu        => 'CLI::Framework::Command::Menu',
        list        => 'CLI::Framework::Command::List',
        'dump'      => 'CLI::Framework::Command::Dump',
        tree        => 'CLI::Framework::Command::Tree',
        alias       => 'CLI::Framework::Command::Alias',
    }
}

sub command_alias { }

sub noninteractive_commands { qw( console menu ) }

sub quit_signals { qw( q quit exit ) }

sub handle_exception {
    my ($app, $e) = @_;
    $app->render( $e->description . "\n\n" . $e->error );
    return;
}

sub render {
    my ($app, $output) = @_;

#XXX-CONSIDER: consider built-in features to help simplify associating templates
#with commands (each command would probably have its own template for its
#output)
    print $output;
}

###############################
#
#   CACHING
#
###############################

package CLI::Framework::Cache;

use strict;
use warnings;

sub new {
    my ($class) = @_;

    bless { _cache => { } }, $class;
}

sub get {
    my ($self, $k) = @_;

    my $v = $self->{_cache}->{$k};
    return $v;
}

sub set {
    my ($self, $k, $v) = @_;

    $self->{_cache}->{$k} = $v;
    return $v;
}

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Application - Build standardized, flexible, testable command-line applications

=head1 SYNOPSIS

    # The code below shows a few of the methods your application class is likely
    # to override...

    package My::Journal;
    use base qw( CLI::Framework );

    sub usage_text { q{
    $0 [--verbose|v]

    OPTIONS
        --db [path]  : path to SQLite database file
        -v --verbose : be verbose
        -h --help    : show help

    COMMANDS
        help        - show application or command-specific help
        menu        - print command menu
        entry       - work with journal entries
        publish     - publish a journal
        console     - start a command console for the application
    } }

    sub option_spec {
        [ 'help|h'      => 'show help' ],
        [ 'verbose|v'   => 'be verbose' ],
        [ 'db=s'        => 'path to SQLite database file for your journal' ],
    }

    sub command_map { {
        help    => 'CLI::Framework::Command::Help',
        menu    => 'My::Journal::Command::Menu',
        entry   => 'My::Journal::Command::Entry',
        publish => 'My::Journal::Command::Publish',
        console => 'CLI::Framework::Command::Console',
    } }

    sub command_alias {
        h   => 'help',
        m   => 'menu',
        e   => 'entry',
        p   => 'publish',
        sh  => 'console',
        c   => 'console',
    }

    sub init {
        my ($self, $opts) = @_;
        my $db = DBI->connect( ... );
        $self->cache->set( db => $db );
        return 1;
    }
    1;

=head1 INTRODUCTION

See L<CLI::Framework> for an introduction to CLIF (it is new to version 0.04;
the general framework documentation has been moved there).

B<Note> that C<CLI::Framework> can now serve as the superclass for your
applications (this is new in version 0.04).  However, as in earlier versions,
C<CLI::Framework::Application> will work as the application base class.

=head1 OBJECT CONSTRUCTION

=head2 new( [interactive => 1] )

    $app = My::Application->new( interactive => 1 );

C<interactive>: Optional parameter.  Set this to a true value if the application
is to be run interactively (or call C<set_interactivity_mode> later)

Constructs and returns a new CLIF Application object.  As part of this
process, some validation is performed on L<SUBCLASS HOOKS|/SUBCLASS HOOKS>
defined in the application class.  If validation fails, an exception is thrown.

=head1 COMMAND INTROSPECTION & REGISTRATION

The methods in this section are responsible for providing access to the
commands in an application.

=head2 is_valid_command_pkg( $package_name )

    $app->is_valid_command_pkg( 'My::Command::Swim' );

Returns a true value if the specified command class (package name) is valid
within the application.  Returns a false value otherwise.

A command class is "valid" if it is included in L<command_map|/command_map()> or
if it is a built-in command that was included automatically in the
application.

=head2 is_valid_command_name( $command_name )

    $app->is_valid_command_name( 'swim' );

Returns a true value if the specified command name is valid within the
application.  Returns a false value otherwise.

A command name is "valid" if it is included in L<command_map|/command_map()> or
if it is a built-in command that was included automatically in the
application.

=head2 registered_command_names()

    @registered_commands = $app->registered_command_names();

Returns a list of the names of all registered commands.  These are the names
that each command was given in L<command_map|/command_map()> (plus any
auto-registered built-ins).

=head2 registered_command_object( $command_name )

    $command_object = $app->registered_command_object( 'fly' );

Given the name of a registered command, returns the L<CLI::Framework::Command>
object that is registered in the application under that name.  If the command
is not registered, returns C<undef>.

=head2 register_command( $cmd )

    # Register by name...
    $command_object = $app->register_command( $command_name );

    # ...or register by object reference...
    $command_object = CLI::Framework::Command->new( ... );
    $app->register_command( $command_object );

Register a command to be recognized by the application.  This method accepts
either the name of a command or a reference to a L<CLI::Framework::Command>
object.

If C<$cmd> is a L<CLI::Framework::Command> object and it is one of the command
types specified (as a value in the hash returned by
L<command_map|/command_map()>) to be valid, the command object is registered and
returned.

If C<$cmd> is the name of a valid command (one of the keys in the
L<command_map|/command_map()>), an object of the corresponding command class is
registered and returned.

If C<$cmd> is not recognized, an exception is thrown.

=head2 get_default_command() / set_default_command( $default_cmd )

C<get_defualt_command()> retrieves the name of the command that is currently
set as the default command for the application.

    my $default_command = $app->get_default_command();

Given a command name, C<set_default_command> makes it the default command for
the application.

    $app->set_default_command( 'jump' );

=head2 get_current_command() / set_current_command( $current )

C<get_current_command> returns the name of the current command (or the one that
was most recently run).

    $status = $app->run();
    print 'The command named: ', $app->get_current_command(), ' was just run';

Given a command name, C<set_current_command> forwards execution to that command.
This might be useful (for instance) to "redirect" to another command.

    $app->set_current_command( 'fly' );

=head2 get_default_usage() / set_default_usage( $default_usage )

The "default usage" message is used as a last resort when usage information is
unavailable by other means.  See L<usage|/usage( $command_name, @subcommand_chain )>.

C<get_default_usage> gets the default usage message for the application.

    $usage_msg = $app->get_default_usage();

C<set_default_usage> sets the default usage message for the application.

    $app->set_default_usage( $usage_message );

=head1 PARSING & RUNNING COMMANDS

=head2 usage( $command_name, @subcommand_chain )

    # Application usage...
    print $app->usage();

    # Command-specific usage...
    $command_name = 'task';
    @subcommand_chain = qw( list completed );
    print $app->usage( $command_name, @subcommand_chain );

Returns a usage message for the application or a specific (sub)command.

If a command name is given (optionally with subcommands), returns a usage
message string for that (sub)command.  If no command name is given or if no
usage message is defined for the specified (sub)command, returns a general usage
message for the application.

Here is how the usage message is produced:

=over

=item *

If a valid command name (or alias) is given, attempt to get a usage message from
the command (this step takes into account C<@subcommand_chain> so that a
subcommand usage message will be shown if applicable); if no usage message is
defined for the command, use the application usage message instead.

=item *

If the application object has defined L<usage_text|/usage_text()>, use its
return value as the usage message.

=item *

Finally, fall back to using the default usage message returned by
L<get_default_usage|/get_default_usage() / set_default_usage( $default_usage )>.

B<Note>: It is advisable to define usage_text because the default usage
message, produced via Getopt::Long::Descriptive, is terse and is not
context-specific to the command request.

=back

=head2 cache()

CLIF Applications may have the need to share data between individual CLIF
Commands and the Application object itself.  C<cache()> provides a way for this
data to be stored, retrieved, and shared between components.

    $cache_object = $app->cache();

C<cache()> returns a cache object.  The following methods demonstrate usage of
the resulting object:

    $cache_object->get( 'key' );
    $cache_object->set( 'key' => $value );

B<Note>: The underlying cache class is currently limited to these rudimentary
features.  In the future, the object returned by C<cache()> may be changed to
an instance of a real caching class, such as L<CHI> (which would maintain
backwards compatibility but offer expiration, serialization, multiple caching
backends, etc.).

=head2 run()

    # as class method:
    My::App->run();

    # as object method (when having an object reference to call other methods
    # is desirable):
    my $app = My::App->new();
    $app->run();

    ...

    # Explicitly specify whether or not initialization should be done:
    $app->run( initialize => 0 );

This method controls the request processing and dispatching of a single
command.  It takes its input from @ARGV (which may be populated by a
script running non-interactively on the command line) and dispatches the
indicated command, capturing its return value.  The command's return value
represents the output produced by the command.  This value is passed to
L<render|/render( $output )> for final display.

If errors occur, they result in exceptions that are handled by
L<handle_exception|/handle_exception( $e )>.

The following parameters are accepted:

C<initialize>: This controls whether or not application initialization (via
L<init|/init( $options_hash )>) should be performed.  If not specified,
initialization is performed upon the first call to C<run>.  Should there be
subsequent calls, initialization is not repeated.  Passing C<initialize>
explicitly can modify this behavior.

=head1 INTERACTIVITY

=head2 get_interactivity_mode() / set_interactivity_mode( $is_interactive )

C<get_interactivity_mode> returns a true value if the application is in an
interactive state and a false value otherwise.

    print "running interactively" if $app->get_interactivity_mode();

C<set_interactivity_mode> sets the interactivity state of the application.  One
parameter is recognized: a true or false value to indicate whether the
application state should be interactive or non-interactive, respectively.

    $app->set_interactivity_mode(1);

=head2 is_interactive_command( $command_name )

    $help_command_is_interactive = $app->is_interactive_command( 'help' );

Returns a true value if there is a valid command with the specified name that
is an interactive command (i.e. a command that is enabled for this application
in interactive mode).  Returns a false value otherwise.

=head2 get_interactive_commands()

    my @interactive_commands = $app->get_interactive_commands();

Return a list of all commands that are to be available in interactive mode
("interactive commands").

=head2 run_interactive( [%param] )

    MyApp->run_interactive();

    # ...or as an object method:
    $app->run_interactive();

Start an event processing loop to prompt for and run commands in sequence.  The
C<menu> command is used to display available command selections (the built-in
C<menu> command, L<CLI::Framework::Command::Menu>, will be used unless the
application defines its own C<menu> command).

Within this loop, valid input is the same as in non-interactive mode except
that application options are not accepted (any application options should be
handled upon application initialization and before the interactive B<command>
loop is entered -- see the description of the C<initialize> parameter below).

The following parameters are recognized:

C<initialize>: causes any application options that are present in C<@ARGV> to be
procesed/validated and causes L<init|/init( $options_hash )> to be invoked
prior to entering the interactive event loop to recognize commands.  If
C<run_interactive()> is called after application options have already been
handled, this parameter can be omitted.

C<invalid_request_threshold>: the number of unrecognized command requests the
user can enter before the menu is re-displayed.

=head2 read_cmd()

    $app->read_cmd();

This method is responsible for retrieving a command request and placing the
user input into C<@ARGV>.  It is called in void context.

The default implementation uses L<Term::ReadLine> to prompt the user and read a
command request, supporting command history.

Subclasses are free to override this method if a different means of
accepting user input is desired.  This makes it possible to read command
selections without assuming that the console is being used for I/O.

=head2 is_quit_signal()

    until( $app->is_quit_signal(read_string_from_user()) ) { ... }

Given a string, return a true value if it is a quit signal (indicating that
the application should exit) and a false value otherwise.
L<quit_signals|/quit_signals()> is an application subclass hook that
defines what strings signify that the interactive session should exit.

=head1 SUBCLASS HOOKS

There are several hooks that allow CLIF applications to influence the command
execution process.  This makes customizing the critical aspects of an
application as easy as overriding methods.

Except where noted, all hooks are optional -- subclasses may choose not to
override them (in fact, runnable CLIF applications can be created with very
minimal subclasses).

=head2 init( $options_hash )

This hook is called in void context with one parameter:

C<$options_hash> is a hash of pre-validated application options received and
parsed from the command line.  The options hash has already been checked
against the options defined to be accepted by the application in
L<option_spec|/option_spec()>.

This method allows CLIF applications to perform any common
initialization tasks that are necessary regardless of which command is to be
run.  Some examples of this include connecting to a database and storing a
connection handle in the shared L<cache|/cache()> slot for use by individual
commands, setting up a logging facility that can be used by each command by
storing a logging object in the L<cache|/cache()>, or initializing settings from
a configuration file.

=head2 pre_dispatch( $command_object )

This hook is called in void context.  It allows applications to perform actions
after each command object has been prepared for dispatch but before the command
dispatch actually takes place.  Its purpose is to allow applications to do
whatever may be necessary to prepare for running the command.  For example, a
log entry could be inserted in a database to store a record of every command
that is run.

=head2 option_spec()

An example definition of this hook is as follows:

    sub option_spec {
        [ 'verbose|v'   => 'be verbose'         ],
        [ 'logfile=s'   => 'path to log file'   ],
    }

This method should return an option specification as expected by
L<Getopt::Long::Descriptive|Getopt::Long::Descriptive/opt_spec>.  The option
specification defines what options are allowed and recognized by the
application.

=head2 validate_options( $options_hash )

This hook is called in void context.  It is provided so that applications can
perform validation of received options.

C<$options_hash> is an options hash parsed from the command-line.

This method should throw an exception if the options are invalid (throwing the
exception using C<die()> is sufficient).

B<Note> that L<Getopt::Long::Descriptive>, which is used internally for part of the
options processing, will perform some validation of its own based on the
L<option_spec|/option_spec()>.  However, the
L<validate_options|/validate_options( $options_hash )>
hook allows for additional flexibility in validating application options.

=head2 command_map()

Return a mapping between command names and Command classes (classes that inherit
from L<CLI::Framework::Command>).  The mapping is a hashref where the keys are
names that should be used to install the commands in the application and the
values are the package names of the packages that implement the corresponding
commands, as in this example:

    sub command_map {
        {
            # custom commands:
            fly     => 'My::Command::Fly',
            run     => 'My::Command::Run',

            # overridden built-in commands:
            menu    => 'My::Command::Menu',

            # built-in commands:
            help    => 'CLI::Framework::Command::Help',
            list    => 'CLI::Framework::Command::List',
            tree    => 'CLI::Framework::Command::Tree',
            'dump'  => 'CLI::Framework::Command::Dump',
            console => 'CLI::Framework::Command::Console',
            alias   => 'CLI::Framework::Command::Alias',
        }
    }

=head2 command_alias()

This hook allows aliases for commands to be specified.  The aliases will be
recognized in place of the actual command names.  This is useful for setting
up shortcuts to longer command names.

C<command_alias> should return a hash where the keys are aliases and the
values are command names.

An example of its definition:

    sub command_alias {
        h   => 'help',
        l   => 'list',
        ls  => 'list',
        sh  => 'console',
        c   => 'console',
    }

=head2 noninteractive_commands()

    sub noninteractive_commands { qw( console menu ) }

Certain commands do not make sense to run interactively (e.g. the "console"
command, which itself puts the application into interactive mode).  This method
should return a list of their names.  These commands will be disabled during
interactive mode.  By default, all commands are interactive commands except for
C<console> and C<menu>.

=head2 quit_signals()

    sub quit_signals { qw( q quit exit ) }

An application can specify exactly what input represents a request to end an
interactive session.  By default, the example definition above is used.

=head2 handle_exception( $e )

    sub handle_exception {
        my ($app, $e) = @_;

        # Handle the exception represented by object $e...
        $app->my_error_logger( error => $e->error, pid => $e->pid, gid => $e->gid, ... );

        warn "caught error ", $e->error, ", continuing...";
        return;
    }

Error conditions are caught by CLIF and forwarded to this exception handler.
It receives an exception object (see L<Exception::Class::Base> for methods
that can be called on the object).

If not overridden, the default implementation extracts the error message from
the exception object and processes it through the L<render|/render( $output )>
method.

=head2 render( $output )

    $app->render( $output );

This method is responsible for presentation of the result from a command.
The default implementation simply attempts to print the C<$output> scalar,
assuming that it is a string.

Subclasses are free to override this method to provide more
sophisticated behavior such as processing the C<$output> scalar through a
templating system.

=head2 usage_text()

    sub usage_text {
        q{
        OPTIONS
            -v --verbose : be verbose
            -h --help    : show help
    
        COMMANDS
            tree        - print a tree of only those commands that are currently-registered in your application
            menu        - print command menu
            help        - show application or command-specific help
            console     - start a command console for the application
            list        - list all commands available to the application
        }
    }

To provide application usage information, this method may be overridden.  It
accepts no parameters and should return a string containing a useful help
message for the overall application.

Overriding this method is encouraged in order to provide a better usage
message than the default.  See
L<usage|/usage( $command_name, @subcommand_chain )>.

=head1 ERROR HANDLING IN CLIF

Internally, CLIF handles errors by throwing exceptions.  

The L<handle_exception|/handle_exception( $e )> method provides an opportunity
for customizing the way errors are treated in a CLIF application.

Application and Command class hooks such as
L<validate_options|/validate_options( $options_hash )>
and L<validate|CLI::Framework::Command/validate( $cmd_opts, @args )> are
expected to indicate success or failure by throwing exceptions (via C<die()> or
something more elaborate, such as exception objects).

=head1 CONFIGURATION & ENVIRONMENT

For interactive usage, L<Term::ReadLine> is used.  Depending on which readline
libraries are available on your system, your interactive experience will vary
(for example, systems with GNU readline can benefit from a command history
buffer).

=head1 DEPENDENCIES

L<Exception::Class::TryCatch>

L<Getopt::Long::Descriptive>

L<Text::ParseWords> (only for interactive use)

L<Term::ReadLine> (only for interactive use)

L<CLI::Framework::Exceptions>

L<CLI::Framework::Command>

=head1 DEFECTS AND LIMITATIONS

No known bugs.

=head1 PLANS FOR FUTURE VERSIONS

=over

=item *

Command-line completion of commands in interactive mode

=item *

Features to make it simpler to use templates for output

=item *

Features to instantly web-enable your CLIF Applications, making them
accessible via a "web console"

=item *

Better automatic usage message generation

=item *

An optional inline automatic class generation interface similar to that of
L<Class::Exception> that will make the simple "inline" form of usage even
more compact

=back

=head1 SEE ALSO

L<CLI::Framework>

L<CLI::Framework::Command>

L<CLI::Framework::Tutorial>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009 Karl Erisman (kerisman@cpan.com). All rights reserved.

This is free software; you can redistribute it and/or modify it under the same
terms as Perl itself. See perlartistic.

=head1 AUTHOR

Karl Erisman (kerisman@cpan.org)

=cut
