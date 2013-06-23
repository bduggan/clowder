#!/usr/bin/env perl

use Test::More qw/no_plan/;
use Test::Mojo;
use POSIX ":sys_wait_h";

require 'jobserver.pl';

use strict;
use warnings;
use Data::Dumper;

my $t = Test::Mojo->new;

$t->post_ok('/clean')->status_is(200);

# queue job 1 which depends on file with key=one
$t->put_ok("/job" => {} => json => { app => 'cat', params => {}, deps => { one => 1 } } );

# check that one job is queued
{
my $list = $t->get_ok('/jobs/waiting')->tx->res->json;
is 3, $list->{count} + 0, '3 jobs in queue';
}

# check that at least one minion is waiting.  If not, run in background
# TODO check that a minion is waiting
my $url = $t->ua->app_url;
my $pid;
unless ($pid = fork) {
    exec "./minion.pl $url";
    die "not reached";
}
diag "started minion $pid";

# post notification that file 1 has arrived, with key=one and md5='abba'
$t->post_ok( '/file' => {} => json => { key => 'one', md5 => 'abba' } );

$t->ua->ioloop->timer(2 => sub { shift->stop; } );
$t->ua->ioloop->start;

# check that there are now two jobs that are waiting
{
my $list = $t->get_ok('/jobs/waiting')->tx->res->json;
is $list->{count} + 0, 2, '2 jobs in queue';
}

# check that job 1 is not waiting

# put file 2, 3, 4
# check that no jobs are waiting

END {
    if (kill 0, $pid) {
        sleep 1;
        kill 'USR2', $pid;
        my $kid =  waitpid($pid,0);
        warn "$pid did not die "unless $kid==$pid;
    }
}

