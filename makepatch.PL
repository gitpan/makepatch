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
my $RCS_Id = '$Id: makepatch.pl,v 1.95 1998-11-01 16:58:05+01 jv Exp jv $ ';
# Author          : Johan Vromans
# Created On      : Tue Jul  7 20:39:39 1992
# Last Modified By: Johan Vromans
# Last Modified On: Sun Nov  1 17:11:37 1998
# Update Count    : 634
# Status          : Experimental
#
# Generate a patch kit from two files or directories.

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
my ($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
$my_version = sprintf ("%d.%02d", $1, $2)
  if $my_version =~ /^(\d+)\.(\d+)$/;
$my_version .= '*' if length('$Locker: jv $ ') > 12;
$my_version .= " (2.0BETA)";

################ Globals ################

## Options and defaults

my $opt_generate;		# style of output
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

my $opt_trace = 0;		# trace messages
my $opt_verbose = 1;		# verbose info
my $opt_debug = 0;		# debugging messages

## Misc

my @goners = ();		# files removed
my %newcomers = ();		# files added
my $patched = 0;		# files patched
my $created = 0;		# files created
my $exclude_pat;		# regex to exclude
my @checkfiles = ();		# for verification
my $TMPDIR = $ENV{"TMPDIR"} || "/usr/tmp";
my $dot = File::Spec->curdir;	# current dir
my $nul = "/dev/null";		# NLA0:

## Subroutines

sub app_options ();
sub app_usage ();
sub debug (@);
sub dodiff ($$$$);
sub doit ($$);
sub domanifest ($);
sub extract ($$$);
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

# Create temp dir and names for temp files.
my $tmpdir   = File::Spec->catdir($TMPDIR, "mp$$.d");
mkdir ($tmpdir, 0777) unless -d $tmpdir;
my $thepatch = catfile($tmpdir, ".mp$$.p");
my $tmpfile  = catfile($tmpdir, ".mp$$.t");

# This will bail out if the directory could not be created.
open (PATCH, ">$thepatch") || die ("$thepatch: $!\n");

# Attach cleanup handler.
$SIG{INT} = \&cleanup;
$SIG{QUIT} = \&cleanup;

# The process.
doit ($old, $new);

# Wrap up.
close (PATCH);
wrapup ();

# In case nothing went wrong...
END { cleanup (); }

################ Subroutines ################

sub verbose (@) { print STDERR (@_) if $opt_verbose; }
sub debug   (@) { print STDERR (@_) if $opt_debug;   }
sub trace   (@) { print STDERR (@_) if $opt_trace;   }

sub doit ($$) {
    my ($old, $new) = @_;

    # Unpack archives. This is Unix specific. Oh well...
    foreach ( $old, $new ) {
	$_ = File::Spec->canonpath ($_);
	if ( /^(.+)\.(tar\.gz|tgz)$/i ) {
	    $_ = extract ($_, "gzip -d | tar xf -", $1);
	}
	elsif ( /^(.+)\.(tar)$/i ) {
	    $_ = extract ($_, "tar xf -", $1);
	}
	elsif ( /^(.+)\.(zip)$/i ) {
	    $_ = extract ($_, "unzip -", $1);
	}
    }

    if ( -f $old && -f $new ) {
	# Two files.
	verbose ("Old file = $old.\n", "New file = $new.\n");
	dodiff ($dot, $old, $dot, $new);
	push (@checkfiles, [ $old, -s $old ]);
    }
    elsif ( -f $old && -d $new ) {
	# File and dir -> File and dir/File.
	my $fn = catfile ($new, $old);
        verbose ("Old file = $old.\n", "New file = $fn.\n");
	if ( -f $fn ) {
	    dodiff ($dot, $old, $new, $old);
	}
	else {
	    dodiff ($dot, "", $new, $old);
	    $newcomers{$fn} = (stat($old))[2];
	}
	push (@checkfiles, [ $old, -s $old ]);
    }
    elsif ( -f $new && -d $old ) {
	my $fn = catfile ($old, $new);
	verbose ("Old file = $fn.\n", "New file = $new.\n");
	if ( -f $new ) {
	    dodiff ($old, $new, $dot, $new);
	}
	else {
	    push (@goners, $fn);
	}
	push (@checkfiles, [ $fn, -s $fn ]);
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

	#$new = ( $new =~ m|^\./?$| ) ? "" : "$new/";
	#$old = ( $old =~ m|^\./?$| ) ? "" : "$old/";
	$new = basename ($new);
	$old = basename ($old);

	if ( $opt_verbose ) {
	    my ($oldstr) = $old;# chomp ($oldstr);
	    my ($newstr) = $new;# chomp ($newstr);
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
	    if ( ! -f catfile($new, $opt_patchlevel) ) {
		die (catfile($new, $opt_patchlevel) . ": $!\n");
	    }
	    if ( -f "$old$opt_patchlevel" ) {
		dodiff ($old, $opt_patchlevel, $new, $opt_patchlevel);
		push (@checkfiles, [ $opt_patchlevel,
				     -s catfile($old,$opt_patchlevel) ]);
	    }
	    else {
		$created++;
		dodiff ($old, "", $new, $opt_patchlevel);
	    }
	}
	else {
	    undef $opt_patchlevel;
	}
        
	foreach ( $old[0], $old[-1] ) {
	    push (@checkfiles, [ $_, -s catfile($old,$_) ]);
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
		    dodiff ($old, "", $new, $n);
                    $newcomers{$n} = 0;
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
		    dodiff ($old, $o, $new, $n);
		}
		undef $n;
		undef $o;
	    }
	}
    }
}

sub cleanup () {
    return unless defined $tmpdir;
    return unless -d $tmpdir;
    verbose ("Cleaning up...\n");
    trace ("+ rm -rf $tmpdir\n");
    system ("rm -rf $tmpdir");
    exit (0);
}

sub make_filelist ($;$$) {
    my ($dir, $compare_dir, $disp) = @_;

    # Return a list of files, sorted, for this directory.
    # Recurses if $opt_recurse.

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
	    next unless $opt_recurse;
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
	$_ = $1 if /^(\S+)\s/;
	push (@ret, $_);
    }
    close ($MAN);
    @ret = grep ($_ !~ /$exclude_pat/mso, @ret) if defined $exclude_pat;
    @ret = sort @ret if $opt_sort;
    @ret;
}

sub extract ($$$) {
    my ($kit, $cmd, $root) = @_;
    verbose ("Extracting $kit to $tmpdir...\n");
    trace ("+ ( cd $tmpdir; $cmd ) < $kit\n");
    my $ret = system ("( cd $tmpdir; $cmd ) < $kit");
    exit (1) if $ret || ($? & 127);
    $kit = catfile ($tmpdir, $root);
    unless ( -d $kit ) {
	die ("Extracting $kit did not produce a directory $root as expected.\n");
    }
    return $kit;
}

sub catfile ($$) {
    File::Spec->canonpath(File::Spec->catfile(@_));
}

sub dodiff ($$$$) {
    my ($olddir, $old, $newdir, $new) = @_;
    my $creating = $old eq "";
    my $fh = new IO::File;

    if ( $creating ) {
	$old = $new;
    }
    # Produce a patch hunk.

    my $cmd = $opt_diff;

    # Check for dangerous file names.
    my $f = $creating ? $nul : catfile($olddir,$old);
    for $f ( $f, catfile($newdir,$new) ) {
	if ( $f eq $nul ) {
	    $cmd .= " $f";
	}
	elsif ( $f !~ /\'/ ) {
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

    # Add output from user defined file information command.
    if ( defined $opt_infocmd ) {
	my $cmd = $opt_infocmd;
	$cmd =~ s/\002P/catfile($olddir,$old)/eg;
	$cmd =~ s/\003P/catfile($newdir,$new)/eg;
	print PATCH (`$cmd`);
    }

    #print PATCH ("Index: ", catfile ($olddir, $old), "\n");
    print PATCH ("Index: $old\n");

    unless ( $creating ) {
	# Try to find a prereq.
	# The RCS code is based on a suggestion by jima@netcom.com, who also
	# pointed out that patch requires blanks around the prereq string.
	open ($fh, catfile ($olddir, $old));
	while ( <$fh> ) {
	    next unless (/(\@\(\#\)\@?|\$Header\:|\$Id\:)(.*)$/);
	    next unless $+ =~ /(\s\d+(\.\d+)*\s)/; # e.g. 5.4
	    print PATCH ("Prereq: $1\n");
	    last;
	}
	close ($fh);
    }

    # Copy patch.
    open ($fh, $tmpfile);

    # Relocate filenames. Check first few lines only.
    while ( <$fh> ) {
	if ( /^(\*\*\*|\+\+\+|\-\-\-)\s+(.*)$/ ) {
	    $_ = "$1 ";
	    my $t = $2;
	    # WARNING: this only works on Unix, Windows, ...
	    if ( substr($t,0,length($olddir)) eq $olddir ) {
		$t = substr($t,length($olddir)+1);
	    }
	    elsif ( substr($t,0,length($newdir)) eq $newdir ) {
		$t = substr($t,length($newdir)+1);
	    }
	    elsif ( substr($t,0,length($nul)) eq $nul ) {
		substr($t,0,length($nul)) = $new;
	    }
	    $_ .= $t . "\n";
	}
	print PATCH ($_);
	last if $. > 2;
    }

    # Copy rest.
    print PATCH <$fh>;
    close ($fh);
}

sub perlfn ($) {
    my ($file) = @_;
    # Protect file name from string expansion. 
    '"'.quotemeta($file).'"';
}

sub generate_perl ($) {
    my ($cmds) = @_;

    my $ts = "".localtime(time);

    # Copy perl program from DATA.
    while ( <DATA> ) {

	if ( /^__END__/ ) {
	    print STDOUT ("__END__\n\n");
	    last;
	}

	if ( /^#### Commands go here/ ) {
	    foreach ( @$cmds ) {
		my ($op, $file, $arg) = @$_;
		if ( $op eq 'r' ) {
		    print STDOUT ("remove_file (".perlfn($file).");\n");
		}
		elsif ( $op eq 'R' ) {
		    print STDOUT ("remove_directory (".perlfn($file).");\n");
		}
		elsif ( $op eq 'C' ) {
		    print STDOUT ("create_directory (".perlfn($file));
		    print STDOUT (", $arg") if defined $arg;
		    print STDOUT (");\n");
		}
		elsif ( $op eq 'c' ) {
		    print STDOUT ("create_file (".perlfn($file));
		    print STDOUT (", $arg") if defined $arg;
		    print STDOUT (");\n");
		}
	    }
	}
	elsif ( /^#### Check goes here/ ) {
	    my $tag = "check (";
	    foreach ( @checkfiles ) {
		my ($file, $size) = @$_;
		print STDOUT ($tag, perlfn($file).", $size");
		$tag = ",\n       ";
	    }
	    print STDOUT (");\n");
	}
	elsif ( /^#### Show options/ ) {
	    print STDOUT ("# This program updates $old to $new.\n#\n");
	    showopts ($ts);
	}
	elsif ( /^my \$olddir/ ) {
	    print STDOUT ("my \$olddir = ".perlfn($old).";\n");
	}
	elsif ( /^my \$newdir/ ) {
	    print STDOUT ("my \$newdir = ".perlfn($new).";\n");
	}
	elsif ( /^It was generated/ ) {
	    print STDOUT ("It was generated by " . $my_name . " " . 
			  $my_version . " on " . $ts . ".\n");
	}
	elsif ( /^my \$endpat/ ) {
	    print STDOUT ("my \$endpat = \"End of Patch [created: $ts]\";\n");
	}
	elsif ( /^my \$realsize/ ) {
	    printf STDOUT ("my \$realsize = %d;\n", (-s $thepatch) + 3);
	}
	else {
	    print STDOUT $_;
	}
    }

    # Copy patch.
    open (PATCH, $thepatch);
    while ( <PATCH> ) {
	print STDOUT $_;
    }
    close (PATCH);

    # Print a reassuring "End of Patch" note so people won't
    # wonder if their mailer truncated patches.
    print STDOUT ("\n\nEnd of Patch [created: $ts]\n");
}

sub generate_shell ($) {
    my ($cmds) = @_;

    my $tmp = '';
    $tmp = "\n#     /bin/sh <this-file>" if @goners || %newcomers;
    my $ts = "".localtime(time);
    print STDOUT <<EOD;
# This is a patch for $old to update it to $new.
# It was generated by $my_name $my_version on $ts.
#
# To apply this patch, chdir to directory $old and enter
#$tmp
#     patch -p0 -N < <this-file>
#
EOD
    showopts ($ts);
    print STDOUT ("#\n");
    foreach ( @$cmds ) {
	my ($op, $file, $arg) = @$_;
	if ( $op eq 'r' ) {
	    print STDOUT ("rm -f $file\n");
	}
	elsif ( $op eq 'R' ) {
	    print STDOUT ("rmdir $file\n");
	}
	elsif ( $op eq 'C' ) {
	    print STDOUT ("mkdir $file\n");
	}
	elsif ( $op eq 'c' ) {
	    print STDOUT ("touch $file\n");
	    printf STDOUT ("chmod %o %s\n", $arg, $file) if defined $arg;
	}
    }

    print STDOUT <<EOD;
exit
# End of preamble.

# Patch input follows.
EOD

    # Copy patch.
    open (PATCH, $thepatch);
    print STDOUT while <PATCH>;
    close (PATCH);

    # Print a reassuring "End of Patch" note so people won't
    # wonder if their mailer truncated patches.
    print STDOUT ("\n\nEnd of Patch.\n");
}

sub YN ($) {
    $_[0] ? "Yes" : "No";
}

sub showopts ($) {
    my ($ts) = @_;

    my $opt_automanifest = $opt_automanifest || "(none)";
    my $opt_newmanifest  = $opt_newmanifest || "(none)";
    my $opt_oldmanifest  = $opt_oldmanifest || "(none)";
    my $opt_infocmd      = $opt_infocmd || "(none)";
    my $opt_patchlevel   = $opt_patchlevel || "(none)";
    my @opt_exclude_regex = ("(none)") unless @opt_exclude_regex;
    $opt_infocmd =~ s/\002/%o/g;
    $opt_infocmd =~ s/\003/%n/g;

    print STDOUT 
      ("# Patch characteristics:\n#\n",
       "#   New source            : $new\n",
       "#   Old source            : $old\n",
       "#   Date generated        : $ts\n",
       "#   Generated by          : $my_name $my_version\n",
       "#   Program written by    : Johan Vromans <jvromans\@squirrel.nl>\n",
       "#   Diff command used     : $opt_diff\n",
       "#   Recurse directories   : ", YN ($opt_recurse), "\n",
       "#   Follow symbolic links : ", YN ($opt_follow), "\n",
       "#   Use manifest files    : ", YN (!$opt_nomanifest), "\n");
    print STDOUT
      ("#   Manifest (auto)       : $opt_automanifest\n",
       "#             (old)       : $opt_oldmanifest\n",
       "#             (new)       : $opt_newmanifest\n") 
	unless $opt_nomanifest;
    print STDOUT
      ("#   Patchlevel file       : $opt_patchlevel\n",
       "#   Info command          : $opt_infocmd\n",
       "#   Excluded files        : ", 
       join("\n#                           ", @opt_exclude_regex), "\n");
}

sub wrapup (;$) {
    my ($reason) = @_;

    if ( defined $reason ) {
	print STDERR ("*** Aborted: $reason ***\n");
    }
    verbose ("Collecting: $patched patch",
	     $patched == 1 ? "" : "es", "... ");
    print STDOUT ("\n") if $opt_verbose && -t STDOUT;

    my @cmds = ();
    my $dgoners = 0;
    {
	my %dir_gone = ();
	foreach ( sort @goners ) {
	    push (@cmds, [ 'r', $_ ]);
	    # WARNING: This code assumes you are running some Unix.
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
	    push (@cmds, [ 'R', $_ ]);
	}
    }
    my $dcreated = 0;
    {
	my %dir_ok = ();
	foreach ( sort keys %newcomers ) {
	    # Explicitly create the new files since not all patch versions
	    # can handle creating new files. 
	    # Create intermediate directories first.
	    # WARNING: This code assumes you are running some Unix.
	    my @p = split (/\//, $_);
	    pop (@p);
	    foreach my $i ( 0..(@p-1) ) {
		my $dir = join('/',@p[0..$i]);
		unless ( defined $dir_ok{$dir} ) {
		    unless ( -d "$old/$dir" ) {
			push (@cmds, [ 'C', $dir ]);
			$dcreated++;
		    }
		    $dir_ok{$dir} = 1;
		}
	    }
	    # Create the file and change the mode if needed.
	    if ( defined $newcomers{$_} && $newcomers{$_} & 0111 ) {
		push (@cmds, [ 'c', $_, $newcomers{$_} & 0777 ])
	    }
	    else {
		push (@cmds, [ 'c', $_ ]);
	    }
	}
    }

    if ( lc($opt_generate) eq 'perl' ) {
	generate_perl (\@cmds);
    }
    else {
	generate_shell (\@cmds);
    }

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
    my $opt_help = 0;
    my $opt_exclude_vc = 0;
    my $opt_ident = 0;
    my $opt_rcfile;

    my @o = (
	     "automanifest=s"		=> \$opt_automanifest,
	     "debug!"			=> \$opt_debug,
	     "diff=s"			=> \$opt_diff, 
	     "exclude-regex=s@"     	=> \@opt_exclude_regex,
	     "exclude-vc!"		=> \$opt_exclude_vc,
	     "exclude=s@"	     	=> \@opt_exclude,
	     "filelist|list!"		=> \$opt_filelist,
	     "follow!"			=> \$opt_follow,
	     "generate=s"		=> \$opt_generate,
	     "help"                 	=> \$opt_help,
	     "ident!"			=> \$opt_ident,
	     "infocmd=s"		=> \$opt_infocmd,
	     "manifest=s"		=> \$opt_manifest,
	     "newmanifest=s"		=> \$opt_newmanifest,
	     "nomanifest!"		=> \$opt_nomanifest,
	     "oldmanifest=s"		=> \$opt_oldmanifest,
	     "patchlevel=s"		=> \$opt_patchlevel,
	     "prefix=s"			=> \$opt_prefix,
	     "quiet!"			=> sub { $opt_verbose = !$_[1]; },
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
	    print STDERR ("Error in MAKEPATCHINIT\n");
	    app_usage ();
	}
    }

    # Process ini file options.
    $init = 1;
    unless ( defined $opt_rcfile ) {
	$opt_rcfile = $ENV{HOME}."/.".$my_name."rc";
	$init = 0;
    }
    my $rcfile = new IO::File;
    if ( open ($rcfile, $opt_rcfile) ) {
	require Text::ParseWords;

	if ( 0 ) {		# Use -options style
	    my @lines = <$rcfile>;
	    close ($rcfile);
	    local (@ARGV) = Text::ParseWords::shellwords (@lines);
	    unless ( GetOptions (@o) && @ARGV == 0 ) {
		print STDERR ("Error in $opt_rcfile\n");
		app_usage ();
	    }
	}
	else {			# Use smail style

	    local (@ARGV);
	    my $ok = 1;

	    # Intercept Getopt::Long warning messages.
	    local (%SIG);
	    my $warn;
	    $SIG{__WARN__} = sub { $warn = "@_"; };

	    # Process the file.
	    while ( <$rcfile> ) {
		# Skip blank and comment lines.
		next if /^\s*[;#]/;
		next unless /\S/;

		# Make sure the "=" gets split.
		s/=/ = /;

		# Split.
		my @a = Text::ParseWords::shellwords ($_);

		# "option = value xxx".
		if ( @a >= 3 && $a[1] eq "=" ) {
		    @a = (shift(@a).shift(@a)."@a");
		}
		# "+ option" or "- option". Reduce.
		elsif ( @a == 2 && $a[0] =~ /^[\-\+]$/ ) {
		    @a = ($a[0].$a[1]);
		}
		# Process possibly reduced cases.
		if ( @a == 1 ) {
		    # "+opt" --> "--opt". Normal case.
		    if ( $a[0] =~ /^\+(.*)/ ) {
			push (@ARGV, "--".$1);
		    }
		    # "-opt" --> "--noopt". Negated case.
		    elsif ( $a[0] =~ /^\-(.*)/ ) {
			push (@ARGV, "--no".$1);
		    }
		    # "opt" or "opt=val". Normal case.
		    else {
			push (@ARGV, "--".$a[0]);
		    }
		    $warn = '';
		    trace ("+ RC: @a\n");
		    # Handle.
		    unless ( GetOptions (@o) ) {
			chomp ($warn);
			print STDERR ("$warn -- at line $. in $opt_rcfile\n");
			$ok = 0;
		    }
		}
		else {
		    print STDERR ("Error in input ",
				  "-- at line $. in $opt_rcfile\n");
		    $ok = 0;
		}
	    }
	    close ($rcfile);
	    unless ( $ok ) {
		app_usage ();
	    }
	}
    }
    # File must be present if explicitly named.
    elsif ( $init ) {
	die ("$opt_rcfile: $!\n");
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
	$opt_sort = 0;
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

    if ( defined $opt_generate ) {
	if ( $opt_generate !~ /^(perl|sh|shell)$/i ) {
	    die ("$0: option \"-generate\" requires a value of ".
		 "\"perl\" or \"shell\"\n");
	}
    }
    elsif ( $opt_verbose ) {
	print STDERR ("Generating a perl program to apply the changes.\n",
		      "(Use \"-generate shell\" to generate a shell script ",
		      "instead.)\n");
	$opt_generate = "perl";
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

Usage: $0 [options] old-src new-src
Usage: $0 -filelist [ -prefix XXX ] [ -nosort ] [ -manifest ] file

Makepatch options:
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
__DATA__
#!/usr/bin/perl -w
eval 'exec perl -w $0 ${1+"$@"}'
  if $running_under_some_shell;
$running_under_some_shell = 0;

#### Show options

################ Common stuff ################

use strict;

################ Command line parameters ################

use Getopt::Long 2.13;
sub app_options();

my $olddir;
my $newdir;

my $check = 0;			# check only
my $patch = 'patch -p0 -N';	# patch command
my $verbose = 0;		# verbose processing
my $force = 0;			# allow continuation after trunc/corruption

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test (no actual processing)

app_options();

# Options post-processing.
$trace |= ($debug || $test);
$patch .= " -s" unless $verbose;

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || '/usr/tmp';

################ The Process ################

sub check (@);
sub create_file ($;$);
sub create_directory ($;$);
sub remove_file ($);
sub remove_directory ($);

# Check that we're in the right place.

#### Check goes here.

# Verify the correctness of the patch.

my $size = 0;
my $endpat = "End of Patch [$ts]";
my $realsize = 1234;
my $pos = tell (DATA);
while ( <DATA> ) {
    chomp;
    last if $_ eq $endpat;
    $size += length($_) + 1;
}
my $die = $force ? \&warn : \&die;
$die->("No \"End of Patch\" seen -- possibly truncated\n")
  unless $_ eq $endpat;
$die->("CORRUPTION: Got $size bytes, expected $realsize bytes\n")
  unless $size == $realsize;

if ( $check ) {
    warn ("Check only -- no changes made\n");
    exit (0);
}

# Preamble.

#### Commands go here.

# End of preamble.

# Execute the patch program.
print STDERR ("+ $patch\n") if $trace;
open (PATCH, "|$patch")
  || die ("Cannot open pipe to \"$patch\"\n");

seek (DATA, $pos, 0);
while ( <DATA> ) {
    last if /^$endpat$/o;
    print PATCH $_;
}
close (PATCH)
  || die ("Possible problems with \"$patch\", status = $?\n");
exit (0);

################ Subroutines ################

sub check (@) {
    my @args = @_;
    my $err = 0;
    while ( @args ) {
	my $file = shift (@args);
	my $size = shift (@args);
	print STDERR ("+ check: $file $size\n") if $trace;
	unless ( -e $file ) {
	    warn ("Integrity check: file $file does not exist\n");
	    $err++;
	}
	unless ( -f _ ) {
	    warn ("Integrity check: $file should be a plain file\n");
	    $err++;
	}
	my $s = -s _;
	unless ( $s == $size ) {
	    warn ("Integrity check: size of file $file should be $size, ".
		  "but it is $s\n");
	    $err++;
	}
    }
    if ( $err ) {
	die ("*** Integrity check failed ***\n",
	     "Apparently this is not the expected source directory $olddir.\n",
	     "Use \"perl $0 -dir <dir>\" to change to the right directory.\n");
    }
}

sub create_file ($;$) {
    my ($file, $mode) = @_;
    $mode = 0666 unless defined $mode;
    print STDERR ("+ create $file\n") if $trace;
    open (F, '>'.$file)
      || die ("Cannot create $file: $!\n");
    close (F);
    printf STDERR ("+ chmod 0%o $file\n", $mode) if $trace;
    chmod ($mode, $file)
      || warn sprintf ("WARNING: Cannot chmod 0%o $file: $!\n", $mode);
}

sub create_directory ($;$) {
    my ($dir, $mode) = @_;
    $mode = 0777 unless defined $mode;
    printf STDERR ("+ mkdir 0%o $dir\n", $mode) if $trace;
    mkdir ($dir, $mode) 
      || die ("Cannot create directory $dir: $!\n");
}

sub remove_file ($) {
    my ($file) = @_;
    print STDERR ("+ unlink $file\n") if $trace;
    unlink ($file)
      || warn ("WARNING: Cannot remove $file: $!\n");
}

sub remove_directory ($) {
    my ($dir) = @_;
    print STDERR ("+ rmdir $dir\n") if $trace;
    rmdir ($dir)
      || warn ("WARNING: Cannot remove directory $dir: $!\n");
}

################ Options and Help ################

sub app_ident;
sub app_usage($);

sub app_options() {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally
    my $dir;			# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;
    
    if ( !GetOptions(
		     'check'	=> \$check,
		     'dir=s'	=> \$dir,
		     'force'    => \$force,
		     'ident'	=> \$ident,
		     'verbose'	=> \$verbose,
		     'quiet'	=> sub { $verbose = 0; },
		     'patch=s'	=> \$patch,
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    ) or $help )
    {
	app_usage(2);
    }
    app_ident if $ident || $verbose;

    if ( defined $dir ) {
	chdir ($dir)
	  || die ("Cannot change to $dir: $!\n");
    }

}

sub app_ident {
    print STDERR <<EOD;
This is a patch for $olddir to update it to $newdir.
It was generated by makepatch.
EOD
}

sub app_usage($) {
    my ($exit) = @_;
    app_ident;
    print STDERR <<EndOfUsage;

To apply this patch, chdir to the source directory $olddir
and run this program. 

Usage: perl $0 [options] [file ...]
    -help		this message
    -dir		change to this directory before executing
    -check              check, but does not execute
    -force              continue after check failures
    -patch XXX		the patch command, default "$patch"
    -ident		show identification
    -quiet		no information
    -verbose		verbose information
EndOfUsage
    exit $exit if $exit != 0;
}
__END__

=head1 NAME

makepatch - create script to update a source tree

=head1 SYNOPSIS

B<makepatch> [ I<options> ] I<old-src> I<new-src>

B<makepatch> B<-filelist> [ I<options> ] I<manifest>

=head1 DESCRIPTION

B<Makepatch> generates a set of differences between two files or two
sets of files maintained in two different directories and prints the
results to I<stdout> in the form of a script. When the script is run,
it uses the B<patch>(1) program to update every file in the source
tree from the old to the new version.

Features of this utility include:

=over 4

=item *

Generates a perl program, optionally a shell script.

The generated perl program will take care of verification that the
source tree to be updated is indeed the right one. It also verifies
that the patch information was not truncated or corrupted during
transfer.

=item *

Generation of commands to remove obsolete files and directories.

Files and directories that were present in the old version but not in
the new version are removed.

=item *

Automatic handling of the I<patchlevel.h> file first.

If a file named "C<patchlevel.h>" exists, it is checked first to
verify that the version matches.

=item *

Automatic generation of I<Index:> and I<Prereq:> lines.

This information will allow the B<patch> program to verify correctness
of files, and allow for the creation of new files.

=item *

Selection using I<manifest> files, wildcards or regular expression patterns.

The list of files to be processed can be controlled by so called
I<manifest> files, and further restricted using shell filename
patterns and B<perl>s regular expression patterns.

=back

=head1 GENERAL USAGE

Suppose you have a directory tree C<pkg-1.16> containing the sources
for a package version 1.16, and a directory tree C<pkg-1.17>
containing the sources for version 1.17. The following command will
generate a perl program that updates the 1.16 sources into their 1.17
versions:

    makepatch pkg-1.16 pkg-1.17 > pkg-1.16-21.17.pl

To apply this script, go to the pkg-1.16 directory and feed the
script to perl:

    cd pkg-1.16
    perl pkg-1.16-21.17.pl

The script will verify that it is executing in the right place and
make all neccessary updates.

=head1 ARGUMENTS

=over 4

=item I<old-src>

This is the name of either a single file or a directory that contains
copies of the older version of the target files; in other words,
copies of the files I<prior> to any modifications.

Alternatively, it may be the name of an archive that holds the files
to be processed. Allowable archive formats are gzipped tar (name ends
in "C<.tar.gz>" or "C<.tgz>"), plain tar (name end in "C<.tar>" and
zip (name ends in "C<.zip>").

B<Important:> When the archive is extracted, the files should be
extracted to a directory that is the base name of the archive. E.g.
C<pkg-1.17.tar.gz> must produce a directory C<pkg-1.17> that
contains the sources.

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

An options file.

By default, B<makepatch> looks for a file named B<.makepatchrc> in the
user's home directory.

An alternative options file can be specified with option B<-rcfile> in
environment variable B<MAKEPATCHINIT>. This is the only way to specify
an alternative options file name.

See section L<OPTIONS FILE SYNTAX> for details on the contents of the
options file.

=item *

The command line.

=back

=head1 MAKEPATCH OPTIONS

Options are matched case insensitive, and may be abbreviated to uniqueness.

=over 4

=item B<-generate> I<type>

This can be used to select the type of script to generate. Default is
a perl program. Alternatively, a script to be executed under the
standard Unix shell I<sh>, can be generated.

I<type> can be B<perl> to designate that a perl program is required,
or B<sh> or B<shell> to designate a shell script.

=item B<-diff> I<cmd>

If specified, I<cmd> is the command to be used to
generate the differences between the two versions of the files.  If
not specified, this command defaults to "B<diff -c>".

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
             (\A|.*/)[sp]\..+\Z'

=back

=head1 FILELIST OPTIONS

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

=head1 GENERAL OPTIONS

=over

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

=head1 MANIFEST FILE SYNTAX

Although there is no formal standard for manifest files, the following
rules apply:

=over 4

=item *

If the second line from the manifest file looks like a separator line
(e.g. it is empty, or contains only dashes), it is discarded and so is
the first line.

=item *

Empty lines and lines that start with a C<#> are ignored.

=item *

If there are multiple space-separated ``words'' on a line, the first
word is considered to be the filename.

=back

=head1 OPTIONS FILE SYNTAX

The options file can contain option settings in the style of the
popular mail program B<smail>.

The lines of the option file can contain the following:

=over 4

=item *

Nothing. Empty lines are ignored.

=item *

A comment, starting with a hatch C<#> or semicolon C<;>. Leading space
is allowed. The line is ignored.

=item *

The name of an option that must be set. It may be preceeded by a plus
sign, C<+>.

=item *

A minus sign followed by the name of an option that must be reset.

=item *

The name of an option, an equal sign C<=>, and the value to be assigned
to this option. The value may be quoted but this is not mandatory.

=back


=head1 ENVIRONMENT VARIABLES

=over

=item MAKEPATCHINIT

When this environment variable is set its contents is considered to be
command line options that are processed upon startup. All normal
options are allowed, plus one: B<-rcfile >I<filename>. If B<-rcfile>
is specified, the file is read and all lines of it are considered to
contain option settings as described in section L<OPTIONS FILE SYNTAX>.

=item TMPDIR

C<TMPDIR> can be used to designate the area where temporary files are
placed. It defaults to C</usr/tmp>.

=back

=head1 EXAMPLES

Suppose you have a directory tree C<pkg-1.16> containing the sources
for a popular package version 1.16, and a directory tree C<pkg-1.17>
containing the sources for version 1.17. The following command will
generate the patch file needed to transform the 1.16 sources into
1.17:

    makepatch pkg-1.16 pkg-1.17 > pkg-1.16-1.17.diff

This is one way to generate and use manifest files:

    (cd pkg-1.16; find . -type f -print > OLDMANIFEST)

    (cd pkg-1.17; find . -type f -print > NEWMANIFEST)

    makepatch \
      -oldmanifest pkg-1.16/OLDMANIFEST \
      -newmanifest pkg-1.17/NEWMANIFEST \
      pkg-1.16 pkg-1.17 > pkg-1.16-1.17.diff

The following example transforms the manifest file into a list of
files suitable for GNU tar. Note the trailing C</> in the prefix
string:

  makepatch -filelist -prefix pkg-1.17/ pkg-1.17/MANIFEST | \
    tar -cvf - -T -Op | gzip > pkg-1.17.tar.gz 

=head1 BUGS AND RESTRICTIONS

Filenames thet contain single quotes may confuse the process.

B<makepatch> does not know about symbolic links.
These will be treated like plain files.

=head1 SEE ALSO

B<diff>(1),
B<patch>(1),
B<perl>(1),
B<rm>(1).

=head1 AUTHOR AND CREDITS

Johan Vromans (jvromans@squirrel.nl) wrote the program, with a little
help and inspiration from: Jeffery Small (jeff@cjsa.uucp), Ulrich
Pfeifer (pfeifer@ls6.informatik.uni-dortmund.de), Nigel Metheringham
<Nigel.Metheringham@ThePLAnet.net>, Julian Yip <julian@computer.org>,
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
