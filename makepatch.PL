#!/usr/local/bin/perl

use Config;
use File::Basename qw(&basename &dirname);

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
chdir(dirname($0));
($file = basename($0)) =~ s/\.PL$//;
$file =~ s/\.pl$//
	if ($^O eq 'VMS' or $^O eq 'os2');  # "case-forgiving"

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
$Config{'startperl'} 
!GROK!THIS!
print OUT <<'!NO!SUBS!';
# makepatch.pl -- generate batch of patches.
$RCS_Id = '$Id: makepatch.pl,v 1.16 1998-07-07 14:20:48+02 jv Exp $ ';
# Author          : Johan Vromans
# Created On      : Tue Jul  7 20:39:39 1992
# Last Modified By: Johan Vromans
# Last Modified On: Tue Jul  7 14:20:04 1998
# Update Count    : 184
# Status          : Released to USEnet.
#
# Generate a patch from two files or directories.
#
# WARNING: THIS PROGRAM IS NOT '-w' and 'use strict' CLEAN.
#

=head1 NAME

makepatch - create patch diffs between two versions of source

=head1 SYNOPSIS

B<makepatch> [ I<options> ] I<old> I<new>

B<makepatch> B<-filelist> [ I<options> ] I<manifest>

=head1 DESCRIPTION

B<Makepatch> generates a set of differences between two files or two
sets of files maintained in two different directories and prints the
results to I<stdout>.  This resulting output is suitable for use by
the B<patch>(1) program to update copies of the target file(s) from
the I<old> to the I<new> version.

Features of this utility include:

=item - Recursive descend through sub-directories.

=item - Generation of commands to remove obsolete files.

=item - Automatic handling of the I<patchlevel.h> file first.

=item - Automatic inclusion of I<Index:> and I<Prereq:> lines.

=item - Ability to utilize specified I<manifest> file(s).

=head1 ARGUMENTS

=over

=item I<old>

This is the name of either a single file or else a directory which
contains copies of the older version of the target file(s); in
other words, copies of the file(s) I<prior> to any modifications.

=item I<new>

This is the name of either a single file or else a directory which
contains copies of the newer version of the target file(s); in other
words, copies of the file(s) I<after> the modifications have been
made.  A B<rm>(1) command will automatically be generated for every
I<old> file that no longer has a corresponding I<new> version.

=back

=head1 MAKEPATCH OPTIONS

=over

=item B<-diff> I<cmd>

If specified, I<cmd> is the command to be used to
generate the differences between the two versions of the files.  If
not specified, this command defaults to "B<diff -c>".

=item B<-patchlevel> I<pfile>

If specified, I<pfile> indicates an alternate file that is to be
used in lieu of "B<patchlevel.h>".

=item B<-man>[B<ifest>] I<mfile>

If specified, I<mfile> indicates the name of the manifest file
which consists of a list of the files contained in both the I<old>
and the I<new> directories.

=item B<-oldman>[B<ifest>] I<omfile>

If specified, I<omfile> indicates the name of the manifest file which
consists of a list of the files contained in the I<old> directory.
This option is designed to be used in conjunction with the
B<-newmanifest> option.  Note that the I<old> and I<new> directories
must still be indicated.

=item B<-newman>[B<ifest>] I<nmfile>

If specified, I<nmfile> indicates the name of the manifest file which
consists of a list of the files contained in the I<new> directory.
This option is designed to be used in conjunction with the
B<-oldmanifest> option.  Note that the I<old> and I<new>
directories must still be indicated.

=item B<-follow>

If specified, symbolic links to directories are traversed as if they
were real directories.

=item B<-fixpath>

Correct diff pathnames for new files.
Use this for buggy B<diff> or B<patch> programs.

=item B<-fixallpath>

Correct diff path names for all files. 
Use this for buggy B<diff> or B<patch> programs.

=back

=head1 FILELIST OPTIONS

=over

=item B<->[B<file>]B<list>

This option instructs B<makepatch> to read a manifest file, and output
the list of files included in this manifest. This option is useful to
turn the contents of a manifest file into a list of files suitable for
other programs.

=item B<-man>[B<ifest>] I<mfile>

If specified, I<mfile> indicates the name of the manifest file to
be used. Alternatively, the name of the manifest file may follow the
command line options.

=item B<-prefix > I<string>

Every entry in the manifest file is prefixed with I<string> before it
is written to I<stdout>.

=item B<-nosort>

Retain the order of filenames from the manifest file.

=back

=head1 GENERAL OPTIONS

=over

=item B<-verbose>

This is the default mode which displays information concerning
B<makepatch>s activity to I<stderr>.

=item B<-quiet>

The opposite of B<-verbose>.  This instructs I<makepatch> to suppress
the display of activity information.

=item B<-help>

This causes a short help message to be displayed, after which the
program immediately exits.

=back

=head1 MANIFEST FILES

Although there is no formal standard for manifest files, the following
rules apply:

=over 2

=item - If the second line from the manifest file looks like a separator line
(e.g. it is empty, or contains only dashes), it is discarded and so is
the first line.

=item - Empty lines and lines that start with a C<#> are ignored.

=item - If there are multiple space-separated ``words'' on a line, the first
word is considered to be the filename.

=back

=head1 EXAMPLES

Suppose you have a directory tree F<emacs-18.58> containing the
sources for GNU Emacs 18.58, and a directory tree F<emacs-18.59>
containing the sources for GNU Emacs 18.59. The following command will
generate the patch file needed to transform the 18.58 sources into
18.59:

 makepatch emacs-18.58 emacs-18.59 > emacs-18.58-18.59.diff

This is one way to generate and use manifest files:

  (cd emacs-18.58; find . -type f -print > MANIFEST)

  (cd emacs-18.59; find . -type f -print > MANIFEST)

  makepatch \
    -oldmanifest emacs-18.58/MANIFEST \
    -newmanifest emacs-18.59/MANIFEST \
    emacs-18.58 emacs-18.59 > emacs-18.58-18.59.diff

The following example transforms the manifest file into a list of
files suitable for GNU tar. Note the trailing F</> in the prefix
string:

  makepatch -filelist -prefix emacs-18.59/ emacs-18.59/MANIFEST | \
    gtar -Zcvf emacs-18.59.tar.Z -T -Op

=head1 SEE ALSO

B<diff>(1),
B<patch>(1),
B<perl>(1),
B<rm>(1).

=head1 AUTHORS

Johan Vromans (jvromans@squirrel.nl) wrote the program.

Jeffery Small (jeff@cjsa.uucp) donated the base version of this manual
page that inspired me to complete it.

Ulrich Pfeifer (pfeifer@ls6.informatik.uni-dortmund.de) convered it to
POD format.

Nigel Metheringham <Nigel.Metheringham@ThePLAnet.net> donated some
more fixes.

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 1992,1998 by Johan Vromans.
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

If you do not have a copy of the GNU General Public License write to
the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, 
MA 02139, USA.

=cut

################ Common stuff ################

# $LIBDIR = $ENV{'LIBDIR'} || '/usr/local/lib/sample';
# unshift (@INC, $LIBDIR);
# require 'common.pl';
$my_package = 'Sciurix';
($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
$my_version = $VERSION = sprintf ("%d.%02d", $1, $2)
  if $my_version =~ /^(\d+)\.(\d+)$/;
$my_version .= '*' if length('$Locker:  $ ') > 12;

################ Program parameters ################

stdio();
options();
($old, $new) = @ARGV;

print STDERR ("This is $my_name version $my_version\n")
  if $opt_verbose;

if ( defined $opt_filelist ) {
    @new = domanifest (shift (@ARGV));
    foreach ( @new ) {
	print STDOUT ($opt_prefix, $_, "\n");
    }
    exit (0);
}

$tmpfile = $ENV{"TMPDIR"} || "/usr/tmp";
$thepatch = "$tmpfile/mp$$.p";
$tmpfile .= "/mp$$.t";
open (PATCH, ">$thepatch") || die ("$thepatch: $!\n");
$patched = $created = 0;
doit ($old, $new);
wrapup ();
exit (0);

################ Subroutines ################

sub doit {
    local ($old, $new) = @_;

    if ( -f $old && -f $new ) {
	# Two files.
	if ( $opt_verbose ) {
	    print STDERR ("Old file = $old.\n",
			  "New file = $new.\n");
	}
	dodiff ("", $old, "", $new, 0);
    }
    elsif ( -f $old && -d $new ) {
	# File and dir -> File and dir/File.
	$new = ( $new =~ m|^\./?$| ) ? "" : "$new/";
	if ( $opt_verbose ) {
	    print STDERR ("Old file = $old.\n",
			  "New file = $new$old.\n");
	}
	dodiff ("", $old, $new, $old, $opt_fixallpath);
    }
    elsif ( -f $new && -d $old ) {
	$old = ( $old =~ m|^\./?$| ) ? "" : "$old/";
	if ( $opt_verbose ) {
	    print STDERR ("Old file = $old$new.\n",
			  "New file = $new.\n");
	}
	dodiff ($old, $new, "", $new, $opt_fixallpath);
    }
    else {
	# Should be two directories.
	local (@old, @new);
	if ( defined $opt_oldmanifest ) {
	    @old = domanifest ($opt_oldmanifest);
	}
	else {
	    @old = make_filelist ($old);
	}
	if ( defined $opt_newmanifest ) {
	    @new = domanifest ($opt_newmanifest);
	}
	else {
	    @new = make_filelist ($new);
	}

	$new = ( $new =~ m|^\./?$| ) ? "" : "$new/";
	$old = ( $old =~ m|^\./?$| ) ? "" : "$old/";

	if ( $opt_verbose ) {
	    local ($old) = $old; chop ($old);
	    local ($new) = $new; chop ($new);
	    print STDERR ("Old dir = $old, file list = ",
			  defined $opt_oldmanifest ? $opt_oldmanifest : "<*>",
			  ", ", 0+@old, " files.\n");
	    print STDERR ("New dir = $new, file list = ",
			  defined $opt_newmanifest ? $opt_newmanifest : "<*>",
			  ", ", 0+@new, " files.\n");
	}
	if ( $opt_debug ) {
	    print STDERR ("Old: @old\nNew: @new\n");
	}

	# Handle patchlevel file first.
	$opt_patchlevel = (grep (/patchlevel\.h/, @new))[0]
	    unless defined $opt_patchlevel;

	if ( defined $opt_patchlevel && $opt_patchlevel ne "" ) {
	    if ( ! -f "$new$opt_patchlevel" ) {
		die ("$new$opt_patchlevel: $!\n");
	    }
	    if ( -f "$old$opt_patchlevel" ) {
		dodiff ($old, $opt_patchlevel, $new, $opt_patchlevel,
			$opt_fixallpath);
	    }
	    else {
		$created++;
		dodiff ("", "/dev/null", $new, $opt_patchlevel, 
			$opt_fixpath);
	    }
	}
	else {
	    undef $opt_patchlevel;
	}

	# Process the filelists.
	while ( @old + @new ) {

	    $o = shift (@old) unless defined $o;
	    $n = shift (@new) unless defined $n;
	    
	    if ( defined $n && (!defined $o || $o gt $n) ) {
		# New file.
		if ( defined $opt_patchlevel && $n eq $opt_patchlevel ) {
		    undef $opt_patchlevel;
		}
		else {
		    $created++;
		    dodiff ("", "/dev/null", $new, $n);
                    $newcomers{$n} = (stat($o))[2]
		      unless $opt_fixpath || $opt_fixallpath;
                }
		undef $n;
	    }
	    elsif ( !defined $n || $o lt $n ) {
		# Obsolete (removed) file.
		push (@goners, $o);
		undef $o;
	    }
	    elsif ( $o eq $n ) {
		# Same file.
		if ( defined $opt_patchlevel && $n eq $opt_patchlevel ) {
		    undef $opt_patchlevel;
		}
		else {
		    dodiff ($old, $o, $new, $n, $opt_fixallpath);
		}
		undef $n;
		undef $o;
	    }
	}
    }
}

sub make_filelist {
    local ($dir, $disp) = @_;

    # Return a list of files, sorted, for this directory.
    # Recurses.

    local (@ret);
    local (*DIR);
    local (@tmp);
    local ($fname);

    $disp = "" unless defined $disp;

    print STDERR ("+ recurse $dir\n") if $opt_trace;
    opendir (DIR, $dir) || die ("$dir: $!\n");
    @tmp = sort (readdir (DIR));
    closedir (DIR);
    print STDERR ("Dir $dir: ", 0+@tmp, " entries\n") if $opt_debug;

    @ret = ();
    foreach $file ( @tmp ) {

	# Skip unwanted files.
	next if $file =~ /^\.\.?$/; # dot and dotdot
	next if $file =~ /~$/;	# editor backup files

	# Push on the list.
	$fname = "$dir/$file";
	if ( -d $fname && ( $opt_follow || ! -l $fname ) ) {
	    # Recurse.
	    push (@ret, make_filelist ($fname, "$disp$file/"));
	}
	elsif ( -f _ ) {
	    push (@ret, $disp . $file);
	}
	else {
	    print STDERR ("Ignored $fname: not a file\n");
	}
    }
    @ret;
}

sub domanifest {
    local ($man) = @_;
    local (*MAN);
    local (@ret) = ();

    open (MAN, $man) || die ("$man: $!\n");
    while ( <MAN> ) {
	if ( $. == 2 && /^[-=_\s]*$/ ) {
	    @ret = ();
	    next;
	}
	next if /^#/;
	next unless /\S/;
	$_ = $` if /\s/;
	push (@ret, $_);
    }
    close (MAN);
    @ret = sort @ret unless defined $opt_nosort;
    @ret;
}

sub dodiff {
    local ($olddir, $old, $newdir, $new, $fixpath) = @_;

    # Produce a patch hunk.

    local ($cmd) = "$opt_diff '$olddir$old' '$newdir$new'";
    print STDERR ("+ ", $cmd, "\n") if $opt_trace;
    $result = system ("$cmd > $tmpfile");
    printf STDERR ("+> result = 0x%x\n", $result) 
	if $result && $opt_debug;

    if ( $result && $result < 128 ) {
	wrapup (($result == 2 || $result == 3) 
		? "User request" : "System error");
	exit (1);
    }
    return unless $result == 0x100;	# no diffs
    $patched++;

    # print PATCH ($cmd, "\n");
    print PATCH ("Index: ", $new, "\n");

    # Try to find a prereq.
    # The RCS code is based on a suggestion by jima@netcom.com, who also
    # pointed out that patch requires blanks around the prereq string.
    open (OLD, $olddir . $old);
    while ( <OLD> ) {
	next unless (/\@\(\#\)/		# SCCS header
		     || /\$Header:/ 	# RCS Header
		     || /\$Id:/); 	# RCS Header
	next unless $' =~ /\s\d+(\.\d+)*\s/; # e.g. 5.4
	print PATCH ("Prereq: $&\n");
	last;
    }
    close (OLD);

    # Copy patch.
    open (TMP, $tmpfile);
    if ( $fixpath ) {
	# As told by Nigel Metheringham <Nigel.Metheringham@ThePLAnet.net>.
	# Fix up pathnames of diff to feed a bug in patch
	# only looks at first 3 lines of diff.
	# The wierd methodology is to avoid strange RE effects.
	local ($linecnt) = 0;
	local ($line, $fnoff);
	while ( $line = <TMP> ) {
	    if ( $line =~ /^\*{3}\s+/ ) {
		$fnoff = length ($&);
		substr ($line, $fnoff, length($olddir)) = ""
		  if substr ($line, $fnoff, length($olddir)) eq $olddir;
	    }
	    elsif ( $line =~ /^\-{3}\s+/ ) {
		$fnoff = length($&);
		substr ($line, $fnoff, length($newdir)) = ""
		  if substr ($line, $fnoff, length($newdir)) eq $newdir;
	    }
	    print PATCH $line;
	    last if ++$linecnt > 2;
	}
	print PATCH <TMP>;
    }
    else {
	# As told by Ulrich Pfeifer (pfeifer@ls6.informatik.uni-dortmund.de).
	local ($ndir) = $newdir;
	$ndir =~ s:/?\.?$::;
	$ndir =~ s:.*/::;
	print PATCH ("####### $newdir => $ndir\n");
	while ( <TMP> ) {
	  s:^\*\*\* /dev/null:*** $newdir$new:;
	  # As told by Julian Yip <julian@computer.org>.
	  # Don't do the following substitution 
	  # if $olddir or $newdir is empty.
	  s:^--- $newdir:--- $ndir/: if $newdir ne "";
	  s:^\*\*\* $olddir:*** $ndir/: if $olddir ne "";
	  print PATCH;
	}
    }
    close (TMP);
}

sub wrapup {
    local ($reason) = @_;

    if ( defined $reason ) {
	print STDERR ("*** Aborted: $reason ***\n");
    }
    if ( $opt_verbose ) {
	local ($goners) = scalar (@goners);
	print STDERR ("Collecting: $patched patch",
		      $patched == 1 ? "" : "es", "... ");
    }
    if ( @goners or %newcomers ) {
	print STDOUT "# To apply this patch, chdir to you source ".
          "directory and enter\n#\n";
        print STDOUT "#     /bin/sh <this-file>\n" if (@goners or %newcomers);
        print STDOUT "#     patch -p1 -N < <this-file>\n\n";
    }
    my $dgoners = 0;
    {
	my %dir_gone = ();
	foreach ( sort @goners ) {
	    print STDOUT ("rm -f ", $_, "\n");
	    my @p = split (/\//, $_);
	    pop (@p);
	    foreach my $i ( (1-@p)..0 ) {
		my $dir = join('/',@p[0..-$i]);
		unless ( defined $dir_gone{$dir} ) {
		    unless ( -d "$new/$dir" ) {
			$dgoners++;
			$dir_gone{$dir} = 1;
		    }
		}
	    }
	}
	foreach ( reverse sort keys %dir_gone ) {
	    print STDOUT ("rmdir ", $_, "\n");
	}
    }
    my $dcreated = 0;
    {
	my %dir_ok = ();
	foreach ( sort keys %newcomers ) {
	    # Explicitly create the new files since not all patch versions
	    # can handle creating new files. 
	    # Create intermediate directories first.
	    my @p = split (/\//, $_);
	    pop (@p);
	    foreach my $i ( 0..(@p-1) ) {
		my $dir = join('/',@p[0..$i]);
		unless ( defined $dir_ok{$dir} ) {
		    unless ( -d "$old/$dir" ) {
			print STDOUT ("mkdir ", $dir, "\n");
			$dcreated++;
		    }
		    $dir_ok{$dir} = 1;
		}
	    }
	    # Create the file and change the mode if needed.
	    print STDOUT ("touch ", $_, "\n");
	    printf STDOUT "chmod %o %s\n", $newcomers{$_} & 0777, $_
	      if $newcomers{$_} & 0111; 
	}
    }
    if (@goners or %newcomers) {
        print STDOUT ("exit\n\n");
    }

    # Copy patch.
    open (PATCH, $thepatch);
    print while <PATCH>;
    close (PATCH);

    if ( $opt_verbose ) {
	local ($goners) = scalar (@goners);
	print STDERR ("done.\n");
	if ( $created ) {
	    print STDERR ("  $created file", 
			  $created == 1 ? "" : "s");
	    print STDERR (" and $dcreated director", 
			  $dcreated == 1 ? "y" : "ies") if $dcreated;
	    print STDERR (" need to be created.\n");
	}
	if ( $goners ) {
	    print STDERR ("  $goners file", 
			  $goners == 1 ? "" : "s");
	    print STDERR (" and $dgoners director", 
			  $dgoners == 1 ? "y" : "ies") if $dgoners;
	    print STDERR (" need to be removed.\n");
	}
    }

    # Cleanup.
    unlink ($tmpfile, $thepatch);
}

sub stdio {
    # Since output to STDERR seems to be character based (and slow),
    # we connect STDERR to STDOUT if they both point to the terminal.
    if ( -t STDOUT && -t STDERR ) {
	close (STDERR);
	open (STDERR, '>&STDOUT');
	select (STDERR); $| = 1;
	select (STDOUT);
    }
}

sub options {
    my ($opt_manifest);
    my ($opt_quiet);
    my ($opt_help);

    # Defaults...
    $opt_diff = "diff -c";
    $opt_verbose = 1;
    $opt_follow = 0;
    $opt_fixpath = 0;
    $opt_fixallpath = 0;

    # Process options, if any...
    if ( $ARGV[0] =~ /^-/ ) {
	use Getopt::Long 2.00;

	if ( !GetOptions(
			 "debug",
			 "diff=s", 
			 "filelist|list",
			 "fixallpath",
			 "fixpath",
			 "follow",
			 "help"                  => \$opt_help,
			 "manifest|man=s"        => \$opt_manifest,
			 "newmanifest|newman=s",
			 "nosort",
			 "oldmanifest|oldman=s",
			 "patchlevel=s",
			 "prefix=s",
			 "quiet"                 => \$opt_quiet,
			 "trace",
			 "verbose|v",
			)
	    || defined $opt_help ) {
	    usage();
	}
	$opt_trace = 1 if defined $opt_debug;
	$opt_verbose = 0 if defined $opt_quiet;
	if ( defined $opt_prefix ) {
	    die ("$0: option \"-prefix\" requires \"-filelist\"\n")
		unless defined $opt_filelist;
	}
	if ( defined $opt_nosort ) {
	    die ("$0: option \"-nosort\" requires \"-filelist\"\n")
		unless defined $opt_filelist;
	}
	if ( defined $opt_filelist ) {
	    die ("$0: option \"-filelist\" only uses \"-manifest\"\n")
		if defined $opt_oldmanifest || defined $opt_newmanifest;
	}
	if ( defined $opt_manifest ) {
	    die ("$0: do not use \"-manifest\" with \"-oldmanifest\"".
		 " or \"-newmanifest\"\n")
		if defined $opt_newmanifest || defined $opt_oldmanifest;
	    $opt_newmanifest = $opt_oldmanifest = $opt_manifest;
	}
    }

    # Argument check.
    if ( defined $opt_filelist ) {
	if ( defined $opt_manifest ) {
	    usage() if @ARGV;
	    @ARGV = ( $opt_manifest );
	}
	else {
	    usage() unless @ARGV == 1;
	}
    }
    else {
	usage() unless @ARGV == 2;
    }
}

sub usage () {
    print STDERR <<EoU;
This is $my_name version $my_version

Usage: $0 [options] old new
Usage: $0 -filelist [ -prefix XXX ] [ -nosort ] [ -manifest ] file

Makepatch options:
   -diff cmd		diff command to use, default \"$opt_diff\"
   -patchlevel file	file to use as patchlevel.h
   -man[ifest] file	list of files for old and new dir
   -newman[ifest] file	list of files for new dir
   -oldman[ifest] file	list of files for old dir
   -follow		follow symbolic links
   -fixpath             fixup diff pathnames for new files
   -fixallpath          fixup diff pathnames for all files
Filelist options:
   -[file]list		extract filenames from manifest file
   -prefix XXX		add a prefix to these filenames
   -nosort		do not sort manifest entries
General options:
   -verbose		verbose output (default)
   -quiet		no verbose output
   -help		this message
EoU
    exit (1);
}
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
