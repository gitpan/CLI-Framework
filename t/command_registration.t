use strict;
use warnings;

use lib 'lib';
use lib 't/lib';

use Test::More qw( no_plan );
use_ok( 'My::Journal' );

my $app = My::Journal->new();

# Register some commands...
ok( my $cmd = $app->register_command( 'console'   ), "register (built-in) 'console' command" );
ok( $cmd->isa( 'CLI::Framework::Command::Console' ), "built-in 'console' command object returned" );
is( $cmd->name(), 'console', 'command name is as expected' );

ok( $cmd = $app->register_command( 'menu'   ), "register (overridden) 'menu' command" );
ok( $cmd->isa( 'My::Journal::Command::Menu' ),
    "application-specific, overridden command returned instead of the built-in 'menu' command" );
is( $cmd->name(), 'menu', 'command name is as expected' );

# Register built-in command to replace custom command 'menu'...
my $builtin_menu = CLI::Framework::Command->manufacture(
    command_search_path => 'CLI/Framework/Command',
    command             => 'menu'
);
ok( $cmd = $app->register_command($builtin_menu),
    "register built-in 'menu' command" );
ok( $cmd->isa( 'CLI::Framework::Command::Menu' ), "built-in 'menu' command object registered in place of existing custom 'menu' command");
is( $cmd->name(), 'menu', 're-registered command name is as expected' );

# Get and check list of all registered commands...
ok( my @registered_cmd_names = $app->get_registered_command_names(),
    'call get_registered_command_names()' );
my @got_cmd_names = sort @registered_cmd_names;
my @expected_cmd_names = sort qw( console menu );
is_deeply( \@got_cmd_names, \@expected_cmd_names,
    'get_registered_command_names() returned expected set of commands that were registered' );

# Check that we can get registered commands by name...
ok( my $console_command = $app->get_registered_command('console'), 'retrieve console command by name' );
ok( $console_command->isa('CLI::Framework::Command::Console'), 'command object is ref to proper class' );
ok( my $menu_command = $app->get_registered_command('menu'), 'retrieve menu command by name' );
ok( $menu_command->isa('CLI::Framework::Command::Menu'), 'command object is a ref to proper class');

__END__

=pod

=head1 PURPOSE

To verify basic CLIF features related to registration of commands.

=cut
