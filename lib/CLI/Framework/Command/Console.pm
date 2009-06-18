package CLI::Framework::Command::Console;
use base qw( CLI::Framework::Command::Meta );

use strict;
use warnings;

our $VERSION = 0.01;

#-------

sub usage_text { 
    q{
    console: invoke interactive command console'
    }
}

sub run {
    my ($self, $opts, @args) = @_;

    my $app = $self->app(); # metacommand is app-aware

    $app->run_interactive( initialize => 1 );

    return;
}

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Command::Console - Built-in CLIF command supporting
interactive mode

=head1 SEE ALSO

CLI::Framework::Command

=cut
