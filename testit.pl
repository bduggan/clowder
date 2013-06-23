#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/:all/;

sub info($) {
    say "@_";
}

# start jobserver and minion
my %processes;
my $pid;
unless ($pid = fork) {
    exec "morbo ./jobserver.pl --listen http://localhost:8080";
    die "notreached";
}
$processes{$pid} = 'morbo';
info "started morbo ($pid)";

sleep 4;
unless ($pid = fork) {
    exec "./minion.pl http://localhost:8080";
    die "notreached";
}
$processes{$pid} = 'minion';

info "started minion ($pid)";

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
