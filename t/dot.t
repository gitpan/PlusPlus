BEGIN {print "1..2\n";}
END {print "not ok 1\n" unless $loaded;}
use PlusPlus;
$loaded = 1;
print "ok 1\n";

my $hr = {a => {b => "ok 2\n"}};
print $hr.a.b;