# Makefile.PL -- Makefile for makepatch
# Author          : Ulrich Pfeifer
# Created On      : Mon Feb 17 10:51:47 1997
# Last Modified By: Johan Vromans
# Last Modified On: Tue Jul  7 14:20:54 1998
# Update Count    : 11
# Status          : Released

use ExtUtils::MakeMaker;

my @scripts = qw (makepatch);
my $wrap = join (';', 
		 map ("cat PLheader.pl $_.pl PLtrailer.pl > $_.PL",  
		      @scripts));

WriteMakefile
  (
   NAME           => 'makepatch',
   VERSION        => '1.16',
   'dist'         => {
                      PREOP    =>"$wrap",
                      COMPRESS =>"gzip",
                      SUFFIX   =>"gz",
                     },
   'EXE_FILES'    => \@scripts,
 );

              
