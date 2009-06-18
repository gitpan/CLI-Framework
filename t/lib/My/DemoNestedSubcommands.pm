package My::DemoNestedSubcommands;
use base qw( CLI::Framework::Application);

use strict;
use warnings;

sub usage_text {
    q{
    Demo app to test nested subcommands...
    }
}

sub command_search_path { 'My/DemoNestedSubcommands' }

sub valid_commands {
    qw(
        tree list
        command0 command0_0 command0_1 command0_1_0
        command1 command1_0 command1_1 command1_1_0
    )
}

#-------
1;

__END__

=pod

=head1 PURPOSE

=cut
