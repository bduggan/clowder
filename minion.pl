#!/usr/bin/env perl

use Mojo::UserAgent;
use Mojo::Log;
use AnyEvent::Open3::Simple;
use Data::Dumper;
use JSON::XS;

use warnings;
no warnings 'uninitialized';
use strict;
use feature qw/:all/;

$| = 1;

$SIG{'USR2'} = sub { Mojo::IOLoop->stop; exit; };

my $log = Mojo::Log->new(path => 'log/minion.log', level => 'debug');

my $json = JSON::XS->new();

sub _log($) {
    $log->info("@_");
}

my $base = $ARGV[0] or die "usage $0 <url>";

my $ua = Mojo::UserAgent->new->connect_timeout(10)->request_timeout(70);

$ua->on(error => sub {
        my ($ua,$err) = @_;
        _log 'error : '.$err;
    });

my $max_jobs = 4;

my %processes;

sub notify_jobserver {
    my $pid = shift;
    # TODO
}

sub run_job {
    my $job = shift;
    my $label = "Job $job->{id} ($job->{app})";
    my $ipc = AnyEvent::Open3::Simple->new(
        on_start => sub {
            my $p = shift;
            _log "Starting $label";
            $processes{ $p->pid }{proc} = $p;
            $p->print($json->encode($job));
            $p->close;
        },
        on_stdout => sub {
            my ( $p, $line ) = @_;
            $processes{ $p->pid }{stdout} .= $line;
        },
        on_stderr => sub {
            my ($p, $line ) = @_;
            $line //= '<undef>';
            _log "$label : $line";
        },
        on_exit => sub {
            my ( $p, $status, $sig ) = @_;
            _log "$label exited with status $status";
            notify_jobserver( $p->pid );
            delete $processes{ $p->pid };
        }
    );
    $ipc->run($job->{app});
    # TODO :
    # Run job in a sandbox.
    # When starting, inform jobserver job is running.
    # When it stops, inform jobserver it has stopped, and send results.
    # STDOUT should be JSON, send it back.
    # Don't run more than $max_jobs at once.
    # Put STDERR and other files generated someplace. (tmpdir for now)
}

sub connect {
    # TODO persistent websocket connection to control running jobs.
}

sub get_next_job {
    $ua->get( "$base/job" => sub {
            my ($ua,$tx) = @_;
            unless (defined($tx)) {
                _log "get request failed; no transaction object, sleeping 2 seconds.";
                sleep 2;
                return get_next_job();
            }
            my $res;
            unless ($res = $tx->success) {
                my ($err,$code) = $tx->error;
                $code //= '<undef>';
                _log "client got $code : $err";
                sleep 1;
                return get_next_job();
            }
            my $job = $tx->res->json;
            unless (defined($job)) {
                _log "error getting json from $base : ".
                     " request :\n".$tx->req->to_string."\n".
                     " response : ".$tx->res->to_string;
            }
            _log "got a job : ".Dumper($job);
            run_job($job);
            get_next_job();
        } );
}

get_next_job();

Mojo::IOLoop->recurring(5 => sub {
        _log(" minion $$ waiting for a job...");
        _log("Jobs running : ".(keys %processes));
    });
Mojo::IOLoop->start;

