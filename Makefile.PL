use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'CLI::Framework',
    AUTHOR              => 'Karl Erisman <karl.erisman@icainformatics.org>',
    VERSION_FROM        => 'lib/CLI/Framework/Application.pm',
    ABSTRACT            => 'Build standardized, flexible, testable command-line applications',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Carp' => 0,
        'Getopt::Long::Descriptive' => 0,
        'Class::Inspector' => 0,
        'Class::ISA'        => 0,
        'File::Spec' => 0,
        'Term::ReadLine' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'CLI::Framework-*' },
);
