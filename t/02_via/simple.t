use strict;
use warnings;
use lib 't/';
require 'util/verify.pl';

use Test::More;

verify(
    rules   => { expire => { from => 'time', via => sub { $_[0] + 100 }} },
    input   => { time   => 10000 },
    expects => { expire => 10100 },
    desc    => 'via simple',
);

verify(
    rules   => { price => { from => [qw/cost tax/], via => sub { $_[0] * (1+$_[1]) } } },
    input   => { cost => 100, tax => 0.05 },
    expects => { price => 105 },
    desc    => 'via multi',
);

done_testing;
