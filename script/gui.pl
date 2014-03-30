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

get '/seq' => sub {
  my $c = shift;
  Mojo::IOLoop->stream($c->tx->connection)->timeout(300);
  $c->res->headers->content_type('text/event-stream');
  my $i = 1;
  my $id = Mojo::IOLoop->singleton->recurring(
    1 => sub {
      my $s = scalar localtime;
      $s .= ' ';
      $i = time % 10;
      $s .= 'x' x $i;
      $c->write("event:seq\ndata: $s\n\n");
    }
  );
  $c->on(finish => sub {
          $c->app->log->info("done");
          Mojo::IOLoop->remove($id);
  });
};

app->start;

