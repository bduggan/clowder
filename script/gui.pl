#!/usr/bin/env perl
use Mojolicious::Lite;

get '/' => 'index';

get '/data.tsv' => sub {
    my $c = shift;
    $c->res->headers->content_type('text/plain');
    my $text = join "\n",map "$_\t$_", 1..14;
    $c->render( text => "name\tvalue\n$text");
};

get '/data.json' => sub {
    my $c = shift;
    Mojo::IOLoop->timer( 0.1 => 
        sub {
            $c->render(json => [
                { name => 'a', value => 10 },
                { name => 'b', value => 22 },
                { name => 'c', value => 142 },
                ]);
        });
    $c->render_later;
};

# EventSource for log messages
# from cookbook
get '/events' => sub {
  my $self = shift;

  # Increase inactivity timeout for connection a bit
  Mojo::IOLoop->stream($self->tx->connection)->timeout(300);

  # Change content type
  $self->res->headers->content_type('text/event-stream');

  # Subscribe to "message" event and forward "log" events to browser
  my $cb = $self->app->log->on(message => sub {
    my ($log, $level, @lines) = @_;
    $self->write("event:log\ndata: [$level] @lines\n\n");
  });

  # Unsubscribe from "message" event again once we are done
  $self->on(finish => sub {
    my $self = shift;
    $self->app->log->unsubscribe(message => $cb);
  });
  $self->rendered;
};

app->start;

