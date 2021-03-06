#!/usr/bin/env perl

=head1 NAME

jobserver.pl -- Clowder job server.

=head1 SCHEMA

clowder uses these redis keys :

    name              type        description
    ----------------- ----------- ---------------
    global:nextid     integer     sequence (for making jobids)
    job:$id:spec      JSON        complete job specification (i.e. app, params)
    job:$id:state     string      state : ready, waiting, taken, complete
    job:$id:deps      set         set of keys on which this job depends
    job:$id:results   JSON        results from running app
    file:$key:jobs    set         set of jobs for which this file key is waiting
    jobs:waiting      set         set of job ids that are waiting for files
    jobs:ready        list        list of jobs ready to be taken by minions
    files:ingest      channel     announcements of ingested file keys and md5s

=cut

use Mojolicious::Lite;
use Mojo::JSON;
use Mojo::Redis;
use Data::Dumper;
use FindBin;

use lib "$FindBin::Bin/../lib";

app->moniker('jobserver');
plugin 'red';

my $json = Mojo::JSON->new();
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
app->secrets([42]);

sub nb($) {
    app->log->debug(@_);
}

get '/' => { text => 'welcome to jobserver' };

post '/clean' => sub {
    my $c = shift;
    $c->red->execute(
        ['keys' => '*'], sub {
            my $red = shift;
            my $vals = shift or return;
            return $c->render(json => { status => 'removed 0 keys'}) unless @$vals;
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
post '/job' => sub {
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
        [ get => "job:$id:results" ],
        sub {
            my $r = shift;
            my ($spec,$state,$results) = @_;
            return $c->render_not_found unless $spec;
            $results &&= $json->decode($results);
            $spec &&= $json->decode($spec);
            my $response = {
                id => $id,
                state => $state,
                spec => $spec,
                results => $results,
            };
            $c->render(json => $response );
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
            return unless $c;
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
            $red->execute(
                [ set => "job:$id:state" => "taken" ],
                [ get => "job:$id:spec" ]
                => sub {
                    my $r = shift;
                    my ($set,$spec) = @_;
                    $c->app->log->info("Job found, sending it out.");
                    $c->res->body($spec);
                    $c->res->code(200);
                    $c->rendered;
                } );
        } );
} => 'getjob';

get '/jobs/waiting' => sub {
    my $c = shift;
    $c->app->red->execute(scard => 'jobs:waiting' => sub {
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

post '/job/:id' => sub {
    # a job has changed state
    my $c = shift;
    my $id = $c->stash('id');
    my $job = $c->req->json;
    $c->red->execute(
        [ set => "job:$id:state" => $job->{state} ],
        [ set => "job:$id:results" => $json->encode($job) ], sub {
            my ($red,$one,$two ) = @_;
            $c->render(json => { status => 'ok' } );
        } );
    $c->render_later;
};

Mojo::IOLoop->recurring(
    2 => sub {
        app->red->smembers('jobs:waiting' => sub {
            my ($rd,$rlt) =  @_;
            if ($rlt && @$rlt) {
                app->log->info("jobs waiting : @$rlt");
            }
        });
    }
);

nb "starting job server $$ ".time;

app->start; 

__DATA__
@@ not_found.development.html.ep
not found : <%= $self->req->url %>

@@ not_found.html.ep
not found : <%= $self->req->url %>

@@ exception.html.ep
%== $exception

