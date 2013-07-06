#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;
use JSON::XS;
use Data::Dumper;
use Test::More;

my $jobserver = 'http://localhost:8080';

#
#  Start jobserver.pl, which waits for new jobs to do.
#  Start minion.pl which runs the jobs for you.
#  submit_job.pl will submit a job request
#  ingest_file.pl adds files (using REST)
#  subscriber.pl watches changes in state
#  so that as dependencies arrive, the minions don't have to wait.
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
my $job = _sys(qq[./submit_job.pl --url $jobserver --app seq --params cli="1 10"]);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'ready', "job with no deps is ready";

my $check = _sys(qq[./check_job.pl --url $jobserver --id $job->{id}]);
is $check->{id}, $job->{id}, "got id from check_job";
is $check->{state}, 'taken', "state is taken";

# submit a job that depends on key 99
$job = _sys(qq[./submit_job.pl --url $jobserver --app cat --keys 99]);
ok $job->{id}, "new job id : $job->{id}";
is $job->{state}, 'waiting', "new job is waiting";

$check = _sys(qq[./check_job.pl --url $jobserver --id $job->{id}]);
is $check->{id}, $job->{id}, "got id from check_job";
is $check->{state}, 'waiting', "state is waiting";

# TODO : ingest_file, then check that state is ready.
$check = `./check_job.pl --url $jobserver --id $job->{id}`;

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
    exit 0;
}
