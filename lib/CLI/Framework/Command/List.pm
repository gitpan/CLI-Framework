package CLI::Framework::Command::List;
use base qw( CLI::Framework::Command::Meta );

use strict;
use warnings;

our $VERSION = 0.01;

#-------

sub usage_text { 
    q{
    list: print a concise list of the names of all commands available to the application
    }
}

sub run {
    my ($self, $opts, @args) = @_;

    my $app = $self->app(); # metacommand is app-aware

    # If interactive, exclude commands that do not apply in interactive mode...
    my @command_set = $app->is_interactive()
        ? $app->get_interactive_commands()
        : $app->valid_commands();

    my $result = join(', ', map { lc $_ } @command_set ) . "\n";
    return $result;
}

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Command::List - Built-in CLIF command to print a list of
commands available to the running application

=head1 SEE ALSO

CLI::Framework::Command

=cut
