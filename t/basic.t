#! perl

print "1..5\n";

open (D, ">t/d1/tdata1");
print D <<EOD;
Squirrel Consultancy
Duvenvoordestraat 46
2013 AG  Haarlem
EOD

close D;

open (D, ">t/d2/tdata1");
print D <<EOD;
Squirrel Consultancy
Duivenvoordestraat 46
2013 AG  Haarlem
EOD

close D;

my $tmpout = "basic.out";

$ENV{MAKEPATCHINIT} = "-test";
@ARGV = qw(-test -quiet -description test t/d1 t/d2);

eval {
    local (*STDOUT);
    open (STDOUT, ">$tmpout");
    local (*STDERR);
    open (STDERR, ">&STDOUT");
    require "blib/script/makepatch";
};
undef *main::app_usage;
undef *main::app_options;

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
    cleanup ();
};
# And blank it.
undef *main::cleanup;
*main::cleanup = sub () {};

# Expect some output.
print "not " unless -s $tmpout > 1300;
print "ok 2\n";

my $tmpou2 = "basic.ou2";

@ARGV = qw(-test -dir t/d1 basic.out);

eval {
    local (*STDOUT);
    open (STDOUT, ">$tmpou2");
    local (*STDERR);
    open (STDERR, ">&STDOUT");
    require "blib/script/applypatch";
};
undef *main::app_usage;
undef *main::app_options;
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
print "not " if -s $tmpou2 > 0;
print "ok 4\n";

# Remove temp files.
unlink $tmpout, $tmpou2;

# Verify resultant data.
print "not " if differ ("t/d1/tdata1", "t/d2/tdata1");
print "ok 5\n";

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
	return 0 if $len1 == $len2 && $len1 == 0;
	return 1 if $len1 != $len2 || ( $len1 && $buf1 ne $buf2 );
    }
}

