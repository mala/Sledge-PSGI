# emulate Apache::Request

package # Hide from PAUSE
    Apache;
sub request { Apache::Request->new }

package 
    Apache::Request;

use Carp;

sub new {
    my $class = shift;
    bless {}, $class;
}

sub connection {
    Carp::croak("Your App hard coding Apache::Request");
    my $page = Sledge::Registrar::context();
    $page->r->connection(@_);
}

sub pnotes {
    Carp::croak("Your App hard coding Apache::Request");
    my $page = Sledge::Registrar::context();
    $page->r->pnotes(@_);
}


$INC{"Apache.pm"} = __FILE__;
$INC{"Apache/Request.pm"} = __FILE__;

1;




