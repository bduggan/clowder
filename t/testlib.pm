package testlib;
use Test::RedisServer;
use strict;
use warnings;

my %processes;

sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::sys"} = \&_sys;
}

sub _spawn($) {
    my ($cmd) = @_;
    my $pid;
    unless ($pid = fork) {
        open STDOUT, "| egrep -v available";
        exec $cmd;
        die "notreached";
    }
    $processes{$pid} = $cmd;
    sleep 1;
}

my $red;
sub start_cluster {
    my $json = JSON::XS->new();
    $red = Test::RedisServer->new(conf => { port => 9999, bind => '127.0.0.1' });
    # until Mojo::Redis supports unix sockets
    $ENV{TEST_REDIS_CONNECT_INFO} = $red->connect_info;
    my $redis_pid = $red->pid;
    my $jobserver = 'http://localhost:8080';
    $ENV{JOBSERVER} = $jobserver;

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
    chdir '../script' or die "chdir : $!";
    -d 'log' or mkdir 'log' or die $!;
    _spawn "morbo ./jobserver.pl --listen $jobserver";
    _spawn "./minion.pl $jobserver";
    _spawn "./subscriber.pl $jobserver";
    return $jobserver;
}

sub _sys {
    my $cmd = shift or die "no command";
    my $json = JSON::XS->new();
    my $got = `$cmd`;
    my $decoded = eval { $json->decode($got) };
    die "Invalid JSON running $cmd\n: $got" if $@;
    return $decoded;
}

sub cleanup {
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

1;

