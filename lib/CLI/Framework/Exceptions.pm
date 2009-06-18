package CLI::Framework::Exceptions;

use strict;
use warnings;

our $VERSION = 0.01;

use Exception::Class (
    'CLI::Framework::Exception',

    'CLI::Framework::Exception::AppOptsParsingException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failed parsing of application options',
    },
    'CLI::Framework::Exception::AppOptsValidationException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failed validation of application options',
    },
    'CLI::Framework::Exception::AppInitException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failed application initialization',
    },
    'CLI::Framework::Exception::AppArgumentException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Invalid application arguments',
    },
    'CLI::Framework::Exception::CmdOptsParsingException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failed parsing of command options',
    },
    'CLI::Framework::Exception::CmdValidationException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failed validation of command options/arguments',
    },
    'CLI::Framework::Exception::CmdRunException' => {
        isa => 'CLI::Framework::Exception',
        description => 'Failure to run command',
    },
);

#-------
1;

__END__

=pod

=head1 NAME

CLI::Framework::Exceptions - Exceptions used by CLIF.

=head1 SEE ALSO

L<CLI::Framework::Application>

=cut
