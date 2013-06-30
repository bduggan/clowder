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

get '/' => { text => 'welcome to jobserver' };

post '/clean' => sub {
    my $c = shift;
    $c->red->del('jobs:waiting');
    $c->red->del('jobs:ready');
    $c->red->del('files');
    $c->render(json => 'ok');
    $c->rendered;
};

my @subscriptions;

#
# PUT a job.  This sets :
#       job:$id:spec to the json spec for the file.  This
#            includes params (hash), and dependencies (array of keys)
#       job:$id:state to ready or waiting
#       file:$key:jobs to the set of jobs waiting for this file
#
# See subcriber.pl for how the file:* keys are used.
#
put '/job' => sub {
    my $c = shift;
    my $job = $c->req->json;
    my $deps = $job->{deps};
    my $id = $c->new_id;
    $job->{id} = $id;

    my @commands = (
        [ set => "job:$id:spec" => $json->encode($job) ],
    );

    my $state;
    if ($deps && @$deps) {
        push @commands, [ sadd => 'jobs:waiting' => $id ];
        for my $key (@$deps) {
            push @commands, [ sadd => "file:$key:jobs" => $id ];
        }
        $state = 'waiting';
    } else {
        push @commands, [ lpush => "jobs:ready" => $id ];
        $state = 'ready';
    }
    push @commands, [ set => "job:$id:state" => $state ];

    $c->red->execute(
        @commands,
        sub {
            $c->res->code(202);
            $c->render(json => { state => $state, id => $id } );
        }
    );
    $c->render_later;
} => 'putjob';

get '/job/:id' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    $c->red->execute(
        [ get => "job:$id:spec" ],
        [ get => "job:$id:state" ],
        sub {
            my $r = shift;
            my ($spec,$state) = @_;
            return $c->render_not_found unless $spec;
            $c->render(json => { %{ $json->decode($spec) }, state => $state } );
        }
    );
    $c->render_later;
};

get '/job' => sub {
    my $c = shift;
    $c->render_later;
    $c->red(new => 1)->brpop('jobs:ready' => 10 => sub {
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
    $redis->execute(scard => 'jobs:waiting' => sub {
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
        Mojo::Redis->new()->smembers('jobs:waiting' => sub {
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

