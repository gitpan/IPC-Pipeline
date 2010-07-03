#! /usr/bin/perl

use Test::More (tests => 13);

use strict;
use warnings;

use IPC::Pipeline;

my @commands = (
    [qw/tr A-Ma-mN-Zn-z N-Zn-zA-Ma-m/],
    [qw/cut -d : -f 2/]
);

my @pids = pipeline(my ($in, $out, $error), @commands);

ok(ref $in eq 'GLOB', 'pipeline() opened standard input writer handle');
ok(ref $out eq 'GLOB', 'pipeline() opened standard output reader handle');
ok(ref $error eq 'GLOB', 'pipeline() opened standard error reader handle');

{
    my $count = 0;
    my $expected = scalar @commands;

    for (my $i=0; $i<$expected; $i++) {
        my $command = @{$commands[$i]}[0];
        my $pid = $pids[$i];

        die unless ok($pid > 0, "pipeline() started subprocess '$command' with pid $pid");

        $count++;
    }

    die unless ok($count == $expected, "pipeline() returned $count nonzero pids (expected $expected)");
}

{
    my %records = (
        'foo:bar:baz'       => 'one',
        'eins:zwei:drei'    => 'mjrv',
        'one:two:three'     => 'gjb'
    );

    foreach (keys %records) {
        ok(eval {
            print $in "$_\n";
        }, "Able to write record '$_' to pipeline");
    }

    ok(eval {
        close($in);
    }, 'Able to close pipeline input');

    foreach (keys %records) {
        my $expected = $records{$_};

        my $line = readline($out);
        chomp($line);

        ok($line eq $expected, "Wrote '$_' to pipeline, received '$line' (expected '$expected')");
    }
}

{
    close($out);

    for (my $i=0; $i<scalar @commands; $i++) {
        my $command = @{$commands[$i]}[0];
        my $pid = $pids[$i];

        waitpid($pid, 1);
    }
}
