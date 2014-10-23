package My::Journal::Command::Entry;
use base qw( CLI::Framework::Command );

use strict;
use warnings;

#-------

sub usage_text {
    q{
    entry [--date=yyyy-mm-dd] [subcommands...]

    OPTIONS
       --date=yyyy-mm-dd:       set date that entry appiles to
   
    ARGUMENTS (subcommands)
        add:                    add an entry
        remove:                 remove an entry
        modify:                 modify an entry
        search:                 search for entries by regex; show summary
        print:                  display full text of entries
    }
}

sub option_spec {
    return unless ref $_[0] eq __PACKAGE__; # non-inheritable behavior
    (
        [ 'date=s' => 'date that entry applies to' ],
    )
}

sub subcommand_alias {
    return unless ref $_[0] eq __PACKAGE__; # non-inheritable behavior
    {
        a   => 'add',
        s   => 'search',
        p   => 'print',

        rm  => 'remove',
        del => 'remove',
        rem => 'remove',

        m   => 'modify',
        mod => 'modify',
    }
}

sub validate {
    my ($self, $opts, @args) = @_;
    return unless ref $_[0] eq __PACKAGE__; # non-inheritable behavior

    # ...
}

sub notify {
    my ($self, $subcommand, $opts, @args ) = @_;
    return unless ref $_[0] eq __PACKAGE__; # non-inheritable behavior

    # ...
}

#-------

#
# Inline subcommand example...
#
# NOTE that the 'search' subcommand is defined inline in the same package
# file as its master commnd, 'entry.'
#
# This is supported as an alternative to defining the subcommand in its
# own separate package file.
#

package My::Journal::Command::Entry::Search;
use base qw( My::Journal::Command::Entry );

use strict;
use warnings;

sub usage_text {
    q{
    entry search --regex=<regex> [--tag=<tag>]: search for journal entries
    }
}

sub option_spec {
    (
        [ 'regex=s' => 'regex' ],
        [ 'tag=s@'   => 'tag' ],
    )
}

sub validate {
    my ($self, $opts, @args) = @_;
    die "missing required option 'regex'\n" unless $opts->{regex};
}

sub run {
    my ($self, $opts, @args) = @_;

    my $regex = $opts->{regex};
    my $tags = $opts->{tag};

    warn "searching...\n" if $self->session('verbose');

    my $db = $self->session('db');  # model class object

    # Show a brief summary of truncated entries with their ids...
    my @tagged_entries;
    for my $tag ( @$tags ) {
        push @tagged_entries, $db->entries_by_tag($tag);
    }
    my @matching;
    for my $entry (@tagged_entries) {
        if( $entry->{entry_text} =~ /$regex/m ) {
            my $entry_summary = sprintf "%10d: %s",
                $entry->{id}, substr( $entry->{entry_text}, 0, 80 );
            push @matching, $entry_summary;
        }
    }
    return join "\n", @matching;
}

#-------
1;

__END__

=pod

=head1 NAME 

My::Journal::Command::Entry - Command to work with journal entries

=head2 My::Journal::Command::Entry::Search

Subcommand to search for journal entries

=cut
