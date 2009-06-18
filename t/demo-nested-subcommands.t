use strict;
use warnings;

use lib 'lib';
use lib 't/lib';

use Test::More qw( no_plan );
use My::DemoNestedSubcommands;

#~~~~~~
close STDOUT;
open ( STDOUT, '>', File::Spec->devnull() );
#~~~~~~

@ARGV = qw( tree );
ok( my $app = My::DemoNestedSubcommands->new(),
    'My::DemoNestedSubcommands->new()' );
ok( $app->register_command( 'command0' ),
    'register command0' );
ok( $app->register_command( 'command1' ),
    'register command1' );

#FIXME: check the class hierarchy for registered commands, ensuring that
#parent-child relationships are as expected:
#        command1
#            command1_0
#            command1_1
#                command1_1_0
#        command0
#            command0_0
#            command0_1
#                command0_1_0

ok( $app->run(), 'run()' );

__END__

=pod

=head1 PURPOSE

=cut
