package Sledge::PSGI::DebugHandler;

# Debugger
use Devel::Symdump;
use Devel::StackTrace;

our $DEBUG_PATH = "/debug";

sub handle_request {
    my ($class, $self, $env) = @_;
    my $path_info = $env->{PATH_INFO};
    warn $path_info;
    if ($path_info =~m{^$DEBUG_PATH/([^/]+)}) {
        my $method = "handle_" . $1;
        warn $method;
        warn $class;
        return unless $class->can($method);
        return $class->$method($self, $env);
    }
    # debugger index
    if ($path_info =~m{^$DEBUG_PATH/}) {
        # TODO
    }
}

sub handle_trace {
    
}


sub handle_versions {
    no strict qw(refs);
    my @versions = map { [$_, ${ "$_" . "::VERSION" }] } Devel::Symdump->rnew->packages;
    @versions = sort { $a->[0] cmp $b->[0] } grep { $_->[1] } @versions;
    my @table = map { sprintf qq{<tr><td>%s</td><td>%s</td></tr>}, @$_ } @versions;
    my $body = ["<table>", @table, "</table>"];
    my $res = [ 200, [ 'Content-Type' => 'text/html' ], $body];
    return $res;
}

sub handle_modules {
    my @tmp = keys %INC;
    my $res = [ 200, [ 'Content-Type' => 'text/plain' ], [join "\n", sort @tmp] ];
    return $res;
}

sub handle_actions {
    my ($class, $self, $env) = @_;
    my @tmp = keys %{$self->ActionMap};
    my $body = "<table>";
    for my $action (sort @tmp) {
        $body .= sprintf qq{<tr><td>%s</td><td>%s</td></tr>}, $action, $self->ActionMap->{$action}->{class};
    }
    $body .= "</table>";
    my $res = [ 200, [ 'Content-Type' => 'text/html' ], [ $body ]];
    return $res;
}

1;


