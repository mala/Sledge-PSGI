package Sledge::PSGI::DebugHandler;

# Debugger
use Data::Dumper;
use Devel::Symdump;
use Devel::StackTrace;
use Devel::StackTrace::AsHTML;
use YAML ();
use Text::MicroTemplate qw(render_mt encoded_string);
use Class::Inspector;


use vars qw(%init_module $init %template);
our $DEBUG_PATH = "/debug";

sub init { 
    $init_module{$_}++ for keys %INC; $init = 1;
    local $/;
    my $data = <DATA>;
    my @templates =  YAML::Load($data);
    warn Dumper @templates;
    for (@templates) {
        $template{$_->{file}} = $_->{template};
        warn $_->{file};
    }
}

sub handle_request {
    my ($class, $self, $env) = @_;
    $class->init unless ($init);
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
        my $body = render_mt($template{"index"})->as_string;
        return [ 200, [ 'Content-Type' => 'text/html' ], [$body] ];
    }
}

sub handle_trace {
    my ($class, $self, $env) = @_;

    $env->{PATH_INFO} =~s{^$DEBUG_PATH\Q/trace/}{};
    $env->{REQUEST_URI} =~s{^$DEBUG_PATH\Q/trace/}{/};

    my %debug_response;
    
    # add trigger
    $self->add_trigger("before_dispatch_psgi", sub {   
        my $psgi = shift;
        my ($self, $page) = @_;
        $debug_response{r} = $self->r;
        $debug_response{request} = $self->req;
    });
    $self->add_trigger("after_dispatch_psgi", sub {
        my $psgi = shift;
        my ($self, $res) = @_;
        my $param = $self->tmpl->{_params}; 
        $debug_response{template_param} = $param;
        $debug_response{response} = $self->res;
        $debug_response{response_header} = $self->res->headers;
    });

    my $app_res = $self->handle_request($env);
    render({
        title => "Trace for ". $env->{REQUEST_URI},
        body => render_mt($template{"trace"}, {
            env => $env,
            %debug_response,
        })->as_string,
    });
}

sub handle_inspect {
    my ($class, $self, $env) = @_;
    my $module = $env->{PATH_INFO};
    $module =~s{^$DEBUG_PATH\Q/inspect/}{};
    render({
        title => $module,
        body => render_mt($template{"inspect"}, {
            module  => $module,
            inspect => $DEBUG_PATH . "/inspect/"
        })->as_string,
    });
   
}

sub handle_versions {
    no strict qw(refs);
    my @versions = map { [$_, ${ "$_" . "::VERSION" }] } Devel::Symdump->rnew->packages;
    @versions = sort { $a->[0] cmp $b->[0] } grep { $_->[1] } @versions;
    render({
        title => "Versions", 
        body  => render_mt($template{"versions"}, @versions)->as_string
    });
}

sub handle_modules {
    my @tmp = keys %INC;
    @tmp = map { ($init_module{$_} ? "" : "* ") . $_  } @tmp;
    render ({ 
        title => "loaded modules",
        body  => "<pre>". (join "\n", sort @tmp) . "</pre>",
    });
}

sub handle_actions {
    my ($class, $self, $env) = @_;
    my @tmp = keys %{$self->ActionMap};
    my @params;
    for my $action (sort @tmp) {
        my $class = $self->ActionMap->{$action}->{class};
        my $method = $action;
        $method =~s{.*/(.*)?$}{$1};
        my $method = $class->can("post_dispatch_$method") ? "GET | POST" : "GET";
        push @params, [$method, $action, $class];
    }
    my $p = {
        base => $DEBUG_PATH,
    };
    render({
        title => "Actions",
        body  => render_mt($template{"actions"}, $p, @params)->as_string,
    });
}

sub render {
    my $param = shift;
    $param->{base} = $DEBUG_PATH;
    $param->{body} = encoded_string $param->{body};
    $param->{css} = encoded_string $template{css};
    my $body = render_mt($template{layout}, $param);
    return [ 200, [ 'Content-Type' => 'text/html' ], [ $body ]];
}


1;

__DATA__

---
file: layout
template: |
  ? my $p = shift;
  <html>
  <head>
    <title>Sledge Debug Console :: <?= $p->{title} ?></title>
    <style type="text/css">
    <?= $p->{css} ?>
    </style>
  </head>
  <body>
  <h1>Sledge Debug Console</h1>
    <a href="<?= $p->{base} ?>/actions">Actions</a>
    <a href="<?= $p->{base} ?>/versions">Versions</a>
    <a href="<?= $p->{base} ?>/modules">Modules</a>
    <hr />
      <?= $p->{body} ?>
  </body>
  </html>
---
file: css
template: |
  h1 { border-bottom: 1px solid #000; font-size: 120% }
  h2 { border-bottom: 1px solid #000; font-size: 100% }
  pre { max-width: 90%; max-height: 300px; overflow: auto;}
---
file: index
template: | 
  Hi. This is Sledge Debug Console.

---
file: trace
template: |
  ? my $param = shift; use Data::Dumper;
  <h2>PSGI env</h2>
  <pre><?= Dumper $param->{env} ?></pre>
  <h2>request headers</h2>
  <pre><?= Dumper $param->{request}->headers ?></pre>

  <h2>output header</h2>
  <pre><?= Dumper $param->{response_header} ?></pre>
  
  <h2>response body</h2>
  <pre><?= Dumper $param->{response}->body ?></pre>
  
---
file: versions
template: |
  <table>
  ? for my $pairs (@_) { my ($package, $version) = @$pairs;
  <tr>
    <td><?= $package ?></td>
    <td><?= $version ?></td>
  </tr>
  ? }
  </table>
---
file: actions
template: |
  <table border=1>
  ? my $p = shift;
  ? for my $pairs (@_) { my ($method, $action, $class) = @$pairs;
  <tr>
    <td><?= $method ?></td>
    <td>
        <a href="<?= $action ?>"><?= $action ?></a>
        <a href="<?= $p->{base} . "/trace" . $action ?>">[trace]</a>
    </td>
    <td>
        <a href="<?= $p->{base} . "/inspect/" . $class ?>"><?= $class ?></a>
    </td> 
  </tr>
  ? }
  </table>
---
file: inspect
template: |
  ? my $p = shift; use Data::Dumper; use UNIVERSAL::which;
  ? my @isa = eval '@{' . $p->{module} . '::ISA}';
  ? my @sub = @{ Class::Inspector->subclasses($p->{module}) || [] };
  ? my $expand = Class::Inspector->methods($p->{module}, "expanded") || []; # full,package,method,codere
  ? my @methods = map { my @a = UNIVERSAL::which($p->{module}, $_->[2]); $_->[4] = $a[0]; $_ } @{$expand}; # add which
  ? my @constants = grep { $_->[2] =~m{^[A-Z_]+$} } @methods;
  ? my @owned     = grep { $_->[4] && $p->{module} eq $_->[4] } @methods;
  ? my @functions = grep { $_->[2] !~m{^[A-Z_]+$} } @methods;
  ? my $m;
  <h2>ISA (Parent Class)</h2>
  <ul>
  ? for $m (@isa) {
    <li><a href="<?= $p->{inspect} . $m ?>"><?= $m ?></a></li>
  ? }
  </ul>
  <h2>Subclasses (Inherited by)</h2>
  <ul>
  ? for $m (@sub) {
    <li><a href="<?= $p->{inspect} . $m ?>"><?= $m ?></a></li>
  ? }
  </ul>
  <h2>Constants</h2>
  <table border=1>
    <tr><th>Name</th><th>Value</th><th>Defined</th></tr>
  ? for $m (@constants) {
    <tr>
      <td><?= $m->[2] ?></td>
      <td><?= $m->[3]->() ?></td>
      <td><a href="<?= $p->{inspect} . $m->[1] ?>"><?= $m->[1] ?></a></td>
    </tr>
  ? }
  </table>
  <h2>Methods</h2>
  <table border=1>
    <tr><th>Name</th><th>Defined</th></tr>
  ? for $m (@owned) {
    <tr>
      <td><?= $m->[2] ?></td>
      <td><a href="<?= $p->{inspect} . $m->[1] ?>"><?= $m->[1] ?></a></td>
    </tr>
  ? }
  </table>






