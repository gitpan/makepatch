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
# makepatch.pl -- generate a patch kit from two files or directories.
my $RCS_Id = '$Id: makepatch.pl,v 1.108 1998-11-17 22:24:24+01 jv Exp $ ';
# Author          : Johan Vromans
# Created On      : Tue Jul  7 20:39:39 1992
# Last Modified By: Johan Vromans
# Last Modified On: Tue Nov 17 22:23:52 1998
# Update Count    : 902
# Status          : Experimental
#

use strict;
use Getopt::Long 2.00;
use IO;
use File::Basename;
use File::Spec;

################ Common stuff ################

# $LIBDIR = $ENV{'LIBDIR'} || '/usr/local/lib/sample';
# unshift (@INC, $LIBDIR);
# require 'common.pl';

my $my_package = 'Sciurix';
my $my_name    = "makepatch";
my $my_version = "1.98";
my $data_version = '1.0';

$my_version .= '*' if length('$Locker:  $ ') > 12;
$my_version .= " (2.0BETA)";

################ Globals ################

## Options and defaults

my $opt_diff = 'diff -c';	# diff command
my $opt_sort;			# sort entries. Default = 1
my $opt_follow = 0;		# follow symbolic links
my $opt_automanifest = "MANIFEST";
my $opt_oldmanifest;		# list of files of the old tree
my $opt_newmanifest;		# list of files of the new tree
my $opt_nomanifest = 0;		# suppress use of MANIFEST files
my $opt_patchlevel;		# patchlevel.h file
my $opt_prefix = '';		# prefix to be added
my $opt_filelist = 0;		# make file list
my $opt_infocmd;		# info command
my $opt_exclude_vc = 0;		# exclude VC files
my @opt_exclude;		# list of excludes (wildcards)
my @opt_exclude_regex;		# list of excludes (regex)
my $opt_recurse = 1;		# recurse
my @opt_descr = ();		# description

# Development options (not shown with -help).
my $opt_trace = 0;		# trace messages
my $opt_verbose = 0;		# verbose info
my $opt_quiet = 0;		# (almost?) no info
my $opt_debug = 0;		# debugging messages

## Misc

my $exclude_pat;		# regex to exclude
my @workq = ();			# pre/post work
my $TMPDIR = $ENV{"TMPDIR"} || "/usr/tmp";
my $dot = File::Spec->curdir;	# current dir
my $nul = "/dev/null";		# NLA0:
my $timestamp = "".localtime();	# timestamp, in string format
my $nulpat = quotemeta ($nul);	# pattern to match nul
my $unified = 0;		# produce unified diff

## Subroutine prototypes

sub app_options ();
sub app_parse_rc ($$$);
sub app_usage ();
sub app_usage_filelist ();
sub catfile ($$);
sub check_extract ($$);
sub cleanup ();
sub debug   (@);
sub dodiff ($$$$);
sub makepatch ();
sub extract ($$$);
sub filelist ($);
sub generate_perl ($);
sub generate_shell ($);
sub make_filelist ($;$);
sub make_filelist_from_manifest ($);
sub message (@);
sub newfile ($$);
sub quotfn ($);
sub setup_excludes ();
sub showopts ($);
sub trace   (@);
sub verbose (@);
sub wrapup (;$);
sub yesno ($);

################ INI files, program parameters ################

app_options ();

################ Presets ################

setup_excludes ();
$unified = $opt_diff =~ /\s(-u|-U|--unified)\b/;

################ The Process ################

# Handle --filelist. Special but obsolete case.
if ( $opt_filelist ) {
    filelist ($ARGV[0]);
    exit (0);
}

my ($oldsrc, $newsrc) = @ARGV;

# Create temp dir and names for temp files.
my $tmpdir   = File::Spec->catdir ($TMPDIR, "mp$$.d");
mkdir ($tmpdir, 0777) unless -d $tmpdir;
my $thepatch = catfile ($tmpdir, ".mp$$.p");
my $tmpfile  = catfile ($tmpdir, ".mp$$.t");
my $patch    = new IO::File;

# Attach cleanup handler.
$SIG{INT} = \&cleanup;
$SIG{QUIT} = \&cleanup;

# The process.
makepatch ();

# Wrap up.
wrapup ();

# In case nothing went wrong...
END { cleanup (); }

################ Subroutines ################

sub message (@) { print STDERR (@_) unless $opt_quiet; }
sub verbose (@) { print STDERR (@_) if $opt_verbose; }
sub debug   (@) { print STDERR (@_) if $opt_debug;   }
sub trace   (@) { print STDERR (@_) if $opt_trace;   }

sub makepatch () {

    my ($orig_old, $orig_new) = ($oldsrc, $newsrc);

    # Unpack archives, if applicable.
    my $old = check_extract ($orig_old, "old");
    my $new = check_extract ($orig_new, "new");

    # This will bail out if the directory could not be created.
    $patch->open(">$thepatch") || die ("$thepatch: $!\n");

    if ( -f $old && -f $new ) {
	# Two files.
	verbose ("Old file = $orig_old.\n", "New file = $orig_new.\n");
	dodiff ($dot, $new, $dot, $old) &&
	  push (@workq, [ 'p', $old, -s $old, (stat($new))[9] ]);
    }
    elsif ( -f $old && -d $new ) {
	# File and dir -> File and dir/File.
	my $fn = catfile ($new, $old);
        verbose ("Old file = $orig_old.\n", "New file = $fn.\n");
	if ( -f $fn ) {
	    dodiff ($new, $old, $dot, $old) &&
	      push (@workq, [ 'p', $old, -s $old, (stat($fn))[9] ]);
	}
	else {
	    newfile ($new, $old);
	    push (@workq, [ 'c', $fn, 0, (stat($fn))[9], (stat(_))[2] ]);
	}
    }
    elsif ( -f $new && -d $old ) {
	my $fn = catfile ($old, $new);
	verbose ("Old file = $fn.\n", "New file = $orig_new.\n");
	if ( -f $new ) {
	    dodiff ($dot, $new, $old, $new) &&
	      push (@workq, [ 'p', $fn, -s $fn, (stat($new))[9] ]);
	}
	else {
	    unshift (@workq, [ 'r', $fn, -s $fn, 0 ]);
	}
    }
    else {
	# Should be two directories.
	my (@old, @new);

	if ( $opt_nomanifest ) {
	    verbose ("Not using MANIFEST files.\n");
	    undef $opt_oldmanifest;
	    undef $opt_newmanifest;
	}
	elsif ( defined $opt_automanifest &&
		!(defined $opt_oldmanifest || defined $opt_newmanifest) &&
		 (-s catfile($old, $opt_automanifest) &&
		  -s catfile($new, $opt_automanifest)) ) {
	    verbose ("Using standard $opt_automanifest files.\n");
	    $opt_oldmanifest = catfile($old,$opt_automanifest);
	    $opt_newmanifest = catfile($new,$opt_automanifest);
	}

	if ( defined $opt_oldmanifest ) {
	    @old = make_filelist_from_manifest ($opt_oldmanifest);
	}
	else {
	    @old = make_filelist ($old);
	}

	if ( defined $opt_newmanifest ) {
	    @new = make_filelist_from_manifest ($opt_newmanifest);
	}
	else {
	    @new = make_filelist ($new);
	}

	if ( $opt_verbose ) {
	    message ("Old dir = $orig_old, file list = ",
		     defined $opt_oldmanifest ? $opt_oldmanifest : "<*>",
		     ", ", 
		     scalar(@old), " file", @old == 1 ? "" : "s", ".\n",
		     "New dir = $orig_new, file list = ",
		     defined $opt_newmanifest ? $opt_newmanifest : "<*>",
		     ", ", 
		     scalar(@new), " file", @new == 1 ? "" : "s", ".\n");
	}
	elsif ( !$opt_quiet ) {
	    message ("$orig_old contains ",
		     scalar(@old), " file", @old == 1 ? "" : "s", ".\n",
		     "$orig_new contains ",
		     scalar(@new), " file", @new == 1 ? "" : "s", ".\n");
	}

	# Handle patchlevel file first.
	$opt_patchlevel = (grep (/patchlevel\.h/, @new))[0]
	    unless defined $opt_patchlevel;

	if ( defined $opt_patchlevel && $opt_patchlevel ne "" ) {
	    my $oldpl = catfile ($old, $opt_patchlevel);
	    my $newpl = catfile ($new, $opt_patchlevel);
	    if ( ! -f $newpl ) {
		die ("$newpl: $!\n");
	    }
	    if ( -f $oldpl ) {
		push (@workq, [ dodiff ($new, $opt_patchlevel, 
					$old, $opt_patchlevel) ? 'p' : 'v',
				$opt_patchlevel,
				-s $oldpl,
				(stat($newpl))[9] ]);
	    }
	    else {
		newfile ($new, $opt_patchlevel);
		push (@workq, [ 'c', $opt_patchlevel, 0, 
				(stat($newpl))[9], (stat(_))[2] ]);
	    }
	}
	else {
	    undef $opt_patchlevel;
	}
        
        my $o;
        my $n;

	# Process the filelists.
	while ( @old + @new > 0 || defined $o || defined $n ) {

	    $o = shift (@old) unless defined $o;
	    $n = shift (@new) unless defined $n;
	    
	    if ( defined $n && (!defined $o || $o gt $n) ) {
		# New file.
		if ( defined $opt_patchlevel && $n eq $opt_patchlevel ) {
		    undef $opt_patchlevel;
		}
		else {
		    newfile ($new, $n);
		    push (@workq, [ 'c', $n, 0, (stat(catfile($new,$n)))[9],
				    (stat(_))[2] ]);
                }
		undef $n;
	    }
	    elsif ( !defined $n || $o lt $n ) {
		# Obsolete (removed) file.
		unshift (@workq, [ 'r', $o, -s catfile($old,$o), 0 ]);
		undef $o;
	    }
	    elsif ( $o eq $n ) {
		# Same file.
		if ( defined $opt_patchlevel && $n eq $opt_patchlevel ) {
		    undef $opt_patchlevel;
		}
		else {
		    dodiff ($new, $n, $old, $o) &&
		      push (@workq, [ 'p', $o, -s catfile($old,$o),
				      (stat(catfile($new,$n)))[9] ]);
		}
		undef $n;
		undef $o;
	    }
	}
    }

    $patch->close;

}

sub cleanup () {
    return unless defined $tmpdir;
    return unless -d $tmpdir;
    verbose ("Cleaning up...\n");
    trace ("+ rm -rf $tmpdir\n");
    system ("rm -rf $tmpdir");
    exit (0);
}

sub setup_excludes () {
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
}

sub make_filelist ($;$) {
    my ($dir, $disp) = @_;

    # Return a list of files, sorted, for this directory.
    # Recurses if $opt_recurse.

    my $dh = new IO::File;
    trace ("+ recurse $dir\n");
    opendir ($dh, $dir) || die ("$dir: $!\n");
    my @tmp = sort (readdir ($dh));
    closedir ($dh);
    debug ("Dir $dir: ", scalar(@tmp), " entries\n");

    my @ret = ();
    my $file;
    foreach $file ( @tmp ) {

	# Skip unwanted files.
	next if $file =~ /^\.\.?$/; # dot and dotdot
	next if $file =~ /~$/;	# editor backup files
        
        my $realname = catfile ($dir, $file);
        my $display_name = defined $disp ? catfile($disp,$file) : $file;

        # Skip exclusions.
        if ( defined $exclude_pat && $display_name =~ /$exclude_pat/mso ) {
          verbose ("Excluding $display_name\n");
          next;
        }

	# Push on the list.
	if ( -d $realname && ( $opt_follow || ! -l $realname ) ) {
	    next unless $opt_recurse;
	    # Recurse.
	    push (@ret, make_filelist ($realname, $display_name));
	}
	elsif ( -f _ ) {
	    push (@ret, $display_name);
	}
	else {
	    warn ("Ignored $realname: not a file\n");
	}
    }
    @ret;
}

sub make_filelist_from_manifest ($) {

    # Return a list of files, optionally sorted, from a manifest file.

    my ($man) = @_;
    my $fh = new IO::File;
    my @ret = ();

    $fh->open($man) || die ("$man: $!\n");
    while ( <$fh> ) {
	if ( $. == 2 && /^[-=_\s]*$/ ) {
	    @ret = ();
	    next;
	}
	next if /^#/;
	next unless /\S/;
	$_ = $1 if /^(\S+)\s/;
	push (@ret, $_);
    }
    $fh->close;
    @ret = grep ($_ !~ /$exclude_pat/mso, @ret) if defined $exclude_pat;
    @ret = sort @ret if $opt_sort;
    @ret;
}

sub check_extract ($$) {
    my ($arg, $tag) = @_;

    my @exctrl = ("\.(tar\.gz|tgz)" => "gzip -d | tar xf -",
		  "\.(tar\.bz2)"    => "bzip2 -d | tar xf -",
		  "\.(tar)"         => "tar xf -",
		  "\.(zip)"         => "unzip -",
		 );

    $arg = File::Spec->canonpath ($arg);
    my $base = basename ($arg);

    while ( @exctrl > 0 ) {
	my $pat = shift (@exctrl);
	my $cmd = shift (@exctrl);
	if ( $base =~ /^(.+)$pat$/i ) {
	    my $newkit = extract ($arg, $cmd, $tag);
	    verbose ("Using $newkit for $arg\n");
	    return $newkit;
	}
    }
    return $arg;
}

sub extract ($$$) {
    my ($kit, $cmd, $root) = @_;

    my $tmp = catfile ($tmpdir, $root);
    verbose ("Extracting $kit to $tmp...\n");

    # Create a temp directory.
    mkdir ($tmp, 0777) || die ("Cannot mkdir $tmp [$!]\n");

    # Extract the kit.
    $cmd = "( cd $tmp; $cmd ) < $kit";
    trace ("+ $cmd\n");
    my $ret = system ($cmd);
    exit (1) if $ret || ($? & 127);

    # Inspect the directory.
    my $dir = new IO::File;
    opendir ($dir, $tmp) || die ("Cannot read $tmp [$!]\n");
    my @files = grep ($_ !~ /^\.+$/, readdir ($dir));
    closedir ($dir);

    # If we have only one directory, assume it is the root.
    if ( @files == 1 && -d catfile($tmp,$files[0]) ) {
	return catfile($tmp,$files[0]);
    }
    # Else, take the temp dir as root.
    return $tmp;
}

sub catfile ($$) {
    File::Spec->canonpath(File::Spec->catfile(@_));
}

sub dodiff ($$$$) {
    my ($newdir, $new, $olddir, $old) = @_;
    my $fh = new IO::File;
    my $oldfn = catfile ($olddir, $old);
    my $newfn = catfile ($newdir, $new);

    # Produce a patch hunk.
    my $cmd = $opt_diff . ' ' . quotfn($oldfn) . ' ' . quotfn($newfn);
    trace ("+ ", $cmd, "\n");

    my $result = system ("$cmd > $tmpfile");
    debug  (sprintf ("+> result = 0x%x\n", $result)) if $result;

    if ( $result && $result < 128 ) {
	wrapup (($result == 2 || $result == 3) 
		? "User request" : "System error");
	exit (1);
    }
    return 0 unless $result == 0x100;	# no diffs
    print $patch ($cmd, "\n");

    # Add output from user defined file information command.
    if ( defined $opt_infocmd ) {
	my $cmd = $opt_infocmd;
	$cmd =~ s/\002P/$oldfn/eg;
	$cmd =~ s/\003P/$newfn/eg;
	print $patch (`$cmd`);
    }

    print $patch ("Index: $old\n");

    # Try to find a prereq.
    # The RCS code is based on a suggestion by jima@netcom.com, who also
    # pointed out that patch requires blanks around the prereq string.
    if ( $fh->open($oldfn) ) {
	while ( <$fh> ) {
	    next unless (/(\@\(\#\)\@?|\$Header\:|\$Id\:)(.*)$/);
	    next unless $+ =~ /(\s\d+(\.\d+)*\s)/; # e.g. 5.4
	    print $patch ("Prereq: $1\n");
	    last;
	}
	$fh->close;
    }
    else {
	warn ("$oldfn: $!\n");
    }

    # Copy patch.
    $fh->open($tmpfile) || die ("$tmpfile: $!\n");
    
    # Replace patch header.
    if ( $unified ) {
	print $patch ("--- ", $old, "\t" . localtime((stat($oldfn))[9]), "\n",
		      "+++ ", $new, "\t" . localtime((stat($newfn))[9]), "\n");
	while ( <$fh> ) {
	    if ( /^\@\@/ ) {
		print $patch ($_);
		last;
	    }
	}
    }
    else {
	print $patch ("*** ", $old, "\t" . localtime((stat($oldfn))[9]), "\n",
		      "--- ", $new, "\t" . localtime((stat($newfn))[9]), "\n",
		      "***************\n");
	while ( <$fh> ) {
	    last if /^\*{15}/;
	}
    }

    # Copy rest.
    print $patch ($_) while <$fh>;
    $fh->close;

    return 1;
}

sub newfile ($$) {

    # In-line production of what diff would have produced.

    my ($newdir, $new) = @_;
    my $fh = new IO::File;
    my $newfn = catfile ($newdir, $new);

    my $lines = 0;
    unless ( $fh->open($newfn) ) {
	warn ("$newfn: $!\n");
	return;
    }
    my $pos = $fh->getpos;
    while ( <$fh> ) {
	$lines++;
    }
    $fh->setpos($pos);

    my $cmd = $opt_diff . " " . $nul . " " . quotfn($newfn);
    trace ("+ $cmd (inlined)\n");
    print $patch ($cmd, "\n");

    # Add output from user defined file information command.
    if ( defined $opt_infocmd ) {
	my $cmd = $opt_infocmd;
	$cmd =~ s/\002P/$newfn/eg;
	$cmd =~ s/\003P/$newfn/eg;
	print $patch (`$cmd`);
    }

    print $patch ("Index: $new\n");

    if ( $unified ) {
	print $patch ("--- ", $new, "\t" . localtime(0), "\n",
		      "+++ ", $new, "\t" . localtime((stat($fh))[9]), "\n",
		      "\@\@ -0,0 +", $lines, " \@\@\n");
	while ( <$fh> ) {
	    print $patch ("+$_");
	}
    }
    else {
	print $patch ("*** ", $new, "\t" . localtime(0), "\n",
		      "--- ", $new, "\t" . localtime((stat($fh))[9]), "\n",
		      "***************\n",
		      "*** 0 ****\n",
		      "--- ", $lines, " ----\n");
	while ( <$fh> ) {
	    print $patch ("+ $_");
	}
    }

    $fh->close;
}

sub remove_file ($$) {
    #  diff -c -N -r t1/f2 t2/f2
    #  *** t1/f2       Tue Jul  7 21:28:45 1992
    #  --- t2/f2       Thu Jan  1 01:00:00 1970
    #  ***************
    #  *** 1 ****
    #  - foo
    #  --- 0 ----

    #  diff -u -N -r t1/f2 t2/f2
    #  --- t1/f2       Tue Jul  7 21:28:45 1992
    #  +++ t2/f2       Thu Jan  1 01:00:00 1970
    #  @@ -1 +0,0 @@
    #  -foo
}

sub quotfn ($) {
    my ($file) = @_;
    # Protect file name.
    $file =~ s/`/\\`/g;
    "'$file'";
}

sub yesno ($) {
    $_[0] ? "Yes" : "No";
}

sub showopts ($) {
    my ($fh) = @_;
    my @opt_exclude_regex = ("(none)") unless @opt_exclude_regex;

    print $fh
      ("# Date generated      : $timestamp\n",
       "# Generated by        : $my_name $my_version\n",
       "# Recurse directories : ", yesno ($opt_recurse), "\n",
       "# Excluded files      : ", 
       join("\n#                       ", @opt_exclude_regex), "\n");
}

sub wrapup (;$) {
    my ($reason) = @_;

    if ( defined $reason ) {
	warn ("*** Aborted: $reason ***\n");
	return;
    }

    # Get a description, unless provided.
    unless ( @opt_descr ) {
	print STDERR ("Enter patch description, terminated with a single '.':\n>> ");
	while ( <STDIN> ) {
	    chomp;
	    last if $_ eq ".";
	    push (@opt_descr, $_);
	    print STDERR (">> ");
	}
	print STDERR ("\n") unless $_ eq ".";
    }
    push (@opt_descr, "");

    verbose ("Collecting patches... ");
    print STDOUT ("\n") if $opt_verbose && -t STDOUT;

    my $goners = 0;		# files removed
    my $newcomers = 0;		# files added
    my $patched = 0;		# files patched
    my $dgoners = 0;		# directories removed
    my $dcreated = 0;		# directories created

    {	my @goners = ();
	my %dir_gone = ();
	my @newcomers = ();
	my %dir_ok = ();
	foreach ( @workq ) {
	    my ($op, $fn) = @$_;
	    push (@newcomers, $fn) if $op eq 'c';
	    push (@goners, $fn) if $op eq 'r';
	    $patched++ if $op eq 'p';
	}
	$newcomers = @newcomers;
	$goners = @goners;
	foreach ( sort @goners ) {
	    # WARNING: This code assumes you are running some Unix.
	    my @p = split (/\//, $_);
	    pop (@p);
	    foreach my $i ( (1-@p)..0 ) {
		my $dir = join('/',@p[0..-$i]);
		unless ( defined $dir_gone{$dir} ) {
		    #### TODO: This does not work when newsrc is an archive
		    unless ( -d catfile($newsrc,$dir) ) {
			$dgoners++;
			$dir_gone{$dir} = 1;
		    }
		}
	    }
	}
	foreach ( reverse sort keys %dir_gone ) {
	    push (@workq, [ 'R', $_ ]);
	}
	foreach ( sort @newcomers ) {
	    # Explicitly create the new files since not all patch versions
	    # can handle creating new files. 
	    # Create intermediate directories first.
	    # WARNING: This code assumes you are running some Unix.
	    my @p = split (/\//, $_);
	    pop (@p);
	    foreach my $i ( 0..(@p-1) ) {
		my $dir = join('/',@p[0..$i]);
		unless ( defined $dir_ok{$dir} ) {
		    #### TODO: This does not work when old/newsrc is an archive
		    unless ( -d catfile($oldsrc,$dir) ) {
			push (@workq, [ 'C', $dir, 0, 0, 
					(stat(catfile($newsrc,$dir)))[2] ]);
			$dcreated++;
		    }
		    $dir_ok{$dir} = 1;
		}
	    }
	}
    }

    my $fh = new IO::File;
    $fh->open(">$tmpfile") || die ("$tmpfile: $!\n");

    foreach ( @opt_descr ) {
	print $fh ("# ", $_, "\n");
    }
    print $fh <<EOD;
# To apply this patch:
# STEP 1: Chdir to the source directory.
# STEP 2: Run the 'applypatch' program with this patch file as input.
#
# If you do not have 'applypatch', it is part of the 'makepatch' package 
# that you can fetch from the Comprehensive Perl Archive Network:
# http://www.perl.com/CPAN/authors/Johan_Vromans/makepatch-x.y.tar.gz
# In the above URL, 'x' should be 2 or higher.
#
# To apply this patch without the use of 'applypatch':
# STEP 1: Chdir to the source directory.
EOD
    if ( $goners || $newcomers ) {
	my $cd = "";
	my $fd = "";
	$cd = "create" if $newcomers;
	if ( $goners ) {
	    $cd .= "/" if $cd;
	    $cd .= "delete";
	}
	$fd = "files";
	if ( $dcreated || $dgoners ) {
	    $fd .= "/" if $fd;
	    $fd .= "directories";
	}
	print $fh <<EOD;
# If you have a decent Bourne-type shell:
# STEP 2: Run the shell with this file as input.
# If you don't have such a shell, you may need to manually $cd
# the $fd as shown below.
# STEP 3: Run the 'patch' program with this file as input.
#
# These are the commands needed to create/delete files/directories:
#
EOD
	foreach ( @workq ) {
	    my ($op, $file, @args) = @$_;
	    if ( $op eq 'C' ) {
		print $fh ("mkdir ", quotfn($file), "\n");
		if ( defined $args[2] && ($args[2] &= 0777) ) {
		    printf $fh ("chmod 0%o %s\n", $args[2], quotfn($file))
		}
	    }
	}
	foreach ( @workq ) {
	    my ($op, $file, @args) = @$_;
	    if ( $op eq 'r' ) {
		print $fh ("rm -f ", quotfn($file), "\n");
	    }
	    elsif ( $op eq 'R' ) {
		print $fh ("rmdir ", quotfn($file), "\n");
	    }
	    elsif ( $op eq 'c' ) {
		print $fh ("touch ", quotfn($file), "\n");
		if ( defined $args[2] && ($args[2] &= 0777) ) {
		    printf $fh ("chmod 0%o %s\n", $args[2], quotfn($file))
		}
	    }
	}
	print $fh <<EOD;
#
# This command terminates the shell and need not be executed manually.
exit
#
EOD
    }
    else {
	print $fh <<EOD;
# STEP 2: Run the 'patch' program with this file as input.
#
EOD
    }
    print $fh <<EOD;
#### End of Preamble ####

#### Patch data follows ####
EOD
    # Copy patch.
    $patch->open($thepatch);
    while ( <$patch> ) {
	print $fh $_;
    }
    $patch->close;

    # Print a reassuring "End of Patch" note so people won't
    # wonder if their mailer truncated patches.
    print $fh ("#### End of Patch data ####\n\n");
    print $fh ("#### ApplyPatch data follows ####\n");
    print $fh ("# Data version        : $data_version\n");
    showopts ($fh);

    foreach ( @workq ) {
	my ($op, $file, @args) = @$_;
	$file = quotfn ($file);
	print $fh ("# ", $op, " ", $file);
	if ( defined ($args[2]) && ($op eq 'c' || $op eq 'C') ) {
	    $args[2] = sprintf ("0%o", $args[2]);
	}
	print $fh (" ", join(" ", @args)) if @args;
	print $fh ("\n");
    }

    print $fh ("#### End of ApplyPatch data ####\n");
    print $fh ("\n#### End of Patch kit [created: $timestamp] ####\n");
    $fh->close;

    my $lines = 0;
    my $bytes = 0;
    my $sum = 0;
    $fh->open ($tmpfile) || die ("$tmpfile: $!\n");
    while ( <$fh> ) {
	$lines++;
	chomp;
	$_ .= "\n";
	$bytes += length ($_);
	# System V 'sum' checksum
	$sum = ($sum + unpack ("%16C*", $_)) % 65535;
	print STDOUT ($_);
    }
    $fh->close;
    print STDOUT ("#### Checksum: $lines $bytes $sum ####\n");

    return unless $opt_verbose;

    message ("Collecting patches... ") if -t STDOUT;
    message ("done.\n");
    message ("  $patched file",
	     $patched == 1 ? "" : "s", " need to be patched.\n");
    if ( $newcomers ) {
	message ("  $newcomers file", $newcomers == 1 ? "" : "s");
	message (" and $dcreated director", 
		 $dcreated == 1 ? "y" : "ies") if $dcreated;
	message (" need", ($dcreated+$newcomers != 1) ? "" : "s",
		 " to be created.\n");
    }
    if ( $goners ) {
	message ("  $goners file", $goners == 1 ? "" : "s");
	message (" and $dgoners director", 
		 $dgoners == 1 ? "y" : "ies") if $dgoners;
	message (" need", ($goners+$dgoners != 1) ? "" : "s",
		 " to be removed.\n");
    }
}

sub filelist ($) {
    my ($man) = @_;
    my @new = make_filelist_from_manifest ($man);
    foreach ( @new ) {
	print STDOUT ($opt_prefix, $_, "\n");
    }
}

sub app_options () {
    my $opt_manifest;
    my $opt_help = 0;
    my $opt_exclude_vc = 0;
    my $opt_ident = 0;
    my $opt_rcfile;

    my @o = (
	     "automanifest=s"		=> \$opt_automanifest,
	     "debug!"			=> \$opt_debug,
	     "description=s@"		=> \@opt_descr,
	     "diff=s"			=> \$opt_diff, 
	     "exclude-regex=s@"     	=> \@opt_exclude_regex,
	     "exclude-vc!"		=> \$opt_exclude_vc,
	     "exclude=s@"	     	=> \@opt_exclude,
	     "filelist|list!"		=> \$opt_filelist,
	     "follow!"			=> \$opt_follow,
	     "help"                 	=> \$opt_help,
	     "ident!"			=> \$opt_ident,
	     "infocmd=s"		=> \$opt_infocmd,
	     "manifest=s"		=> \$opt_manifest,
	     "newmanifest=s"		=> \$opt_newmanifest,
	     "nomanifest!"		=> \$opt_nomanifest,
	     "oldmanifest=s"		=> \$opt_oldmanifest,
	     "patchlevel=s"		=> \$opt_patchlevel,
	     "prefix=s"			=> \$opt_prefix,
	     "quiet!"			=> \$opt_quiet,
	     "sort!"			=> \$opt_sort,
	     "recurse!"			=> \$opt_recurse,
	     "trace!"			=> \$opt_trace,
	     "verbose!"			=> \$opt_verbose,
	    );

    my $init;

    # Process ENV options.
    if ( defined ($init = $ENV{MAKEPATCHINIT}) ) {
	require Text::ParseWords;
	local (@ARGV) = Text::ParseWords::shellwords ($init);
	unless ( GetOptions (@o, "rcfile=s" => \$opt_rcfile) &&
		 @ARGV == 0 ) {
	    warn ("Error in MAKEPATCHINIT\n");
	    app_usage ();
	}
	else {
	    trace ("+ INIT: $init\n");
	}
    }

    # Process ini file options.
    my $rcname = ".".$my_name."rc";
    # First, try HOME .rc.
    app_parse_rc (catfile ($ENV{HOME}, $rcname), 1, \@o);
    # Then try --rcfile, defaulting to .rc in current dir.
    if ( defined $opt_rcfile ) {
	app_parse_rc (catfile ($ENV{HOME}, $rcname), 0, \@o);
    }
    else {
	app_parse_rc (catfile ($dot, $rcname), 1, \@o);
    }

    # Process command line options
    if ( !GetOptions (@o) || $opt_help ) {
	app_usage();
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

    $opt_trace = 1 if $opt_debug;

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
	    warn ("Warning: $1 in info command may become ",
		  "special in the future\n");
	}
    }

    # Exclude options.
    unshift (@opt_exclude_regex, 
	     '(\A|.*/)CVS(/.*|\Z)',
	     '(\A|.*/)RCS(/.*|\Z)', ',v\Z',
	     '(\A|.*/)SCCS(/.*|\Z)', '(\A|.*/)[sp]\..+\Z',
	    ) if $opt_exclude_vc;

    $opt_verbose = 0 if $opt_quiet;
}

sub app_parse_rc ($$$) {
    my ($file, $opt, $optref) = @_;

    my $rcfile = new IO::File;
    unless ( $rcfile->open($file) ) {
	die ("$file: $!\n") unless $opt;
	return;
    }

    require Text::ParseWords;

    local (@ARGV);
    my $ok = 1;

    # Intercept Getopt::Long warning messages.
    my $warn;
    $SIG{__WARN__} = sub { $warn = "@_"; };

    # Process the file.
    while ( <$rcfile> ) {
	# Skip blank and comment lines.
	next if /^\s*[;#]/;
	next unless /\S/;

	# Split.
	my @a = Text::ParseWords::shellwords ($_);
	$warn = '';
	trace ("+ RC: @a\n");
	# Handle.
	@ARGV = @a;
	unless ( GetOptions (@$optref) ) {
	    chomp ($warn);
	    print STDERR ("$warn -- at line $. in $file\n");
	    $ok = 0;
	}
	if ( @ARGV > 0 ) {
	    print STDERR ("Garbage \"@ARGV\"",
			  " -- at line $. in $file\n");
	    $ok = 0;
	}
    }
    $rcfile->close;
    $SIG{__WARN__} = 'DEFAULT';
    unless ( $ok ) {
	app_usage ();
    }
    $ok;
}

sub app_usage () {
    print STDERR <<EoU;
This is $my_name version $my_version

Usage: $0 [options] old-src new-src

Makepatch options:
   -description XXX	descriptive message about this patch
   -diff cmd		diff command to use, default \"$opt_diff\"
   -patchlevel file	file to use as patchlevel.h
   -man[ifest] file	list of files for old and new dir, defaults to $opt_automanifest
   -nomanifest		suppress use of MANIFEST files
   -automan[ifest] XXX	assumend name for MANIFEST files
   -newman[ifest] file	list of files for new dir
   -oldman[ifest] file	list of files for old dir
   -follow		follow symbolic links
   -infocmd cmd		add output of cmd to each patch chunk
   -exclude pat         exclude files according to wildcard pattern
   -exclude-regex pat   exclude files and dirs matching regex pattern
   -exclude-vc          exclude version control files (RCS, CVS, SCCS)
   -[no]recurse         recurse through directories (default)
   -generate XXX	style of output, either "perl" (default) or "shell"
   -verbose		verbose progress information
   -quiet		no progress information
   -help		this message
EoU
    exit (1);
}

sub app_usage_filelist () {
    print STDERR <<EoU;
This is $my_name version $my_version

Usage: $0 -filelist [ options ] [ -manifest ] file

Filelist options:
   -[file]list		extract filenames from manifest file
   -prefix XXX		add a prefix to these filenames
   -nosort		do not sort manifest entries
   -man[ifest] file	list of files
   -exclude pat         exclude files according to wildcard pattern
   -exclude-regex pat   exclude files and dirs matching regex pattern
   -exclude-vc          exclude version control files (RCS, CVS, SCCS)
   -verbose		verbose output (default)
   -quiet		no verbose output
   -help		this message
EoU
    exit (1);
}
__DATA__
################ Documentation ################

=head1 NAME

makepatch - create script to update a source tree

=head1 SYNOPSIS

B<makepatch> [ I<options> ] I<old-src> I<new-src>

=for comment
B<makepatch> B<-filelist> [ I<options> ] I<manifest>

=head1 Introduction

Traditionally, source trees are updated with the B<patch> program,
processing patch information that is generated by the B<diff> program.
Although B<diff> and B<patch> do a very good job at patching file
contents, most versions do not handle creating and deleting files and
directories, and adjusting of file modes and time stamps. Newer
versions of B<diff> and B<patch> seem to be able to create files, and
very new versions of B<patch> can remove files. But that's about it.

Another typical problem is that patch kits are typically downloaded
from the Internet, of transmitted via electronic mail. It is often
desirable to verify the correctness of a patch kit before even
attempting to apply it.

The B<makepatch> package is designed to overcome these limitations.

=head1 DESCRIPTION

The B<makepatch> package contains two Perl programs:
B<makepatch> and B<applypatch>.

B<makepatch> will generate a patch kit from two source trees. It
traverses the source directory and runs a B<diff> on each pair of
corresponding files, accumulating the output into a patch kit. It
knows about the conventions for patch kits: if a file named
C<patchlevel.h> exists, it is handled first, so B<patch> can check the
version of the source tree. Also, to deal with the non-perfect
versions of B<patch> that are in use, it supplies "C<Index:>" and
"C<Prereq:>" lines, so B<patch> can correctly locate the files to
patch, and it relocates the patch to the current directory to avoid
problems with creating new files.

The list of files can be specified in a so called B<MANIFEST> file,
but it can also be generated by recursively traversing the source
tree. Files can be excludes using shell style wildcards and Perl regex
patterns.

But that is not it! B<makepatch> also inserts some additional
information in the patch kit for use by the B<applypatch> program.

It is important to emphasize that the generated patch kit is still
valid input for B<patch>. When used with B<patch>, there are no
verifications and problems may arise when new files need to be
created. B<makepatch> prepends a small shell script in front of the
patch kit that creates the necessary files and directories for the
patch process. If you can not run B<applypatch> for some reason, you
can run the patch kit I<as a shell script> to prepare the source
directory for the patching process.

The B<applypatch> program will do the following:

=over 4

=item *

It will extensively verify that the patch kit is complete and not
corrupted during transfer.

=item *

It will apply some heuristics to verify that the directory in
which the patch will be applied does indeed contain the expected
sources.

=item *

It creates files and directories as necessary.

=item *

It applies the patch by running the B<patch> program.

=item *

Upon completion, obsolete files, directories and C<.orig> files are
removed, file modes of new files are set, and the timestamps of
all patched files are adjusted.

=back 

Note that B<applypatch> only requires the B<patch> program. It does not
rely on a shell or shell tools. This makes it possible to apply
patches on non-Unix systems.

=head1 General usage

Suppose you have an archive `C<pkg-1.6.tar.gz>' containing the sources
for package `C<pkg>' version 1.6, and a directory tree `C<pkg-1.7>'
containing the sources for version 1.7. The following command will
generate a patch kit that updates the 1.6 sources into their 1.7
versions:

    makepatch pkg-1.6.tar.gz pkg-1.7 > pkg-1.6-1.7.patch

To apply this script, go to the directory containing the 1.6 sources
and feed the script to B<applypatch>:

    cd old/pkg-1.6
    applypatch pkg-1.6-1.7.patch

B<applypatch> will verify that it is executing in the right place and
make all neccessary updates.

=head1 Makepatch arguments

B<makepatch> requires two arguments: I<old_src> and I<new_src>.

=over 4

=item I<old-src>

This is the name of either a single file or a directory that contains
copies of the older version of the target files; in other words,
copies of the files I<prior> to any modifications.

Alternatively, it may be the name of an archive that holds the files
to be processed. Allowable archive formats are gzipped tar (name ends
in "C<.tar.gz>" or "C<.tgz>"), bzipped tar (name ends in
"C<.tar.bz2>"), plain tar (name ends in "C<.tar>" and zip (name ends in
"C<.zip>").

=item I<new-src>

This is the name of either a single file or a directory that contains
copies of the newer version of the target files; in other words,
copies of the files I<after> the modifications have been made. 

Alternatively, it may be the name of an archive that holds the files
to be processed.

=back

The patch script generated by B<makepatch> will take care of creating
new files and directories, update existing files, and remove files and
directories that are no longer present in the I<new-src> directory.

=head1 MANIFEST files

The purpose of a manifest file is to provide the list of files that
constitute a package. Manifest files are traditionally called
"C<MANIFEST>" and reside in the top level directory of the package.

Although there is no formal standard for the contents of manifest
files, B<makepatch> uses the following rules:

=over 4

=item *

If the second line from the manifest file looks like a separator line
(e.g. it is empty, or contains only dashes), it is discarded and so is
the first line.

=item *

Empty lines and lines that start with a C<#> are ignored.

=item *

If there are multiple space-separated "words" on a line, the first
word is considered to be the filename.

=back

=head2 Default treatment

By default, B<makepatch> looks for files named "C<MANIFEST>" in the
top level directories of the old and the new source trees. If these
files (or one of them) are found, they are used.
If no manifest file could be found, the package is assumed to consist
of all files in the directory.

The default name of the default manifest file can be modified with the
command line option "C<-automanifest>", see Section L<Command line
options>.

=head2 Explicitly naming of manifest files

Command line options "C<-oldmanifest>" and "C<-newmanifest>" can be
used to explicitly designate old and new manifest files. Option
"C<-manifest>" is a short way to set one manifest file for both the
old and new source trees.

=head2 Suppress manifest file processing

Command line option "C<-nomanifest>" can be used to suppress all
manifest file processing. The package is assumed to consist
of all files in the source directories.

=head1 Makepatch options

B<makepatch> takes several options to control its behaviour. Options
are usually specified on the command line, but B<makepatch> can take
options from three sources in the following order:

=over 4

=item *

Environment variable B<MAKEPATCHINIT>.

When this environment variable is set its contents are considered to
be command line options that are processed upon startup. All normal
options are allowed, plus one: B<-rcfile >I<filename>. Option
B<-rcfile> can be used to specify an alternate option file, see below.

=item *

Options files.

B<makepatch> first tries to process a file named B<.makepatchrc> in
the user's home directory.

Empty lines and lines starting with C<;> or C<#> are ignored. All
other lines are considered to contain options exactly as if they had
been supplied on the command line.

After processing this file, B<makepatch> tries to process a file named
B<.makepatchrc> in the current directory. An alternative filename can
be specified with option B<-rcfile> in environment variable
B<MAKEPATCHINIT>. This is the only way to specify an alternative
options file name.

=item *

The command line.

=back

=head1 Command line options

Options are matched case insensitive, and may be abbreviated to uniqueness.

=over 4

=item B<-description> I<text>

Provide a descriptive text for this patch. Multiple B<-description>
options may be supplied.

If no description is provided, the program will ask for one.

=item B<-diff> I<cmd>

If specified, I<cmd> is the command to be used to
generate the differences between the two versions of the files.  If
not specified, this command defaults to "C<diff -c>".

For best results, only use "C<diff -c>" or "C<diff -u>".

=item B<-patchlevel> I<pfile>

If specified, I<pfile> indicates an alternate file that is to be
used in lieu of "B<patchlevel.h>".

=item B<-automanifest> I<mfile>

B<makepatch> will automatically use manifest files of the given name
if they appear in the directories. The default name is "B<MANIFEST>".

=item B<-nomanifest>

Suppress using manifest files.

=item B<-manifest> I<mfile>

If specified, I<mfile> indicates the name of the manifest file
which consists of a list of the files contained in both the I<old>
and the I<new> directories.

=item B<-oldmanifest> I<omfile>

If specified, I<omfile> indicates the name of the manifest file which
consists of a list of the files contained in the I<old> directory.
This option is designed to be used in conjunction with the
B<-newmanifest> option.  Note that the I<old> and I<new> directories
must still be indicated.

=item B<-newmanifest> I<nmfile>

If specified, I<nmfile> indicates the name of the manifest file which
consists of a list of the files contained in the I<new> directory.
This option is designed to be used in conjunction with the
B<-oldmanifest> option.  Note that the I<old> and I<new>
directories must still be indicated.

=item B<->[B<no>]B<recurse>

B<makepatch> recurses through directories by default. Option
B<-norecurse> prevents recursion beyond the initial directories.

=item B<->[B<no>]B<follow>

If set, symbolic links to directories are traversed as if they
were real directories.

=item B<-infocmd> I<command>

If specified, the output of running I<command> will be added before
each patch chunk. I<command> will undergo the following substitutions
first: C<%oP> will be replaced by the name of the old file, C<%nP>
will be replaced by the name of the new file. C<%%> will be replaced
by a single C<%>; other C<%> sequences may be added in future
versions. When a new file is being created, the name of the new file
will be supplied for both C<%oP> and C<%nP>.

Note that C<%oP> and C<%nP> are modeled after the C<%> sequences of
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

=item B<->[B<no>]B<exclude-vc>

If set, files and directories that are usually part of version control
systems are excluded. Supported version control systems are CVS, RCS
and SCCS.

B<-exclude-vc> is a quick way to enable exclusion by the following
regular expressions:

	     (\A|.*/)CVS(/.*|\Z)
	     (\A|.*/)RCS(/.*|\Z)
             ,v\Z
	     (\A|.*/)SCCS(/.*|\Z)
             (\A|.*/)[sp]\..+\Z

=begin comment

=back

=head1 Filelist options

=over

=item B<->[B<file>]B<list>

This option instructs B<makepatch> to read a manifest file, and output
the list of files included in this manifest. This option is useful to
turn the contents of a manifest file into a list of files suitable for
other programs.

=item B<-manifest> I<mfile>

If specified, I<mfile> indicates the name of the manifest file to
be used. Alternatively, the name of the manifest file may follow the
command line options.

=item B<-prefix> I<string>

Every entry in the manifest file is prefixed with I<string> before it
is written to standard output.

=item B<-nosort>

Retain the order of filenames from the manifest file.

=back

The exclude options B<-exclude>, B<-exclude-regex> and B<-exclude-vc>
can also be used with B<filelist>.

=over *

=end comment

=item B<->[B<no>]B<ident>

If set, the program name and version is reported.

=item B<->[B<no>]B<verbose>

This is set by default, making B<makepatch> display information concerning
itsactivity to I<stderr>.

=item B<->[B<no>]B<quiet>

The opposite of B<-verbose>. If set, this instructs B<makepatch> to
suppress the display of activity information.

=item B<->[B<no>]B<help>

If set, this causes a short help message to be displayed, after which
the program immediately exits.

=back

=head1 Environment variables

=over

=item MAKEPATCHINIT

When this environment variable is set its contents is considered to be
command line options that are processed upon startup. All normal
options are allowed, plus one: B<-rcfile >I<filename>. If B<-rcfile>
is specified, the file is read and all lines of it are considered to
contain option settings as described in section L<Makepatch options>.

=item TMPDIR

C<TMPDIR> can be used to designate the area where temporary files are
placed. It defaults to C</usr/tmp>.

=back

=head1 Examples

Suppose you have a directory tree `C<pkg-1.6>' containing the sources
for package `C<pkg>' version 1.6, and a directory tree `C<pkg-1.7>'
containing the sources for version 1.7. The following command will
generate a patch kit that updates the 1.6 sources into their 1.7
versions:

    makepatch pkg-1.6 pkg-1.7 > pkg-1.6-1.7.patch

To apply this script, go to the pkg-1.6 directory and feed the
script to B<applypatch>:

    cd old/pkg-1.6
    applypatch pkg-1.6-1.7.patch

B<applypatch> will verify that it is executing in the right place and
make all neccessary updates.

This is one way to generate and use manifest files:

    (cd pkg-1.6; find . -type f -print > OLDMANIFEST)

    (cd pkg-1.7; find . -type f -print > NEWMANIFEST)

    makepatch \
      -oldmanifest pkg-1.6/OLDMANIFEST \
      -newmanifest pkg-1.7/NEWMANIFEST \
      pkg-1.6 pkg-1.7 > pkg-1.6-1.7.diff

=begin comment

The following example transforms the manifest file into a list of
files suitable for GNU tar. Note the trailing C</> in the prefix
string:

  makepatch -filelist -prefix pkg-1.7/ pkg-1.7/MANIFEST | \
    tar -cvf - -T -Op | gzip > pkg-1.7.tar.gz 

=end comment

=head1 Bugs and restrictions

B<makepatch> does not know about symbolic links.
These will be treated like plain files.

=head1 SEE ALSO

B<applypatch>(1),
B<diff>(1),
B<patch>(1),
B<perl>(1),
B<rm>(1).

=head1 AUTHOR AND CREDITS

Johan Vromans (jvromans@squirrel.nl) wrote the program, with a little
help and inspiration from: Jeffery Small, Ulrich Pfeifer, Nigel
Metheringham, Julian Yip, Tim Bunce, Gurusamy Sarathy, Hugo van der
Sanden, Rob Browning, and others.

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 1992,1998 by Johan Vromans.

This program is free software; you can redistribute it and/or modify
it under the terms of either: a) the GNU General Public License as
published by the Free Software Foundation; either version 1, or (at
your option) any later version, or b) the "Artistic License" which
comes with Perl.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See either the
GNU General Public License or the Artistic License for more details.

=cut
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
