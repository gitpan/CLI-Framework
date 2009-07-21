use strict;
use warnings;

use lib 'lib';
use lib 't/lib';

use Test::More tests => 1;

use File::Spec;
open( my $devnull, '>', File::Spec->devnull() );
select $devnull;

my $SHARED_KEY = 'shared-key';
my $SHARED_VALUE = '*** producer was here ***';

my $app = Test::Of::Session::Persistence->new();
@ARGV = qw( prod a b );
$app->run();

@ARGV = qw( cons );
$app->run();

is( $app->cache->get( $SHARED_KEY ), $SHARED_VALUE, 'values stored in cache persist' );

close $devnull;

############################
#
#   APPLICATION CLASS
#
############################

package Test::Of::Session::Persistence;
use base qw( CLI::Framework::Application );

use strict;
use warnings;

sub command_map {
    {
        console             => 'CLI::Framework::Command::Console',
        'session-producer'  => 'Producer',
        'session-consumer'  => 'Consumer',
    }
}

sub command_alias {
    'prod' => 'session-producer',
    'cons' => 'session-consumer',
}

############################
#
#   COMMAND CLASSES
#
############################

# command to WRITE TO the cache
package Producer;
use base qw( CLI::Framework::Command );

use strict;
use warnings;

sub run {
    my ($self, $opts, @args) = @_;

    # If args provided, treat them as set of key-value pairs to be added to
    # the cache...
    die 'zero or even number of args required' if @args % 2;
    my %kv = @args;
    for my $key (keys %kv) {
        $self->cache->set( $key => $kv{$key} );
    }
    $self->cache->set($SHARED_KEY => $SHARED_VALUE);

    return '';
}

#-------

# command to READ FROM the cache
package Consumer;
use base qw( CLI::Framework::Command );

use strict;
use warnings;

sub run {
    my ($self, $opts, @args) = @_;
    my $value_passed_by_producer = $self->cache->get( $SHARED_KEY );
    return $value_passed_by_producer;
}

#-------

__END__

=pod

=head1 PURPOSE

Test session persistence in CLIF

=cut
