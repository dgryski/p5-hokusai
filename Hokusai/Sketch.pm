package Hokusai::Sketch;

use warnings;
use strict;

use CountMin;

use constant defaultSize => 18;

sub new {

    my ($class, $epoch0, $windowSize) = @_;

    my $self = {
        sk => newsketch(defaultSize),
        epoch0 => $epoch0,
        endEpoch => $epoch0 + $windowSize,
        windowSize => $windowSize,
        items => [],
        times => [],
        itemtimes => [],
    };

    bless $self, $class;

    return $self;
}


sub newsketch {
    my $sz = shift;
    return CountMin::sketch_new(1 << $sz, 4);
}


sub add {
    my ($self, $epoch, $s, $count) = @_;

    if ($epoch < $self->{endEpoch}) {
        CountMin::sketch_add($self->{sk}, $s, $count);
        return;
    }

    $self->{timeUnits}++;
    $self->{endEpoch} += $self->{windowSize};

    # Algorithm 3 -- Item Aggregation
    my $ln = scalar @{$self->{items}};
    my $l = ilog2($self->{timeUnits} - 1);
    for (my $k=1;$k<$l;$k++) {
		my $sk = $self->{items}->[$ln - (1 << $k)];
                CountMin::sketch_compress($sk);
    }
    push @{$self->{items}}, CountMin::sketch_clone($self->{sk});

    # Algorithm 2 -- Time Aggregation
    $l = 0;
    while ($self->{timeUnits} % (1 << $l) == 0) {
            $l++;
    }

    my $m = CountMin::sketch_clone($self->{sk});

    for (my $j=0;$j<$l;$j++) {
        my $t = CountMin::sketch_clone($m);
        if (scalar @{$self->{times}} <= $j) {
            push @{$self->{times}}, newsketch(defaultSize);
        }

        my $mj = $self->{times}->[$j];

        CountMin::sketch_merge($m, $mj);

        $self->{times}->[$j] = $t;
    }

    # Algorithm 4 -- Item and Time Aggregation

    if ($self->{timeUnits} >= 2) {
        my $ssk = CountMin::sketch_clone($self->{times}->[0]);

        for (my $j=0; $j < $l; $j++) {
            CountMin::sketch_compress($ssk);
            my $t = CountMin::sketch_clone($ssk);

            if (scalar @{$self->{itemtimes}} <= $j) {
                push @{$self->{itemtimes}}, newsketch(defaultSize - $j - 1);
            }

            my $bj = $self->{itemtimes}->[$j];
            CountMin::sketch_merge($ssk, $bj);
            $self->{itemtimes}->[$j] = $t;
        }
    }

    $self->{sk} = newsketch(defaultSize);

    CountMin::sketch_add($self->{sk}, $s, 1);
}

sub count {

    my ($self, $epoch, $s) = @_;

    my $t = int(($epoch - $self->{epoch0}) / $self->{windowSize});

    if ($t == $self->{timeUnits}) {
        return CountMin::sketch_count($self->{sk}, $s);
    }

    # Algorithm 5

    # how far in the past are we?
    my $past = $self->{timeUnits} - $t;

    # how many bins wide is this sketch?
    my $width;
    if ($past <= 2) {
        $width = defaultSize;
    } else {
        $width = defaultSize - ilog2($past-1) + 1;
    }


    my $avals = CountMin::sketch_values($self->{items}->[$t], $s);

    my $mina = $avals->[0];

    for (@$avals) {
        if ($_ < $mina) {
            $mina = $_;
        }
    }

    if ($mina > ((exp(1) * $t)/(1 << $width))) {
        return $mina;
    }

    my $jstar = ilog2($past) - 1;

    my $mvals = CountMin::sketch_values($self->{times}->[$jstar], $s);
    my $bvals = CountMin::sketch_values($self->{itemtimes}->[$jstar], $s);

    my $nxt = (1 << 32);

    for (my $i=0; $i < scalar @$avals; $i++) {
        if ($bvals->[$i] == 0) {
                $nxt = 0;
        } else {
            my $n = ($mvals->[$i] * $avals->[$i]) / $bvals->[$i];
            if ($n < $nxt) {
                $nxt = $n;
            }
        }
    }

    return $nxt;
}

sub ilog2 {
    my $v = shift;
    my $r = 0;

    while ($v >>= 1) {
        $r++;
    }

    return $r;
}

1;
