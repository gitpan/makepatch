# Makefile.PL -- Makefile for makepatch
# Author          : Ulrich Pfeifer
# Created On      : Mon Feb 17 10:51:47 1997
# Last Modified By: Johan Vromans
# Last Modified On: Sun Nov  1 17:14:38 1998
# Update Count    : 18
# Status          : Released

use ExtUtils::MakeMaker;

my @scripts = qw (makepatch);
my $wrap = join (';', 
		 map ("cat PLheader.pl $_.pl PLtrailer.pl > $_.PL",  
		      @scripts));

WriteMakefile
  (
   NAME           => 'makepatch',
   VERSION        => '1.94',
   'dist'         => {
                      PREOP    =>"$wrap",
                      COMPRESS =>"gzip",
                      SUFFIX   =>"gz",
                     },
   'EXE_FILES'    => \@scripts,
 );

              
