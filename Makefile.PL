# Makefile.PL -- Makefile for makepatch
# Author          : Ulrich Pfeifer
# Created On      : Mon Feb 17 10:51:47 1997
# Last Modified By: Johan Vromans
# Last Modified On: Sat Nov  7 20:58:04 1998
# Update Count    : 29
# Status          : Released

# Verify perl version.
require 5.000;

# Verify CORE modules.
use Getopt::Long 2.00;
use IO;
use File::Basename;
use File::Spec;

use ExtUtils::MakeMaker;

my @scripts = qw (makepatch);

WriteMakefile
  (
   NAME         => 'makepatch',
   AUTHOR	=> 'Johan Vromans (jvromans@squirrel.nl)',
   ABSTRACT	=> 'patchkit generating tool', 
   VERSION      => 1.97,
   dist         => {COMPRESS =>"gzip", SUFFIX   =>"gz",},
   EXE_FILES    => \@scripts,
 );
