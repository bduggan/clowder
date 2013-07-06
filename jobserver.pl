#!/usr/bin/env perl

=head1 NAME

jobserver.pl -- Clowder job server.

=head1 SCHEMA

clowder uses these redis keys :

    name              type        description
    ----------------- ----------- ---------------
    global:nextid     integer     sequence (for making jobids)
    job:$id:spec      JSON        complete job specification (i.e. app, params)
    job:$id:state     string      state : ready, waiting, taken
    job:$id:deps      set         set of keys on which this job depends
    file:$key:jobs    set         set of jobs for which this file key is waiting
    jobs:waiting      set         set of job ids that are waiting for files
    jobs:ready        list        list of jobs ready to be taken by minions
    files:ingest      channel     announcements of ingested file keys and md5s

=cut

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
        $c->red->incr('global:nextid' => sub { $i = $_[1];} );
        my $wait = 0;
        Mojo::IOLoop->one_tick until (defined($i) || $wait++ > 1000);
        unless (defined($i)) {
            $c->app->log->error("Could not increment global:nextid");
            die "error incrementing global:nextid";
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
    $c->red->execute(
        ['keys' => '*'], sub {
            my $red = shift;
            my $vals = shift;
            $red->execute(
                 ( map [ 'del' => $_ ], grep defined, @$vals ), sub {
                    $c->render(json => { status => "removed ".@$vals." keys "});
                 }
            );
        } );
  $c->render_later;
};

#
# PUT a job.  This sets :
#       job:$id:spec to the json spec for the file.  This
#            includes params (hash), and dependencies (array of keys)
#       job:$id:deps to the set of dependencies for this file.
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
            push @commands, [ sadd => "job:$id:deps"   => $key ];
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
    $c->red(new => 1)->brpop('jobs:ready' => 60 => sub {
            my $red = shift;
            my $next = shift;  # $k == 'jobs:ready'
            unless ($next) {
                $c->app->log->info("no job found after 60 seconds of waiting");
                return $c->render_not_found if $c->tx;
                $c->app->log->info("client is gone");
                return;
            }
            if (@$next > 2) {
                $c->app->log->info("brpop return @$next");
                return $c->render_exception("brpop returned @$next");
            }
            my $id = $next->[1];  # next is [ 'jobs:ready' => $id ]
            $red->execute( [ set => "job:$id:state" => "taken" ]
                => sub {
                    $c->app->log->info("Job found, sending it out.");
                    $c->render(code => 200, json => {job => $next} );
                } );
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
    $c->red->publish('files:ingest' => $c->req->body) or die "could not publish";
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

