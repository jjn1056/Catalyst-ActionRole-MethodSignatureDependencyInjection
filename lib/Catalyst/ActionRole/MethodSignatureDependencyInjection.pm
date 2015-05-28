package Catalyst::ActionRole::MethodSignatureDependencyInjection;

use Moose::Role;

our $VERSION = '0.007';

has use_prototype => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_prototype');

  sub _build_at {
    my ($self) = @_;
    my ($attr) =  @{$self->attributes->{UsePrototype}||[0]};
    return $attr;
  }

has execute_args_template => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_execute_args_template');

  sub _build_execute_args_template {
    my ($self) = @_;
    my ($attr) =  @{$self->attributes->{ExecuteArgsTemplate}||['']};
    return $attr;
  }

has prototype => (
  is=>'ro', 
  required=>1,
  lazy=>1, 
  builder=>'_build_prototype');

  sub _build_prototype {
    my ($self) = @_;
    if($INC{'Function/Parameters.pm'}) {
      return join ',',
        map {$_->type? $_->type->class : $_->name}
          Function::Parameters::info($self->code)->positional_required;
    } else {
      return prototype($self->code);
    }
  }

has template => (
  is=>'ro', 
  required=>1,
  lazy=>1, 
  builder=>'_build_template');

  sub _build_template {
    my ($self) = @_;
    return $self->use_prototype ?
      $self->prototype : $self->execute_args_template;
  }



sub _parse_dependencies {
  my ($self, $ctx, @args) = @_;

  # These Regexps could be better to allow more whitespace.
  my $p = qr/[^,]+/;
  my $p2 = qr/$p<.+?>/x;
  
  my @dependencies = ();
  my $template = $self->template;

  foreach my $what ($template=~/($p2|$p)/gx) {
    $what =~ s/^\s+|\s+$//g; #trim

    push @dependencies, $ctx if lc($what) eq '$ctx';
    push @dependencies, $ctx if lc($what) eq '$c';
    push @dependencies, $ctx->req if lc($what) eq '$req';
    push @dependencies, $ctx->res if lc($what) eq '$res';
    push @dependencies, $ctx->req->args if lc($what) eq '$args';
    push @dependencies, $ctx->req->body_data||+{}  if lc($what) eq '$bodydata';
    push @dependencies, $ctx->req->body_parameters if lc($what) eq '$bodyparams';
    push @dependencies, $ctx->req->query_parameters if lc($what) eq '$queryparams';

    #This will blow stuff up unless its the last...
    push @dependencies, @{$ctx->req->args} if lc($what) eq '@args';
    push @dependencies, @{$ctx->req->body_parameters} if lc($what) eq '%bodyparams';

    if(defined(my $arg_index = ($what =~/^\$Arg(.+)$/i)[0])) {
      push @dependencies, $ctx->req->args->[$arg_index];
    }

    if(my $model = ($what =~/^Model\:\:(.+)\s+.+$/)[0] || ($what =~/^Model\:\:(.+)/)[0]) {
      my @inner_deps = ();
      if(my $extracted = ($model=~/.+?<(.+)>$/)[0]) {
        @inner_deps = $self->_parse_dependencies($extracted, $ctx, @args);
        ($model) = ($model =~ /^(.+?)</);
      }

      my ($ret, @rest) = $ctx->model($model, @inner_deps);
      warn "$model returns more than one arg" if @rest;
      warn "$model is not defined, action will not match" unless defined $ret;
      push @dependencies, $ret;
    }

    if(my $view = ($what =~/^View\\:\:(.+)\s+.+$/)[0] || ($what =~/^View\:\:(.+)\s+.+$/)[0]) {
      my @inner_deps = ();
      if(my $extracted = ($view=~/.+?<(.+)>$/)[0]) {
        @inner_deps = $self->_parse_dependencies($extracted, $ctx, @args);
        ($view) = ($view =~ /^(.+?)</);
      }

      my ($ret, @rest) = $ctx->view($view, @inner_deps);
      warn "$view returns more than one arg" if @rest;
      warn "$view is not defined, action will not match" unless defined $ret;
      push @dependencies, $ret;
    }

    if(my $controller = ($what =~/^Controller\:\:(.+)\s+.+$/)[0] || ($what =~/^Controller\:\:(.+)\s+.+$/)[0]) {
      my ($ret, @rest) = $ctx->controller($controller);
      warn "$controller returns more than one arg" if @rest;
      warn "$controller is not defined, action will not match" unless defined $ret;
      push @dependencies, $ret;
    }
  }

  unless(scalar @dependencies) {
    @dependencies = ($ctx, @{$ctx->req->args});
  }

  return @dependencies;
}

around ['match', 'match_captures'] => sub {
  my ($orig, $self, $ctx, @args) = @_;
  return 0 unless $self->$orig($ctx, @args);
  
  my @dependencies = $self->_parse_dependencies($ctx, @{$ctx->req->args});
  foreach my $dependency (@dependencies) {
    return 0 unless defined($dependency);
  }

  $ctx->stash(__method_signature_dependencies=>\@dependencies);
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

Attribute syntax:

  package MyApp::Controller
  use base 'Catalyst::Controller';

  sub test_model :Local :Does(MethodSignatureDependencyInjection)
    ExecuteArgsTemplate($c, $Req, $Res, $BodyData, $BodyParams, $QueryParams, Model::A, Model::B)
  {
    my ($self, $c, $Req, $Res, $Data, $Params, $Query, $A, $B) = @_;
  }

Prototype syntax

  package MyApp::Controller
  use base 'Catalyst::Controller';

  no warnings::illegalproto;

  sub test_model($c, $Req, $Res, $BodyData, $BodyParams, $QueryParams, Model::A, Model::B)
    :Local :Does(MethodSignatureDependencyInjection) UsePrototype(1)
  {
    my ($self, $c, $Req, $Res, $Data, $Params, $Query, $A, $B) = @_;
  }

=head1 WARNING

Lets you declare required action dependencies via the a subroutine attribute
and additionally via the prototype (if you dare)

This is a weakly documented, early access prototype.  The author reserves the
right to totally change everything and potentially disavow all knowledge of it.
Only report bugs if you are capable of offering a patch and discussion.

B<UPDATE> This module is starting to stablize, and I'd be interested in seeing
people use it and getting back to me on it.  But I do recommend using it only
if you feel like its code you understand.

Please note if any of the declared dependencies return undef, that will cause
the action to not match.  This could probably be better warning wise...

=head1 DESCRIPTION

L<Catalyst> when dispatching a request to an action calls the L<Action::Class>
execute method with the following arguments ($self, $c, @args).  This you likely
already know (if you are a L<Catalyst> programmer).

This action role lets you describe an alternative 'template' to be used for
what arguments go to the execute method.  This way instead of @args you can
get a model, or a view, or something else.  The goal of this action role is
to make your action bodies more concise and clear and to have your actions
declare what they want.

Additionally, when we build these arguments, we also check their values and
require them to be true during the match/match_captures phase.  This means
you can actually use this to control how an action is matched.

There are two ways to use this action role.  The default way is to describe
your execute template using the 'ExecuteArgsTemplate' attribute.  The
second is to enable UsePrototype (via the UsePrototype(1) attribute) and
then you can declare your argument template via the method prototype.  You
will of course need to use 'no warnings::illegalproto' for this to work.
The intention here is to work toward something that would play nice with
a system for method signatures like L<Kavorka>.

If this sounds really verbose it is.  This distribution is likely going to
be part of something larger that offers more sugar and less work, just it was
clearly also something that could be broken out and hacked pn separately.
If you use this you might for example set this action role in a base controller
such that all your controllers get it (one example usage).

Please note that you must still access your arguments via C<@_>, this is not
a method signature framework.  You can take a look at L<Catalyst::ActionSignatures>
for a system that bundles this all up more neatly.

=head1 DEPENDENCY INJECTION

You define your execute arguments as a positioned list (for now).  The system
recognizes the following 'built ins' (you always get $self automatically).

=head2 $c

=head2 $ctx

The current context.  You are encouraged to more clearly name your action
dependencies, but its here if you need it.

=head2 $req

The current L<Catalyst::Request>

=head2 $res

The current L<Catalyst::Response>

=head2 $args

The current an arrayref of the current args

=head2 @args

An array of the current args.  Only makes sense if this is the last specified
argument.

=head2 $arg0 .. $argN

One of the indexed args, where $args0 => $args[0];

=head2 $bodyData

$c->req->body_data

=head2 $bodyParams

$c->req->body_parameters

=head2 $QueryParams

$c->req->query_parameters

=head1 Accessing Components

You can request a L<Catalyst> component (a model, view or controller).  You
do this via [Model||View||Controller]::$component_name.  For example if you
have a model that you'd normally access like this:

    $c->model("Schema::User");

You would say "Model::Schema::User". For example:

    ExecuteArgsTemplate(Model::Schema::User)

Or via the prototype

    sub myaction(Model::Schema::User) ...

You can also pass arguments to your models.  For example:

    ExecuteArgsTemplate(Model::UserForm<Model::User>)

same as $c->model('UserForm', $c->model('User'));

=head1 Integration with Function::Parameters

For those of you that would like to push the limits even harder, we have
experimental support for L<Function::Parameters>.  You may use like in the
following example.

    package MyApp::Controller::Root;

    use base 'Catalyst::Controller';

    use Function::Parameters({
      method => {defaults => 'method'},
      action => {
        attributes => ':method :Does(MethodSignatureDependencyInjection) UsePrototype(1)',
        shift => '$self',
        check_argument_types => 0,
        strict => 0,
        default_arguments => 1,
      }});

    action test_model($c, $res, Model::A $A, Model::Z $Z) 
      :Local 
    {
      # ...
      $res->body(...);
    }

    method test($a) {
      return $a;
    }

Please note that currently you cannot use the 'parameterized' syntax for component
injection (no Model::A<Model::Z> support).

=head1 SEE ALSO

L<Catalyst::Action>, L<Catalyst>, L<warnings::illegalproto>,
L<Catalyst::ActionSignatures>

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
