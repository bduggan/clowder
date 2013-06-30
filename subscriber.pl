#!/usr/bin/env perl

use warnings;
use strict;
use feature qw/:all/;
use Mojo::Redis;
use Mojo::Log;
use Data::Dumper;

$| = 1;

$SIG{'USR2'} = sub { Mojo::IOLoop->stop; exit; };

my $log = Mojo::Log->new(path => 'log/subscriber.log', level => 'debug');
sub _log($) {
    $log->info("@_");
}

my $redis = Mojo::Redis->new;

#
# watch or a message in files:ingested; this will just
# be a key for a file. When a key is received, look for
# jobs which are waiting for this key.  For each job, if
# there are no more dependencies, change the status to 'ready'.
#
sub watch_files {
    my ($redis, $data) = @_;
    my ($action,$queue,$msg) = @$data;
    _log "files: action $action";
    return unless $action eq 'message';
    _log "saw $msg in files";
    my $key = $msg;
    $redis->get( "file:$key:jobs" => sub {
            my $r = shift;
            my $jobs = shift;
            _log "Received $key, checking jobs : ".Dumper($jobs);
        });
}

$redis->subscribe(files => \&watch_files );

#    for my $key (keys %deps) {
#        nb "subscribing to files : (key=$key)";
#        push @subscriptions, $c->red(new => 1)->subscribe('files', sub {
#                my ($sub, $data) = @_;
#                my ($action,$channel,$message) = @$data;
#                nb "# subscribe to data called ($action, $channel, $message)";
#                return unless $action eq 'message'; # ignore other subscribes.
#                my $file = $json->decode($message) or nb "could not decode $message";
#                unless (defined($file->{key})) {
#                    nb "# error: no key for file\n";
#                    nb "subscription got : ".Dumper($file);
#                    return;
#                }
#                unless ($file->{key} eq $key) {
#                    nb "# we are waiting for $key, so we ignore $file->{key}";
#                    return;
#                }
#                nb "# Matched incoming key with desired key $key, this job is not waiting.";
#                $c->red->srem('waiting_jobs', $id );
#                delete $job->{deps}->{$key}; 
#                if (keys %{$job->{deps}} == 0) {
#                    $c->red->lpush('ready_jobs', $id );
#                } else {
#                    $c->red->sadd('waiting_jobs', $id );
#                }
#            } );
#    }

Mojo::IOLoop->recurring(5 => sub {
        _log(" subscriber is watching...");
    });

Mojo::IOLoop->start;

