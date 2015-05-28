package Catalyst::ActionSignatures;

use Moose;
use B::Hooks::Parser;
extends 'signatures';

around 'callback', sub {
  my ($orig, $self, $offset, $inject) = @_;

  my @parts = map { $_=~s/^.*([\$\%])/$1/; $_ } split ',', $inject;
  my $signature = join(',', (@parts));

  $self->$orig($offset, $signature);

  #Is this an action?  Sadly we have to guess using a hueristic...

  my $linestr = B::Hooks::Parser::get_linestr();
  my ($attribute_area) = ($linestr =~m/\)(.*){/);

  # If there's anything in the attribute area, we assume a catalys action...
  # Sorry thats th best I can do for now, patches to make it smarter very 
  # welcomed.

  if($attribute_area =~m/\S/) {
    $linestr =~s/\{/:Does(MethodSignatureDependencyInjection) :ExecuteArgsTemplate($inject) \{/;
    B::Hooks::Parser::set_linestr($linestr);
  }
};

1;

=head1 NAME

Catalyst::ActionSignatures - so you can stop looking at @_

=head1 SYNOPSIS

    use Moose;
    use MooseX::MethodAttributes;
    use Catalyst::ActionSignatures;

    extends 'Catalyst::Controller';

    sub test($Req, $Res, Model::A $A, Model::Z $Z) :Local {
        # Stuff...
    }

=head1 DESCRIPTION

Lets you declare required action dependencies via the method signature.

This subclasses L<signatures> to allow you a more concise approach to
creating your controllers.

=head1 SEE ALSO

L<Catalyst::Action>, L<Catalyst>, L<signatures>

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
