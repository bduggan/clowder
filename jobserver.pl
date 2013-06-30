#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::JSON;
use Mojo::Redis;
use Data::Dumper;

my $json = Mojo::JSON->new();
my $redis = Mojo::Redis->new();

my $error_cb = sub {
        my ($red,$err) = @_;
        app->log->warn("redis error : $err");
    };

$redis->on(error => $error_cb);
app->helper(red => sub {
        my $c = shift;
        my %a = @_;
        return $redis unless $a{new};
        my $red = Mojo::Redis->new();
        $red->on(error => $error_cb );
        return $red;
    });
app->helper(new_id => sub {
        my $c = shift;
        my $i;
        $c->red->incr('nextid' => sub { $i = $_[1];} );
        my $wait = 0;
        Mojo::IOLoop->one_tick until (defined($i) || $wait++ > 1000);
        unless (defined($i)) {
            $c->app->log->error("Could not increment nextid");
            die "error incrementing nextid";
        }
        return $i;
    });
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
    $c->rendered;
};

my @subscriptions;

put '/job' => sub {
    my $c = shift;
    my $job = $c->req->json;
    my $deps = $job->{deps};
    my %deps;
    $job->{id} = $c->new_id;
    unless ($deps && @$deps) {
        $c->app->log->info('no dependencies, this job is ready');
        $c->red->lpush('ready_jobs', $json->encode($job)) or die "could not sadd";
        $c->res->code(202);
        return $c->render(json => { state => 'Ready', id => $job->{id} } );
    }

    %deps = map { $_ => 1 } @$deps;
    $job->{deps} = \%deps;

    $c->app->log->info('dependencies.  Subscribing to files for this job');
    $c->red->sadd('waiting_jobs', $json->encode($job)) or die "could not sadd";
    $c->app->log->info('added to waiting_jobs');
    $c->red->smembers('waiting_jobs' => sub {
            my ($rd,$rlt) =  @_;
            $c->app->log->info("waiting : @$rlt");
        });
    for my $key (keys %deps) {
        nb "subscribing to files : (key=$key)";
        push @subscriptions, $c->red(new => 1)->subscribe('files', sub {
                my ($sub, $data) = @_;
                my ($action,$channel,$message) = @$data;
                nb "# subscribe to data called ($action, $channel, $message)";
                return unless $action eq 'message'; # ignore other subscribes.
                my $file = $json->decode($message) or nb "could not decode $message";
                unless (defined($file->{key})) {
                    nb "# error: no key for file\n";
                    nb "subscription got : ".Dumper($file);
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
                    $c->red->sadd('waiting_jobs', $json->encode($job));
                }
            } );
    }
    $c->res->code(202);
    $c->render(json => { state => 'Waiting' } );

} => 'putjob';

get '/job' => sub {
    my $c = shift;
    $c->render_later;
    $c->red(new => 1)->brpop('ready_jobs' => 10 => sub {
            my $red = shift;
            my $next = shift;
            unless ($next && @$next) {
                $c->app->log->info("no job found after 10 seconds of waiting");
                return $c->render_not_found;
            }
            $c->app->log->info("Job found, sending it out.");
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
    nb "finished publishing : ".$c->req->body;
    $c->render(json => { status => 'ok' });
};

Mojo::IOLoop->recurring(
    2 => sub {
        Mojo::Redis->new()->smembers('waiting_jobs' => sub {
            my ($rd,$rlt) =  @_;
            app->log->info("still waiting : @$rlt");
        });
    }
);

app->start; 

__DATA__
@@ not_found.development.html.ep
not found : <%= $self->req->url %>

@@ not_found.html.ep
not found : <%= $self->req->url %>

@@ exception.html.ep
%== $exception

