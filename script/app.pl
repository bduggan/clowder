#!/usr/bin/env perl

# sample app to be run by clowder tests

use strict;
use warnings;
use feature qw/:all/;
use JSON::XS;
use YAML::XS qw/Load/;
use Time::HiRes qw/gettimeofday/;
use Sys::Hostname qw/hostname/;
use Data::Dumper;
use Path::Class qw/file/;
use Mojo::UserAgent;

my $json = JSON::XS->new();
my $ua = Mojo::UserAgent->new();

our $spec = ( (join '', <>) || "{}" );
our $input = eval { $json->decode($spec); } || Load ($spec);

print STDERR "running job.  id is $input->{id}\n";

my $output = {
    input     => $input,
    timestamp => scalar( gettimeofday() ),
    pid       => $$,
    host      => hostname(),
};

our $p = $input->{params} || {};

if (my $secs = $p->{sleep}) {
    sleep $secs;
}
if (my $err = $p->{die_with_error}) {
    die $err;
}

if (my $write_files = $p->{write_files}) {
    for (@$write_files) {
        file($_->{name})->spew($_->{content});
    }
}

sub sandbox::lookup {
    my $class = shift;
    my $key = shift;
    our $spec;
    state %cache;
    if (defined(my $have = $cache{$key})) {
        warn "found $key in cache";
        return $have;
    };
    my $jobserver = $ENV{JOBSERVER} or do { warn "cannot lookup without jobserver url"; return };
    warn "going to $jobserver for file";
    $ua->max_redirects(2);
    my $tx = $ua->get("$jobserver/file/$key");
    my $res = $tx->success or warn "could not get key $key : ".$tx->error.$tx->res->body;
    return unless $res;
    my $content = $res->body or warn "no content";
    $cache{$key} = $content;
    return $content;
}

if (my $eval_perl = $p->{eval_perl}) {
    $output->{eval_results} = eval qq[ $eval_perl ];
    $output->{eval_errors} = "$@";
}

say STDOUT $json->encode($output);
say STDERR "Finished";

1;

