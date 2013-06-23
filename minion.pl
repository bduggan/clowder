#!/usr/bin/env perl

use warnings;
use strict;
use feature qw/:all/;
use Mojo::UserAgent;
use Data::Dumper;

$| = 1;

$SIG{'USR2'} = sub { Mojo::IOLoop->stop; exit; };

sub _log($) {
    say "# @_";
}

my $base = $ARGV[0] or die "usage $0 <url>";

my $ua = Mojo::UserAgent->new->connect_timeout(10)->request_timeout(30);

$ua->on(error => sub {
        my ($ua,$err) = @_;
        _log 'error : '.$err;
    });

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
                _log "client got $code : $err";
                return get_next_job();
            }
            my $job = $tx->res->json;
            unless (defined($job)) {
                _log "hey no json, I tried ($base)  :\n".$tx->req->to_string;
                _log "hey no json, I got :\n".$tx->res->to_string;
            }
            _log "got a job : ".Dumper($job);
            sleep 1;
            get_next_job();
        } );
}

get_next_job();

Mojo::IOLoop->start;

