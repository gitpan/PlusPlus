BEGIN {print "1..2\n";}
END {}
use PlusPlus;

my $hr = {a => {b => 'ok'}};

with ($hr) {print "$.a.b 1\n"};
with ($hr.a) {print "$.b 2\n"};

