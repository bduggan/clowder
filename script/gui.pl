#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::JSON;
use Mojo::Util qw/sha1_sum/;
use Time::HiRes qw/gettimeofday/;

my $j = Mojo::JSON->new();

get '/' => 'index';

get '/seq' => sub {
  my $c = shift;
  Mojo::IOLoop->stream($c->tx->connection)->timeout(300);
  $c->res->headers->content_type('text/event-stream');
  my $i = 1;
  my $id = Mojo::IOLoop->singleton->recurring(
    1 => sub {
      my @new_files;
      for (1..1 + (int rand 10_000)) {
        push @new_files,
            {
                filename => "file-" . rand,
                created  => scalar gettimeofday(),
                sha1     => sha1_sum(scalar gettimeofday().(rand 2).(rand 1)),
            };
      }

      my $s = $j->encode(\@new_files);
      $c->write("event:seq\ndata: $s\n\n");
    }
  );
  $c->on(finish => sub {
          $c->app->log->info("done");
          Mojo::IOLoop->remove($id);
  });
};

app->start;

