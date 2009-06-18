package My::DemoNoUsage;
use base qw( CLI::Framework::Application );

use lib 'lib';
use lib 't/lib';

use strict;
use warnings;

sub option_spec {
    (
        [ "arg1|o=s" => "arg1" ],
        [ ],
        [ "arg2|t=s" => "arg2" ]
    )
}

sub valid_commands { qw( tree a ) }

#-------
1;

__END__

=pod

=head1 NAME

My::DemoNoUsage - Test the case where no usage_text() is provided by the CLIF Application class.

=cut
