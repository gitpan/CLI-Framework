package My::Journal::Command::Menu;
use base qw( CLI::Framework::Command::Menu );

use strict;
use warnings;

sub usage_text {
    q{
    menu (My::Journal command overriding the built-in): test of overriding a built-in command...'
    }
}

sub menu_txt {
    my ($self) = @_;

    my $app = $self->app();

    # Build a numbered list of visible commands...
    my @cmd = $app->get_interactive_commands();

    my $txt;
    my $augmented_aliases = $app->command_alias();
    for my $i (0..$#cmd) {
        $txt .= $i+1 . ') ' . $cmd[$i] . "\n";
        $augmented_aliases->{$i+1} = $cmd[$i];
    }
    # Add numerical aliases corresponding to menu options to the original
    # command aliases defined by the application...
    no strict 'refs'; no warnings;
    *{ (ref $app).'::command_alias' } = sub { $augmented_aliases };

    return "\n".$txt;
}

#-------
1;

__END__

=pod

=head1 NAME

My::Journal::Command::Menu

=head1 PURPOSE

A demonstration and test of overriding a built-in CLIF Menu command.

=head1 NOTES

This example replaces the built-in command menu.  The particular replacement
is useless, but shows how such a replacement could be done.

Note that overriding the menu command is a special case of overriding a
built-in command and it is necessary that the overriding command inherit from
the built-in menu class, CLI::Framework::Command::Menu.

This example just changes the way the menu looks.

=cut
