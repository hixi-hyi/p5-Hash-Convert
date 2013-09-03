package Hash::Convert;
use 5.008005;
use strict;
use warnings;

use Carp qw(croak);

our $VERSION = "0.01";

my $allow_combine = [
    [qw/from/],
    [qw/from default/],

    [qw/from via/],
    [qw/from via default/],

    [qw/contain/],
    [qw/contain default/],

    [qw/define/],
];

sub new {
    my ($class, $rules) = @_;

    my $self = bless {
        rules         => $rules,
    }, $class;

    $self->_prepare($rules);

    $self;
}

sub _validate_cmd {
    my ($self, $cmd_map) = @_;

    for my $combine (@{$allow_combine}) {
        my $valid = [grep { $cmd_map->{$_} } @$combine];

        if ( scalar @$valid == scalar keys %$cmd_map ) {
            return 1;
        }
    }
    return 0;
}

sub _prepare {
    my ($self, $rules) = @_;

    for my $name (sort keys %$rules) {
        my $rule = $rules->{$name};
        my %cmds = map { $_ => 1 } keys %{$rule};

        unless ($self->_validate_cmd(\%cmds)) {
            croak sprintf "%s rules invalid combinations (%s)", $name, join(',', sort keys %cmds);
        }
        if ($cmds{contain}) {
            $self->_prepare($rule->{contain});
            $rule->{depends} = $self->_contain_depends($rule->{contain});
            next;
        }

        if ($cmds{from} && not $cmds{via}) {
            if ( (ref $rule->{from} eq 'ARRAY') && (scalar @{$rule->{from}} != 1) ) {
                croak sprintf "multiple value allowed only 'via' rule. ( from => [%s] )", join(', ', map { "'$_'" } @{$rule->{from}} );
            }
        }
        my $from = $rule->{from};
        $from = [$from] if ($from && ref $from ne 'ARRAY');
        $rule->{depends} = $from;
    }
}

sub convert {
    my ($self, @before) = @_;

    if (@before && scalar @before == 1 && ref $before[0] eq 'HASH') {
        my $after = $self->_process($self->{rules}, $before[0]);
        return $after;
    }
    elsif (@before && scalar @before % 2 == 0) {
        my %hash  = @before;
        my $after =  $self->_process($self->{rules}, \%hash);
        return %{$after};
    }
    else {
        croak 'convert require HASH or HASH ref'
    }
}

sub _process {
    my ($self, $rules, $before) = @_;

    my %after;
    for my $name (sort keys %$rules) {
        my $rule = $rules->{$name};

        if (exists $rule->{from} && exists $rule->{via}) {
            $self->via($name, $rule, $before, \%after);
        }
        elsif (exists $rule->{from}) {
            $self->from($name, $rule, $before, \%after);
        }
        elsif (exists $rule->{contain}) {
            $self->contain($name, $rule, $before, \%after);
        }
        elsif (exists $rule->{define}) {
            $self->define($name, $rule, $before, \%after);
        }
        else {
            # not do this
        }
    }
    return \%after;
}

sub _is_exists {
    my ($self, $before, $names) = @_;

    my $exists_size = grep { $before->{$_} } @$names;
    if ($exists_size == scalar @$names) {
        return 1;
    }
    return 0;
}


sub from {
    my ($self, $name, $rule, $before, $after) = @_;

    if ($self->_is_exists($before, $rule->{depends})) {
        $after->{$name} = $before->{$rule->{depends}->[0]};
    } elsif (exists $rule->{default}) {
        $after->{$name} = $rule->{default};
    }
}

sub via {
    my ($self, $name, $rule, $before, $after) = @_;

    if ($self->_is_exists($before, $rule->{depends})) {
        my @args = map { $before->{$_} } @{$rule->{depends}};
        $after->{$name} = $rule->{via}->(@args);
    } elsif (exists $rule->{default}) {
        $after->{$name} = $rule->{default};
    }
}

sub define {
    my ($self, $name, $rule, $before, $after) = @_;
    $after->{$name} = $rule->{define};
}

sub contain {
    my ($self, $name, $rule, $before, $after) = @_;

    if ($self->_is_exists($before, $rule->{depends})) {
        $after->{$name} = $self->_process($rule->{contain}, $before);
    } elsif (exists $rule->{default}) {
        $after->{$name} = $rule->{default};
    }
}

sub _contain_depends {
    my ($self, $rules) = @_;
    my @depends = ();

    for my $rule (sort values %$rules) {

        my $contain = $rule->{contain};
        if ($contain) {
            my $nested = $self->_contain_depends($contain);
            push @depends, @$nested;
        }

        my $from = $rule->{from};
        if ($from) {
            my $vars = $from;
            $vars = [$vars] if (ref $from ne 'ARRAY');
            push @depends, @$vars;
        }
    }

    return \@depends;
}

#sub _resolve_var_name {
#    my ($self, $args) = @_;
#
#    my $vars = $args;
#    $vars = [$args] unless (ref $args eq 'ARRAY');
#
#    my @names;
#    for my $var (@$vars) {
#        if (index($var, '.') == -1) {
#            push @names, sprintf "\$before->{%s}", $var;
#        }
#        else {
#            (my $nest_exp = $var) =~ s/\./\}\->\{/g;
#            push @names, sprintf "\$before->{%s}", $nest_exp;
#        }
#    }
#
#    \@names;
#}
#

1;
__END__

=encoding utf-8

=head1 NAME

Hash::Convert - Rule based Hash converter.

=head1 SYNOPSIS

  #!/usr/bin/env perl
  use strict;
  use warnings;
  use Hash::Convert;

  my $rules = {
      visit   => { from => 'created_at' },
      count   => { from => 'count', via => sub { $_[0] + 1 }, default => 1 },
      visitor => {
          contain => {
              name => { from => 'name' },
              mail => { from => 'mail' },
          },
          default => {
              name => 'anonymous',
              mail => 'anonymous',
          }
      },
      price => {
          from => [qw/item.cost item.discount/],
          via => sub {
              my $cost     = $_[0];
              my $discount = $_[1];
              return $cost * ( (100 - $discount) * 0.01 );
          },
      },
  };

  my $converter = Hash::Convert->new($rules);

  my $before = {
      created_at => time,
      count      => 1,
      name       => 'hixi',
      mail       => 'hixi@cpan.org',
      item => {
          name     => 'chocolate',
          cost     => 100,
          discount => 10,
      },
  };
  my $after = $converter->convert($before);
  print Dumper $after;
  #{
  #    'visitor' => {
  #        'mail' => 'hixi@cpan.org',
  #        'name' => 'hixi'
  #    },
  #    'count' => 2,
  #    'visit' => '1377019766',
  #    'price' => 9000
  #}

=head1 DESCRIPTION

Hash::Convert is can define hash converter based on the rules.

=head1 Function

=head2 convert

Convert hash structure from before value.

  my $rules = {
      mail => { from => 'email' }
  };
  my $converter = Hash::Convert->new($rules);
  my $before = { email => 'hixi@cpan.org' };
  my $after  = $converter->convert($before);
  #{
  #  mail => 'hixi@cpan.org',
  #}

=head2 rules

Print rules of internal.

  my $rules = {
      version => { from => 'version', via => sub { $_[0] + 1 }, default => 1 },
  };
  my $converter = Hash::Convert->new($rules);
  print $converter->rules;
  #(
  #(exists $before->{version})?
  #    (version => sub {
  #        $_[0] + 1;
  #    }->($before->{version})):
  #    (version => 1),
  #)

=head1 Rules

=head2 Command

=over

=item from

  my $rules = { visit => { from => 'created_at' } };
  #(
  #(exists $before->{created_at})?
  #    (visit => $before->{created_at}): (),
  #)

=item from + via

`via` add after method toward `from`.
`via` can receive multiple args from `from.

Single args

  my $rules = { version => { from => 'version', via => sub { $_[0] + 1 } } };
  #(
  #(exists $before->{version})?
  #    (version => sub {
  #        $_[0] + 1;
  #    }->($before->{version})): (),
  #)

Multi args

  my $rules = { price => {
      from => [qw/cost discount/],
      via => sub {
          my $cost     = $_[0];
          my $discount = $_[1];
          return $cost * (100 - $discount);
  }};
  #(
  #(exists $before->{item}->{cost} && exists $before->{item}->{discount})?
  #    (price => sub {
  #        my $cost = $_[0];
  #        my $discount = $_[1];
  #        return $cost * (100 - $discount);
  #    }->($before->{item}->{cost}, $before->{item}->{discount})): (),
  #)

=item contain

  my $rules = { visitor => {
      contain => {
          name => { from => 'name' },
          mail => { from => 'mail' },
      }
  }};
  #(
  #(exists $before->{name} && exists $before->{mail})?
  #    (visitor => {
  #    (exists $before->{mail})?
  #        (mail => $before->{mail}): (),
  #    (exists $before->{name})?
  #        (name => $before->{name}): (),
  #    }): (),
  #)

=back

=head2 Others expression

=over

=item default

default can add all command (`from`, `from`+`via`, `contain`) .

  my $rules = { visitor => {
      contain => {
          name => { from => 'name' },
          mail => { from => 'mail' },
      },
      default => {
          name => 'anonymous',
          mail => 'anonymous',
      }
  }};
  #(
  #(visitor => {
  #(exists $before->{mail})?
  #    (mail => $before->{mail}): (),
  #(exists $before->{name})?
  #    (name => $before->{name}): (),
  #}):
  #(visitor => {
  #  'name' => 'anonymous',
  #  'mail' => 'anonymous'
  #}),
  #)

=item dot notation

`dot notation` make available nested hash structure.

  my $rules = { price => {
      from => [qw/item.cost item.discount/],
      via => sub {
          my $cost     = $_[0];
          my $discount = $_[1];
          return $cost * ( (100 - $discount) * 0.01 );
      },
  }};
  #(
  #(exists $before->{item}->{cost} && exists $before->{item}->{discount})?
  #    (price => sub {
  #        my $cost = $_[0];
  #        my $discount = $_[1];
  #        return $cost * ( (100 - $discount) * 0.01 );
  #    }->($before->{item}->{cost}, $before->{item}->{discount})): (),
  #)

=back


=head1 LICENSE

Copyright (C) Hiroyoshi Houchi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Hiroyoshi Houchi E<lt>hixi@cpan.orgE<gt>

=cut

