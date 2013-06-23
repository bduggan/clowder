#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;

sub info($) {
    say "@_";
}

my %processes;
my $pid;
my $server_url = 'http://localhost:8080';

# Start server.
unless ($pid = fork) {
    exec "morbo ./jobserver.pl --listen $server_url";
    die "notreached";
}
$processes{$pid} = 'morbo';
info "started morbo ($pid)";

# Start minion.
sleep 1;
unless ($pid = fork) {
    exec "./minion.pl $server_url";
    die "notreached";
}
$processes{$pid} = 'minion';
info "started minion ($pid)";

# Submit a job with no dependencies.
my $got = `./submit_job.pl --url $server_url --app seq --params cli="1 10"`;
say "job with no dependencies : $got";

# submit a job that depends on key 99
my $got = `./submit_job.pl --url $server_url --app cat --keys 99`;

sleep 30;

END {
    info "cleaning up";
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
