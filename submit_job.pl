#!/usr/bin/env perl

# submit_job.pl
# Submit a job to the jobserver for processing.

use Getopt::Long;
use Mojo::UserAgent;
use strict;
use warnings;
use feature qw/:all/;

my $app;
my %job_params;
my @keys;
my $url = $ENV{JOBSERVER};

GetOptions(
    "app=s" => \$app,
    "params=s" => \%job_params,
    "keys=s" => \@keys,
    "url=s" => \$url,
) or die "invalid options";

die "missing url" unless $url;
die "missing app" unless $app;

my $ua = Mojo::UserAgent->new;
$url = Mojo::URL->new($url);
my $put_url = $url->clone->path('/job');
my $tx = $ua->put($put_url => {} => json => { app => $app, params => \%job_params, deps => \@keys } );
my $res = $tx->success;
if ($res && $res->code==202) {
    say $tx->res->body;
} else {
    say "error";
    say $tx->res->to_string;
}

