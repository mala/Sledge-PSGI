package Sledge::PSGI::Handler;

use strict;
use base qw(Exporter);
our @EXPORT_OK = qw(handle_request);
use Data::Dumper;
use Devel::Symdump;

sub handle_request {
    my ($self, $psgi_env) = @_;

    # url rewrite etc.
    if ($self->{ModifierClass}) {
        $self->{ModifierClass}->call($psgi_env);
    }
   
    # for Compatibility
    local *ENV = $psgi_env;

    my $path_info = $psgi_env->{PATH_INFO};
    my $action = $self->lookup($path_info);

    if ($self->debug_level) {
        my $res = Sledge::PSGI::DebugHandler($self, $psgi_env);
        return $res if $res;
    }

    if (!$action) {
        # just a render Template File
        if ($self->{StaticClass}) {
            $action = +{
                class => $self->{StaticClass},
                page  => $path_info,
            };
        } else {
            my $res = [ 400, [ 'Content-Type' => 'text/plain' ], [ 'Bad Request' ] ];
            return $res;
        }
    }
    my $class = $action->{class};
    $class->require;
    my $pages = $class->new($psgi_env);
    if ($action->{args}) {
        $pages->r->arguments($action->{args});
    }
    dispatch_psgi($pages, $action->{page})
}

sub dispatch_psgi {
    my ( $self, $page ) = @_;

    local *Sledge::Registrar::context = sub { $self };
    Sledge::Exception->do_trace(1) if $self->debug_level;

    my $res = eval { 
        make_response($self, $page);
    };
    
    if ($@) {
        # $content = "$@";
    }
    # $self->handle_exception($@) if $@;
    # my $res = $self->response;
    $self->_destroy_me;
    return $res->finalize;
}

sub make_response {
    my ( $self, $page ) = @_;
    $self->init_dispatch($page);
    $self->invoke_hook('BEFORE_DISPATCH') unless $self->finished;

    if ( $self->is_post_request && !$self->finished ) {
        my $postmeth = 'post_dispatch_' . $page;
        $self->$postmeth() if $self->can($postmeth);
    }
    unless ( $self->finished ) {
        my $method = 'dispatch_' . $page;
        $self->$method() if $self->can($method);
        $self->invoke_hook('AFTER_DISPATCH');
    }

    my $req = $self->r->request;
    my $res = $self->r->response;

    $res->status(200) unless $res->status;

    if ( $self->r->stream ) {
        $res->body($self->r->stream);
        return $res;
    }
    elsif ( !$res->body ) {
        # SCALAR only
        my $content = $self->make_content;
        $res->body($content);
        $res->content_length( length $content );
        $res->content_type( $self->charset->content_type ) unless $res->content_type;
    }

    $self->invoke_hook('AFTER_OUTPUT');
    $self->finished(1);
    
    return $res;
}



1;

__END__
