package Component;

require Tie::Hash;
@ISA = (Tie::StdHash);

sub STORE {
    my ($self, $field, $value) = @_;
    my $classname = ref $self;
    my $settername = "$classname\::set_$field";
    if (defined &$settername) {
	&$settername ($self, $value)
    } else {
	$self -> {$field} = $value
    }
}

sub FETCH {
    my ($self, $field) = @_;
    my $classname = ref $self;
    my $gettername = "$classname\::get_$field";
    if (defined &$gettername) {
	return &$gettername ($self)
    } else {
	return $self -> {$field}
    }
}

package PlusPlus;

use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '1.23';

use Filter::Util::Call;

sub import {
    my ($type) = @_;
    filter_add (bless {oo => 'none', export => [], export_ok => [], isa => ['Exporter'], comment => 0});
}

sub filter {
    my $self = shift;
    $_ = translate_oneline ($_, $self) if my ($status) = filter_read ();
    unless ($status) {
	if ($self -> {oo} eq 'none') {
	    return 0;
	} else {
	    $_ = '';
	    $_ .= 'sub new {my $class = shift; my $self = {}; ';
	    $_ .= 'tie %$self, $class; ' if $self -> {isa} -> [0] eq 'Component';
	    $_ .= 'bless ($self, $class); eval {$self -> init (@_)}; return $self}; ';
	    $_ .= '@ISA = qw(' . join (' ', @{$self -> {isa}})  . '); @EXPORT = qw(' . join (' ', @{$self -> {export}}) . '); @EXPORT_OK = qw(' . join (' ', @{$self -> {export_ok}}) . "); 1;\n";
	    $self -> {oo} = 'none';
	    return 1;
	}
    }
    return $status;
}

sub list_to_nested_hashes {
 my $parts = shift;
 my $str = shift @$parts;
 foreach my $key (@$parts) { 
 	$key =~ /^\[.+\]$/ or $key = "\{$key\}";
 	$str = "\$\{$str\}$key" 
 };
 return $str;
};

sub list_to_method {
    my $parts = shift;
    my $str = shift @$parts;
    my $method = pop @$parts;
    $str .= ' -> ';
    $str .= join (' -> ', (map {"{'$_'}"} @$parts)) . ' -> ' if @$parts;
    $str .= $method; 
    return $str;
};

sub code_parse_fields_and_methods {
    return 0 unless shift =~ /([\$]\w+)(\.\[?\$?\w+\]?)+|\$\.\w+(\.\[?\$?\w+\]?)*/;
    my $r =  {pre => $`, match => $&, post => $'};
    my @parts = split (/\./, $r -> {match});
    $r -> {parts} = \@parts;
    return $r;
};

sub code_translate_fields_and_methods {
    my $src_line = shift;
    while (1) {
	last unless (my $parsed = code_parse_fields_and_methods ($src_line));
	my $str = ($parsed -> {post} =~ /^\s*\(/ ? 
	    list_to_method ($parsed -> {parts}) :
	    list_to_nested_hashes ($parsed -> {parts})
	);
	$src_line = $parsed -> {pre} . $str . $parsed -> {post}
    }
    return $src_line;
};

sub arglist {
    my ($proto) = @_;
    my %init = ();
    my @names = ();
    foreach my $arg (split /,/, $proto) {
    	my ($name, $initval) = split /=/, $arg;
    	$init {$name} = $initval if defined $initval;
    	push @names, $name; 
    }
    my $r = 'my (' . (join ', ', @names) . ') = @_; ';
    while (my ($name, $initval) = each %init) {
    	$r .= "$name = $initval unless defined $name;";
    }
    return $r;
}

sub translate_oneline {
    local $_ = shift;
    my $cntxt = shift;

    if (/^\/\*\s*$/) {
    	$cntxt -> {comment} = 1;
    	return "\n";
    }	
    
    if (/^\*\/\s*$/) {
    	$cntxt -> {comment} = 0;
    	return "\n";
    }	
    
    return "#\t$_" if ($cntxt -> {comment});

    if (/\s*(select.*)->(.*)/i) {
    	my ($sql, $st) = ($1, $2);
    	$st  =~ s/[\n\r;]//g;
    	$sql =~ s/"/\"/g;   	
	$_ = "$st = \$dbh -> prepare (\"$sql\");\n";
    }

    s/forsql\s+(\$\w+)\s+\((.*)\)\s\{/$1 -> execute ($2); while (my \$__with__prefix__ = $1 -> fetchrow_hashref) {/;
    
    if (s/class\s+([\w\:]+)\s*(\([^\)]+\))?\s*\;/package $1; use Exporter; use vars qw(\@ISA \@EXPORT \@EXPORT_OK);/) {
	$cntxt -> {oo} = 'class';
	if (defined $2) {
		foreach my $ancestor (split /,/, $2) {
		    $ancestor =~ s /[\s\(\)]//g;
		    push @{$cntxt -> {isa}}, $ancestor;
		}
    }
	}

    if (s/module\s+([\w\:]+)\s*(\([^\)]+\))?\s*\;/package $1; use Exporter; use vars qw(\@ISA \@EXPORT \@EXPORT_OK);/) {
	$cntxt -> {oo} = 'module';
	foreach my $ancestor (split /,/, $2) {
	    $ancestor =~ s /[\s\(\)]//g;
	    push @{$cntxt -> {isa}}, $ancestor;
	}
    }

    if (/([gs])etter\s+(\w+)/) {
	$_ = "$` method $1et_$2 $'";
	$cntxt -> {isa} -> [0] eq 'Component' or unshift @{$cntxt -> {isa}}, 'Component';
    }

    if (/method\s+(\w+)\s*(?:\((.+)\))?\s*\{/) {
	my ($name, $proto, $args) = ($1, $2, '');
	$args = arglist ($proto) if $proto;
	$_ = "$` sub $name { my \$self = shift; my \$__with__prefix__ = \$self; $args $'";
    }

    if (/function\s+(\w+)\s*(?:\((.+)\))?\s*\{/) {
	my ($name, $proto, $args) = ($1, $2, '');
	$args = arglist ($proto) if $proto;
	$_ = "$` sub $name { $args $'";
    }
    
    if (s/(export_ok|export)\s+sub\s+(\w+)/sub $2/) {
	my $name = $2;
	push @{$cntxt -> {export_ok}}, $name if ($1 eq 'export_ok');
	push @{$cntxt -> {export}},    $name if ($1 eq 'export'); 
    }
    
    s/new\s+([\w\:]+)/ $1 -> new/g;
    s/with\s+([^\{]+)\{/do { my \$__with__prefix__ = $1\;/g;
    s/\$\./\$__with__prefix__\./g;
    code_translate_fields_and_methods ($_);
};

1;

__END__

=head1 NAME

PlusPlus - [Delphi|VB|Java]-like Perl preprocessor

=head1 SYNOPSIS


  ### Case 1: plain script

  use PlusPlus;
  
  /*
  	This is 
  	a long awaited
  	multiline
  	comment
  */
  
  my $nested_hash = {outer => {inner => {a => 1, b => [19, 73], c => 3}}}
  
  $nested_hash.outer.inner.a = 5;      # colon in variable names
  $nested_hash.outer.inner.b.[1] = 37; 
  
  $dbh.do ("DROP DATABASE TEST");      # colon in method names
  
  with ($nested_hash.outer.inner) {    # 'with' operator
      ($.a, $.c) = (10, 30);
      print " b[0] = $.b.[0]\n";
  };
  
  function f ($x, $y = 0) {            # named parameters and default values
      return sin ($x) * cos ($y)
  };
  
  ### Case 2: working with a database
  
  use PlusPlus;
  use DBI;
  
  my $dbh = DBI -> connect ($dsn, $user, $password);

  select name, phone from staff where salary between ? and ? -> my $sth;
  
  forsql $sth (1000, 1500) {
      print "<tr>   <td> $.name </td>  <td> $.phone </td>  </tr>"
  }
  
  
  ### Case 3: procedural module
  
  use PlusPlus;
  
  module Child (Ancestor::Mother, Ancestor::Father);  
  
            sub foo { ... };           # not exported
  
  export    sub bar { ... };           # exported by default
  
  export_ok sub baz { ... };           # can be imported explicitly
  
  
  ### Case 4: class

  class Child (Ancestor::Mother, Ancestor::Father);  

  method init {	                       # constructor callback
      ($.x, $.y) = (10, 3);
  }
  
  method diag {                        # some method
      sqrt ($.x * $.x + $.y * $.y)
  }

  method do_it_to_me ($coderef) {      # one more method
      &$coderef ($self);
  }
  
  getter fldname {                     # getter method
      print "They asked my value!\n";
      return $.fldname;
  }

  setter fldname ($value) {            # setter method
      $.setting_counter ++;  
      $.fldname = $value;
  }

=head1 DESCRIPTION

B<PlusPlus> is a quick hack providing many features that are 
to be implemented in Perl6 but a lot of people would use right now.

B<PlusPlus> is a preprocessor based on the B<Filter> 
distribution available from CPAN. It alters the standard Perl synax
transparently: you don't need to recompile the interpreter or 
launch your scripts in some specific way. All you need is to install
B<Filter> - and 

 use PlusPlus;

=head2 '.' instead of '-> {}'

Using B<PlusPlus>, you can dramatically clearify your code by typing

    $foo.bar.[$i].baz
    
each time instead of
    
    $foo -> {bar} -> [$i] -> {baz}

Yes, of course, the colon means the concatenation. So, you might
suppose a collision in case like 

    $foo.$bar
    
What would it be: I<"$foo.$bar"> or I<$foo->{$bar}>? Please, remind: 
when using B<PlusPlus>, always type at least one space aside of your
concatenation colon. So,

    $foo.$bar      eq  $foo->{$bar}
    $foo . $bar    eq  "$foo$bar"

And what about the method calls? It's very similar (see SYNOPSYS). But,
note: the method call must be followed by an open paranthesis, even 
if the argument list is void.

    $st.finish	   eq  $st -> {finish}
    $st.finish ()  eq  $st -> finish ()

=head2 WITH statement

The B<PlusPlus> preprocessor introduces the I<with> statement in the manner
similar to Borland (C) Delphi (R) and MS ($) VB (...). Each fragment of code
like 

    with ($foo) {
	...
    };

is mapped to 

    do { my $__with__prefix__ = ($foo);
	...
    };
    
All variables like $.bar are renamed to $__with__prefix__.bar.
It is very unprobably that you use the variable named $__with__prefix__,
but, in any case, you are warned. 

And, please, don't forget to put a semicolon after the closing brace: 
I<with> is I<do>, not I<while>.

=head2 Named args

As you know, there is whole a lot of ways to access argument values
passed to a sub from within its body (I<shift>, I<$_[$n]>...). But
usually you write a sub that receive a predefined set of args that 
you want to access by name. In this case, your code looks like

    sub mySub {
	my ($arg1, $arg2, @all_other) = @_;
	...
    }

With B<PlusPlus>, you can obtain the same with 

    function mySub ($arg1, $arg2, @all_other) {
	...
    }
    
Moreover, often some of parameters have default values 
to be set if an undef is passed as argument. Using not 
B<PlusPlus>, you make something like 

    sub mySub {
    	my ($arg1, $arg2, $arg3, @all_other) = @_;
    	$arg2 = 2 unless defined ($arg2);
    	$arg3 ||= 3;
	...
    }
    
With B<PlusPlus>: 

    function mySub ($arg1, $arg2 = 2, $arg3 = 3, @all_other) {
	...
    }

=head2 DBI-related Stuff

When using DBI, it's very usual to code like this:

    $sth -> execute ($arg1, $arg2);
    while (my $hash_ref = $sth -> fetchrow_hashref) {
    	do_somthing ($hash_ref -> {a}, $hash_ref -> {b})
    }

OK, it's really nice (when comparing to JDBC :-), but with
B<PlusPlus> you can express yourself a little bit cleaner:

    forsql $sth ($arg1, $arg2) {
    	do_somthing ($.a, $.b)
    }

Simple, isn't it? But it is not all. B<PlusPlus> allows
to use pretty plain SQL in your perl scripts. The source line

    SELECT * FROM foo WHERE id = 6535 -> my $sth;
    
is mapped to

    my $sth = $dbh -> prepare ("SELECT * FROM foo WHERE id = 6535");
    
The I<$dbh> name is hardcoded, sorry. Currently only B<SELECT>
statements are allowed.  

=head2 Procedural Modules

B<PlusPlus> simplifies the creation of Perl modules. You don't need to 
use B<Export.pm> explicitly nor fill manually B<@ISA>, B<@EXPORT> and
B<@EXPORT_OK> arrays.

The string 

  module Child (Ancestor::Mother, Ancestor::Father);  

is mapped to 

  package Child; use Exporter; use vars qw(\@ISA \@EXPORT \@EXPORT_OK);    

Moreover, the last (additional) line of your source will contain the 
needed B<@ISA> expression.

You can add a modifier B<export> or B<export_ok> to any sub, then
its name will appear in B<@EXPORT> or B<@EXPORT_OK> list at the end of
source.

And, finally, you don't ever need to put a B<1;> after all: it is done
automatically.

=head2 Classes

B<PlusPlus> provides a simple OO-syntax addon to the Perl interpreter.
The string like  

  class MyObject (Ancestor::Mother, Ancestor::Father);  

does the same thing as the B<module> statement described above, but 
creates a standard constructor called B<new> that blesses a void anonymous
hashref. Now you can create the appropriate objects with expressions like

  my $object = new MyObject ('blah', "blah");

in any script that uses your module.

B<PlusPlus> introduces a special kind of sub for class modules: methods.
The source 

  method do_it ($x, $y, @foo) {
    ...
  }  

is mapped to 

  sub do_it { my $self = shift; my $__with__prefix__ = $self; my ($x, $y, @foo) = @_;
    ...  
  }

The metod named B<init> is called by the constructor B<new> with the
arglist passed to it. 

=head2 Quasimembers

From the OO point of view, explicit use of class members is not good practice.
In theory, you'd never access to object's fields but always call appropriate
getter/setter methods when you want to obtain/change its values. Good OO programming
languages have some special syntax that allows an implicit binding of getters/setters
to some fake class members. (I mean the Borland Delphi's feature called 'properties').
B<PlusPlus> have something similar.

Suppose you want to have some side effect when the field I<bar> of an instance of class 
I<Foo> changes. Write

  class Foo;
  
  setter bar ($value) {	
      print "And now bar = $value\n"; # side effect
      $.bar = $value;
  }
  
Now, if I<$foo> is an instance of I<Foo>, a statement

      $foo.bar = 666;
      
will dump the message 

      And now bar = 666
      
to the stdout. If you're afraid of some kind of numbers or just want to overload
the getting procedure, add a getter method:

  getter bar {	
      return $.bar == 666 ? 'Oh no!' : $.bar;
  }


=head1 AUTHOR

D. E. Ovsyanko, do@rambler.ru

=head1 SEE ALSO

Filter(3).


=cut
