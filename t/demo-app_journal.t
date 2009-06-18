use strict;
use warnings;

use lib 'lib';
use lib 't/lib';

use Test::More qw( no_plan );
use My::Journal;

my $app = My::Journal->new();

#~~~~~~~
close STDOUT;
open ( STDOUT, '>', File::Spec->devnull() );
#~~~~~~~

@ARGV = qw( --verbose entry list) unless @ARGV;

#print "\n==== running My::Journal in non-interactive mode via script $0 with \@ARGV = (", join(' ', @ARGV), ")...\n\n";
ok( my $rv = My::Journal->run(), "run My::Journal in non-interactive mode via script $0 with \@ARGV = (" . join(' ', @ARGV) . ")..." );

#print "\n==== running My::Journal in interactive mode...\n";
#my $rv = My::Journal->run_interactive( invalid_request_threshold => 3 );

#-------

__END__

=pod

=head1 PURPOSE

To demonstrate CLIF using an example CLIF-derived application.

=cut
