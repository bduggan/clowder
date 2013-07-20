package Mojolicious::Plugin::Red;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Redis;

sub register {
    my ($self,$app,$conf) = @_;
    $app->helper( red =>
          $self->make_helper( app_name => $app->moniker, log => $app->log )
    );
}

sub make_helper {
    my $self = shift;
    my %args = @_;

    my $app_name = $args{app_name};
    my $log = $args{log};

    my $error_cb = sub {
            my ($red,$err) = @_;
            warn "redis error ($app_name) : $err\n";
            $log->error("redis error : $err");
        };

    my $new_connection = sub {
        my $conn = $ENV{TEST_REDIS_CONNECT_INFO};
        my $redis = Mojo::Redis->new( $conn ? ( server => $ENV{TEST_REDIS_CONNECT_INFO} ) : () );
        $redis->on(error => $error_cb );
        return $redis;
    };

    my %connections;
    return sub {
        my $c = shift;
        my %a = @_;
        return $new_connection->() if $a{new};
        my $which = $a{which} || 'default';
        $connections{$which} ||= $new_connection->();
        return $connections{$which};
    };
}

1;

