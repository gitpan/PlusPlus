package PlusPlus;

use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '1.00';

use Filter::Util::Call;

sub import {
    my ($type) = @_;
    filter_add (bless {});
}

sub filter {
    $_ = translate_oneline ($_) if my ($status) = filter_read ();
    return $status;
}

sub list_to_nested_hashes {
 my $parts = shift;
 my $str = shift @$parts;
 foreach (@$parts) { $str = "\$\{$str\}\{'$_'\}" };
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
    return 0 unless shift =~ /([\$]\w+)(\.\$?\w+)+|\$\.\w+(\.\$?\w+)*/;
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

sub translate_multiline { 
    join ("\n", map {translate_oneline ($_)} split (/\n/, shift)); 
};

sub translate_oneline {
    local $_ = shift; 
    s/new\s+([\w\:]+)/ $1 -> new/g;
    s/with([^\{]+)\{/do { my \$__with__prefix__ = $1\;/g;
    s/\$\./\$__with__prefix__\./g;
    code_translate_fields_and_methods ($_);
};

1;
__END__

=head1 NAME

PlusPlus - [Delphi|VB|Java]-like Perl preprocessor

=head1 SYNOPSIS

  use PlusPlus;
  
  my $nested_hash = {outer => {inner => {a => 1, b => 2, c => 3}}}
  
  $nested_hash.outer.inner.a = 5;      # dot syntax for variables
  
  $dbh.do ("DROP DATABASE TEST");      # dot syntax for methods
  
  with ($nested_hash.outer.inner) {    # 'with' operator
      ($.a, $.c) = (10, 30);
      print " b = $.b\n";
  };

=head1 DESCRIPTION

B<PlusPlus> is a quick and (maybe) a little bit dirty way to have some 
additional comfort when working with nested Perl data structures. This
module allows some extensions to the Perl syntax.

B<PlusPlus> is a source filter (preprocessor) based on the module B<Filter>.

=head2 DOT SYNTAX

Using B<PlusPlus>, you can dramatically clearify your code by typing

    $foo.bar.baz
    
each time instead of
    
    $foo -> {bar} -> {baz}

Yes, of course, the dot means the concatenation operator. So, you might
suppose a collision in case like 

    $foo.$bar
    
What would it be: I<"$foo.$bar"> or I<$foo->{$bar}>? Please, remind: 
when using B<PlusPlus>, always type at least one space aside of your
concatenation dot. So,

    $foo.$bar      eq  $foo->{$bar}
    $foo . $bar    eq  "$foo$bar"

And what about the method calls? It's very similar (see SYNOPSYS). But,
note: the method call must be followed by an open paranthesis, even 
if the argument list is void.

    $st.finish	   eq  $st -> {finish}
    $st.finish ()  eq  $st -> finish ()

=head2 WITH

The B<PlusPlus> preprocessor introduces the I<with> operator in the manner
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

=head1 AUTHOR

D. E. Ovyanko, do@mobile.ru

=head1 SEE ALSO

Filter(3).

=cut
