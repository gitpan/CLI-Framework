package My::Journal;
use base qw( CLI::Framework::Application );

use strict;
use warnings;

use lib 't/lib';

use My::Journal::Model;

#-------

sub usage_text {
    q{
    OPTIONS
        --db [path]  : path to SQLite database file for your journal
        -v --verbose : be verbose
        -h --help    : show help

    COMMANDS
        entry       - work with journal entries
        publish     - publish a journal
        tree        - print a tree of only those commands that are currently-registered in your application
        dump        - examine the internals of your application object using Data::Dumper 
        menu        - print command menu
        help        - show application or command-specific help
        console     - start a command console for the application
        list        - list all commands available to the application
    }
}

#-------

sub option_spec {
    (
        [ 'help|h'      => 'show help' ],
        [ 'verbose|v'   => 'be verbose' ],
        [ 'db=s'        => 'path to SQLite database file for your journal' ],
    )
}

sub valid_commands { qw( console list menu dump tree publish entry ) }

sub command_alias {
    {
        h   => 'help',

        e   => 'entry',
        p   => 'publish',

        'list-commands'   => 'list',
        l   => 'list',
        ls  => 'list',
        t   => 'tree',
        d   => 'dump',

        sh  => 'console',
        c   => 'console',
        m   => 'menu',
    }
}

#-------

sub init {
    my ($app, $opts) = @_;

    # Command redirection for --help or -h options...
    $app->set_current_command('help') if $opts->{help};

    # Store App's verbose setting where it will be accessible to commands...
    $app->session( 'verbose' => $opts->{verbose} );

    # Get object to work with database...
    my $db = My::Journal::Model->new( dbpath => 't/db/myjournal.sqlite' );
    
    # ...store object in the application session...
    $app->session( 'db' => $db );
}

#-------
1;

__END__

=pod

=head1 NAME

My::Journal - Demo CLIF application used as a documentation example and for
testing.

=cut
