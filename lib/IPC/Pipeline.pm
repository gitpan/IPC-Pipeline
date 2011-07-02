package IPC::Pipeline;

use strict;
use warnings;

use POSIX ();

BEGIN {
    use Exporter    ();
    use vars        qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

    $VERSION        = '0.4';
    @ISA            = ('Exporter');
    @EXPORT         = ('pipeline');
    @EXPORT_OK      = ();
    %EXPORT_TAGS    = ();
}

sub exec_filter {
    my ($filter) = @_;

    if (ref($filter) eq 'CODE') {
        exit $filter->();
    } elsif (ref($filter) eq 'ARRAY') {
        exec(@$filter) or die("Cannot exec(): $!");
    }

    die('Invalid filter');
}

sub pipeline {
    my @filters = @_[3..$#_];

    return undef unless @filters;

    #
    # Validate the filters and die early.
    #
    foreach my $filter (@filters) {
        next if ref($filter) =~ /^CODE|ARRAY$/;

        die('Filter passed is not a CODE reference or ARRAY containing command and arguments');
    }

    #
    # Create the initial pipe for passing data into standard input to the first
    # filter passed.
    #
    pipe my ($child_out, $in) or die('Cannot create a file handle pair for standard input piping');

    #
    # Only create a standard error pipe if a standard error file handle glob
    # was passed in the 3rd argument position.
    #
    my ($error_out, $error_in);

    if (defined $_[2]) {
        pipe $error_out, $error_in or die('Cannot create a file handle pair for standard error piping');
    }

    my @pids;

    foreach my $filter (@filters) {
        pipe my ($out, $child_in) or die('Cannot create a file handle pair for standard output piping');

        my $pid = fork();

        if (!defined $pid) {
            die("Cannot fork(): $!");
        } elsif ($pid == 0) {
            open(STDIN, '<&', $child_out) or die('Cannot dup2() last output fd to current child stdin');
            open(STDOUT, '>&', $child_in) or die('Cannot dup2() last input fd to current child stdout');

            if (defined $_[2]) {
                open(STDERR, '>&', $error_in) or die('Cannot dup2() error pipe input to current child stderr');
            }

            exec_filter($filter);
        }

        #
        # This last child STDOUT file handle should be duplicated onto the next
        # process' standard input reader, or will be passed as the last child
        # output file descriptor if no other subsequent commands are left
        # to be run.
        #
        $child_out = $out;

        push @pids, $pid;
    }

    #
    # Substitute the first three arguments passed by the user with the file
    # handle on the parent's writing end of the initial pipe created for
    # writing to the first command, the last output file handle for the
    # last command, and the standard error handle.  If typeglobs or numeric
    # file descriptors for existing file handles are passed, an attempt will
    # be made to dup2() them as appropriate.
    #

    if (!defined $_[0]) {
        $_[0] = $in;
    } elsif (ref $_[0] eq 'GLOB') {
        open($_[0], '>&=', $in);
    } else {
        POSIX::dup2(fileno($in), $_[0]);
    }

    if (!defined $_[1]) {
        $_[1] = $child_out;
    } elsif (ref $_[1] eq 'GLOB') {
        open($_[1], '<&=', $child_out);
    } else {
        POSIX::dup2(fileno($child_out), $_[1]);
    }

    if (!defined $_[2]) {
        $_[2] = $error_out;
    } elsif (ref $_[2] eq 'GLOB') {
        open($_[2], '<&=', $error_out);
    } else {
        POSIX::dup2(fileno($error_out), $_[2]);
    }

    #
    # If called in array context, return each subprocess ID in the same order
    # as they are specified in the commands provided.  Otherwise, return the
    # pid of the first child.
    #
    return wantarray? @pids: $pids[0];
}

1;

__END__

=head1 NAME

IPC::Pipeline - Create a shell-like pipeline of many running commands

=head1 SYNOPSIS

    use IPC::Pipeline;

    my @pids = pipeline(\*FIRST_CHLD_IN, \*LAST_CHLD_OUT, \*CHILDREN_ERR,
        [qw(filter1 args)],
        sub { filter2(); return 0 },
        [qw(filter3 args)],
        ...
        [qw(commandN args)]
    );

    ... do stuff ...

    my %statuses = map {
        waitpid($_, 0);
        $_ => ($? >> 8);
    } @pids;

=head1 DESCRIPTION

Similar in calling convention to IPC::Open3, pipeline() spawns N children,
connecting the first child to the FIRST_CHLD_IN handle, the final child to
LAST_CHLD_OUT, and each child to a shared standard error handle, CHILDREN_ERR.
Each subsequent filter specified causes a new process to be fork()ed.  Each
process is linked to the last with a file descriptor pair created by pipe(),
using dup2() to chain each process' standard input to the last standard output.

=head2 FEATURES

IPC::Pipeline accepts external commands to be executed in the form of ARRAY
references containing the command name and each argument, as well as CODE
references that are executed within their own processes as well, each as
independent parts of a pipeline.

=head3 ARRAY REFS

When a filter is passed in the form of an ARRAY containing an external system
command, each such item is executed in its own subprocess in the following
manner.

    exec(@$filter) or die("Cannot exec(): $!");

=head3 CODE REFS

When a filter is passed in the form of a CODE ref, each such item is executed in
its own subprocess in the following way.

    exit $filter->();

=head2 BEHAVIOR

If fileglobs or numeric file descriptors are passed in any of the three
positional parameters, then they will be duplicated onto the file handles 
allocated as a result of the process pipelining.  Otherwise, simple scalar
assignment will be performed.

Like IPC::Open3, pipeline() returns immediately after spawning the process
chain, though differing slightly in that the IDs of each process is returned
in order of specification in a list when called in array context.  When called
in scalar context, only the ID of the first child process spawned is returned.

Also like IPC::Open3, one may use select() to multiplex reading and writing to
each of the handles returned by pipeline(), preferably with non-buffered
sysread() and syswrite() calls.  Using this to handle reading standard output
and error from the children is ideal, as blocking and buffering considerations
are alleviated.

=head2 CAVEATS

If any child process dies prematurely, or any of the piped file handles are
closed for any reason, the calling process inherits the kernel behavior of
receiving a SIGPIPE, which requires the installation of a signal handler for
appropriate recovery.

Please be advised that any usage of numeric file descriptors will result in an
implicit import of POSIX::dup2() at runtime.

=head1 EXAMPLE ONE - OUTPUT ONLY

The following example implements a quick and dirty, but relatively sane tar and
gzip solution.  For proper error handling from any of the children, use select()
to multiplex the output and error streams.

    use IPC::Pipeline;

    my @paths = qw(/some /random /locations);

    my @pids = pipeline(my ($in, $out), undef,
        [qw(tar pcf -), @paths],
        ['gzip']
    );

    open(my $fh, '>', 'file.tar.gz');
    close $in;

    while (my $len = sysread($out, my $buf, 512)) {
        syswrite($fh, $buf, $len);
    }

    close $fh;
    close $out;

    #
    # We may need to wait for the children to die in some extraordinary
    # circumstances.
    #
    foreach my $pid (@pids) {
        waitpid($pid, 1);
    }

=head1 EXAMPLE TWO - INPUT AND OUTPUT

The following solution implements a true I/O stream filter as provided by any
Unix-style shell.

    use IPC::Pipeline;

    my @pids = pipeline(my ($in, $out), undef,
        [qw(tr A-Ma-mN-Zn-z N-Zn-zA-Ma-m)],
        [qw(cut -d), ':', qw(-f 2)]
    );

    my @records = qw(
        foo:bar:baz
        eins:zwei:drei
        cats:dogs:rabbits
    );

    foreach my $record (@records) {
        print $in $record ."\n";
    }

    close $in;

    while (my $len = sysread($out, my $buf, 512)) {
        syswrite(STDOUT, $buf, $len);
    }

    close $out;

    foreach my $pid (@pids) {
        waitpid($pid, 1);
    }

=head1 EXAMPLE THREE - MIXING COMMANDS AND CODEREFS

The following solution demonstrates the ability of IPC::Pipeline to execute CODE
references in the midst of a pipeline.

    use IPC::Pipeline;

    my @pids = pipeline(my ($in, $out), undef,
        sub { print 'cats'; return 0 },
        [qw(tr acst lbhe)]
    );

    close $in;

    while (my $line = readline($out)) {
        chomp $line;
        print "Got '$line'\n";
    }

    close $out;

=head1 SEE ALSO

=over

=item * IPC::Open3

=item * IPC::Run, for a Swiss Army knife of Unix I/O gizmos

It should be mentioned that mst's IO::Pipeline has very little in common with IPC::Pipeline.

=back

=head1 COPYRIGHT

Copyright 2011, Erin Schönhals <wrath@cpan.org>.  Released under the terms of
the MIT license.
