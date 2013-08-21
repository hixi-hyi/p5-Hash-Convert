package Hash::Convert;
use 5.008005;
use strict;
use warnings;

use Carp qw(croak);

our $VERSION = "0.01";

sub new {
    my ($class, $rules, $opts) = @_;

    my $allow_combine = [
        [qw/from/],
        [qw/from default/],

        [qw/from via/],
        [qw/from via default/],

        [qw/contain/],
        [qw/contain default/],

        [qw/define/],
    ];
    my $self = bless {
        rules         => undef,
        rules_map     => undef,
        indent        => 1,
        formatter     => Hash::Convert::Formatter->new(),
        allow_cmobine => $allow_combine,
    }, $class;

    $self->_compile($rules);
    $self;
}

sub rules {
    my $self = shift;
    $self->{rules_map};
}

sub convert {
    my ($self, @before) = @_;

    if (@before && scalar @before == 1 && ref $before[0] eq 'HASH') {
        my %after = $self->{rules}->($before[0]);
        return \%after;
    }
    elsif (@before && scalar @before % 2 == 0) {
        my %hash  = @before;
        my %after =  $self->{rules}->(\%hash);
        return %after;
    }
    else {
        croak 'convert require HASH or HASH ref'
    }
}

sub _compile {
    my ($self, $rules) = @_;

    my $hash_body     = $self->_create_hash_body($rules);
    my $hash_like_exp =$self->{formatter}->curly_parentheses($hash_body);

    $self->{rules_map} = $hash_like_exp;
    $self->{rules}     = eval "sub { my \$before = shift; return $hash_like_exp }";
}

sub _validate_cmd {
    my ($self, $cmd_map) = @_;

    for my $combine (@{$self->{allow_cmobine}}) {
        my $valid = [grep { $cmd_map->{$_} } @$combine];

        if ( scalar @$valid == scalar keys %$cmd_map ) {
            return 1;
        }
    }
    return 0;
}

sub _create_hash_body {
    my ($self, $rules) = @_;

    my $after;
    for my $name (sort keys %$rules) {
        my %rule = %{$rules->{$name}};
        my %cmds = map { $_ => 1 } keys %rule;

        my $valid = $self->_validate_cmd(\%cmds);
        unless ($valid) {
            croak sprintf "%s rules invalid combinations (%s)", $name, join(',', sort keys %cmds);
        }

        if ($cmds{from}) {
            if ($cmds{via}) {
                $after .= $self->via($name, \%rule);
            }
            else {
                $after .= $self->from($name, \%rule);
            }
        }
        elsif ($cmds{contain}) {
            $after .= $self->contain($name, \%rule);
        }
        elsif ($cmds{define}) {
            $after .= $self->define($name, \%rule);
        }
        else {
            # not do this
        }
    }
    return $after;
}

sub via {
    my ($self, $name, $rules) = @_;

    my $var_name = $self->_resolve_var_name($rules->{from});
    my $vars = join(', ', @$var_name);
    my $via = sprintf("%s->(%s)", $self->{formatter}->decode_value($rules->{via}), $vars);
    my $hash_exp = $self->{formatter}->hash($name, $via);
    return $self->optional($name, $hash_exp, $rules, $var_name);
}

sub from {
    my ($self, $name, $rules) = @_;

    if (ref $rules->{from} eq 'ARRAY') {
        croak sprintf "multiple value allowed only 'via' rule. ( from => [%s] )", join(', ', map { "'$_'" } @{$rules->{from}} );
    }

    my $before = $self->_resolve_var_name($rules->{from})->[0];
    my $hash_exp = $self->{formatter}->hash($name, $before);
    return $self->optional($name, $hash_exp, $rules, $before);
}

sub contain {
    my ($self, $name, $rules) = @_;
    $self->{formatter}->inc_indent;
    my $hash_body = $self->_create_hash_body($rules->{contain});
    my $value = $self->{formatter}->curly_brace($hash_body);
    $self->{formatter}->dec_indent;
    $value =~ s/\s*$//;
    my $hash_exp = $self->{formatter}->hash($name, $value);
    my $depends = $self->_contain_depends($rules->{contain});

    return $self->optional($name, $hash_exp, $rules, $depends);
}

sub optional {
    my ($self, $name, $value, $rules, $cond) = @_;

    if (exists $rules->{default}) {
        my $default_exp = $self->{formatter}->default($name, $rules->{default});
        return $self->{formatter}->cond_exists($value, $cond, $default_exp);
    }
    else {
        return $self->{formatter}->cond_exists($value, $cond);
    }

}

sub define {
    my ($self, $name, $rules) = @_;

    my $string = $self->{formatter}->decode_value($rules->{define});
    $self->{formatter}->cond_nothing($self->{formatter}->hash($name, $string));
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
            my $vars = $self->_resolve_var_name($from);
            push @depends, @$vars;
        }
    }

    return \@depends;
}

sub _resolve_var_name {
    my ($self, $args) = @_;

    my $vars = $args;
    $vars = [$args] unless (ref $args eq 'ARRAY');

    my @names;
    for my $var (@$vars) {
        if (index($var, '.') == -1) {
            push @names, sprintf "\$before->{%s}", $var;
        }
        else {
            (my $nest_exp = $var) =~ s/\./\}\->\{/g;
            push @names, sprintf "\$before->{%s}", $nest_exp;
        }
    }

    \@names;
}


package
    Hash::Convert::Formatter;
use B::Deparse;
use Data::Dumper qw(Dumper);
$Data::Dumper::Deparse = 1;
$Data::Dumper::Terse = 1;

sub new {
    my $class = shift;

    bless {
        indent  => 1,
        string  => {
            indent => "    ",
            line   => "\n",
        },
    }, $class;
}

sub inc_indent {
    my $self = shift;
    $self->{indent} += 1;
}

sub dec_indent {
    my $self = shift;
    $self->{indent} -= 1;
}

sub cond_nothing {
    my ($self, $value) = @_;
    $self->indent($value);
}

sub cond_exists {
    my ($self, $value, $keys, $default_exp) = @_;
    $keys = [$keys] unless (ref $keys eq 'ARRAY');

    my $pre_indent = $self->{string}->{indent} x ($self->{indent}-1);
    my $indent = $self->{string}->{indent} x $self->{indent};
    my $cond = join(' && ', map { "exists $_" } @$keys);

    if ($default_exp) {
        sprintf "%s(%s)?\n%s(%s):\n%s(%s),\n", $pre_indent, $cond, $indent, $value, $indent, $default_exp;
    }
    else {
        sprintf "%s(%s)?\n%s(%s): (),\n", $pre_indent, $cond, $indent, $value;
    }
}

sub default {
    my ($self, $after, $default) = @_;

    my $default_str;
    unless ($default) {
        $default_str = 'undef';
    }
    elsif (ref $default) {
        $default_str = $self->decode_value($default);
    }
    elsif ($self->_is_number($default)) {
        $default_str = $default;
    }
    else {
        $default_str = "'$default'";
    }
    return sprintf "%s => %s", $after, $default_str;
}

sub decode_value {
    my ($self, $ref) = @_;
    unless (ref $ref) {
        return $ref;
    }

    if (ref $ref eq 'CODE') {
        my $deparse = B::Deparse->new('-P');
        $deparse->ambient_pragmas(strict => 'all', warnings => 'all');
        my $code   = $deparse->coderef2text($ref);
        my $indent = $self->{string}->{indent} x ($self->{indent});
        $code      =~ s/^/$indent/gm;
        $code      =~ s/^$self->{string}->{indent}*//;
        my $coderef_exp = 'sub '.$code;
        return $coderef_exp;
    }
    else { # 'ARRAY', 'HASH'
        my $string_exp = Dumper $ref;
        my $indent = $self->{string}->{indent} x ($self->{indent});
        $string_exp      =~ s/^/$indent/gm;
        $string_exp      =~ s/^$self->{string}->{indent}*//;
        chomp($string_exp);
        return $string_exp;
    }
}

sub hash {
    my ($self, $after, $before) = @_;

    return sprintf "%s => %s", $after, $before;
}

sub indent {
    my ($self, $str) = @_;

    my $indent = $self->{string}->{indent} x $self->{indent};
    return sprintf "%s%s,\n", $indent, $str;
}

sub curly_brace {
    my ($self, $value) = @_;
    my $indent = $self->{string}->{indent} x ($self->{indent} - 1);
    sprintf "{\n%s%s}\n", $value, $indent;
}

sub curly_parentheses {
    my ($self, $value) = @_;
    my $indent = $self->{string}->{indent} x ($self->{indent} - 1);
    sprintf "(\n%s%s)\n", $value, $indent;
}

sub _is_number {
    my ($self, $val) = @_;
    return ( B::svref_2object(\$val)->FLAGS & B::SVp_IOK ) ? 1 : 0;
}

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

