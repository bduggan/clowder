#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;
use JSON::XS;
use Data::Dumper;
use Test::More;

my $jobserver = 'http://localhost:8080';

my $json = JSON::XS->new();

my %processes;
my $pid;

system('pkill -f morbo') if $ENV{KILL_RUNAWAY_MORBO};

# Start server.
unless ($pid = fork) {
    open STDOUT, "| egrep -v available";
    exec "morbo ./jobserver.pl --listen $jobserver";
    die "notreached";
}
$processes{$pid} = 'morbo';
ok $pid, "started morbo";

# Start minion.
sleep 1;
unless ($pid = fork) {
    exec "./minion.pl $jobserver";
    die "notreached";
}
$processes{$pid} = 'minion';
ok $pid, "started minion";

# Submit a job with no dependencies.
my $got = `./submit_job.pl --url $jobserver --app seq --params cli="1 10"`;
my $job = $json->decode($got);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'ready', "job with no deps is ready";

$got = `./check_job.pl --url $jobserver --id $job->{id}`;
my $check = eval { $json->decode($got);};
die "check_job said : $got" if $@;
is $check->{id}, $job->{id}, "got id from check_job";
is $check->{state}, 'ready', "state is ready";

# submit a job that depends on key 99
$got = `./submit_job.pl --url $jobserver --app cat --keys 99`;
$job = $json->decode($got);
ok $job->{id}, "new job id : $job->{id}";
is $job->{state}, 'waiting', "new job is waiting";

$got = `./check_job.pl --url $jobserver --id $job->{id}`;
$check = eval { $json->decode($got);};
die "check_job said : $got" if $@;
is $check->{id}, $job->{id}, "got id from check_job";
is $check->{state}, 'waiting', "state is waiting";

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
