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

my $json = JSON::XS->new();

my $spec = ( (join '', <>) || "{}" );
my $input = eval { $json->decode($spec); } || Load ($spec);

print STDERR "running job.  id is $input->{id}\n";

my $output = {
    input     => $input,
    timestamp => scalar( gettimeofday() ),
    pid       => $$,
    host      => hostname(),
};

my $p = $input->{params};

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

if (my $eval_perl = $p->{eval_perl}) {
    $output->{eval_results} = eval $eval_perl;
    $output->{eval_errors} = "$@";
}

say STDOUT $json->encode($output);
say STDERR "Finished";

1;

