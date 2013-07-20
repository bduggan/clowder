#!/usr/bin/env perl

use Mojo::Redis;
use Mojo::Log;
use Data::Dumper;
use JSON::XS;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Plugin::Red;

use warnings;
use strict;
use feature qw/:all/;

$| = 1;

$SIG{'USR2'} = sub { Mojo::IOLoop->stop; exit; };

my $log = Mojo::Log->new(path => 'log/subscriber.log', level => 'debug');
sub _log($) { $log->info("@_"); }
my $json = JSON::XS->new;
my $cb = Mojolicious::Plugin::Red->make_helper(app_name => 'subscriber', log => $log);

sub _red {
    my %a = @_;
    return $cb->('',%a);
}

#
# Watch for a message in the files:ingest channel.  Messages
# take the form { key => foo, md5 => bar }.
#
# Look for jobs which are waiting for this key.  For each job, if
# there are no more dependencies, change the status to 'ready'.
#
sub watch_files {
    my ($redis, $data) = @_;
    return unless $data;
    my ($action,$queue,$msg) = @$data;
    _log "files: action $action";
    return unless $action eq 'message';
    _log "saw $msg in files";
    my $spec = $json->decode($msg);
    my $file_key = $spec->{key};
    _log "looking for file:$file_key:jobs";
    _red(which => 'getter')->execute(
        [ smembers => "file:$file_key:jobs" ] => sub {
            my $r = shift;
            my $jobs = shift;
            unless (@$jobs) {
                _log "nobody waiting for $file_key";
                return;
            }
            _log "Received $file_key, checking jobs @$jobs";
            $r->execute(
                 ( map {(
                        [ srem => "job:$_:deps" => $file_key ], 
                        [ scard => "job:$_:deps" ], 
                 )} @$jobs ),
                 sub {
                     my $red = shift;
                     my @left = @_;
                     my $i = 0;
                     while (my $rem_ok = shift @left) {
                         my $card = shift @left;
                         my $job = $jobs->[$i];
                         _log "job ".$job." deps left : ".$card;
                         next if $card;
                         _log "job $job has no more deps.  It is ready.";
                         $red->execute(
                            [ set   => "job:$job:state" => 'ready' ],
                            [ lpush => "jobs:ready"     => $job    ],
                            [ srem  => "jobs:waiting"   => $job    ],
                            , sub {
                                _log "made job $job ready";
                            } );
                     } continue {
                         $i++;
                     }

                 }
            );
    });
}

_red(which => 'default')->subscribe('files:ingest' => \&watch_files );

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

