package CLI::Framework::Command::Alias;
use base qw( CLI::Framework::Command::Meta );

use strict;
use warnings;

our $VERSION = 0.01;

#-------

sub usage_text {
    q{
    alias [<cmd-name>]: show command aliases
                        [and subcommand aliases for <cmd-name>, if given]

    ARGUMENTS
        <cmd-name>: if specified, show aliases for this command only and show
                    its subcommand aliases
    }
}

sub validate {
    my ($self, $cmd_opts, @args) = @_;

    my $app = $self->get_app();

    # If an argument is provided, it should be a valid command name...
    if( @args ) {
        $app->is_valid_command_name( $args[0] )
            or die "'", $args[0], "' is not a valid command\n";
    }
    return 1;
}

sub run {
    my ($self, $opts, @args) = @_;

    my $app = $self->get_app();
    my %cmd_alias_to_name = $app->command_alias();
    my $cmd = shift @args;

    # Alias command only recognizes one argument: a top-level command...
    if( $cmd ) {
        # Get formatted display of aliases to command...
        my $summary = $self->_cmd_alias_hash_to_summary(
            \%cmd_alias_to_name,
            target => $cmd
        );
        # Get formatted display of aliases to subcommand...
        my $cmd_object = $app->registered_command_object( $cmd )
            || $app->register_command( $cmd );
        my %subcommand_alias = $cmd_object->subcommand_alias();
        my $subcommand_summary = $self->_cmd_alias_hash_to_summary(
            \%subcommand_alias,
        );
        if( $subcommand_summary ) {
            $summary .= sprintf( "\n%15s '%s':\n", 'SUBCOMMANDS of command', $cmd );
            $summary .= sprintf( "\n%s", $subcommand_summary );
        }
        return $summary;
    }
    else {
        my $summary = $self->_cmd_alias_hash_to_summary(
            \%cmd_alias_to_name,
        );
        return $summary;
    }
}

sub _cmd_alias_hash_to_summary {
    my ($self, $aliases, %param) = @_;

    my $target = $param{target};

#FIXME: if in interactive mode, need to omit non-interactive commands

    my %name_to_alias_set;
    while( my ($alias, $name) = each %$aliases ) {
        next if $alias =~ /^\d+$/;  # ignore numerical aliases
        next if $target && $name ne $target;
        push @{ $name_to_alias_set{$name} }, $alias;
    }
    return $self->format_name_to_aliases_hash( \%name_to_alias_set );
}

sub format_name_to_aliases_hash {
    my ($self, $h, $indent) = @_;

    $indent ||= 10;
    my $format = '%'.$indent."s: %s\n";

    my @output;
    for my $command (keys %$h) {
        push @output, sprintf
            $format, $command, join( ', ', @{$h->{$command}} );
    }
    my @output_sorted = sort {
        my $name_a = substr( $a, index($a, ':') );
        my $name_b = substr( $b, index($b, ':') );
        $name_a cmp $name_b;
    } @output;
    return join( '', @output );
}

__END__

=pod

=head1 NAME

CLI::Framework::Command::Alias - CLIF built-in command to display the command
aliases that are in effect for the running application and its commands

=cut
