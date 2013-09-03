use strict;
use warnings;

use Test::More;
use Test::Exception;
use Hash::Convert;

sub verify {
    my (%specs) = @_;
    my ($rules, $input, $expects, $desc) = @specs{qw/rules input expects desc/};

    subtest $desc => sub {
        my $converter = Hash::Convert->new($rules);
        my $result = $converter->convert($input);
        is_deeply $result, $expects;
        note explain $result;
        done_testing;
    };
}

sub verify_hash {
    my (%specs) = @_;
    my ($rules, $input, $expects, $desc) = @specs{qw/rules input expects desc/};

    subtest $desc => sub {
        my $converter = Hash::Convert->new($rules);
        my %result = $converter->convert(%{$input});
        is_deeply \%result, $expects;
        note explain \%result;
        done_testing;
    };
}

sub verify_error {
    my (%specs) = @_;
    my ($rules, $input, $error, $desc) = @specs{qw/rules input error desc/};

    subtest $desc => sub {
        throws_ok {
            my $converter = Hash::Convert->new($rules);
            $converter->convert($input);
        } qr/$error/;
        done_testing;
    };
}

1;
