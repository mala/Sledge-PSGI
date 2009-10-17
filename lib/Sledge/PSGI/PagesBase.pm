package Sledge::PSGI::PagesBase;

# Sledge::Pages class using Plack::Request for create_request
# $page->new($psgi_env); # OK
# $page->new; # don't work!

use strict;
use base qw(Sledge::Pages::Base);
use Plack::Request;
use Plack::Response;
use Sledge::PSGI::Request;

__PACKAGE__->mk_accessors(qw(request response));

# self->r is REQUEST object, but contain some method for create response for compatible old app
# use new API
# $self->res->body("write body");
# $self->res->content_length(length $content);

sub req { shift->request  }
sub res { shift->response }

sub create_request {
    my ( $self, $env ) = @_;

    my $request  = Plack::Request->new($env);
    my $response = Plack::Response->new;

    # raw Plack Request/Response
    $self->request($request);
    $self->response($response);

    # create $self->r for compatibility

    Sledge::PSGI::Request->new({
        env         => $env,
        request     => $request,
        response    => $response,
    }); 

}


1;

__END__

