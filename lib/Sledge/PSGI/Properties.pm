package Sledge::PSGI::Properties;

use strict;
use FileHandle;
use Data::Properties;
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(path props));

sub new {
    my ($class, $path) = @_;
    my $self = bless { 
        path  => $path,
        props => Data::Properties->new,
    }, $class;
    $self->reload;
    $self;
}

sub reload {
    my $self = shift;
    my $path = $self->path;
    my $handle = FileHandle->new($path) or Sledge::Exception::PropertiesNotFound->throw("$path: $!");
    $self->props->load($handle);
    return $self;
}

sub each {
    my $self = shift;
    my $code = shift;
    my $props = $self->props;
    for my $name ( $props->property_names ) {
        my $class = $props->get_property($name);
        $code->($name, $class);
    }
}

1;
__END__

=head1 NAME

Sledge::PSGI::Properties - dispatch manually for Sledge::PSGI

=head1 SYNOPSIS

  # map.props
  / = My::Pages::Index
  /bar = My::Pages::Bar

  # http://localhost/
  # => My::Pages::Index->new->dispatch('index')
  # http://localhost/bar/baz
  # => My::Pages::Bar->new->dispatch('baz')

=head1 AUTHOR

 mala <cpan at ma.la>

=cut
