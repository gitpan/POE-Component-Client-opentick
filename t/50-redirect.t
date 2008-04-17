#!/usr/bin/perl
#
#   Unit tests of connection redirection, and basic packet coherency tests
#   Has built-in socket server.  2, in fact.
#
#   Covers:
#       OT_LOGIN
#       server redirection
#       OT_LOGOUT
#
#   infi/2008
#
#   Do not taunt the Happy Fun Ball.
#

use strict;
use warnings;

use Test::More tests => 37;
use Data::Dumper;
use Socket;
use POE qw( Component::Server::TCP Filter::Stream );

### "Constants"

my( $server_main, $server_redir, $sess, $ot );
my $args = {
    username    => 'testuser',
    password    => 'testpass',
    host        => 'localhost',
    port        => 10015,
    redirhost   => 'localhost',
    redirport   => 31415,
    myalias     => 'testclient95',
    b64         => 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
};

### Tests, in no particular order, and quite scattered about.

BEGIN {
    use_ok( 'POE::Component::Client::opentick' );
    use_ok( 'POE::Component::Client::opentick::Util' );
}

# Create our session
$sess = POE::Session->create(
        inline_states => {
            _start => sub { $poe_kernel->alias_set( $args->{myalias} ); },
            ot_on_login => sub {
                ok( 1, 'ot_on_login event received from OT' );
                $ot->yield( 'shutdown' );
            },
            ot_on_logout => sub {
                ok( 1, 'ot_on_logout event received from OT' );

                # Start cleaning up
                undef( $ot );
                $poe_kernel->call( 'pocoottest'  => 'shutdown' );
                $poe_kernel->call( 'pocoottest2' => 'shutdown' );
                undef( $server_main );
                undef( $server_redir );
                $poe_kernel->alias_remove( $args->{myalias} );
                undef( $sess );

                # We should have exited by now.
            },
        },
);
# Create main server
$server_main = POE::Component::Server::TCP->new(
        Hostname        => $args->{'host'},
        Port            => $args->{'port'},
        Domain          => AF_INET,
        Alias           => 'pocoottest',
        ClientFilter    => POE::Filter::Stream->new(),
        Started         => \&POE_startup,
        ClientInput     => \&client_input_main,
        ClientDisconnected  => \&client_disconnected_main,
);
# Create redirection handling server
$server_redir = POE::Component::Server::TCP->new(
        Hostname        => $args->{'redirhost'},
        Port            => $args->{'redirport'},
        Domain          => AF_INET,
        Alias           => 'pocoottest2',
        ClientFilter    => POE::Filter::Stream->new(),
        Started         => \&POE_startup,
        ClientConnected => \&client_reconnected_redir,
        ClientInput     => \&client_input_redir,
);

# Create the OT object
ok(
    $ot = POE::Component::Client::opentick->spawn(
        Username        => $args->{username},
        Password        => $args->{password},
        Notifyee        => $args->{myalias},
        Events          => [ 'all' ],
        AutoLogin       => 1,
        Debug           => 0,
        Quiet           => 1,
        Servers         => [ $args->{host} ],
        Port            => $args->{port},
    ),
    'OT object creation',
);

### Handler subs, with tests thrown in where possible/appropriate

sub client_input_main
{
    my( $heap, $input ) = @_[HEAP,ARG0];

#    print dump_hex( $input );

    my @args = unpack( 'V CCxxVV vCCA16a6A64A64', $input );

    # OT_LOGIN packet correctness
    is( $args[0], 0xa6,                 'MessageLength' );
    is( $args[1],    1,                 'MessageType == OT_LOGIN' );
    is( $args[2],    1,                 'CommandStatus' );
    is( $args[3],    1,                 'CommandType' );
    is( $args[4],    1,                 'RequestID' );
    is( $args[5],    4,                 'ProtocolVersion' );
    is( $args[6],   20,                 'OSID' );
    is( $args[7],    1,                 'PlatformID' );
    is( $args[8],   '',                 'PlatformIDPwd' );
    is( length($args[9]),   6,          'MacAddress length' );
    is( $args[10],   $args->{username}, 'Username' );
    is( $args[11],   $args->{password}, 'Password' );

    # Build packet
    my $packet = pack( 'CCxxVV a64Ca64v',
                       # header
                       2, 1, 1, 1,
                       # body
                       $args->{b64},
                       1,
                       $args->{redirhost},
                       $args->{redirport}
    );
    my $len = pack( 'V', length($packet) );
    $packet = $len . $packet;

#    print dump_hex( $packet );

    # Send packet
    $heap->{client}->put( $packet );

    return;
}

sub client_disconnected_main
{
    ok( 1, 'Client disconnected from main server' );
}

sub client_input_redir
{
    my( $input, $heap ) = @_[ARG0,HEAP];

    my @args = unpack( 'V CCxxVV a*', $input );

    if( $args[3] == 1 )
    {
        # Check OT_LOGIN packet correctness ( AGAIN )
        my @args = unpack( 'V CCxxVV vCCA16a6A64A64', $input );

        # OT_LOGIN packet correctness
        is( $args[0], 0xa6,                 'MessageLength' );
        is( $args[1],    1,                 'MessageType == OT_LOGIN' );
        is( $args[2],    1,                 'CommandStatus' );
        is( $args[3],    1,                 'CommandType' );
        is( $args[4],    2,                 'RequestID' );
        is( $args[5],    4,                 'ProtocolVersion' );
        is( $args[6],   20,                 'OSID' );
        is( $args[7],    1,                 'PlatformID' );
        is( $args[8],   '',                 'PlatformIDPwd' );
        is( length($args[9]),   6,          'MacAddress length' );
        is( $args[10],   $args->{username}, 'Username' );
        is( $args[11],   $args->{password}, 'Password' );

        # Build packet, don't redirect this time.
        my $packet = pack( 'CCxxVV a64Ca64v',
                           # header
                           2, 1, 1, 1,
                           # body
                           $args->{b64},
                           0,
                           '',
                           0,
        );
        my $len = pack( 'V', length($packet) );
        $packet = $len . $packet;
#        diag( dump_hex( $packet ) );

        # Send packet
        $heap->{client}->put( $packet );
    }
    elsif( $args[3] == 2 )
    {
#        diag( dump_hex( $input ) );
        my @args = unpack( 'V CCxxVV a64', $input );

        # Check OT_LOGOUT packet correctness
        is( $args[0], length( $input ) - 4, 'MessageLength' );
        is( $args[1], 1, 'MessageType' );
        is( $args[2], 1, 'CommandStatus' );
        is( $args[3], 2, 'MessageType == OT_LOGOUT' );
        ok( $args[4] >= 3, 'RequestID' );
        is( $args[5], $args->{b64}, 'SessionID' );

        # Generate response packet
        my $packet = pack( 'CCxxVV', 2, 1, 2, 2 );
        my $len    = pack( 'V', length( $packet ) );
        $packet    = $len . $packet;

        # And send.
        $heap->{client}->put( $packet );
    }
    elsif( $args[3] == 9 )
    {
        # ignore heartbeat
    }
    else
    {
        # Oops, got some other junk.  Abort.
        fail( 'Got junk!' );
        diag( "input:\n" . dump_hex( $input ) );
        die "ERROR!";
    }

    return;
}

sub client_reconnected_redir
{
    # extend connect timeout
    $poe_kernel->delay( 'shutdown' => 2 );
    ok( 1, 'Client reconnected correctly' );
}

sub POE_startup
{
    # set connect timeout
    $poe_kernel->delay( 'shutdown' => 2 );
}

#diag( "Running POE kernel" );
$poe_kernel->run();
#diag( "POE kernel ended." );

__END__

