#!/usr/bin/perl

use Hokusai::Sketch;

my $h = Hokusai::Sketch->new(0, 1, 20, 4);

my $maxepoch = 0;

my $query = shift;

while(<>) {
    my ($epoch, $key) = split;
    $h->add($epoch, $key, 1);
    if ($epoch > $maxepoch) {
        $maxepoch = $epoch;
    }
}

printf ("$_: %d\n", $h->count($_, $query)) for 1..$maxepoch;

