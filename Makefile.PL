# Makefile.PL -- Makefile for makepatch
# Author          : Ulrich Pfeifer
# Created On      : Mon Feb 17 10:51:47 1997
# Last Modified By: Johan Vromans
# Last Modified On: Tue Nov 17 23:17:21 1998
# Update Count    : 32
# Status          : Released

# Verify perl version.
require 5.000;

# Verify CORE modules.
use Getopt::Long 2.00;
use IO;
use File::Basename;
use File::Spec;

use ExtUtils::MakeMaker;

my @scripts = qw (makepatch applypatch);

WriteMakefile
  (
   NAME         => 'makepatch',
   AUTHOR	=> 'Johan Vromans (jvromans@squirrel.nl)',
   ABSTRACT	=> 'patchkit generate and apply tool', 
   VERSION      => 1.99,
   dist         => {COMPRESS =>"gzip", SUFFIX   =>"gz",},
   EXE_FILES    => \@scripts,
 );
