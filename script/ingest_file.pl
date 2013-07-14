#!/usr/bin/env perl

# ingest_file.pl
# Notify the jobserver that we have ingested a file with a given key and md5.

use Getopt::Long;
use Mojo::UserAgent;
use strict;
use warnings;
use feature qw/:all/;

my $key;
my $md5;
my $url = $ENV{JOBSERVER};

GetOptions(
    "key=s" => \$key,
    "md5=s" => \$md5,
    "url=s" => \$url,
) or die "invalid options";

die "missing url" unless $url;
die "missing key" unless $key;
die "missing md5" unless $md5;

my $ua = Mojo::UserAgent->new;
$url = Mojo::URL->new($url);

my $post_url = $url->clone->path('/file');
my $tx = $ua->post($post_url => json => { key => $key, md5 => $md5 } );
if (my $res = $tx->success) {
    say $res->body;
} else {
    say $tx->error;
}

