#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;
use JSON::XS;
use Data::Dumper;
use Path::Class qw/file/;
use Test::More;

chdir file($0)->dir;
-d 'log' or mkdir 'log' or die $!;

my $jobserver = 'http://localhost:8080';

#
# Start jobserver.pl, which waits for new jobs to do.
# Start minion.pl which runs the jobs for you.
# submit_job.pl will submit a job request
# ingest_file.pl adds files (using REST)
# subscriber.pl watches changes in state
# so that as dependencies arrive, the minions don't have to wait.
#
# Use check_job.pl in order to see
# if your job is running or waiting for a key.
# "Key"s represent files, or a granule of data.
# We represent them with hashes; the content doesn't matter.
#

system('pkill -f morbo') if $ENV{KILL_RUNAWAY_MORBO};

my %processes;
sub _spawn($) {
    my ($cmd) = @_;
    my $pid;
    unless ($pid = fork) {
        open STDOUT, "| egrep -v available";
        exec $cmd;
        die "notreached";
    }
    $processes{$pid} = $cmd;
    ok $pid, "started $cmd";
    sleep 1;
}

sub _sys {
    my $cmd = shift;
    my $json = JSON::XS->new();
    $ENV{JOBSERVER} = $jobserver;
    my $got = `$cmd`;
    my $decoded = eval { $json->decode($got) };
    die "Invalid JSON running $cmd\n: $got" if $@;
    return $decoded;
}

my $pid;

_spawn "morbo ./jobserver.pl --listen $jobserver";
_spawn "./minion.pl $jobserver";
_spawn "./subscriber.pl $jobserver";

my $status = _sys qq[mojo get --method=POST $jobserver/clean];
like $status->{status}, qr/removed/, 'cleaned up';

# Submit a job with no dependencies.
my $job = _sys(qq[./submit_job.pl --app seq --params cli="1 10"]);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'ready', "job $job->{id} with no deps is ready";

my $check = _sys(qq[./check_job.pl --id $job->{id}]);
is $check->{id}, $job->{id}, "got id from check_job";
is $check->{state}, 'taken', "state is taken";

my $count = 10;
# submit 10 jobs that depends on key 99
my @jobs;
for (1..$count) {
    $job = _sys(qq[./submit_job.pl --app cat --keys 99]);
    ok $job->{id}, "new job id : $job->{id}";
    is $job->{state}, 'waiting', "new job is waiting";
    $check = _sys(qq[./check_job.pl --id $job->{id}]);
    is $check->{id}, $job->{id}, "got id from check_job";
    is $check->{state}, 'waiting', "state is waiting";
    push @jobs, $job;
}

my $counts = _sys(qq[mojo get $jobserver/jobs/waiting]);
is $counts->{count}, $count, $count." jobs waiting";

my $md5 = 'abcd' x 8;
my $ingest = _sys(qq[./ingest_file.pl --key 99 --md5 $md5]);

for (1..2) {
    my $job = $jobs[$_-1];
    $check = _sys(qq[./check_job.pl --id $job->{id}]);
    is $check->{state}, 'taken', "state of $job->{id} is taken";
}

$counts = _sys(qq[mojo get $jobserver/jobs/waiting]);
is $counts->{count}, 0, "No jobs waiting";

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
    exit 0;
}
