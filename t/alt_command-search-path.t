use strict;
use warnings;

use lib 'lib';
use lib 't/lib';

use Test::More tests => 2;

use My::DemoAltSearchPath;

my $app = My::DemoAltSearchPath->new();
my $command_name = 'x';
@ARGV = ( $command_name );

ok( $app->run(),
    'successful exit status from run() when invoking a user-defined command '.
    'located in a non-standard command search path' );

is( $app->get_current_command(), $command_name,
    "correct command ($command_name) was run" );

__END__

=pod

=head1 PURPOSE

=cut
