#! perl

require 5.004;

if ( $^O eq "solaris" ) {
    print STDERR <<EOD;

**************** You're running Solaris ****************

The Solaris version of the 'patch' program seems to be extremely buggy.
If this test fails with a message like

  patch: Line must begin with '+ ', '  ', or '! '.

you must install a better version of 'patch', for example, GNU patch.

**************** Let the games begin ****************
EOD
}

print "1..6\n";

my $data1 = <<EOD;
Squirrel Consultancy
Duvenvoordestraat 46
2013 AG  Haarlem
EOD
my $data2 = <<EOD;
Squirrel Consultancy
Duivenvoordestraat 46
2013 AG  Haarlem
EOD

open (D, ">t/d1/tdata1"); binmode(D); print D $data1; close D;
open (D, ">t/d2/tdata1"); binmode(D); print D $data2; close D;
open (D, ">t/d1/tdata2"); binmode(D); print D $data2; close D;
open (D, ">t/d2/tdata2"); binmode(D); print D $data1; close D;

my $tmpout = "basic.out";

$ENV{MAKEPATCHINIT} = "-test";
@ARGV = qw(-test -quiet -description test t/d1 t/d2);

eval {
    package MakePatch;
    local (*STDOUT);
    open (STDOUT, ">$tmpout");
    local (*STDERR);
    open (STDERR, ">&STDOUT");
    require "blib/script/makepatch";
};

# Should exit Okay.
if ( !$@ || $@ =~ /^Okay/ ) {
   print "ok 1\n";
}
else {
   print "not ok 1\n";
   print $@;
}

# Run makepatch's END block
eval {
    MakePatch::cleanup ();
};
# And blank it.
undef &MakePatch::cleanup;
*MakePatch::cleanup = sub {};

# Expect some output.
print "not " unless -s $tmpout > 1300;
print "ok 2\n";

my $tmpou2 = "basic.ou2";

@ARGV = qw(-test -dir t/d1 basic.out);

eval {
    package ApplyPatch;
    local (*STDOUT);
    open (STDOUT, ">$tmpou2");
    local (*STDERR);
    open (STDERR, ">&STDOUT");
    require "blib/script/applypatch";
};
# applypatch will chdir to t/d1; change back.
chdir ("../..");

# Should exit Okay.
if ( $@ =~ /^Okay/ ) {
   print "ok 3\n";
}
else {
   print "not ok 3\n";
   print $@;
}

# Expect no output.
# print "not " if -s $tmpou2 > 0;
{
    my $s;
    if ( ($s = -s $tmpou2) > 0 ) {
	open (FX, $tmpou2) or die ("$tmpou2: $!\n");
	local $/;
	my $c = <FX>;
	close (FX);
	$c =~ s/^/####/gm;
	$c .= "####";
	print ("# tmpou2[$tmpou2]s[$s]c[$c]\nnot ");
    }
}
print "ok 4\n";

# Remove temp files.
unlink $tmpout, $tmpou2;

# Verify resultant data.
print "not " if differ ("t/d1/tdata1", "t/d2/tdata1");
print "ok 5\n";
print "not " if differ ("t/d1/tdata1", "t/d2/tdata1");
print "ok 6\n";

sub differ {
    # Perl version of the 'cmp' program.
    # Returns 1 if the files differ, 0 if the contents are equal.
    my ($old, $new) = @_;
    unless ( open (F1, $old) ) {
	print STDERR ("$old: $!\n");
	return 1;
    }
    unless ( open (F2, $new) ) {
	print STDERR ("$new: $!\n");
	return 1;
    }
    my ($buf1, $buf2);
    my ($len1, $len2);
    while ( 1 ) {
	$len1 = sysread (F1, $buf1, 10240);
	$len2 = sysread (F2, $buf2, 10240);

	$buf1 =~ s/(\r\n|\r|\n)/\n/g;
	$buf2 =~ s/(\r\n|\r|\n)/\n/g;
	$len1 = length $buf1;
	$len2 = length $buf2;

	return 0 if $len1 == $len2 && $len1 == 0;
	return 1 if $len1 != $len2 || ( $len1 && $buf1 ne $buf2 );
    }
}

