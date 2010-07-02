package IPC::Pipeline;

use strict;
use warnings;

BEGIN {
    use Exporter    ();
    use vars        qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;

    $VERSION        = '0.2';
    @ISA            = qw/Exporter/;
    @EXPORT         = qw/pipeline/;
    @EXPORT_OK      = ();
    %EXPORT_TAGS    = ();
}

#
# my @pids = pipeline(\*FIRST_CLD_IN, \*LAST_CLD_OUT, \*CHILDREN_ERROR,
#     [qw/command1 args .../],
#     [qw/command2/, @moreargs/],
#     ...
#     [qw/commandN/]
# );
#
# First, second, and third arguments will be modified upon return to hold the read,
# write, and error ends of the command pipeline.  An array of process IDs, in the
# order of specification at method invocation time, shall be returned upon success.
# Any exceptional conditions will cause a die() to be thrown with appropriate error
# information.  If called in scalar context, the first pid will be returned only.
# Will return undef if no command arguments are passed.
#
sub pipeline {
    my @commands = @_[3..$#_];

    return undef unless scalar @commands;

    #
    # Create the initial pipe for passing data into standard input to the first
    # command passed; then, create the standard error pipe that will be used
    # for all subsequent processes.
    #
    pipe my ($child_out, $in) or die('Unable to create a file descriptor pair for standard input piping');
    pipe my ($error_out, $error_in) or die('Unable to create a file descriptor pair for standard error piping');

    my @pids = ();

    foreach my $command (@commands) {
        pipe my ($out, $child_in) or die('Unable to create a file descriptor pair for standard output piping');

        my $pid = fork();

        if (!defined $pid) {
            die $!;
        } elsif ($pid == 0) {
            open(STDIN, '>&', $child_out) or die('Cannot dup2() last output fd to current child stdin');
            open(STDOUT, '>&', $child_in) or die('Cannot dup2() last input fd to current child stdout');
            open(STDERR, '>&', $error_in) or die('Cannot dup2() error pipe input to current child stderr');

            #
            # Let Perl's death warnings percolate through in the event of a failure
            # here, as we must use waitpid() to gather the status information from
            # this child.
            #
            exec(@$command);
        }

        #
        # This last child STDOUT file descriptor should be duplicated onto the
        # next process' standard input reader, or will be passed as the last
        # child output file descriptor if no other subsequent commands are left
        # to be run.
        #
        $child_out = $out;

        push @pids, $pid;
    }

    #
    # Substitute the first three arguments passed by the user with the file
    # descriptor on the parent's writing end of the initial pipe created for
    # writing to the first command, the last output file descriptor for the
    # last command, and the standard error descriptor.
    #
    $_[0] = $in;
    $_[1] = $child_out;
    $_[2] = $error_out;

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

    my @pids = pipeline(\*FIRST_CLD_IN, \*LAST_CLD_OUT, \*CHILDREN_ERR,
        [qw/command1/],
        [qw/command2/],
        ...
        [qw/commandN/]
    );

    ... do stuff ...

    my @statuses = map {
        waitpid($_, 0);
        $? >> 8;
    } @pids;

=head1 DESCRIPTION

Similar in calling convention to IPC::Open3, pipeline() spawns N children,
connecting the first child to the FIRST_CLD_IN handle, the final child to
LAST_CLD_OUT, and each child to a shared standard error handle, CHILDREN_ERR.
Each subsequent command specified causes a new process to be fork()ed.  Each
process is linked to the last with a file descriptor pair created by pipe(),
using dup2() to chain each process' standard input to the last standard output.
The commands specified in the anonymous arrays passed are started in the child
processes with a simple exec() call.

Like IPC::Open3, pipeline() returns immediately after spawning the process
chain, though differing slightly in that the IDs of each process is returned
in order of specification in a list when called in array context.  When called
in scalar context, only the ID of the first child process spawned is returned.

Also like IPC::Open3, one may use select() to multiplex reading and writing to
each of the descriptors returned by pipeline(), preferably with non-buffered
sysread() and syswrite() calls.  Using this to handle reading standard output
and error from the children is ideal, as blocking and buffering considerations
are alleviated.

If any child process dies prematurely, or any of the piped file descriptors
are closed for any reason, the calling process inherits the kernel behavior
of receiving a SIGPIPE, which requires the installation of a signal handler
for appropriate recovery.

=head1 EXAMPLE ONE - OUTPUT ONLY

The following example implements a quick and dirty, but relatively sane tar and
gzip solution.  For proper error handling from any of the children, use select()
to multiplex the output and error streams.

    use IPC::Pipeline;

    my @paths = qw(/some /random /locations);

    my @pids = pipeline(my ($in, $out), undef,
        [qw/tar pcf -/, @paths],
        [qw/gzip/]
    );

    open(my $fh, '>', 'file.tar.gz');
    close($in);

    while (my $len = sysread($out, my $buf, 512)) {
        syswrite($fh, $buf, $len);
    }

    close($fh);
    close($out);

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
        [qw/tr A-Ma-mN-Zn-z N-Zn-zA-Ma-m/],
        [qw/cut -d/, ':', qw/-f 2/]
    );

    my @records = qw(
        foo:bar:baz
        eins:zwei:drei
        cats:dogs:rabbits
    );

    foreach my $record (@records) {
        print $in $record ."\n";
    }

    close($in);

    while (my $len = sysread($out, my $buf, 512)) {
        syswrite(STDOUT, $buf, $len);
    }

    close($out);

    foreach my $pid (@pids) {
        waitpid($pid, 1);
    }

=head1 SEE ALSO

=over

=item * IPC::Open3

=item * IPC::Run, for a Swiss Army knife of Unix I/O gizmos

It should be mentioned that mst's IO::Pipeline has very little in common with IPC::Pipeline.

=back

=head1 COPYRIGHT

Copyright 2010, wrath@cpan.org.  Released under the terms of the MIT license.
