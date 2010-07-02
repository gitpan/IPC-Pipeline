#! /usr/bin/perl

use Test::More (tests => 2);

use strict;
use warnings;

use IPC::Pipeline;

ok(!defined pipeline(undef, undef, undef), 'Calling pipeline() without commands returns undef');

{
    my $pid = pipeline(my ($in, $out, $error), [qw/echo hi/], [qw/cat/]);

    close($in);
    close($out);

    waitpid($pid, 1);

    ok($pid > 0, "Calling pipeline() in scalar context returns single nonzero pid ($pid)");
}
