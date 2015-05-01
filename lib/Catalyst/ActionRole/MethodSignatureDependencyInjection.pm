package Catalyst::ActionRole::MethodSignatureDependencyInjection;

use Moose::Role;

our $VERSION = '0.001';

sub _parse_dependencies {
  my ($self, $proto, $ctx, @args) = @_;

  my $p = qr/[^,]+/;
  my $p2 = qr/$p<.+?>/x;
  my @dependencies = ();

  foreach my $what ($proto=~/($p2|$p)/gx) {
    $what =~ s/^\s+|\s+$//g; #trim
    push @dependencies, $ctx if $what eq '$Ctx';
    push @dependencies, $ctx if $what eq '$ctx';
    push @dependencies, $ctx if $what eq '$c';
    push @dependencies, $ctx->req if $what eq '$req';
    push @dependencies, $ctx->req if $what eq '$Req';
    push @dependencies, $ctx->res if $what eq '$res';
    push @dependencies, $ctx->res if $what eq '$Res';
    push @dependencies, $ctx->log if $what eq '$log';
    push @dependencies, $ctx->log if $what eq '$Log';
    push @dependencies, $ctx->session if $what eq '$session';
    push @dependencies, $ctx->session if $what eq '$Session';
    push @dependencies, $ctx->req->body_data||+{} if $what eq '$Data';
    push @dependencies, $ctx->req->body_data||+{}  if $what eq '$BodyData';
    push @dependencies, $ctx->req->body_parameters if $what eq '$Params';
    push @dependencies, $ctx->req->body_parameters if $what eq '$BodyParams';
    push @dependencies, $ctx->req->query_parameters if $what eq '$Query';
    push @dependencies, $ctx->req->query_parameters if $what eq '$QueryParams';
    push @dependencies, $ctx->req->args if $what eq '$Args';
    push @dependencies, $ctx->req->args if $what eq '$args';

    #This will blow stuff up unless its the last...
    push @dependencies, @{$ctx->req->args} if $what eq '@Args';
    push @dependencies, @{$ctx->req->args} if $what eq '@args';

    if(defined(my $arg_index = ($what =~/^Arg(.+)$/)[0])) {
      push @dependencies, $ctx->req->args->[$arg_index];
    }

    if(my $model = ($what =~/^Model\:\:(.+)$/)[0]) {
      my @inner_deps = ();
      if(my $extracted = ($model=~/.+?<(.+)>$/)[0]) {
        @inner_deps = $self->_parse_dependencies($extracted, $ctx, @args);
        ($model) = ($model =~ /^(.+?)</);
      }

      my ($ret, @rest) = $ctx->model($model, @inner_deps);
      warn "$model returns more than one arg" if @rest;
      push @dependencies, $ret;
    }

    if(my $view = ($what =~/^View\:\:(.+)$/)[0]) {
      my @inner_deps = ();
      if(my $extracted = ($view=~/.+?<(.+)>$/)[0]) {
        @inner_deps = $self->_parse_dependencies($extracted, $ctx, @args);
        ($view) = ($view =~ /^(.+?)</);
      }

      my ($ret, @rest) = $ctx->view($view, @inner_deps);
      warn "$view returns more than one arg" if @rest;
      push @dependencies, $ret;
    }

    if(my $controller = ($what =~/^Controller\:\:(.+)$/)[0]) {
      push @dependencies, $ctx->controller($controller);
    }
  }

  unless(scalar @dependencies) {
    @dependencies = ($ctx, @{$ctx->req->args});
  }

  $ctx->stash(__method_signature_dependencies=>\@dependencies);
  return @dependencies;
}

around ['match', 'match_captures'] => sub {
  my ($orig, $self, $ctx, $captures) = @_;
  # ->match does not get args :( but ->match_captures get captures...
  
  my $proto = prototype( $self->class ."::". $self->name);
  my @dependencies = $self->_parse_dependencies($proto, $ctx, @{$ctx->req->args});

  foreach my $dependency (@dependencies) {
    return 0 unless defined($dependency);
  }

  return 1;
};

around 'execute', sub {
  my ($orig, $self, $controller, $ctx, @args) = @_;
  my @dependencies = @{$ctx->stash->{__method_signature_dependencies}};
  return $self->$orig($controller, @dependencies);
};

1;

=head1 NAME

Catalyst::ActionRole::MethodSignatureDependencyInjection - Experimental Action Signature Dependency Injection

=head1 SYNOPSIS

  package MyApp::Controller
  use base 'Catalyst::Controller';

  no warnings::illegalproto;

  sub test_model($Ctx, $Req, $Res, $Data, $Params, $Query, Model::A, Model::B) 
  :Local :Does(MethodSignatureDependencyInjection)
  {
    my ($self, $c, $Req, $Res, $Data, $Params, $Query, $A, $B) = @_;
  }

=head1 DESCRIPTION

Lets you declare required action dependencies via the method signature.

This is a poorly documented, early access prototype.  The author reserves the
right to totally change everything and potentially disavow all knowledge of it.
Only report bugs if you are capable of offering a patch and discussion.

Please note if any of the declared dependencies return undef, that will cause
the action to not match.  This could probably be better warning wise...

=head1 SEE ALSO

L<Catalyst::Action>, L<Catalyst>, L<warnings::illegalproto>.

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
