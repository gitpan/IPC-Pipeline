use ExtUtils::MakeMaker;

use strict;
use warnings;

WriteMakefile(
    NAME            => 'IPC::Pipeline',
    VERSION_FROM    => 'lib/IPC/Pipeline.pm',
    AUTHOR          => 'wrath@cpan.org',
    ABSTRACT        => 'IPC::Open3-like interface providing shell-style pipelines in Perl',

    PREREQ_PM       => {
        'POSIX' => 0,
        'Test::More' => 0
    }
);
