#!/usr/bin/env perl

# check_job.pl
# Check the status of a job in a jobserver.

use Getopt::Long;
use Mojo::UserAgent;
use Mojo::URL;
use strict;
use warnings;
use feature qw/:all/;

my $app;
my $url = $ENV{JOBSERVER};
my $id;
my $cli = "$0 @ARGV";

GetOptions(
    "app=s" => \$app,
    "url=s" => \$url,
    "id=s" => \$id,
) or die "invalid options ($cli)";

die "missing url" unless $url;
die "missing id" unless $id;

my $ua = Mojo::UserAgent->new;
$url = Mojo::URL->new($url);
my $get_url = $url->clone->path("/job/$id");
my $tx = $ua->get($get_url);
if (my $res = $tx->success) {
    say $res->body;
} else {
    say $tx->error;
}

