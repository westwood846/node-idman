package Graph::Man::Algorithm::Bird;
use strict;
use warnings;
use feature qw(fc);
use base 'Graph::Man::Algorithm';
use Getopt::Long qw(GetOptionsFromArray);
use List::Util qw(max);
use Memoize;
use Text::Levenshtein::XS qw(distance);


sub make_alternation {
    return join '|', map { quotemeta } @_;
}

our @TERMS = qw(administrator admin. support development
                dev. developer maint. maintainer);

our @SUFFIXES = qw(mr. mrs. miss ms. prof. pr. dr. ir. rev.
                   ing. jr. d.d.s. ph.d. capt. lt.);

our $TERM   = qr/\b${\make_alternation(@TERMS)}\b/;
our $SUFFIX = qr/${\make_alternation(@SUFFIXES)}$/;


memoize 'normalized_distance';

sub normalized_distance {
    my ($str1, $str2) = @_;
    return 0 unless length($str1) && length($str2);
    return 1 - distance($str1, $str2) / max(length $str1, length $str2);
}

sub normalize {
    my ($str) = @_;
    $str =  fc $str;
    $str =~ s/$TERM//g;
    $str =~ s/$SUFFIX//g;
    $str =~ s/\pP//g;
    $str =~ s/\s+/ /g;
    return $str;
}

sub initial_and_rest {
    my ($str, $initial, $rest) = @_;

    my $index = index $str, $rest;
    return if $index == -1;

    substr $str, $index, length($rest), '';
    return index($str, substr $initial, 0, 1) != -1;
}


sub new {
    my ($class, @args) = @_;

    my $threshold = $ENV{GRAPHMAN_THRESHOLD};
    GetOptionsFromArray(\@args, 'threshold|t=f' => \$threshold)
        or die "$class: error parsing arguments.\n";

    unless ($threshold > 0 && $threshold <= 1) {
        my $got = defined($threshold) ? "'$threshold'" : 'nothing';
        die "$class: a threshold > 0 and <= 1 is required, but I got $got.\n",
            "Specify it via `--threshold` on the command line or the ",
            "`GRAPHMAN_THRESHOLD` environment variable.\n",
    }

    return bless {artifacts => {}, threshold => $threshold}, $class;
}


sub _save_artifact {
    my ($self, $str) = @_;

    if (!$self->{artifacts}{$str}) {
        my %artifact;

        if ($str =~ /^(?<first>\S+)\s+(?<last>\S+)$/
        ||  $str =~ /^(?<last>\S+)\s*,\s*(?<first>\S+)$/) {
            %artifact = (
                type  => 'name',
                first => normalize($+{first}),
                last  => normalize($+{last}),
                full  => normalize($+{full} // $str),
            );
        }
        else {
            my $alias = normalize($str =~ /^([^@]+)@/ ? $1 : $str);
            return unless length $alias;
            %artifact = (
                type  => 'alias',
                alias => $alias,
            );
        }

        $self->{artifacts}{$str} = \%artifact;
    }
}


sub process_artifacts {
    my ($self, @artifacts) = @_;
    $self->_save_artifact($_) for @artifacts;
    return @artifacts;
}


sub _similar {
    my ($self, $str1, $str2) = @_;
    return normalized_distance($str1, $str2) >= $self->{threshold};
}

sub _cmp_name_name {
    my ($self, $a1, $a2) = @_;
    return $self->_similar($a1->{first}, $a2->{first})
        && $self->_similar($a1->{last }, $a2->{last })
        || $self->_similar($a1->{full }, $a2->{full });
}

sub _cmp_alias_alias {
    my ($self, $a1, $a2) = @_;
    return length($a1->{alias}) >= 3
        && length($a2->{alias}) >= 3
        && $self->_similar($a1->{alias}, $a2->{alias});
}

sub _cmp_name_alias {
    my ($self, $a1, $a2) = @_;
    my ($first, $last)   = @{$a1}{'first', 'last'};
    my  $alias            = $a2->{alias};

    return length($first) >= 2
        && length($last ) >= 2
        && (initial_and_rest($alias, $first, $last )
         || initial_and_rest($alias, $last,  $first)
         || index($alias, $first) != -1 && index($alias, $last) != -1);
}

sub _cmp_alias_name {
    my ($self, $a1, $a2) = @_;
    return $self->_cmp_name_alias($a2, $a1);
}


sub artifacts_equal {
    my $self      = shift;
    my ($a1, $a2) = @{$self->{artifacts}}{@_};
    return unless $a1 && $a2;

    my $method = "_cmp_$a1->{type}_$a2->{type}";
    return $self->$method($a1, $a2);
}


1;
