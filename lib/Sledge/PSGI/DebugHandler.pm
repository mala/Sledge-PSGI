package Sledge::PSGI::DebugHandler;

# Debugger

sub handle_request {
    my ($self, $env) = @_;
    my $path_info = $env->{PATH_INFO}; 
    if ($path_info =~m{^/versions}) {
        no strict qw(refs);
        my @versions = map { [$_, ${ "$_" . "::VERSION" }] } Devel::Symdump->rnew->packages;
        @versions = sort { $a->[0] cmp $b->[0] } grep { $_->[1] } @versions;
        my @table = map { sprintf qq{<tr><td>%s</td><td>%s</td></tr>}, @$_ } @versions;
        my $body = ["<table>", @table, "</table>"];
        my $res = [ 200, [ 'Content-Type' => 'text/html' ], $body];
        return $res;
    }
    if ($path_info =~m{^/modules}) {
        my @tmp = keys %INC;
        my $res = [ 200, [ 'Content-Type' => 'text/plain' ], [join "\n", sort @tmp] ];
        return $res;
    }

    if ($path_info =~m{^/actions}) {
        my @tmp = keys %{$self->ActionMap};
        my $body = "<table>";
        for my $action (sort @tmp) {
            $body .= sprintf qq{<tr><td>%s</td><td>%s</td></tr>}, $action, $self->ActionMap->{$action}->{class};
        }
        $body .= "</table>";
        my $res = [ 200, [ 'Content-Type' => 'text/html' ], [ $body ]];
        return $res;
    }
 
}


1;


