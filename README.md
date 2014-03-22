clowder [![Build Status](https://secure.travis-ci.org/bduggan/clowder.png)](http://travis-ci.org/bduggan/clowder)

This is a prototype for a distributed event-driven job
server which uses HTTP as a transport and redis as a backend.

Quick start :

Test :

    prove t/01-process.t

Run :

    JOBSERVER=http://localhost:3000
    cd script
    redis-server &
    ./jobserver.pl daemon --listen $JOBSERVER &
    ./subscriber.pl &
    ./minion.pl $JOBSERVER &
    ./submit_job.pl --app './app.pl'
    ./check_job.pl --id 1

System Architecture :

    Start jobserver.pl, which waits for new jobs to do.
    Start minion.pl which runs the jobs for you.

    submit_job.pl will submit a job request
    ingest_file.pl adds files (using REST)

    subscriber.pl watches changes in state
    so that as dependencies arrive, the minions don't have to wait.

    Use check_job.pl in order to see
    if your job is running or waiting for a key.

   "Key"s represent files, or a granule of data.
    We represent them with hashes; the content doesn't matter.

Contents :

* jobserver.pl   : job server
* minion.pl      : sample job processor (minion)
* submit_job.pl  : client for submitting job requests
* ingest_file.pl : client for announcing file ingests
* subscriber.pl  : backend process for event-driven state changes


