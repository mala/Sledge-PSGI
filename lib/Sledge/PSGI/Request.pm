package Sledge::PSGI::Request;

# wrapper for Plack::Request
# based on Sledge::Request::CGI
# good compatible Apache::Request

use strict;
use Carp;
use base qw(Plack::Request Class::Accessor);
__PACKAGE__->mk_accessors(qw(header_hash request response stream arguments));

use Plack::Util;
use Plack::Request;
use Plack::Response;

use Sledge::Request::Table;

sub new {
    my($class, $args) = @_;

    my %header;
    tie %header, 'Sledge::Request::Table::HASH', $args->{response}->headers;

    my $self = {
        %{$args},
        header_hash => \%header
    };
    bless $self, $class;
}


sub req { $_[0]->{request} }
sub res { $_[0]->{response} }

sub args { 
    my $self = shift;
    $self->req->env->{QUERY_STRING}
} 

# for Apache::Table compat
sub header_out {
    my ( $self, $key, $value ) = @_;
    $self->header_hash->{$key} = $value if @_ == 3;
    $self->header_hash->{$key};
}

sub headers_out {
    my $self = shift;
    return wantarray
      ? %{ $self->header_hash }
      : Sledge::Request::Table->new( $self->header_hash );
}

sub header_in {
    my($self, $key) = @_;
    $self->req->header($key);
}

sub status {
    my($self, $status) = @_;
    $self->res->status($status);
}

sub content_type {
    my($self, $type) = @_;
    $self->res->content_type($type);
}

# do nothing
sub send_http_header {
    Carp::carp("Obsolete method.");
    return;
}

sub print {
    my $self = shift;
    Carp::carp("Obsolete method.");
    my $buf = $self->{__content_buf} ||= [];
    push @{$buf}, @_;
    $self->res->body($buf);
}

sub upload {
    my $self = shift;
    $self->req->upload(@_);
}

sub uploads {
    shift->req->uploads;
}

sub pnotes {
    my $self = shift;
    my $pnotes = $self->{__pnotes} ||= {};
    if ( @_ >= 2 ) {
        $pnotes->{ $_[0] } = $_[1];
    }
    $pnotes->{ $_[0] };
}

# nothing
sub subprocess_env { Carp::carp("Nothing todo") }

# mod_perl's <Location /appname1> <Location /appname2>
# this is not necessary with using Plack::App::URLMap
sub location { "" }

# return URI object for current url.
sub uri { shift->req->uri }
# $ENV{REQUEST_URI}
sub request_uri { shift->req->request_uri }

# emulate Apache::Request->connection
sub connection     {
    my $self = shift;
    my $oops = sub { Carp::carp("Not supported. Don't use it!") };
    Plack::Util::inline_object(
        user =>  sub { 
            Carp::carp('Deprecated.'); 
            $self->env->{REMOTE_USER} = $_[0] if (@_); # can set for logging, $self->r->connection->user("username");
            $self->req->user;
        },
        remote_ip => sub { 
            $self->env->{REMOTE_ADDR} = $_[0] if (@_); # can set for X-Forwarded-For or special case.
            $self->req->addr;
        },
        remote_host => sub { $self->req->hostname },
        local_addr => $oops,
        remote_addr => $oops,
        remote_logname => $oops,
        auth_type => $oops,
        aborted => $oops,
        fileno => $oops,
    );
}

# update header_hash and req->headers;
package Sledge::Request::Table::HASH;
require Tie::Hash;
our @ISA = qw(Tie::ExtraHash);

# $self is  [ header_hash, HTTP::Headers ]

sub STORE {
    my ($self, $key, $value) = @_;
    $self->[0]{ $_[1] } = $_[2];
    $self->[1]->push_header($key => $value);
}

sub DELETE {
    my ($self, $key) = @_;
    delete $self->[0]{$key};
    $self->[1]->remove_header($key); 

}

sub CLEAR {
    my $self = shift;
    %{$self->[0]} = ();
    $self->[1]->clear;
}

1;
