package CLI::Framework::Command;

use strict;
use warnings;

#FIXME:'strangepkgs' warnings category -- not working...
#use warnings::register;

use Carp;

our $VERSION = 0.01;

use Getopt::Long::Descriptive;
use Class::ISA;
use File::Spec;

use CLI::Framework::Exceptions;

###############################
#
#   OBJECT CONSTRUCTION
#
###############################

sub manufacture {
    my ($pkg_or_ref, %args) = @_;

    my $command_search_path = $args{command_search_path};
    my $command_name        = $args{command}
        or croak "Missing required param 'command'";

    $command_name =~ s/^(\w)(.*)/\u$1\L$2/; # normalize command name

    my $object;
    if( ref $pkg_or_ref ) {
        # Manufacture subcommand from its own package file...
        my $cmd_obj = $pkg_or_ref;
        my $class = (ref $cmd_obj).'::'.$command_name;

        my @class_name_parts = split /::/, ref $cmd_obj;
        my $location = File::Spec->catdir( @class_name_parts, $command_name );
        $location .= '.pm';
        require $location
            or croak "Error: failed to require() subcommand from package file '$location'";
        $object = $class->new()
            or croak "Error: failed to instantiate subcommand '$class' via method new()";

        $cmd_obj->register_subcommand( $object );
    }
    else {
        # Manufacture base command from package file found in search path...
        $command_search_path
            or croak "Must specify 'command_search_path' for command construction";

        my @dirs = File::Spec->splitdir( $command_search_path );
        my $class = join('::', @dirs) . '::' . $command_name;
        my $location = File::Spec->catfile( @dirs, "$command_name.pm");
        require $location
            or croak "Error: failed to require() base command from package file '$location'";
        $object = $class->new()
            or croak "Error: Cannot instantiate class '$class' via method new()";
#FIXME:unless( $object->isa('CLI::Framework::Command') ) {
#    NonCommandException->throw( error => "" );
#}
    }
    # Look for subcommands of the current (sub)command.  These subcommand
    # packages may be found in their own package files or their packages may
    # be defined inline in the parent command package file...
    $object->_manufacture_subcommands_in_dir_tree();
    $object->_manufacture_subcommands_in_parent_pkg_file();
    return $object;
}

sub _manufacture_subcommands_in_dir_tree {
    my ($parent_command_object) = @_;

    # Check for a subdirectory by the name of the current command containing .pm
    # files representing subcommands, then manufacture() any that are found...

    # Look for subdirectory with name of current command...
    my $subcommand_dir = Class::Inspector->resolved_filename( ref $parent_command_object );
    substr( $subcommand_dir, -3, 3 ) = ''; # trim trailing '.pm'

    if( -d $subcommand_dir ) {
        # Directory with name of current command exists; look inside for .pm
        # files representing subcommands...

        my $dh;
        opendir( $dh, $subcommand_dir ) or die "cannot opendir '$dh': $!";
        while( my $subcommand = readdir $dh ) {
            # Ignore non-module files...
            next unless substr( $subcommand, -3 ) =~ s/\.pm//; # trim trailing '.pm'

            # This is a mutually-recursive case -- manufacture subcommand as a
            # subcommand of the current command...
            # (NOTE: subcommand will be registered in manufacture(), so
            # register_subcommand() need not be called here)

            # Ignore .pm files that do not represent subcommands of the parent...
            my $subcommand_pkg = (ref $parent_command_object).'::'.$subcommand;
            eval "require $subcommand_pkg";
            unless( $subcommand_pkg->isa(ref $parent_command_object) ) {
#FIXME-NOT-WORKING:'strangepkgs' warnings category -- warn when an unexpected module is found in the dir tree.  This will make it easier for users to notice when they forget to 'use base' in commands
#                warnings::warnif('strangepkgs', "Found a non-subclass Perl package file in search path: '$subcommand_pkg' -- ignoring...");
                next;
            }
            my $sub_obj = $parent_command_object->manufacture( command => $subcommand );
        }
    }
    return 1;
}

sub _manufacture_subcommands_in_parent_pkg_file {
    my ($parent_command_object) = @_;

    # Check for subcommands defined internally within parent package file;
    # instantiate and register any that are found...

    # Get filename of parent package...
    my $inc_entry = Class::Inspector->resolved_filename( ref $parent_command_object );
    my $parent_pkg = ref $parent_command_object;

    # Read parent package file, searching for package declarations...
    open( my $fh, '<', $inc_entry )
        or die "Error: failed to open '$inc_entry' for reading: $!";

    # Find and store each command package declared in this file (exclude the
    # parent command)...
    my %command_map = ( # map command package names to object references
        $parent_pkg => $parent_command_object
    );
    while( my $parent_pkg_line = <$fh> ) {
        # Find package name...
        if( (my $subpkg = $parent_pkg_line) =~ s/^\s*package\s+([\w:]+)\s*;.*/$1/s ) {
            unless( $subpkg eq $parent_pkg ) {
                # Inline package declaration for non-parent package =>
                # instantiate it...
                my $object;
                eval{ $object = $subpkg->new() };
                # Silently ignore failures to call new() on internally-defined
                # packages (there may be internally-defined packages that do not
                # have a new() method)
                next if $@;

                # Store object in mapping if it is a command object...
                $command_map{ $subpkg } = $object if( $object->isa($parent_pkg) );
            }
        }
        # (else: inline package declaration is for the parent package => ignore)
    }
    close $fh;

    # For each subcommand defined in this package file (excluding the parent
    # command), register it as a subcommand of its parent...
    for my $type (keys %command_map) {
        my $immediate_super = (Class::ISA::super_path( $type ))[0];
        my $super_obj = $command_map{ $immediate_super };
        my $sub_obj = $command_map{ $type };
        next unless $super_obj;
        $super_obj->register_subcommand( $sub_obj );
    }
    return 1;
}

sub new { bless { _session => undef }, $_[0] }

###############################
#
#   SESSION DATA
#
###############################

sub set_session { $_[0]->{_session} = $_[1] }

sub session {
    my ($cmd, $k, $v) = @_;

    if( defined $k && defined $v ) {
        # Set session element...
        $cmd->{_session}->{$k} = $v;
    }
    elsif( defined $k ) {
        # Get session element...
        return $cmd->{_session}->{$k};
    }
    else {
        # Get entire session...
        return $cmd->{_session};
    }
}

###############################
#
#   COMMAND DISPATCHING
#
###############################

sub set_default_usage { $_[0]->{_default_usage} = $_[1] }
sub get_default_usage { $_[0]->{_default_usage}         }

#sub _command_package_file {
#    my ($cmd, @search_ancestors) = @_;
#
#    # Get the filename of the package defining the requested command class,
#    # even if the requested class does not have its own file due to its being
#    # defined inline in the package file of an ancestral class...
#
#    @search_ancestors = Class::ISA::self_and_super_path(ref $cmd)
#        unless @search_ancestors;
#    require Class::Inspector;
#    my $target_path = Class::Inspector->loaded_filename(shift @search_ancestors);
#    unless( defined $target_path ) {
#        return unless @search_ancestors;
#        $target_path = $cmd->_command_package_file( @search_ancestors );
#    }
#    return $target_path;
#}

sub usage {
    my ($cmd, $subcommand_name, @subcommand_args) = @_;

    # Allow subcommand aliases in place of subcommand name...
    $cmd->_canonicalize($subcommand_name);

    my $usage_text;
    if( my $subcommand = $cmd->get_registered_subcommand($subcommand_name) ) {
        # Get usage from subcommand object...
        $usage_text = $subcommand->usage(@subcommand_args);
    }
    else {
        # Get usage from Command object...
        $usage_text = $cmd->usage_text();
    }
    # Finally, fall back to default command usage message...
    $usage_text ||= $cmd->get_default_usage();
    return $usage_text;
}

#-------

sub _canonicalize {
    my ($self, $input) = @_;

    # Translate shorthand aliases for subcommands to full names...

    return unless $input;

    my $aliases = $self->subcommand_alias();
    return unless $aliases;

    my $command_name = $aliases->{$input} || $input;
    $_[1] = $command_name;
}

#-------

#
# ARGV_Format
#
# $ app [app-opts] <cmd> [cmd-opts] <the rest>
#
# params contain: $cmd = <cmd>, $cmd_opts = [cmd-opts], @args = <the rest>
#
# <the rest> could, in turn, indicate nested subcommands:
#   { <subcmd> [subcmd-opts] {...} } [subcmd-args]
#

sub dispatch {
    my ($cmd, $cmd_opts, @args) = @_;

    # --- VALIDATE COMMAND OPTIONS AND ARGS ---
    eval { $cmd->validate($cmd_opts, @args) };
    if( my $e = Exception::Class->caught() ) { # (command failed validation)
        ref $e ? $e->rethrow :


        #FIXME: Devel::Stacktrace gives error "Bizarre copy of ARRAY in aassign"
        #       here from throwing exception in the usual way
        #        CLI::Framework::Exception::CmdValidationException->throw( error => $e );
        die $e;


    }
    # Check if a subcommand is being requested...
    my $first_arg = shift @args; # consume potential subcommand name from input
    $cmd->_canonicalize( $first_arg );
    my ($subcmd_opts, $subcmd_usage);
    if( my $subcommand = $cmd->get_registered_subcommand($first_arg) ) {
        # A subcommand is being requested; parse its options...
        @ARGV = @args;
        my $format = $cmd->name().' '.$subcommand->name().'%o ...';
        eval { ($subcmd_opts, $subcmd_usage) = describe_options( $format, $subcommand->option_spec() ) };
        if( my $e = Exception::Class->caught() ) { # (subcommand failed options parsing)
            ref $e ? $e->rethrow :
            CLI::Framework::Exception::CmdOptsParsingException->throw( error => $e );
        }
        $subcommand->set_default_usage( $subcmd_usage->text() );

        # Reset arg list to reflect only arguments ( options may have been
        # consumed by describe_options() )...
        @args = @ARGV;

        # Pass session data to subcommand...
        $subcommand->set_session( $cmd->session() );

        # --- NOTIFY MASTER COMMAND OF SUBCOMMAND DISPATCH ---
        $cmd->notify( $subcommand, $cmd_opts, @args );

        # Dispatch subcommand with its options and the remaining args...
        $subcommand->dispatch( $subcmd_opts, @args );
    }
    else {
        # If first arg is not a subcommand then put it back in input...
        unshift @args, $first_arg if defined $first_arg;

        my $output;
        eval { $output = $cmd->run( $cmd_opts, @args ) };
        if( my $e = Exception::Class->caught() ) { # (error during command execution)
            ref $e ? $e->rethrow : CLI::Framework::Exception::CmdRunException->throw( error => $e );
        }
        return $output;
    }
}

###############################
#
#   COMMAND REGISTRATION
#
###############################

sub get_registered_command_names { keys %{ $_[0]->{_subcommands} }      }
sub registered_subcommand_names { $_[0]->get_registered_command_names() }    # alias method

#-------

sub get_registered_command {
    my ($self, $subcommand_name) = @_;

    return unless $subcommand_name;

    return $self->{_subcommands}->{$subcommand_name};
}
sub get_registered_subcommand { $_[0]->get_registered_command($_[1]) }   # alias method

sub register_command {
    my ($self, $subcommand_obj) = @_;

    return unless $subcommand_obj && $subcommand_obj->isa("CLI::Framework::Command");

    my $subcommand_name = $subcommand_obj->name();
    $self->{_subcommands}->{$subcommand_name} = $subcommand_obj;

    return $subcommand_obj;
}
sub register_subcommand { $_[0]->register_command( $_[1] ) }    # alias method

###############################
#
#   COMMAND SUBCLASS HOOKS
#
###############################

# By default, use base name of package as command name...
sub name {
    my ($app) = @_;

    my $pkg = ref $app;
    my @pkg_parts = split /::/, $pkg;
    return lc $pkg_parts[-1];
}

sub option_spec { ( ) }

sub subcommand_alias { ( ) }

sub validate { }

sub notify { }

sub usage_text { }

sub run { $_[0]->usage() }

###############################
#
#   SUBCLASS FOR METACOMMANDS
#
###############################

package CLI::Framework::Command::Meta;
use base qw( CLI::Framework::Command );

sub new {
     my ($class, %args) = @_;
     my $app = $args{app};
     bless { _app => $app }, $class;
}

sub app { $_[0]->{_app} } # (metacommands know about their application (and thus, the other commands in the app))

sub set_app { $_[0]->{_app} = $_[1] }

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Command - CLIF Command superclass

=head1 SYNOPSIS

    # Define commands and subcommands for use in a CLIF application...
    # (placing package files with this content in the command search path for
    # a CLIF app will make the commands available to the application)

    # Command:
    package My::Example::Command;
    use base qw( CLI::Framework::Command );
    sub usage_text { ... }
    sub notify { ... }
    1;

    # Sub-command:
    package My::Example::Subcommand;
    use base qw( My::Example::Command );
    sub usage_text { ... }
    sub run { ... }
    1;

    # Sub-sub-command:
    package My::Example:SubSubcommand;
    use base qw( My::Example::Subcommand );
    sub usage_text { ... }
    sub run { ... }
    1;

    ...

=head1 DESCRIPTION

CLI::Framework::Command (command class for use with
L<CLI::Framework::Application>) is the base class for CLIF commands.  All CLIF
commands should inherit from this class.

=head1 CONCEPTS

=over

=item subcommands

Commands can have "subcommands," which are also objects of this class.
Subcommands can, in turn, have their own subcommands, and this pattern repeats
recursively.

NOTE that in this documentation, the term "command" may be used to refer to both
commands and subcommands.

=back

=head1 METHODS: OBJECT CONSTRUCTION

=head2 manufacture

    # (manufacture MyApp::Command::Go)
    my $go = CLI::Framework::Command->manufacture(
        command_search_path => "MyApp/Command", command => 'go'
    );

    # (manufacture MyApp::Command::Go::Fast)
    $go->manufacture( command => 'fast' );


CLI::Framework::Command is an abstract factory; this is the factory method
that constructs and returns an object of the specific command that is
requested.  Called as a class method, the named command is constructed and
returned.  As an object method, the named subcommand is constructed and
registered under the main command that C<manufacture()> is being invoked on.

=head2 new

    $object = $cli_framework_command_subclass->new() or die "Cannot instantiate $class";

Basic constructor.

=head1 METHODS: SESSION DATA

CLIF commands may need to share data with other commands and with their
associated application.  These methods support those needs.

=head2 set_session

    $app->set_session( \%session_data );

Set the entire session from the given hash.

=head2 session

    # get a single item from the session...
    $value = $app->session( $key );

    # save a single item in the session...
    $app->session( $key => $value );

    # get the entire session...
    $s = $app->session();

Accessor/mutator for the session 

=head1 METHODS: COMMAND DISPATCHING

=head2 set_default_usage

    $cmd->set_default_usage( $usage_message );

Set the default usage message for the command.

=head2 get_default_usage

    $usage_msg = $cmd->get_default_usage();

Get the default usage message for the command.  This message is used by
L<usage|/usage>.

NOTE: C<get_default_usage()> merely retrieves the usage data that has already been
set.  CLIF only sets the default usage message for a command when processing a
run request for the command.  Therefore, the default usage message for a
command may be empty.

=head2 usage

    # Command usage...
    print $cmd->usage();

    # Subcommand usage...
    print $cmd->usage( $subcommand_name, @subcommand_chain );

Attempts to find and return a usage message for a command or subcommand.

If a subcommand is given, returns a usage message for that subcommand.  If no
subcommand is given or if the subcommand cannot produce a usage message,
returns a general usage message for the application.

Logically, here is how the usage message is produced:

=over

=item *

If registered subcommand(s) are given, attempt to get usage message from a
subcommand (NOTE that a sequence of subcommands could be given, e.g.
C<qw(task list completed)>, which would result in the usage message for final
subcommand, C<completed>).  If no usage message is defined for the subcommand,
the usage message for the command is used instead.

=item *

If the command has implemented L<usage_text|/usage_text>, its return value is
used as the usage message.

=item *

Finally, if no usage message has been found, the default usage message
produced by L<get_default_usage|/get_default_usage> is returned.

=back

=head2 dispatch

    $command->dispatch( $cmd_opts, @args );

For the given command request, perform any applicable validation and
initialization with respect to the supplied options C<$cmd_opts> and arguments
(C<@args>).

C<@args> may indicate the request for a subcommand:

    { <subcmd> [subcmd-opts] {...} } [subcmd-args]

If a subcommand registered under the indicated command is requested,
initialize and C<dispatch> the subcommand with its options C<[subcmd-opts]>
and arguments.  Otherwise, C<run> the command itself.

This means that a request for a subcommand will result in the C<run()>
method of only the deepest-nested subcommand (because C<dispatch()> will keep
forwarding to subcommands until the args no longer indicate that a subcommand
is requested).  Furthermore, the only command that can receive args is the
final subcommand in the chain (but all commands in the chain can receive
options).  However, each command in the chain can affect the execution process
through its L<notify|notify> method.

=head1 METHODS: COMMAND REGISTRATION

=head2 get_registered_command_names

This is an alias for L<registered_subcommand_names>.

=head2 registered_subcommand_names

    @registered_subcommands = $cmd->registered_subcommand_names();

Return a list of the currently-registered subcommands.

=head2 get_registered_command

This is an alias for L<get_registered_subcommand>.

=head2 get_registered_subcommand

    $subcmd_obj = $cmd->get_registered_subcommand('name');

Given the name of a registered subcommand, return a reference to the
subcommand object.  If the subcommand is not registered, returns undef.

=head2 register_command

This is an alias for L<register_subcommand>.

=head2 register_subcommand

    $cmd->register_subcommand( $subcmd_obj );

Register C<$subcmd_obj> as a subcommand under master command C<< $cmd >>.

If C<$subcmd_obj> is not a CLI::Framework::Command, returns undef.  Otherwise,
returns C<$subcmd_obj>.

NOTE: Subcommand names must be unique.  If C<register_subcommand()> is called
with a subcommand having the same name as an existing registered subcommand,
the existing one will be replaced by the new one.

=head1 COMMAND SUBCLASS HOOKS

Just as CLIF Applications have hooks that subclasses can take advantage of,
CLIF Commands are able to influence the command dispatch process via several
hooks.  Subclasses can (and must, in some cases, as noted) override the
following methods:

=head2 name

Class method that takes no arguments and returns the name of the command.  The
default implementation of this method uses the normalized base name of the
package as the command name, e.g. the command defined by the package
My::Application::Command::Xyz would be named 'xyz'.

Subclasses may override this if a different naming scheme is desired.

=head2 option_spec

    sub option_spec {
        (
            [ "verbose|v"   => "be verbose"         ],
            [ "logfile=s"   => "path to log file"   ],
        )
    }

This method should return an option specification as expected by the
Getopt::Long::Descriptive function C< describe_options >.  The option
specification defines what options are allowed and recognized by the command.

Subclasses should override this method if commands accept options (otherwise,
the command will not recognize any options).

=head2 subcommand_alias

    sub subcommand_alias {
        rm  => 'remove',
        new => 'create',
        j   => 'jump',
        r   => 'run',
    }

Subcommands can have aliases to support shorthand versions of subcommand
names.

Subclasses should override this method if subcommand aliases are desired.
Otherwise, the commands will only be recognized by their full names.

=head2 validate

To provide strict validation of a command request, a subclass may override
this method.  Otherwise, validation is skipped.

C<validate> is called during command dispatch as follows:

    $cmd->validate( $cmd_opts, @args );

C<$cmd_opts> is an options hash with received command options as keys and
their values as hash values.

C<@args> is a list of received command arguments.

C<validate> is expected to throw an exception if validation fails.  This
allows your validation routine to provide a context-specific failure message.

NOTE that Getop::Long::Descriptive performs some validation of its own based
on the L<option_spec|/option_spec>.  However, C<validate> allows more
flexibility in validating command options and also allows validation of
arguments.

=head2 notify

If a request for a subcommand is received, the master command itself does not
run().  Instead, its notify() method is called.  This gives the master command
a chance to act before the subcommand is run.

The <notify> method is called as follows:

    $cmd->notify( $subcommand, $cmd_opts, @args );

C<$subcommand> is the subcommand object.

C<$cmd_opts> is the options hash for the subcommand.

C<@args> is the argument list for the subcommand.

=head2 usage_text

If implemented, this method should simply return a string containing usage
information for the command.  It is used automatically to provide
context-specific help.

Implementing this method is optional.  See
L<usage|CLI::Framework::Application/usage> for details on how usage
information is generated within the context of a CLIF application.

=head2 run

This method is responsible for the main execution of the command.  It is
called as follows:

    $output = $cmd->run( $cmd_opts, @args )

C<$cmd_opts> is a pre-validated options hash with command options as keys and
their values as hash values.

C<@args> is a list of the command arguments.

The default implementation of this method simply calls L<usage|usage> to show
help information for the command.  Therefore, subclasses will usually override
C<run()> (Occasionally, it is useful to have a command that does little or
nothing on its own but has subcommands that define the real behavior.  In such
relatively uncommon cases, it may make sense not to override C<run()>).

If an error occurs during the execution of a command via its C<run> method,
the C<run> method code should throw an exception.  The exception will be
caught and handled appropriately by CLIF.

The return value of the C<run> method is treated as data to be output by
the L<render|CLI::Framework::Application/render> method in your CLIF Application
class.  Note that nothing should be printed directly.  Also note that if no
output is produced, the C<run> method should return undef or empty string.

=head1 SUBCLASSING

Inheriting from L<CLI::Framework::Command> to produce new commands is almost
as easy as implementing the purely abstract methods in L<COMMAND SUBCLASS
HOOKS> and overriding the others as necessary for your new command class.
However, there are a few additional details to be aware of...

=head1 METACOMMANDS

CLI::Framework::Command::Meta - Class defining application-aware commands.

This class is a subclass of CLI::Framework::Command.  It defines
"metacommands", commands that are application-aware (and thus, implicitly
aware of all other commands registered within the application).  Metacommands
have methods that set and retrieve the application within which they are
running.  This class exists as a separate class because, with few exceptions,
commands should be independent of the application they are associated with and
should not affect that application.  Metacommands represent the exception to
that rule.

=head2 app

    $app = $command->app();

Return the application object associated with a command object.

=head2 set_app

    $command->set_app( $app );

Set the application object associated with a command object.

=head1 DIAGNOSTICS

=over

=item C<< Missing required param 'command' >>

L<manufacture|manufacture> requires a named parameter C<command>, which
specifies the name of the requested command.

=item C<< Error: failed to require() subcommand from package file '<file path>' >>

L<manufacture|manufacture> failed when trying to C<require()> a subcommand
(a package located in a directory named after the master command).

=item C<< Error: failed to instantiate subcommand '<class>' via method new() >>

Object construction for the subcommand <class> (whose package has already been
C<require()d>) was unsuccessful.

=item C<< Must specify 'command_search_path' for command construction >>

L<manufacture|manufacture> requires the C<command_search_path> parameter when
called as a class method.

=item C<< Error: failed to require() base command from package file '<file path>' >>

L<manufacture|manufacture> failed when trying to C<require()> a "master
command."

=item C<< Error: Cannot instantiate class '<class>' via method new() >>

Object construction for the "master command" <class> was unsuccessful.

=back

=head1 CONFIGURATION & ENVIRONMENT

When called as an object method on an existing Command object "X", L<manufacture>
looks for the named subcommand in the directory path F<X>:

    # Where $x isa X...
    $x->manufacture( command => 'foo' );
    # ...CLIF will search for X/Foo.pm

So remember that subcommands should be given names that explicitly convey
their class hierarchy (e.g. subcommand of C<Do::Something> should be
C<Do::Something::Now> and not Some::Other::Now), and located as such on the
filesystem.

=head1 DEPENDENCIES

Carp

Getopt::Long::Descriptive

Class::ISA

File::Spec

Class::Inspector

CLI::Framework::Exceptions

=head1 SEE ALSO

CLI::Framework::Application

CLI::Framework::Quickstart

CLI::Framework::Tutorial

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009 Karl Erisman (karl.erisman@icainformatics.com), ICA
Informatics. All rights reserved.

This is free software; you can redistribute it and/or modify it under the same
terms as Perl itself. See perlartistic.

=head1 AUTHOR

Karl Erisman (kerisman@cpan.org)

=cut
