#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::JSON;
use Mojo::Redis;
use Data::Dumper;

my $json = Mojo::JSON->new();
my $redis = Mojo::Redis->new();
app->helper(red => sub { $redis; });
app->log->level('debug');
app->secret(42);

sub nb($) {
    app->log->debug(@_);
}

post '/clean' => sub {
    my $c = shift;
    $c->red->del('waiting_jobs');
    $c->red->del('ready_jobs');
    $c->red->del('files');
    $c->render(json => 'ok');
};

put '/job' => sub {
    my $c = shift;
    my $job = $c->req->json;
    my $deps = $job->{deps};

    $c->red->sadd('waiting_jobs', $json->encode($job)) or die "could not sadd";
    for my $key (keys %$deps) {
        nb "subscribing to files : $key";
        $c->red->subscribe('files')->on(data => sub {
                my ($sub, $data) = @_;
                my ($action,$channel,$message) = @$data;
                nb "# subscribe to data called ($action, $channel, $message)";
                return unless $action eq 'message'; # ignore other subscribes.
                my $file = $json->decode($data);
                unless (defined($file->{key})) {
                    nb "# error: no key for file\n";
                    nb "subscription got : ".Dumper($data);
                    return;
                }
                unless ($file->{key} eq $key) {
                    nb "# we are waiting for $key, so we ignore $file->{key}";
                    return;
                }
                nb "# Matched incoming key with desired key $key, this job is not waiting.";
                $c->red->srem('waiting_jobs', $json->encode($job));
                delete $job->{deps}->{$key}; 
                if (keys %{$job->{deps}} == 0) {
                    $c->red->lpush('ready_jobs', $json->encode($job));
                } else {
                    # waiting is the hardest part.
                    $c->red->sadd('waiting_jobs', $json->encode($job));
                }
            } );
    }
    $c->render(code => 202, json => { status => 'Accepted' } );

} => 'putjob';

get '/job' => sub {
    my $c = shift;
    $c->render_later;
    $c->red->brpop('ready_jobs' => 10 => sub {
            my $red = shift;
            my $next = shift;
            unless ($next && @$next) {
                $c->app->log->info("no job found after 10 seconds of waiting");
                return $c->render_not_found;
            }
            return $c->render(code => 200, json => {job => $next} );
        } );
} => 'getjob';

get '/jobs/waiting' => sub {
    my $c = shift;
    $redis->execute(scard => 'waiting_jobs' => sub {
            my ($redis, $count) = @_;
            $c->render(json => { count => $count } );
        }
    );
    $c->render_later;
};

post '/file' => sub {
    # a file has arrived.
    my $c = shift;
    my $spec = $c->req->json;
    my ($key,$md5) = @$spec{qw[key md5]};
    nb "# got file $key, publishing a message";
    $c->red->publish(files => $c->req->body) or die "could not publish";
    nb "finished publishing";
    $c->render(json => { status => 'ok' });
};

app->start; 

__DATA__
@@ not_found.development.html.ep
not found : <%= $self->req->url %>

