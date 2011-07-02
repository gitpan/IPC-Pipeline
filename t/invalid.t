#! /usr/bin/perl

use Test::More ('tests' => 5);
use Test::Exception;

use strict;
use warnings;

use BSD::Resource;
use IPC::Pipeline;

use Symbol;

my $nproc = getrlimit(RLIMIT_NPROC);
my $nfile = getrlimit(RLIMIT_NOFILE);

throws_ok {
    pipeline(my ($in, $out, $err), 'foo');
} qr/^Filter passed is not a/, 'pipeline() fails when filter is not CODE or ARRAY';

{
    setrlimit(RLIMIT_NOFILE, 3, $nfile);
    
    throws_ok {
        pipeline(my ($in, $out, $err), ['echo']);
    } qr/^Cannot create a file handle pair for standard input piping/, "pipeline() dies on stdin pipe() failure";
}

{
    my $err = Symbol::gensym;

    setrlimit(RLIMIT_NOFILE, 5, $nfile);

    throws_ok {
        pipeline(my ($in, $out), $err, ['echo']);
    } qr/^Cannot create a file handle pair for standard error piping/, "pipeline() dies on stderr pipe() failure";
}

{
    setrlimit(RLIMIT_NOFILE, 7, $nfile);
    
    throws_ok {
        pipeline(my ($in, $out, $err), ['echo']);
    } qr/^Cannot create a file handle pair for standard output piping/, "pipeline() dies on stdout pipe() failure";
}

{
    setrlimit(RLIMIT_NOFILE, $nfile, $nfile);
    setrlimit(RLIMIT_NPROC, 0, $nproc);

    throws_ok {
        pipeline(my ($in, $out, $err), ['echo']);
    } qr/^Cannot fork|Resource temporarily unavailable/, "pipeline() dies on fork() failure";
}
