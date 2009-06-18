package CLI::Framework::Command::Menu;
use base qw( CLI::Framework::Command::Meta );

use strict;
use warnings;

our $VERSION = 0.01;

#-------

sub usage_text { 
    q{
    menu: menu of available commands
    }
}

sub run {
    my ($self, $opts, @args) = @_;

    return $self->menu_txt();
}

sub menu_txt {
    my ($self) = @_;

    my $app = $self->app(); # metacommand is app-aware

    my $menu;
    $menu = "\n" . '-'x13 . "menu" . '-'x13 . "\n";
    for my $c ( $app->get_interactive_commands() ) {
        $menu .= sprintf("\t%s\n", $c)
    }
    $menu .= '-'x30 . "\n";
    return $menu;
}

sub line_count {
    my ($self) = @_;

    my $menu = $self->menu_txt();
    my $line_count = 0;
    $line_count++ while $menu =~ /\n/g;
    return $line_count;
}

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Command::Menu - Built-in CLIF command to show a command menu
including the commands that are available to the running application

=head1 SEE ALSO

CLI::Framework::Command

=cut
