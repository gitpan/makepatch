# Makefile.PL -- Makefile for makepatch
# Author          : Ulrich Pfeifer
# Created On      : Mon Feb 17 10:51:47 1997
# Last Modified By: Johan Vromans
# Last Modified On: Fri Sep  3 11:49:20 1999
# Update Count    : 75
# Status          : Released

# Verify perl version.
require 5.000;

# Verify CORE modules.
use Getopt::Long 2.00;
use IO;
use File::Basename;
use File::Spec;

use ExtUtils::MakeMaker;

# WriteMakefile parameter hash.
my %p = ( NAME => 'makepatch', VERSION => "2.00_01" );

# Extra info for newer versions.
if ( $[ >= 5.005 ) {
    $p{AUTHOR} = 'Johan Vromans (jvromans@squirrel.nl)';
    $p{ABSTRACT} = 'patchkit generate and apply tool';
}

# Scripts.
my @scripts = qw (makepatch applypatch);

=ignore

# Included modules.
my @mods = ();

# Required modules that are included in this kit for convenience.
# Syntax and semantics like PREREQ_PM.
my %req = ( Text::Filter => 0,
	    Text::Diff   => 0,
	    Text::Patch  => 0,
	  );

# Check modules, and ask to install them now.
$p{PREREQ_PM} = {};

foreach ( sort keys %req ) {
    my $mod = $_;
    my $rev = $req{$mod};
    my $eval = "use $mod $rev";
    eval $eval;
    if ( $@ ) {
	print STDERR ("\nI need the $mod package",
		      ($rev ? ", version $rev or higher" : ""), ".\n",
		      "Shall I install it for you? ");
	my $ans = <STDIN>;
	if ( $ans =~ /^y/i ) {
	    $mod =~ s/::/\//g;
	    push (@mods, "$mod.pm");
	}
	else {
	    # Have MakeMaker complain.
	    $p{PREREQ_PM}->{$mod} = 0;
	}
    }
}

=cut

# Append scripts and modules to WriteMakefile args.
$p{EXE_FILES} = [ map { "script/$_" } @scripts ];
$p{PM}->{"lib/$_"} = '${INST_LIBDIR}'."/$_" foreach @mods;

# Write the Makefile.
WriteMakefile (%p);
