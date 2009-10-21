package Sledge::PSGI;

use strict;

use base qw(Class::Data::Inheritable);

use Carp ();
use Class::Trigger;
use Class::Inspector;
use File::Basename ();
use UNIVERSAL::require;
use Scalar::Util qw(blessed);
use String::CamelCase qw(camelize);
use Module::Pluggable::Object;

use Sledge::Utils;
use Sledge::PSGI::Properties;
use Sledge::PSGI::Handler qw(handle_request);

our $VERSION = '0.01';
our $StaticExtension = '.html';

sub import {
    my $pkg = shift;
    $pkg->mk_classdata('ActionMap' => {});
    $pkg->mk_classdata('ActionMapKeys' => []);
    $pkg->mk_classdata('components' => []);
}

# ActionMap 
#  /foo/bar => { class => MyApp::Foo, page => "bar" }
#  => dispatch to MyApp::Foo::dispatch_bar 

sub new {
    my $class = shift;
    my $opt = shift || {};
    my $self = bless $opt, $class;
    $self;
}

# create ActionMap
sub setup {
    my $class = shift;
    my $path = shift;
    if ($path) {
        $class->_setup_by_properties($path); 
    } else {
        $class->_setup_auto;
    }
}

# setup by module pluggable
sub _setup_auto {
    my $pkg = shift;

    my $pages_class = join '::', $pkg, 'Pages';
    $pages_class->use or die $@;
    my $finder = Module::Pluggable::Object->new(
        search_path => [$pages_class],
        # require => 1,
    );
    $pkg->components([$finder->plugins]);
    
    for my $subclass(@{$pkg->components}) {
        $subclass->require;
        if ($@) { warn $@ ; next }
        my $methods = Class::Inspector->methods($subclass, 'public');
        for my $method(@{$methods}) {
            if ($method =~ s/^dispatch_//) {
                $pkg->register($subclass, $method);
            }
        }
    }
    $pkg->ActionMapKeys([
        sort { length($a) <=> length($b) } keys %{$pkg->ActionMap}
    ]);
}

# setup by map.properties
sub _setup_by_properties {
    my $pkg = shift;
    my $path = shift;
    my $prop = Sledge::PSGI::Properties->new($path);
    $prop->each(sub {
        my ($prefix, $module) = @_;
        $module->require or die $UNIVERSAL::require::ERROR;
        $pkg->register_module($prefix, $module);
    });
}

# register page class and method, url is auto generated
sub register {
    my($pkg, $class, $page) = @_;
    my $prefix = Sledge::Utils::class2prefix($class);
    my $path = $prefix eq '/' ? "/$page" : "$prefix/$page";
    $path =~ s{/index$}{/};
    $pkg->_register($path, $class, $page);
}

# register prefix and page class, scan dispatch_* methods and register
sub register_module {
    my($pkg, $prefix, $class) = @_;
    my $methods = Class::Inspector->methods($class, 'public');
    for my $page (@$methods) {
        if ($page =~ s/^dispatch_//) {
            my $path = $prefix eq '/' ? "/$page" : "$prefix/$page";
            $path =~ s{/index$}{/};
            $pkg->_register($path, $class, $page);
        }
    }
}

sub _register {
    my $pkg = shift;
    my ($path, $class, $page) = @_;
    $pkg->ActionMap->{$path} = {
        class => $class,
        page => $page,
    };
}

sub lookup {
    my($self, $path) = @_;
    $path ||= '/';
    $path =~ s{/index$}{/};
    my $action;
    if ($action = $self->ActionMap->{$path}) {
        return $action;
    }
    elsif ($action = $self->lookup_static($path)) {
        warn $action;
        return $action;
    }

    # handle PATH_INFO type args
    # /foo/bar/baz/path_info 
    my @parts = split ("/", $path);
    warn scalar @parts;
    for (1 .. scalar @parts) {
        my $level = @parts - $_;
        my $dispatch_path = join ("/", @parts[0 .. $level]);
        warn $dispatch_path;
        last if $dispatch_path eq "";
        if ($action = $self->ActionMap->{$dispatch_path} || $self->ActionMap->{$dispatch_path."/"}) {
            my %action = %{ $action };
            my $args = $path;
            $args =~ s{^$dispatch_path/?}{};
            $action{args} = [split '/', $args];
            return \%action;
        }
    }
}

sub lookup_static {
    my($self, $path) = @_;
    my($page, $dir, $suf) = 
        File::Basename::fileparse($path, $StaticExtension);
    use Data::Dumper;
    warn Dumper [$page, $dir, $suf];
    return if index($page, '.') >= 0;
    $page ||= 'index';
    my $class;
    if ($dir eq '/') {
        my $appname = ref $self;
        for my $subclass(qw(Root Index)) {
            $class = join '::', $appname, 'Pages', $subclass;
            last if $class->require;
        }
    }
    else {
        $dir =~ s{^/}{};
        $dir =~ s{/$}{};
        $class = join '::', 
            ref($self), 'Pages', map { camelize($_) } split '/', $dir;
    }
    if ((Class::Inspector->loaded($class) || $class->require) && 
            -e $class->guess_filename($page)) {
        no strict 'refs';
        *{"$class\::dispatch_$page"} = sub {} 
            unless $class->can("dispatch_$page");
        my %action = (class => $class, page => $page);
        $self->ActionMap->{$path} = \%action;
        return \%action;
    }
}

sub override_pages {
    #TODO 
}

sub override_compat {
    my $class = shift;
    my $pages_class = shift || "Sledge::PSGI::PagesBase";

    # monkey patch for Sledge::Pages::Compat;
    require Sledge::Pages::Compat;
    *{Sledge::Pages::Compat::import} = sub {
        my $pkg = caller;
        no strict 'refs';
        unshift @{"$pkg\::ISA"}, $pages_class;
    }
}

sub run {
    my $self = shift;
    unless (blessed $self) {
        $self = $self->new;
    }
    $self->handle_request(@_);
}

1;

__END__

=head1 NAME

Sledge::PSGI - run Sledge based application on PSGI/Plack

=head1 SYNOPSIS

 # MyApp.pm
 package MyApp;
 use base qw(Sledge::PSGI);
 1;

 # myapp.psgi
 use MyApp;
 # MyApp->override_compat; # override Sledge::Pages::Compat for using Sledge::PSGI
 MyApp->setup; # auto-setup by scanning MyApp::Pages::*
 # MyApp->setup("map.properties"); # setup by map.properties file
 my $app = sub { MyApp->new->run(@_) };

=head1 AUTHOR

mala <cpan at ma.la>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

