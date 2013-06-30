#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;
use JSON::XS;
use Data::Dumper;
use Test::More;

my $json = JSON::XS->new();

sub info($) {
    say "@_";
}

my %processes;
my $pid;
my $server_url = 'http://localhost:8080';

system('pkill -f morbo') if $ENV{KILL_RUNAWAY_MORBO};

# Start server.
unless ($pid = fork) {
    open STDOUT, "| egrep -v available";
    exec "morbo ./jobserver.pl --listen $server_url";
    die "notreached";
}
$processes{$pid} = 'morbo';
ok $pid, "started morbo";

# Start minion.
sleep 1;
unless ($pid = fork) {
    exec "./minion.pl $server_url";
    die "notreached";
}
$processes{$pid} = 'minion';
ok $pid, "started minion";

# Submit a job with no dependencies.
my $got = `./submit_job.pl --url $server_url --app seq --params cli="1 10"`;
my $job = $json->decode($got);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'Ready', "job with no deps is ready";

# submit a job that depends on key 99
#$got = `./submit_job.pl --url $server_url --app cat --keys 99`;

sleep 5;

done_testing();

END {
    diag "cleaning up";
    for my $pid (keys %processes) {
        if ($processes{$pid} =~ /hypnotoad/) {
            `hypnotoad -s ./jobserver.pl`;
            next;
        }
        if (kill 0, $pid) {
            sleep 1;
            kill 'USR2', $pid;
            my $kid =  waitpid($pid,0);
            warn "$pid did not die "unless $kid==$pid;
        }
    }
}
