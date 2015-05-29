package Catalyst::ActionSignatures;

use Moose;
use B::Hooks::Parser;
use Carp;
extends 'signatures';

around 'callback', sub {
  my ($orig, $self, $offset, $inject) = @_;

  my @parts = map { $_=~s/^.*([\$\%\@]\w+).*$/$1/; $_ } split ',', $inject;
  my $signature = join(',', ('$self', @parts));

  $self->$orig($offset, $signature);

  #Is this an action?  Sadly we have to guess using a hueristic...

  my $linestr = B::Hooks::Parser::get_linestr();
  my ($attribute_area) = ($linestr =~m/\)(.*){/);

  # If there's anything in the attribute area, we assume a catalyst action...
  # Sorry thats th best I can do for now, patches to make it smarter very 
  # welcomed.

  if($attribute_area =~m/\S/) {
    $linestr =~s/\{/:Does(MethodSignatureDependencyInjection) :ExecuteArgsTemplate($inject) \{/;

    # How many numbered or unnumberd args?
    my $count_args = scalar(my @countargs = $inject=~m/(Arg)[\d+\s]/ig);
    if($count_args and $attribute_area!~m/Args\(.+?\)/i) {
      
      my @constraints = ($inject=~m/Arg[\d+\s+][\$\%\@]\w+\s+isa\s+([\w"']+)/gi);
      if(@constraints) {
        if(scalar(@constraints) != $count_args) {
          confess "If you use constraints in a method signature, all args must have constraints";
        }
        my $constraint = join ',',@constraints;
        $linestr =~s/\{/ :Args($constraint) \{/;
      } else {
        $linestr =~s/\{/ :Args($count_args) \{/;
      }
    }

    my $count_capture = scalar(my @countcaps = $inject=~m/(capture)[\d+\s]/ig);
    if($count_capture and $attribute_area!~m/CaptureArgs\(.+?\)/i) {

      my @constraints = ($inject=~m/Capture[\d+\s+][\$\%\@]\w+\s+isa\s+([\w"']+)/gi);
      if(@constraints) {
        if(scalar(@constraints) != $count_capture) {
          confess "If you use constraints in a method signature, all args must have constraints";
        }
        my $constraint = join ',',@constraints;
        $linestr =~s/\{/ :CaptureArgs($constraint) \{/;
      } else {
        $linestr =~s/\{/ :CaptureArgs($count_capture) \{/;
      }
    }

    # Check for Args
    if(($inject=~m/Args/i) and ($attribute_area!~m/Args\s/)) {
      $linestr =~s/\{/ :Args \{/;
    }

    # If this is chained but no Args, Args($n) or Captures($n), then add 
    # a CaptureArgs(0).  Gotta rebuild the attribute area since we might
    # have modified it above.
    ($attribute_area) = ($linestr =~m/\)(.*){/);

    if(
      $attribute_area =~m/Chained/i && 
        $attribute_area!~m/[\s\:]Args/i &&
          $attribute_area!~m/CaptureArgs/i
    ) {
      $linestr =~s/\{/ :CaptureArgs(0) \{/;
    }

    B::Hooks::Parser::set_linestr($linestr);

    #warn "\n $linestr \n";

  } 
};

1;

=head1 NAME

Catalyst::ActionSignatures - so you can stop looking at @_

=head1 SYNOPSIS

    package MyApp::Controller::Example;

    use Moose;
    use MooseX::MethodAttributes;
    use Catalyst::ActionSignatures;

    extends 'Catalyst::Controller';

    sub test($Req, $Res, Model::A $A, Model::Z $Z) :Local {
        # has $self implicitly
        $Res->body('Look ma, no @_!')
    }

    sub regular_method ($arg1, $arg1) {
      # has $self implicitly
    }

    __PACKAGE__->meta->make_immutable;

=head1 DESCRIPTION

Lets you declare required action dependencies via the method signature.

This subclasses L<signatures> to allow you a more concise approach to
creating your controllers.  This injects your method signature into the
code so you don't need to use @_.  You should read L<signatures> to be
aware of any limitations.

For actions and regular controller methods, "$self" is implicitly injected,
but '$c' is not.  You should add that to the method signature if you need it
although you are encouraged to name your dependencies rather than hang it all
after $c.

You should review L<Catalyst::ActionRole::MethodSignatureDependencyInjection>
for more on how to construct signatures.

=head1 Args and Captures

If you specify args and captures in your method signature, you can leave off the
associated method attributes (Args($n) and CaptureArgs($n)) IF the method 
signature is the full specification.  In other works instead of:

    sub chain(Model::A $a, Capture $id, $res) :Chained(/) CaptureArgs(1) {
      Test::Most::is $id, 100;
      Test::Most::ok $res->isa('Catalyst::Response');
    }

      sub endchain($res, Arg0 $name) :Chained(chain) Args(1) {
        $res->body($name);
      }
   
      sub endchain2($res, Arg $first, Arg $last) :Chained(chain) PathPart(endchain) Args(2) {
        $res->body("$first $last");
      }

You can do:

    sub chain(Model::A $a, Capture $id, $res) :Chained(/) {
      Test::Most::is $id, 100;
      Test::Most::ok $res->isa('Catalyst::Response');
    }

      sub endchain($res, Arg0 $name) :Chained(chain)  {
        $res->body($name);
      }
   
      sub endchain2($res, Arg $first, Arg $last) :Chained(chain) PathPart(endchain)  {
        $res->body("$first $last");
      }

=head1 Type Constraints

If you are using a newer L<Catalyst> (greater that 5.90090) you may declare your
Args and CaptureArgs typeconstraints via the method signature.

    use Types::Standard qw/Int Str/;

    sub chain(Model::A $a, Capture $id isa Int, $res) :Chained(/) {
      Test::Most::is $id, 100;
      Test::Most::ok $res->isa('Catalyst::Response');
    }

      sub typed0($res, Arg $id) :Chained(chain) PathPart(typed) {
        $res->body('any');
      }

      sub typed1($res, Arg $pid isa Int) :Chained(chain) PathPart(typed) {
        $res->body('int');
      }

B<NOTE> If you declare any type constraints on args or captures, all declared
args or captures must have them.

=head1 SEE ALSO

L<Catalyst::Action>, L<Catalyst>, L<signatures>

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
