
# TODO, this is a placeholder, work in progress...

    for my $key (keys %deps) {
        nb "subscribing to files : (key=$key)";
        push @subscriptions, $c->red(new => 1)->subscribe('files', sub {
                my ($sub, $data) = @_;
                my ($action,$channel,$message) = @$data;
                nb "# subscribe to data called ($action, $channel, $message)";
                return unless $action eq 'message'; # ignore other subscribes.
                my $file = $json->decode($message) or nb "could not decode $message";
                unless (defined($file->{key})) {
                    nb "# error: no key for file\n";
                    nb "subscription got : ".Dumper($file);
                    return;
                }
                unless ($file->{key} eq $key) {
                    nb "# we are waiting for $key, so we ignore $file->{key}";
                    return;
                }
                nb "# Matched incoming key with desired key $key, this job is not waiting.";
                $c->red->srem('waiting_jobs', $id );
                delete $job->{deps}->{$key}; 
                if (keys %{$job->{deps}} == 0) {
                    $c->red->lpush('ready_jobs', $id );
                } else {
                    $c->red->sadd('waiting_jobs', $id );
                }
            } );
    }
