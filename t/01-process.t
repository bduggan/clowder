#!/usr/bin/env perl

# TODO : a job that depends on one of several keys
# TODO : a job with several rules, each of which sets dependencies

use strict;
use warnings;
use feature qw/:all/;

use JSON::XS;
use Data::Dumper;
use Path::Class qw/file/;
use Test::More;
use FindBin;
use Mojolicious ();
use Mojo::UserAgent;
use lib $FindBin::Bin;
use testlib;
use v5.14;

BEGIN {
    chdir file($0)->dir;
}

unless ($Mojolicious::VERSION == 4.16) {
    say "# warning : This is only known to work with mojolicious 4.16";
    say "# and is known to fail with later versions";
}
my $jobserver = testlib->start_cluster;

my $ua = Mojo::UserAgent->new();
my $got;

$got = $ua->post("$jobserver/clean")->res->json;
like $got->{status}, qr/removed/, 'cleaned up';

# Simple job with no dependencies.
$got = $ua->post("$jobserver/job" => json => { app => './app.pl' })->res->json;
ok $got->{id}, "Job with no deps";
is $got->{state}, 'ready', "job $got->{id} with no deps is ready";
sleep 1;
$got = $ua->get("$jobserver/job/$got->{id}")->res->json;
is $got->{state}, 'complete', "Completed trivial job";

# Add two numbers.
$got = $ua->post("$jobserver/job" => json => { app => './app.pl', params => { eval_perl => '3+7' } })->res->json;
ok $got->{id}, "Job with no deps";
is $got->{state}, 'ready', "job $got->{id} with no deps is ready";
sleep 1;
$got = $ua->get("$jobserver/job/$got->{id}")->res->json;
is $got->{state}, 'complete', "Completed addition job";
is $got->{results}{eval_results}, 10, "Added 3 + 7, got 10";

# Put one number in one input file, another number in another input file.
# Run an app that adds two numbers and stores the results in a third file.


# TODO tell app to die and look for an error
my $count = 2;
# submit $count jobs that depends on key 99
my @jobs;
for (1..$count) {
    $got = $ua->post("$jobserver/job" => json => {
            app => './app.pl',
            deps => [ 99 ],
            params => {
                sleep => 8,
                num => $_
            } })->res->json;
    sleep 0.2;
    ok $got->{id}, "new job id : $got->{id}";
    is $got->{state}, 'waiting', "new job is waiting";
    $got = $ua->get("$jobserver/job/$got->{id}")->res->json;
    is $got->{state}, 'waiting', "state is waiting";
    push @jobs, $got;
}

my $counts = $ua->get("$jobserver/jobs/waiting")->res->json;
is $counts->{count}, $count, $count." jobs waiting";

my $md5 = 'abcd' x 8;
$got = $ua->post("$jobserver/file" => json => { key => 99, md5 => $md5 } );

sleep 1;
for (1..2) {
    my $got = $jobs[$_-1];
    $got = $ua->get("$jobserver/job/$got->{id}")->res->json;
    is $got->{state}, 'taken', "state of $got->{id} is taken";
}

$counts = $ua->get("$jobserver/jobs/waiting")->res->json;
is $counts->{count}, 0, "No jobs waiting";

sleep 2;

done_testing();

END {
    diag "cleaning up";
    testlib->cleanup;
    exit 0;
}
