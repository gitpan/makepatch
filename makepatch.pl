#!/usr/local/bin/perl
# makepatch.pl -- generate batch of patches.
$RCS_Id = '$Id: makepatch.pl,v 1.10 1995/10/29 11:14:46 jv Exp $ ';
# Author          : Johan Vromans
# Created On      : Tue Jul  7 20:39:39 1992
# Last Modified By: Johan Vromans
# Last Modified On: Sun Oct 29 12:13:52 1995
# Update Count    : 136
# Status          : Released to USEnet.
#
# Generate a patch from two files or directories.
#
# Resembles "diff -c -r -N", but:
#
#   - always recursive
#   - handles 'patchlevel.h' first
#   - supplies 'Index:' and 'Prereq:' lines
#   - can use manifest file
#   - generates shell commands to remove files
#   - manipulates manifest files
#
################################################################
#
# Usage:
# 
#   makepatch <old-dir> <new-dir
# 
#     This will compare all files in <new-dir> against the files in
#     <old-dir>, and generate a bunch of patches to transform every
#     file in <old-dir> into the corresponding one in <new-dir>.
#     Files that appear in <new-dir> but not in <old-dir> are created.
#     For files that appear in <old-dir> but not in <new-dir>
#     'rm'-commands are generated at the beginning of the patch.
# 
# Using MANIFEST files:
# 
#   makepatch -oldmanifest <oldmanifest> -newmanifest <newmanifest> \
#           <new-dir> <old-dir>
# 
#     <oldmanifest> and <newmanifest> list the files in <old-dir>
#     and <new-dir> that are to be examined.
#     Only the files that are named will be examined. 
#     <oldmanifest> should contain the names of the files relative to
#     <old-dir> and <newmanifest> should contain the names of the files
#     relative to <new-dir>.
# 
#   makepatch -manifest <manifest> <new-dir> <old-dir>
# 
#     This is a simplified form of the above example.
#     <manifest> applies to both <old-dir> and <new-dir>.
# 
#   makepatch -filelist [ -prefix xxx ] manifest
#
#     The filenames are extracted from the manifest file,
#     optionally prefixed, sorted and written to standard output.
#
# Examples:
# 
#   % makepatch -verbose emacs-18.58 emacs-18.59 > emacs-18.58-18.59.diff
# 
#   % (cd emacs-18.58; find . -type f -print > MANIFEST)
#   % (cd emacs-18.59; find . -type f -print > MANIFEST)
#   % makepatch -verbose \
#         -oldmanifest emacs-18.58/MANIFEST \
#         -newmanifest emacs-18.59/MANIFEST \
#         emacs-18.58 emacs-18.59 > emacs-18.58-18.59.diff
#
#   % makepatch -filelist -prefix emacs-18.59/ emacs-18.59/MANIFEST |
#	gtar -zcvf emacs-18.59.tar.Z -T -
#
################################################################

################ Common stuff ################

# $LIBDIR = $ENV{'LIBDIR'} || '/usr/local/lib/sample';
# unshift (@INC, $LIBDIR);
# require 'common.pl';
$my_package = 'Sciurix';
($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
$my_version .= '*' if length('$Locker:  $ ') > 12;

################ Program parameters ################

&stdio;
&options;
($old, $new) = @ARGV;

print STDERR ("This is $my_name version $my_version\n") if $opt_verbose;

if ( defined $opt_filelist ) {
    @new = &domanifest (shift (@ARGV));
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
&doit ($old, $new);
&wrapup;
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
	&dodiff ("", $old, "", $new);
    }
    elsif ( -f $old && -d $new ) {
	# File and dir -> File and dir/File.
	$new = ( $new =~ m|^\./?$| ) ? "" : "$new/";
	if ( $opt_verbose ) {
	    print STDERR ("Old file = $old.\n",
			  "New file = $new$old.\n");
	}
	&dodiff ("", $old, $new, $old);
    }
    elsif ( -f $new && -d $old ) {
	$old = ( $old =~ m|^\./?$| ) ? "" : "$old/";
	if ( $opt_verbose ) {
	    print STDERR ("Old file = $old$new.\n",
			  "New file = $new.\n");
	}
	&dodiff ($old, $new, "", $new);
    }
    else {
	# Should be two directories.
	local (@old, @new);
	if ( defined $opt_oldmanifest ) {
	    @old = &domanifest ($opt_oldmanifest);
	}
	else {
	    @old = &make_filelist ($old);
	}
	if ( defined $opt_newmanifest ) {
	    @new = &domanifest ($opt_newmanifest);
	}
	else {
	    @new = &make_filelist ($new);
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
		&dodiff ($old, $opt_patchlevel, $new, $opt_patchlevel);
	    }
	    else {
		$created++;
		&dodiff ("", "/dev/null", $new, $opt_patchlevel);
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
		    &dodiff ("", "/dev/null", $new, $n);
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
		    &dodiff ($old, $o, $new, $n);
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
	    push (@ret, &make_filelist ($fname, "$disp$file/"));
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
    local ($olddir, $old, $newdir, $new) = @_;

    # Produce a patch hunk.

    local ($cmd) = "$opt_diff '$olddir$old' '$newdir$new'";
    print STDERR ("+ ", $cmd, "\n") if $opt_trace;
    $result = system ("$cmd > $tmpfile");
    printf STDERR ("+> result = 0x%x\n", $result) 
	if $result && $opt_debug;

    if ( $result && $result < 128 ) {
	&wrapup (($result == 2 || $result == 3) 
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
    print PATCH <TMP>;
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
		      $patched == 1 ? "" : "es");
	print STDERR (" ($created new file", 
		      $created == 1 ? "" : "s", ")") if $created;
	print STDERR (", $goners goner", 
		      $goners == 1 ? "" : "s") if $goners;
	print STDERR (".\n");
    }
    if ( @goners ) {
	print STDOUT 
	    ("# Please remove the following file",
	     @goners == 1 ? "" : "s", " before applying this patch.\n",
	     "# (You can feed this patch to 'sh' to do so.)\n",
	     "\n");
	foreach ( @goners ) {
	    print STDOUT ("rm -f ", $_, "\n");
	}
	print STDOUT ("exit\n\n");
    }

    # Copy patch.
    open (PATCH, $thepatch);
    print while <PATCH>;
    close (PATCH);

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
    local ($opt_manifest);
    local ($opt_quiet);

    # Defaults...
    $opt_diff = "diff -c";
    $opt_verbose = 1;
    $opt_follow = 0;

    # Process options, if any...
    if ( $ARGV[0] =~ /^-/ ) {
	require "newgetopt.pl";

	# Aliases.
	*opt_man = *opt_manifest;
	*opt_oldman = *opt_oldmanifest;
	*opt_newman = *opt_newmanifest;
	*opt_v = *opt_verbose;
	*opt_list = *opt_filelist;

	if ( ! &NGetOpt ("patchlevel=s", "diff=s", 
			 "manifest=s", "newmanifest=s", "oldmanifest=s",
			 "man=s", "newman=s", "oldman=s", "follow",
			 "list", "filelist", "prefix=s", "nosort",
			 "quiet", "verbose", "v", "help", "debug", "trace")
	    || defined $opt_help ) {
	    &usage;
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
	    &usage if @ARGV;
	    @ARGV = ( $opt_manifest );
	}
	else {
	    &usage unless @ARGV == 1;
	}
    }
    else {
	&usage unless @ARGV == 2;
    }
}

sub usage {
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
