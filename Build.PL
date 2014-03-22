use 5.006;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Clowder',
    license             => 'agpl_3',
    dist_author         => q{Brian Duggan <bduggan@matatu.org>},
    dist_version_from   => 'lib/Clowder.pm',
    dist_abstract       => 'RESTful data processing system',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
          'Test::More'               => 0,
          'YAML::XS'                 => 0,
          'Time::HiRes'              => 0,
          'Sys::Hostname'            => 0,
          'Path::Class'              => 0,
          'Mojolicious'              => 0,
          'Mojo::Redis'              => '0.9921',
          'Test::RedisServer'        => 0,
          'JSON::XS'                 => 0,
          'Getopt::Long'             => 0,
          'FindBin'                  => 0,
          'AnyEvent::Open3::Simple'  => 0,
          'AnyEvent'                 => 0,
          'EV'                       => 0,
    },
    requires => {
    },
    add_to_cleanup     => [ 'Clowder-*' ],
    #create_makefile_pl => 'traditional',
);

$builder->create_build_script();
