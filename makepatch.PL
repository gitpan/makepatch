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
my $RCS_Id = '$Id: makepatch.pl,v 1.90 1998-09-11 13:13:45+02 jv Exp $ ';
# Author          : Johan Vromans
# Created On      : Tue Jul  7 20:39:39 1992
# Last Modified By: Johan Vromans
# Last Modified On: Fri Sep 11 13:10:29 1998
# Update Count    : 304
# Status          : Experimental
#
# Generate a patch kit from two files or directories.

use strict;
use Getopt::Long 2.00;
use IO;

################ Common stuff ################

# $LIBDIR = $ENV{'LIBDIR'} || '/usr/local/lib/sample';
# unshift (@INC, $LIBDIR);
# require 'common.pl';
my $my_package = 'Sciurix';
my ($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
$my_version = sprintf ("%d.%02d", $1, $2)
  if $my_version =~ /^(\d+)\.(\d+)$/;
$my_version .= '*' if length('$Locker:  $ ') > 12;
$my_version .= " (2.0BETA)";

################ Globals ################

## Options and defaults

my $opt_diff = 'diff -c';	# diff command
my $opt_sort;			# sort entries. Default = 1
my $opt_follow = 0;		# follow symbolic links
my $opt_fixpath = 0;		# fix pathnames for buggy diff/patch
my $opt_fixallpath = 0;		# more fixes
my $opt_oldmanifest;		# list of files of the old tree
my $opt_newmanifest;		# list of files of the new tree
my $opt_patchlevel;		# patchlevel.h file
my $opt_prefix = '';		# prefix to be added
my $opt_filelist = 0;		# make file list
my $opt_infocmd;		# info command
my $opt_exclude_vc = 0;		# exclude VC files
my @opt_exclude;		# list of excludes (wildcards)
my @opt_exclude_regex;		# list of excludes (regex)

my $opt_trace = 0;		# trace messages
my $opt_verbose = 1;		# verbose info
my $opt_debug = 0;		# debugging messages

## Misc

my @goners = ();		# files removed
my %newcomers = ();		# files added
my $patched = 0;		# files patched
my $created = 0;		# files created
my $exclude_pat;		# regex to exclude

## Subroutines

sub app_options ();
sub app_usage ();
sub debug (@);
sub dodiff ($$$$$);
sub doit ($$);
sub domanifest ($);
sub make_filelist ($;$$);
sub trace (@);
sub verbose (@);
sub wrapup (;$);

################ Program parameters ################

app_options ();

################ The Process ################

my ($old, $new) = @ARGV;

# Add --exclude wildcards to --exclude-regex list.
if ( @opt_exclude ) {
    my $pat;
    foreach $pat ( @opt_exclude ) {
	my @a = split (/(\[[^\]]+\]|[*.?])/, $pat);
	push (@opt_exclude_regex,
	      join ('', 
		    '(\A|/)',
		    (map { ($_ eq '*' ? '.*' :
			    ($_ eq '?' ? '.' :
			     ($_ eq '.' ? '\.' :
			      ($_ =~ /^\[/ ? $_ : quotemeta ($_)))))
		       } @a),
		    '\Z'));
    }
}

# Build regex from --exclude-regex list.
if ( @opt_exclude_regex ) {
    $exclude_pat = '(';
    my $re;
    foreach $re ( @opt_exclude_regex ) {
	verbose ("  Exclude regex: ", $re, "\n");
	eval { '' =~ /$re/ };
	if ( $@ ) {
	    $@ =~ s/ at .* line.*$//;
	    die ("Invalid regex: $re $@");
	}
	$exclude_pat .= "($re)|";
    }
    chop ($exclude_pat);
    $exclude_pat .= ')';
    debug ("Exclude pattern: $exclude_pat\n");
}

# Handle --filelist.
if ( $opt_filelist ) {
    my @new = domanifest (shift (@ARGV));
    foreach ( @new ) {
	print STDOUT ($opt_prefix, $_, "\n");
    }
    exit (0);
}

# Create temp files.
my $tmpfile = $ENV{"TMPDIR"} || "/usr/tmp";
my $thepatch = "$tmpfile/mp$$.p";
$tmpfile .= "/mp$$.t";
open (PATCH, ">$thepatch") || die ("$thepatch: $!\n");

# The process.
doit ($old, $new);
wrapup ();

exit (0);

################ Subroutines ################

sub verbose (@) { print STDERR (@_) if $opt_verbose; }
sub debug   (@) { print STDERR (@_) if $opt_debug;   }
sub trace   (@) { print STDERR (@_) if $opt_trace;   }

sub doit ($$) {
    my ($old, $new) = @_;

    if ( -f $old && -f $new ) {
	# Two files.
	verbose ("Old file = $old.\n", "New file = $new.\n");
	dodiff ("", $old, "", $new, 0);
    }
    elsif ( -f $old && -d $new ) {
	# File and dir -> File and dir/File.
	$new = ( $new =~ m|^\./?$| ) ? "" : "$new/";
        verbose ("Old file = $old.\n", "New file = $new$old.\n");
	dodiff ("", $old, $new, $old, $opt_fixallpath);
    }
    elsif ( -f $new && -d $old ) {
	$old = ( $old =~ m|^\./?$| ) ? "" : "$old/";
	verbose ("Old file = $old$new.\n", "New file = $new.\n");
	dodiff ($old, $new, "", $new, $opt_fixallpath);
    }
    else {
	# Should be two directories.
	my (@old, @new);

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
	    my ($oldstr) = $old; chomp ($oldstr);
	    my ($newstr) = $new; chomp ($newstr);
	    verbose ("Old dir = $oldstr, file list = ",
		     defined $opt_oldmanifest ? $opt_oldmanifest : "<*>",
		     ", ", scalar(@old), " files.\n",
		     "New dir = $newstr, file list = ",
		     defined $opt_newmanifest ? $opt_newmanifest : "<*>",
		     ", ", scalar(@new), " files.\n");
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
        
        my $o;
        my $n;

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
		    dodiff ("", "/dev/null", $new, $n, undef);
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

sub make_filelist ($;$$) {
    my ($dir, $compare_dir, $disp) = @_;

    # Return a list of files, sorted, for this directory.
    # Recurses.

    my $DIR = new IO::File;
    my $fname;

    $disp = "" unless defined $disp;
    $compare_dir = "" unless defined $compare_dir;

    trace ("+ recurse $dir\n");
    opendir ($DIR, $dir) || die ("$dir: $!\n");
    my @tmp = sort (readdir ($DIR));
    closedir ($DIR);
    debug ("Dir $dir: ", scalar(@tmp), " entries\n");

    my @ret = ();
    my $file;
    foreach $file ( @tmp ) {

	# Skip unwanted files.
	next if $file =~ /^\.\.?$/; # dot and dotdot
	next if $file =~ /~$/;	# editor backup files
        
        my $fname = "$dir/$file";
        my $compare_name;
        if ( $compare_dir ) {
	    $compare_name = "$compare_dir$file";
        }
	else {
	    $compare_name = "$file";          
        }

        # Skip exclusions.
        if ( defined $exclude_pat && $compare_name =~ /$exclude_pat/mso ) {
          verbose ("Excluding $compare_name\n");
          next;
        }

	# Push on the list.
	if ( -d $fname && ( $opt_follow || ! -l $fname ) ) {
	    # Recurse.
	    push (@ret, make_filelist ($fname,
                                       $compare_dir . "$file/",
                                       $disp . "$file/"));
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

sub domanifest ($) {
    my ($man) = @_;
    my $MAN = new IO::File;
    my @ret = ();

    open ($MAN, $man) || die ("$man: $!\n");
    while ( <$MAN> ) {
	if ( $. == 2 && /^[-=_\s]*$/ ) {
	    @ret = ();
	    next;
	}
	next if /^#/;
	next unless /\S/;
	$_ = $` if /\s/;
	push (@ret, $_);
    }
    close ($MAN);
    @ret = grep ($_ !~ /$exclude_pat/mso, @ret) if defined $exclude_pat;
    @ret = sort @ret if $opt_sort;
    @ret;
}

sub dodiff ($$$$$) {
    my ($olddir, $old, $newdir, $new, $fixpath) = @_;

    # Produce a patch hunk.

    my $cmd = $opt_diff;

    # Check for dangerous file names.
    my $f;
    for $f ( $olddir.$old, $newdir.$new ) {
	if ( $f !~ /\'/ ) {
	    $cmd .= " '$f'";
	}
	elsif ( $f !~ /[\"\$\`]/ ) {
	    $cmd .= " \"$f\"";
	}
	else {
	    print STDERR ("Dangerous filename $f -- skipped\n");
	    return;
	}
    }
    trace ("+ ", $cmd, "\n");
    my $result = system ("$cmd > $tmpfile");
    debug  (sprintf ("+> result = 0x%x\n", $result)) if $result;

    if ( $result && $result < 128 ) {
	wrapup (($result == 2 || $result == 3) 
		? "User request" : "System error");
	exit (1);
    }
    return unless $result == 0x100;	# no diffs
    $patched++;

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

    # Add output from user defined file information command.
    if ( defined $opt_infocmd ) {
	my $cmd = $opt_infocmd;
	$cmd =~ s/\002P/$olddir$old/g;
	$cmd =~ s/\003P/$newdir$new/g;
	print PATCH (`$cmd`);
    }

    # Copy patch.
    open (TMP, $tmpfile);
    if ( $fixpath ) {
	# As told by Nigel Metheringham <Nigel.Metheringham@ThePLAnet.net>.
	# Fix up pathnames of diff to feed a bug in patch
	# only looks at first 3 lines of diff.
	# The wierd methodology is to avoid strange RE effects.
	my $linecnt = 0;
	my $line;
	my $fnoff;
	while ( defined ($line = <TMP>) ) {
	    if ( $line =~ /^\*{3}\s+/ ) {
		$fnoff = length ($&);
		substr ($line, $fnoff, length($olddir)) = ""
		  if substr ($line, $fnoff, length($olddir)) eq $olddir;
	    }
	    elsif ( $line =~ /^\-{3}\s+/ ) {
		$fnoff = length ($&);
		substr ($line, $fnoff, length($newdir)) = ""
		  if substr ($line, $fnoff, length($newdir)) eq $newdir;
	    }
	    print PATCH ($line);
	    last if ++$linecnt > 2;
	}
	print PATCH <TMP>;
    }
    else {
	# As told by Ulrich Pfeifer (pfeifer@ls6.informatik.uni-dortmund.de).
	my $ndir = $newdir;
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

sub wrapup (;$) {
    my ($reason) = @_;

    if ( defined $reason ) {
	print STDERR ("*** Aborted: $reason ***\n");
    }
    verbose ("Collecting: $patched patch",
	     $patched == 1 ? "" : "es", "... ");
    print STDOUT ("\n") if $opt_verbose && -t STDOUT;

    my $tmp = '';
    $tmp = "\n#     /bin/sh <this-file>" if @goners || %newcomers;
    my $ts = "".localtime(time);
    print STDOUT <<EOD;
# This is a patch for $old to update it to $new.
# It was generated by $my_name $my_version on $ts.
#
# To apply this patch, chdir to source directory $old and enter
#$tmp
#     patch -p1 -N < <this-file>

EOD

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
	      if defined $newcomers{$_} && $newcomers{$_} & 0111; 
	}
    }
    print STDOUT <<EOD;
exit
# End of preamble.

EOD

    # Copy patch.
    open (PATCH, $thepatch);
    print STDOUT while <PATCH>;
    close (PATCH);

    # Print a reassuring "End of Patch" note so people won't
    # wonder if their mailer truncated patches.
    print STDOUT ("\n\nEnd of Patch.\n");

    # Cleanup.
    unlink ($tmpfile, $thepatch);

    return unless $opt_verbose;

    my $goners = scalar (@goners);
    print STDERR ("Collecting patches... ") if -t STDOUT;
    print STDERR ("done.\n");
    if ( $created ) {
	print STDERR ("  $created file", 
		      $created == 1 ? "" : "s");
	print STDERR (" and $dcreated director", 
		      $dcreated == 1 ? "y" : "ies") if $dcreated;
	print STDERR (" need",
		      ($dcreated+$created != 1) ? "" : "s",
		      " to be created.\n");
    }
    if ( $goners ) {
	print STDERR ("  $goners file", 
		      $goners == 1 ? "" : "s");
	print STDERR (" and $dgoners director", 
		      $dgoners == 1 ? "y" : "ies") if $dgoners;
	print STDERR (" need",
		      ($goners+$dgoners != 1) ? "" : "s",
		      " to be removed.\n");
    }
}

sub app_options () {
    my $opt_manifest;
    my $opt_quiet = 0;
    my $opt_help = 0;
    my $opt_exclude_vc = 0;
    my $opt_ident = 0;

    my @o = (
	     "debug"			=> \$opt_debug,
	     "diff=s"			=> \$opt_diff, 
	     "exclude-regex=s@"     	=> \@opt_exclude_regex,
	     "exclude-vc"		=> \$opt_exclude_vc,
	     "exclude=s@"	     	=> \@opt_exclude,
	     "filelist|list"		=> \$opt_filelist,
	     "fixallpath"		=> \$opt_fixallpath,
	     "fixpath"			=> \$opt_fixpath,
	     "follow"			=> \$opt_follow,
	     "help"                 	=> \$opt_help,
	     "ident"			=> \$opt_ident,
	     "infocmd=s"		=> \$opt_infocmd,
	     "manifest|man=s"		=> \$opt_manifest,
	     "newmanifest|newman=s"	=> \$opt_newmanifest,
	     "oldmanifest|oldman=s"	=> \$opt_oldmanifest,
	     "patchlevel=s"		=> \$opt_patchlevel,
	     "prefix=s"			=> \$opt_prefix,
	     "quiet"			=> \$opt_quiet,
	     "sort!"			=> \$opt_sort,
	     "trace"			=> \$opt_trace,
	     "verbose|v"		=> \$opt_verbose,
	    );

    # Process options
    if ( !GetOptions (@o) || $opt_help ) {
	app_usage();
    }

    $opt_trace = 1 if $opt_debug;
    $opt_verbose = 0 if $opt_quiet;

    print STDERR ("This is $my_name version $my_version\n")
      if $opt_verbose || $opt_ident;

    if ( $opt_prefix ne '' ) {
	die ("$0: option \"-prefix\" requires \"-filelist\"\n")
	  unless $opt_filelist;
    }
    if ( defined $opt_sort ) {
	die ("$0: option \"-[no]sort\" requires \"-filelist\"\n")
	  unless $opt_filelist;
    }
    else {
	$opt_sort = 1;
    }
    if ( $opt_filelist ) {
	die ("$0: option \"-filelist\" only uses \"-manifest\"\n")
	  if defined $opt_oldmanifest || defined $opt_newmanifest;
    }
    if ( defined $opt_manifest ) {
	die ("$0: do not use \"-manifest\" with \"-oldmanifest\"".
	     " or \"-newmanifest\"\n")
	  if defined $opt_newmanifest || defined $opt_oldmanifest;
	$opt_newmanifest = $opt_oldmanifest = $opt_manifest;
    }
    if ( defined $opt_infocmd ) {
	die ("$0: \"-infocmd\" can not be used with \"-filelist\"\n")
	  if $opt_filelist;
	# Protect %% sequences.
	$opt_infocmd =~ s/\%\%/\001/g;
	# Encode %o and %n sequences.
	$opt_infocmd =~ s/\%o([P])/\002$1/g;
	$opt_infocmd =~ s/\%n([P])/\003$1/g;
	# Restore %% sequences.
	$opt_infocmd =~ s/\001/%%/g;
	while ( $opt_infocmd =~ /(\%[on]\S)/g ) {
	    print STDERR ("Warning: $1 in info command may become ",
			  "special in the future\n");
	}
    }

    # Argument check.
    if ( $opt_filelist ) {
	if ( defined $opt_manifest ) {
	    app_usage () if @ARGV;
	    @ARGV = ( $opt_manifest );
	}
	else {
	    app_usage () unless @ARGV == 1;
	}
    }
    else {
	app_usage () unless @ARGV == 2;
    }

    # Exclude options.
    unshift (@opt_exclude_regex, 
	     '(\A|.*/)CVS(/.*|\Z)',
	     '(\A|.*/)RCS(/.*|\Z)', ',v\Z',
	     '(\A|.*/)SCCS(/.*|\Z)', '(\A|.*/)[sp]\..+\Z',
	    ) if $opt_exclude_vc;

}

sub app_usage () {
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
   -infocmd cmd		add output of cmd to each patch chunk
   -exclude pat         exclude files according to wildcard pattern
   -exclude-regex pat   exclude files and dirs matching regex pattern
   -exclude-vc          exclude version control files (RCS, CVS, SCCS)

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
__END__

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

=item B<-infocmd> I<command>

If specified, the output of running I<command> will be added before
each patch chunk. I<command> will undergo the following substitutions
first: C<%oP> will be replaced by the name of the old file, C<%nP>
will be replaced by the name of the new file. C<%%> will be replaced
by a single C<%>; other C<%> sequences may be added in future
versions.

Note that C<%oP> and C<%nP> are modelled after the C<%> sequences of
B<find -printf>.

=item B<-exclude> I<pattern>

If specified, files that match the shell pattern I<pattern> will be
excluded. Only wildcard characters C<*> and C<?>, and character
classes C<[...]> are handled. Multiple B<-exclude> options may be
supplied.

=item B<-exclude-regex> I<pattern>

If specified, files and directories that match the Perl regular
expression pattern I<pattern> will be excluded. 
Multiple B<-exclude-regex> options may be supplied.

=item B<-exclude-vc>

If specified, files and directories that are usually part of version
control systems are excluded. Supported version control systems are
CVS, RCS and SCCS.

B<-exclude-vc> is a quick way to enable exclusion by the following
regular expressions:

	     (\A|.*/)CVS(/.*|\Z)
	     (\A|.*/)RCS(/.*|\Z)
             ,v\Z
	     (\A|.*/)SCCS(/.*|\Z)
             (\A|.*/)[sp]\..+\Z'

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

The exclude options B<-exclude>, B<-exclude-regex> and B<-exclude-vc>
can also be used with b<filelist>.

=head1 GENERAL OPTIONS

=over

=item B<-ident>

The program name and version is reported.

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

=head1 ENVIRONMENT VARIABLES

=over

=item TMPDIR

C<TMPDIR> can be used to designate the area where temporary files are
placed. It defaults to C</usr/tmp>.

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

=head1 BUGS AND RESTRICTIONS

Filenames thet contain single quotes may confuse the process.

B<makepatch> does not know how to handle symbolic links.
These will be ignored.

=head1 SEE ALSO

B<diff>(1),
B<patch>(1),
B<perl>(1),
B<rm>(1).

=head1 AUTHOR AND CREDITS

Johan Vromans (jvromans@squirrel.nl) wrote the program, with a little
help and inspiration from: Jeffery Small (jeff@cjsa.uucp), Ulrich
Pfeifer (pfeifer@ls6.informatik.uni-dortmund.de), Nigel Metheringham
<Nigel.Metheringham@ThePLAnet.net>, Julian Yip <julian@imoney.com>,
Tim Bunce <Tim.Bunce@ig.co.uk>, Rob Browning <rlb@cs.utexas.edu>, and
others.

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
the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA 02111-1307 USA.

=cut
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
