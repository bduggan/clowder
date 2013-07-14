#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;

use JSON::XS;
use Data::Dumper;
use Path::Class qw/file/;
use Test::More;
use FindBin;
use lib $FindBin::Bin;
use testlib;

BEGIN {
    chdir file($0)->dir;
}

my $jobserver = testlib->start_cluster;

my $status = sys(qq[mojo get --method=POST $jobserver/clean]);
like $status->{status}, qr/removed/, 'cleaned up';

# Simple job with no dependencies.
my $job = sys(qq[./submit_job.pl --app ./app.pl --params deps=none]);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'ready', "job $job->{id} with no deps is ready";
sleep 1;
my $check = sys(qq[./check_job.pl --id $job->{id}]);
is $check->{state}, 'complete', "Completed trivial job";

# Add two numbers.
$job = sys(qq[./submit_job.pl --app ./app.pl --params eval_perl='3+7']);
ok $job->{id}, "Job with no deps";
is $job->{state}, 'ready', "job $job->{id} with no deps is ready";
sleep 1;
$check = sys(qq[./check_job.pl --id $job->{id}]);
is $check->{state}, 'complete', "Completed addition job";
is $check->{results}{eval_results}, 10, "Added 3 + 7, got 10";

my $count = 2;
# submit $count jobs that depends on key 99
my @jobs;
for (1..$count) {
    $job = sys(qq[./submit_job.pl --app ./app.pl --params sleep=8 --keys 99 --params deps=99 num=$_]);
    ok $job->{id}, "new job id : $job->{id}";
    is $job->{state}, 'waiting', "new job is waiting";
    $check = sys(qq[./check_job.pl --id $job->{id}]);
    is $check->{id}, $job->{id}, "got id from check_job" or diag explain $check;
    is $check->{state}, 'waiting', "state is waiting";
    push @jobs, $job;
}

my $counts = sys(qq[mojo get $jobserver/jobs/waiting]);
is $counts->{count}, $count, $count." jobs waiting";

my $md5 = 'abcd' x 8;
my $ingest = sys(qq[./ingest_file.pl --key 99 --md5 $md5]);

for (1..2) {
    my $job = $jobs[$_-1];
    $check = sys(qq[./check_job.pl --id $job->{id}]);
    is $check->{state}, 'taken', "state of $job->{id} is taken";
}

$counts = sys(qq[mojo get $jobserver/jobs/waiting]);
is $counts->{count}, 0, "No jobs waiting";

sleep 2;

done_testing();

END {
    diag "cleaning up";
    testlib->cleanup;
    exit 0;
}
