use strict;
use warnings;
use lib 't/';
require 'util/verify.pl';

use Test::More;

verify(
    rules   => { created_at => { from => 'time' } },
    input   => { time => '10000' },
    expects => { created_at => '10000' },
    desc    => 'simple',
);

verify_error(
    rules => { error => { from => [qw/args0 args1/] } },
    input => {},
    error => "multiple value allowed only 'via' rule.",
    desc  => 'multiple value',
);

done_testing;
