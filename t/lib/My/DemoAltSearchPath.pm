package My::DemoAltSearchPath;
use base qw( CLI::Framework::Application );

use strict;
use warnings;
use Carp;

sub command_search_path { 'My/Command/Shared' }

sub valid_commands { qw( console tree x ) }

#-------
1;

__END__

=pod

=head1 PURPOSE

An application to test the use of a command search path that differs from the
default (see L<CLI::Framework::Application/command_search_path>).

=cut
