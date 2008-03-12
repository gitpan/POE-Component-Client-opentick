package POE::Component::Client::opentick::OTClient;
#
#   opentick.com POE client, otFeed API facade class.
#
#   infi/2008
#
#   Full POD documentation after __END__
#

use strict;
use Socket;
use Carp qw( croak );
use Data::Dumper;
use Time::HiRes qw( time );
use POE;

# Ours.
use POE::Component::Client::opentick::Constants;
use POE::Component::Client::opentick;

###
### Variables
###

use vars qw( $VERSION $TRUE $FALSE $poe_kernel );

($VERSION) = q$Revision: 43 $ =~ /(\d+)/;
*TRUE      = \1;
*FALSE     = \0;

my $dispatch_cmd = {
    OTConstant( 'OT_REQUEST_LIST_EXCHANGES' )   => 'onListExchanges',
    OTConstant( 'OT_REQUEST_LIST_SYMBOLS' )     => 'onListSymbols',
    OTConstant( 'OT_REQUEST_LIST_SYMBOLS_EX' )  => 'onListSymbols',
    OTConstant( 'OT_REQUEST_SPLITS' )           => 'onSplit',
    OTConstant( 'OT_REQUEST_DIVIDENDS' )        => 'onDividend',
    OTConstant( 'OT_REQUEST_OPTION_INIT' )      => 'onOptionInit',
    OTConstant( 'OT_REQUEST_EQUITY_INIT' )      => 'onEquityInit',
    OTConstant( 'OT_REQUEST_TICK_STREAM' )      => 'onRealtime',
    OTConstant( 'OT_REQUEST_TICK_STREAM_EX' )   => 'onRealtime',
    OTConstant( 'OT_REQUEST_TICK_SNAPSHOT' )    => 'onRealtime',
    OTConstant( 'OT_REQUEST_HIST_DATA' )        => 'onHist',
    OTConstant( 'OT_REQUEST_HIST_TICKS' )       => 'onHist',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN' )     => 'onRealtime',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN_EX' )  => 'onRealtime',
    OTConstant( 'OT_REQUEST_BOOK_STREAM' )      => 'onBook',
    OTConstant( 'OT_REQUEST_BOOK_STREAM_EX' )   => 'onBook',
    OTConstant( 'OT_REQUEST_HIST_BOOKS' )       => 'onHistBook',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN' )     => 'onRealtime',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN_EX' )  => 'onRealtime',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN_U' )   => 'onRealtime',
    OTConstant( 'OT_REQUEST_OPTION_CHAIN_SNAPSHOT' ) => 'onRealtime',
};

my $dispatch_dt = {
    OTConstant( 'OT_DATATYPE_QUOTE' )           => 'Quote',
    OTConstant( 'OT_DATATYPE_MMQUOTE' )         => 'MMQuote',
    OTConstant( 'OT_DATATYPE_TRADE' )           => 'Trade',
    OTConstant( 'OT_DATATYPE_BBO' )             => 'BBO',
    OTConstant( 'OT_DATATYPE_OHLC' )            => 'OHLC',
    OTConstant( 'OT_DATATYPE_CANCEL' )          => 'Cancel',
    OTConstant( 'OT_DATATYPE_CHANGE' )          => 'Change',
    OTConstant( 'OT_DATATYPE_DELETE' )          => 'Delete',
    OTConstant( 'OT_DATATYPE_EXECUTE' )         => 'Execute',
    OTConstant( 'OT_DATATYPE_ORDER' )           => 'Order',
    OTConstant( 'OT_DATATYPE_PRICELEVEL' )      => 'PriceLevel',
    OTConstant( 'OT_DATATYPE_PURGE' )           => 'Purge',
    OTConstant( 'OT_DATATYPE_REPLACE' )         => 'Replace',
    OTConstant( 'OT_DATATYPE_OHL_TODAY' )       => 'onTodaysOHL',
};

########################################################################
###   Public methods                                                 ###
########################################################################

# Create the object
sub new
{
    my( $class, $username, $password, @args ) = @_;
    croak( "$class requires an even number of parameters" ) if( @args & 1 );

    # Set our default variables
    my $self = {
        alias       => 'otFeed-' . time,    # our alias
        opentick    => undef,               # opentick object
        session_id  => undef,               # POE session pointer
        requests    => {},                  # outstanding requests
        hosts       => [],                  # host list
    };

    bless( $self, $class );

    $self->initialize( $username, $password, @args );

    return( $self );
}

# Initialize this object instance
sub initialize
{
    my( $self, $username, $password, %args ) = @_;

    $args{username} = $username or $ENV{OPENTICK_USER} or
        croak( "OTClient requires a \$username argument" );
    $args{password} = $password or $ENV{OPENTICK_PASS} or
        croak( "OTClient requires a \$password argument" );

    $self->{hosts} = $args{Hosts} if( $args{Hosts} );
    $self->{hosts} = $args{hosts} if( $args{hosts} );

    # Create our own POE session here
    $self->{session_id} = POE::Session->create(
        object_states   => [
            $self => {
                _start                  => '_poe_started',
                ot_on_login             => '_ot_on_login',
                ot_status_changed       => '_ot_status_changed',
                ot_on_data              => '_ot_on_data',
                ot_on_error             => '_ot_on_error',
                ot_request_complete     => '_ot_request_complete',
                ot_request_cancelled    => '_ot_request_cancelled',
# Not needed for this interface.
#                ot_connect_failed       => '_ot_connect_failed',
#                ot_on_logout            => '_ot_on_logout',
            },
        ],
        heap    => $self,
    )->ID();

    # Create main object POE session here, passing args along
    $self->{opentick} = POE::Component::Client::opentick->spawn(
            Notifyee        => $self->{alias},  # our alias
            Events          => [ 'all' ],       # events to catch
            ReconnRetries   => 0,               # unlimited
#            Debug           => 1,               # TALK LOTS
            Quiet           => 1,               # Hush.
            AutoLogin       => 0,               # manual login.
            %args,
    );

    $self->startup();

    return;
}

#######################################################################
###   otFeed API Methods                                            ###
#######################################################################

sub requestTickStream
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestTickStreamEx', @args ) );
}

sub requestBookStream
{
    my( $self, $exch, $sym, $mask ) = @_;

    my $req_id = $mask
         ? $self->_issue_request( 'requestBookStreamEx', $exch, $sym, $mask )
         : $self->_issue_request( 'requestBookStream', $exch, $sym );

    return( $req_id );
}

# Duplicates functionality from API interface
sub requestMarketDepth
{
    my( $self, $exch, $sym ) = @_;

    my $book_exchanges = { ar => 1, at => 1, br => 1, bt => 1,
                           is => 1, no => 1, cm => 1, em => 1,
                           ct => 1, ec => 1 };

    if( exists( $book_exchanges->{$exch} ) )
    {
        return( $self->_issue_request( 'requestBookStream', $exch, $sym ) );
    }
    else
    {
        return( $self->_issue_request( 'requestTickStreamEx', $exch, $sym,
                                       OTConstant( 'OT_TICK_TYPE_LEVEL2' ) ) );
    }
}

sub requestOptionChain
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestOptionChainEx', @args ) );
}

sub requestEquityInit
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestEqInit', @args ) );
}

sub requestHistData
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestHistData', @args ) );
}

sub requestHistTicks
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestHistTicks', @args ) );
}

sub requestTodaysOHL
{
    my( $self, $exchange, $symbol ) = @_;

    return( $self->_issue_request( 'requestHistData',
                                   $exchange,
                                   $symbol,
                                   0,
                                   0,
                                   OTConstant( 'OT_HIST_OHL_TODAY' ),
                                   0,
    ) );

    return;
}

# Don't store a request id
sub requestListExchanges
{
    my( $self, @args ) = @_;

    $self->{opentick}->yield( 'requestListExchanges', @args );

    return;
}

# Don't store a request id
sub requestListSymbols
{
    my( $self, @args ) = @_;

    $self->{opentick}->yield( 'requestListSymbolsEx', @args );

    return;
}

sub requestHistBooks
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestHistBooks', @args ) );
}

sub requestOptionInit
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestOptionInit', @args ) );
}

sub requestSplits
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestSplits', @args ) );
}

sub requestDividends
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestDividends', @args ) );
}

sub requestTickSnapshot
{
    my( $self, $exch, $sym, $mask ) = @_;

    $mask ||= OTConstant( 'OT_MASK_TYPE_QUOTE' ) |
              OTConstant( 'OT_MASK_TYPE_MMQUOTE' ) |
              OTConstant( 'OT_MASK_TYPE_TRADE' ) |
              OTConstant( 'OT_MASK_TYPE_BBO' );

    return( $self->_issue_request( 'requestTickSnapshot', $exch, $sym, $mask ));
}

sub requestOptionChainSnapshot
{
    my( $self, @args ) = @_;

    return( $self->_issue_request( 'requestOptionChainSnapshot', @args ) );
}

# Cancellation
sub cancelTickStream
{
    my( $self, $req_id ) = @_;

    return( $self->_cancel_request( 'cancelTickStream', $req_id ) );
}

sub cancelOptionChain
{
    my( $self, $req_id ) = @_;

    return( $self->_cancel_request( 'cancelOptionChain', $req_id ) );
}

sub cancelBookStream
{
    my( $self, $req_id ) = @_;

    return( $self->_cancel_request( 'cancelBookStream', $req_id ) );
    my( $self ) = @_;

    return;
}

sub cancelMarketDepth
{
    my( $self, $req_id ) = @_;

    # leave command undef, and let _cancel_request resolve it.
    return( $self->_cancel_request( undef, $req_id ) );
}

sub cancelHistData
{
    my( $self, $req_id ) = @_;

    return( $self->_cancel_request( 'cancelHistData', $req_id ) );
}

########################################################################
###   otFeed Auxiliary Functions                                     ###
########################################################################

# Halfassed workaround.
sub addHost
{
    my( $self, $host, $port ) = @_;

    push( @{ $self->{hosts} }, $host );
    $self->{opentick}->set_hosts( $self->{hosts} );
    $self->{opentick}->set_port( $port ) if( $port );

    return;
}

# Halfassed workaround.
sub clearHosts
{
    my( $self ) = @_;

    $self->{hosts} = [];
    $self->{opentick}->set_hosts( $self->{hosts} );

    return;
}

sub login
{
    my( $self ) = @_;

    $self->{opentick}->call( 'connect' );

    return;
}

sub logout
{
    my( $self ) = @_;

    $self->{opentick}->call( 'disconnect' );

    return;
}

sub isLoggedIn
{
    my( $self ) = @_;

    return( $self->{opentick}->ready() );
}

sub getStatus
{
    my( $self ) = @_;

    return( $self->{opentick}->get_status() );
}

sub setPlatformId
{
    my( $self, $id, $pass ) = @_;

    $self->{opentick}->set_platform_id( $id, $pass );

    return;
}

sub getEntityById
{
    my( $self, $req_id ) = @_;

    my $requqest = $self->{requests}->{$req_id};
    my $exchange = $req->{exchange};
    my $symbol   = $req->{symbol};

    return( $exchange, $symbol );
}

########################################################################
###   Event Handlers                                                 ###
########################################################################

### NOTE: These do nothing by default.  You are to subclass this module
#         and override these methods to do something useful in your
#         application.

# Local extension
sub startup {}

# From API
sub onLogin {}
sub onRestoreConnection {}
sub onStatusChanged {}
sub onError {}
sub onMessage {}
sub onListExchanges {}
sub onListSymbols {}
sub onRealtimeTrade {}
sub onRealtimeQuote {}
sub onRealtimeBBO {}
sub onRealtimeMMQuote {}
sub onTodaysOHL {}
sub onEquityInit {}
sub onBookCancel {}
sub onBookChange {}
sub onBookDelete {}
sub onBookExecute {}
sub onBookOrder {}
sub onBookPriceLevel {}
sub onBookPurge {}
sub onBookReplace {}
sub onHistQuote {}
sub onHistMMQuote {}
sub onHistTrade {}
sub onHistBBO {}
sub onHistOHLC {}
sub onHistBookCancel {}
sub onHistBookChange {}
sub onHistBookDelete {}
sub onHistBookExecute {}
sub onHistBookOrder {}
sub onHistBookPriceLevel {}
sub onHistBookPurge {}
sub onHistBookReplace {}
sub onSplit {}
sub onDividend {}
sub onOptionInit {}

########################################################################
###   Private methods                                                ###
########################################################################

sub _issue_request
{
    my( $self, $command, @args ) = @_;

    # Call opentick to issue the request and get a ReqID
    my $req_id = $self->{opentick}->call( $command, @args );

    # Stash the ReqID and issue time
    $self->{requests}->{$req_id} = {
            cmd_id      => OTAPItoCommand( $command ),
            stamp       => time,
            # FIXME: These won't always be valid; will fix later.
            exchange    => $args[0],
            symbol      => $args[1],
    };

    return( $req_id );
}

sub _cancel_request
{
    my( $self, $command, $req_id ) = @_;

    # Resolve command for requestMarketDepth
    $command =
        OTCommandtoAPI( OTCanceller( $self->{requests}->{$req_id}->{cmd_id} ) )
            unless( $command );

    # Just return boolean; handle req deletion in _ot_on_data
    return( $self->{opentick}->call( $command, $req_id ) ? $TRUE : $FALSE );
}

sub _delete_request
{
    my( $self, $req_id ) = @_;

    return( delete( $self->{requests}->{$req_id} ) );
}

########################################################################
###   POE event handlers                                             ###
########################################################################

# Happens very early, so we'll call started() from initialize() instead.
sub _poe_started
{
    my( $self ) = @_;

    $poe_kernel->alias_set( $self->{alias} );

    return;
}

sub _ot_on_login
{
    my( $self ) = @_;

    my( $wasloggedin ) = $self->{wasloggedin};
    $self->{wasloggedin} = $TRUE;

    # Why do there need to be two of these?  The semantics are confused.
    $wasloggedin && $self->onRestoreConnection() || $self->onLogin();

    return;
}

sub _ot_status_changed
{
    my( $self, $state ) = @_[OBJECT,ARG0];

    $self->onStatusChanged( $state );

    return;
}

# Dispatch to the appropriate request handler.
sub _ot_on_data
{
    my( $self, $req_id, $cmd_id, $object ) = @_[OBJECT,ARG0..ARG2];

    return unless( ref( $object ) );
    my $datatype = $object->get_datatype();

    # Ugly as sin.  Works like a charm.
    my $method;
    if( ( $datatype >= OTConstant('OT_DATATYPE_QUOTE') &&
          $datatype <= OTConstant('OT_DATATYPE_REPLACE') ) ||
          $datatype == OTConstant('OT_DATATYPE_OHLC') )
    {
        $method = $dispatch_cmd->{ $cmd_id } . $dispatch_dt->{ $datatype };
    }
    elsif( $datatype == OTConstant( 'OT_DATATYPE_OHL_TODAY' ) )
    {
        $method = $dispatch_dt->{ $datatype };
    }
    else
    {
        $method = $dispatch_cmd->{ $cmd_id };
    }

    $self->$method( $req_id, $cmd_id, $object );

    return;
}

sub _ot_on_error
{
    my( $self, @args ) = @_[OBJECT,ARG0..$#_];

    $self->onError( @args );

    return;
}

sub _ot_request_complete
{
    my( $self, $req_id, $cmd_id, $obj ) = @_[OBJECT,ARG0..$#_];

    $self->_delete_request( $req_id ) if( $req_id );

    $self->onMessage( $req_id,
                      $cmd_id,
                      OTConstant( 'OT_MSG_END_OF_DATA' ),
                      "Request $req_id completed." );

    return;
}

sub _ot_request_cancelled
{
    my( $self, $req_id, $cmd_id, $obj ) = @_[OBJECT,ARG0..$#_];

    $self->_delete_request( $req_id ) if( $req_id );

    $self->onMessage( $req_id,
                      $cmd_id,
                      OTConstant( 'OT_MSG_END_OF_REQUEST' ),
                      "Request $req_id cancelled." );

    return;
}

1;

__END__

=pod

=head1 NAME

POE::Component::Client::opentick::OTClient - An opentick.com otFeed-compatible interface for the POE opentick client.

=head1 SYNOPSIS

 #!/usr/bin/perl

 package OTTest;

 use strict;
 use POE qw( Component::Client::opentick::OTClient );
 use base qw( POE::Component::Client::opentick::OTClient );

 sub onLogin {
    my( $self, @args ) = @_;
    print "Logged in.\n";
    $self->requestEquityInit( 'Q' => 'MSFT' );
 }

 sub onEquityInit
 {
    my( $self, $req_id, $cmd_id, $record ) = @_;
    print "Data: ", join( ', ', $record->get_data() ), "\n";
    print "Logging out.\n";
    $self->logout();
 }

 sub onError {
    my( $self, $req_id, $cmd_id, $error ) = @_;
    print "ERROR: $error\n";
 }

 sub startup {
    my( $self ) = @_;
    print "Connecting to opentick server...\n";
    $self->login();
 }

 package main;

 use strict;
 use POE qw( Component::Client::opentick::OTClient );

 my $user = 'CHANGEME';
 my $pass = 'CHANGEMETOO';

 my $opentick = OTTest->new( $user, $pass );

 $poe_kernel->run();
 exit(0);

=head1 QUICK START FOR THE IMPATIENT

See F<examples/OTClient-example.pl>

But please read this documentation when you are done.  99% of your questions
will be answered below.

=head1 DESCRIPTION

This facade interface component allows you to easily interact with
opentick.com's market data feed service using the power of POE to
handle the asynchronous, simultaneous requests allowed with their protocol.

The full documentation for the otFeed standard is available at:

L<http://www.opentick.com/dokuwiki/doku.php?id=general:standard>

The API documentation will not be fully repeated here.  This documentation
builds upon the material on their website, to explain how to use this
particular implementation of their standard.

It is not 100%-compatible with their standard, especially in the returned
objects for the event handlers.  The entire functionality of the opentick
service can be accessed, with many additional features, using the base
L<POE::Component::Client::opentick> module.  This is primarily provided as a
usability bridge, based upon a much more robust and current underlying
implementation.

=head1 DIFFERENCES WITH THE MAINLINE API

=over 4

=item B<startup() callback>

The main entry point is provided in an additional B<startup> callback.

B<You should overload this and place your client initialization code into
it.>

=item B<Other callbacks>

Instead of having numerous subclasses, you simply receive a
POE::Component::Client::opentick::Record object for EACH INDIVIDUAL RECORD
of data from the message.

This means that, if you use requestListExchanges, and there are 15 exchanges
available, onListExchanges will be called 15 times, once per record, and
passed a ::Record object with each call.

The documentation for L<POE::Component::Client::opentick::Record> covers the
available accessor methods in detail.

If it should prove useful in the future to add the remaining classes back
into this facade interface, I may consider doing so.  It doesn't strike
me as necessary at this time, as I generally want the data itself, and both
the data and the field names for all response types are available in
::Record, so I personally find this interface much cleaner.

=item B<Constants>

Instead of the $Package::SubPackage::CONSTANT_NAME syntax from the mainline
client, use OTConstant( 'OT_STATUS_OK' ) syntax.

OTConstant() is exported from POE::Component::Client::opentick::Constants.

e.g.

use POE::Component::Client::opentick::Constant;

OTConstant('OT_FLAG_HIGH')

It's a bit more terse, and jives with the philosophy, "export behaviour, not
data."  (Of course, they aren't exporting anything at all, but in this case
it is useful.)

=item B<new() constructor>

The B<new()> constructor of the base class takes the otFeed-standard
$username and $password arguments, but in addition, you can pass any of the
parameters available to L<POE::Component::Client::opentick>, to initialize
the object in a more complete fashion.  Please see those documents for these
additional parameters.

You shouldn't probably overload the Notifyee and Events parameters, but some
ones worth noting might be:

=over 4

=item B<AutoLogin>

=item B<Servers>

=item B<Port>

=item B<Realtime>

=item B<Debug>

=back

In addition, so that you don't have to store your username/password in a
file on the filesystem, you can simply not pass them in, and use the
B<OPENTICK_USER> and B<OPENTICK_PASS> environment variables (detailed in
L</ENVIRONMENT> below) to have them passed in automagically.

If you do this, and still pass other arguments, you must use the following
constructor syntax:

 my $opentick = OTClient->new( undef, undef, AutoLogin => 1, ... );

Since, to follow the API, I locked them as the first 2 arguments.

=item B<setHosts()/clearHosts()>

These will work, but they are not paired as hostname:port combinations like
you are likely used to.

Because the underlying implementation uses these differently, you should
probably not use these, and just rely upon the hostnames provided within the
main application.  I keep these updated regularly, and you can additionally
use the Servers => [] and Port => XXXXX arguments to B<new()> to explicitly
pass them in at object construction time, for the all-too-often occasion
when opentick's servers become unavailable.

As long as you disconnect and reconnect, you can indeed change the servers
using these methods, though.

=back

=head1 SUBCLASSING

This module is designed to be subclassed, and you are intended to overload
the event handler methods with handlers of your own, as they do nothing by
default.

You should overload all methods that you want to trap, named under
L</EVENT HANDLERS>, especially B<startup()>, as this is where you place your
initialization code for what you wish to do once the opentick client object
has been instantiated.

=head1 METHODS

=over 4

=item B<$obj = new( $username, $password [, { arg => value, ... } ] )>

Create a new OTClient object, connect to the opentick server, log in, and
get ready for action.

RETURNS: blessed $object or undef

ARGUMENTS:

All arguments are of the hash form  Var => Value.  spawn() will complain and
exit if they do not follow this form.

=over 4

=item B<$username>       [ I<required> ] (but see B<NOTE>)

=item B<$password>       [ I<required> ] (but see B<NOTE>)

These are your login credentials for opentick.com.  If you do not have an
opentick.com account, please visit their website (L</SEE ALSO>) to create
one.  Note, that it is not a free service, but it is very inexpensive.
(Also, I don't work for them.)

If you do not have an account with them, this component is fairly useless to
you, so what are you still doing reading this?

B<NOTE>: A username and password I<MUST> be specified either as arguments
to spawn() or via the B<OPENTICK_USER> and/or B<OPENTICK_PASS> environment
variables (detailed in B<ENVIRONMENT> below), or the component will throw an
exception and exit.

B<ALL other arguments>, passed in the 3rd argument, as a hashref, are handed
off as options to the constructor for the primary ::opentick component.
Please refer to L<POE::Component::Client::opentick> for details on these
arguments.

=back

=back

=head1 OPENTICK API

The opentick.com API provides several commands that you may send.  All of the
API requests return a unique numeric $request_id for the particular command
you issue.  You properly send these commands by using the $object->call()
method (or the $poe_kernel->call() method with the session ID of the
component), so that you receive a numeric $request_id as a return value.
->yield() and ->post() are asynchronous, and do not return the $request_id.

Getting this $request_id into your client is essential to keep track of and
match particular requests with their corresponding responses.

It is left as an exercise to the implementor (YOU!) as to how best keep
track of your requests, although a %hash would work quite well.  See the
I<examples/> directory for some examples of how to do this if you are not
sure.

Here are the API-related events that you can issue to the POE component,
which correspond to the opentick.com API.  If they deviate from the otFeed
API, it will be noted.

=over 4

=item B<initialize( %args )>

This is not part of the official spec; just initalizes the object, and
starts the appropriate POE sessions.

=item B<addHost( $hostname, $port )>

=item B<clearHosts( )>

=item B<getStatus( )>

=item B<isLoggedIn( )>

=item B<setPlatformId( $id )>

=item B<login( )>

=item B<logout( )>

=item B<getEntityById( $request_id )>

Works differently from the API; returns a list consisting of the exchange
and symbol for which the request was issued.  Returns the 2-item list
directly, rather than storing into an OTDataEntity object.

e.g.

 my( $exchange, $symbol ) = $otclient->getEntityById( $request_id );

=item B<requestTickStream( $exchange, $symbol [, $flags ] )>

=item B<requestBookStream( $exchange, $symbol [, $flags ] )>

=item B<requestMarketDepth( $exchange, $symbol )>

=item B<requestOptionChain( $exchange, $symbol, $expMonth, $expYear, $mask )>

=item B<requestEquityInit( $exchange, $symbol )>

=item B<requestHistData( $exchange, $symbol, $startDate, $endDate, $dt, $interval )>

=item B<requestHistTicks( $exchange, $symbol, $startDate, $endDate, $mask )>

=item B<requestTodaysOHL( $exchange, $symbol )>

=item B<requestListExchanges( )>

=item B<requestListSymbols( $exchange )>

=item B<requestHistBooks( $exchange, $symbol, $startDate, $endDate, $mask )>

=item B<requestOptionInit( $exchange, $symbol, $expMonth, $expYear, $minStrike, $maxStrike, $paramsType )>

=item B<requestSplits( $exchange, $symbol, $startDate, $endDate )>

=item B<requestDividends( $exchange, $symbol, $startDate, $endDate )>

=item B<requestTickSnapshot( $exchange, $symbol, $mask )>

=item B<requestOptionChainSnapshot( $exchange, $symbol, $expMonth, $expYear, $mask, $minStrike, $maxStrike, $paramsType )>

=item B<cancelTickStream( $req_id )>

=item B<cancelBookStream( $req_id )>

=item B<cancelMarketDepth( $req_id )>

=item B<cancelOptionChain( $req_id )>

=item B<cancelHistData( $req_id )>

=back

More information regarding the opentick API, exchange codes, required
arguments, field definitions, etc., can be found at
L<http://www.opentick.com/dokuwiki/doku.php?id=general:standard>

=head1 EVENT HANDLERS

The otFeed standard specifies a list of event handlers which you may
overload to receive notifications for particular events.

=over 4

=item B<startup>

This is a custom extension to the main API.  This is called after the
opentick object initializes, and is a hook for you to start placing your
client code into, for instance, such commands as login(), etc.

It is called as an object method, and so receives the object handle as
the first parameter, so you can call other object methods from it.

e.g.

 sub startup
 {
    my( $self ) = @_;

    $self->login();

    return;
 }

=back

The remainder, listed below, follow the opentick.com standard.  They
all receive the following arguments (unless otherwise noted):

 ( B<$self, $request_id, $command_id, $record> )

=over 4

=item B<$self>

The object handle.

=item B<$request_id>

The numeric request ID, to match up with the response from request*

=item B<$command_id>

The numeric command ID of this request, as delineated in the opentick
protocol specification.

=item B<$record>

An object of type POE::Component::Client::opentick::Record, containing
the results of your request, accessible by its class methods.

=back

And finally, the callback list:

=over 4

=item B<onLogin>( void )

void -- receives no arguments.

=item B<onRestoreConnection>( void )

void -- receives no arguments.

=item B<onStatusChanged>( $state )

B<$state> -- The new state you have entered.  Follows the otFeed standard.

=item B<onError>( $req_id, $cmd_id, $error )

B<$error> -- An object of type POE::Component::Client::opentick::Error.  But
it is overloaded with formatted stringification, if you would prefer to simply
print it.

See L<POE::Component::Client::opentick::Error> for class methods.

=item B<onMessage>( $req_id, $cmd_id, $constant, $message )

B<$constant> -- 10 = End of Data, 20 = Request cancelled

B<$message> -- a $string containing a text message to the same effect.

=item B<onListExchanges>

=item B<onListSymbols>

=item B<onRealtimeTrade>

=item B<onRealtimeQuote>

=item B<onRealtimeBBO>

=item B<onRealtimeMMQuote>

=item B<onTodaysOHL>

=item B<onEquityInit>

=item B<onBookCancel>

=item B<onBookChange>

=item B<onBookDelete>

=item B<onBookExecute>

=item B<onBookOrder>

=item B<onBookPriceLevel>

=item B<onBookPurge>

=item B<onBookReplace>

=item B<onHistQuote>

=item B<onHistMMQuote>

=item B<onHistTrade>

=item B<onHistBBO>

=item B<onHistOHLC>

=item B<onHistBookCancel>

=item B<onHistBookChange>

=item B<onHistBookDelete>

=item B<onHistBookExecute>

=item B<onHistBookOrder>

=item B<onHistBookPriceLevel>

=item B<onHistBookPurge>

=item B<onHistBookReplace>

=item B<onSplit>

=item B<onDividend>

=item B<onOptionInit>

=back

NOTE: You will I<NOT> receive an B<onMessage> event upon the completion
of B<requestListExchanges> or B<requestListSymbols>, so plan accordingly.

=head1 ENVIRONMENT

This module suite uses the following environment variables:

=over 4

=item B<OPENTICK_USER>

=item B<OPENTICK_PASS>

These are used as a fallback mechanism, in case Username or Password are
not passed as arguments to B<spawn()>.  If after exhausting these two
possibilities, the username and password are not set, the suite will
signal an exception and exit.

They are also provided as a security option, since many people do not desire
to store passwords directly in their software.

=item B<OPENTICK_LIB>

This is part of the official opentick otFeed software.  This module suite
will also use this environment variable when attempting to locate the
original opentick library, to preload constant values used in the protocol.

L<POE::Component::Client::opentick::Constants.pm> attempts to load the
original libraries from @INC, and will prepend the directory specified in
B<OPENTICK_LIB> to the @INC search path, if it is set.

If the original libraries are not found, that is not a problem; we use our
own values; but this is an attempt to maintain compatibility with the
mainline software itself.

=back

=head1 SEE ALSO

The L<POE> documentation

L<http://poe.perl.org/>

L<http://www.opentick.com/>

L<http://www.opentick.com/dokuwiki/doku.php>

The examples/ directory of this module's distribution.

=head1 ACKNOWLEDGEMENTS

Thank you, Rocco Caputo (dngor) for inventing and unleashing POE upon the
world!

=head1 AUTHOR

Jason McManus (infi) -- infidel@cpan.org

=head1 LICENSE

Copyright (c) Jason McManus

This module may be used, modified, and distributed under the same terms
as Perl itself.  Please see the license that came with your Perl
distribution for details.

The data from opentick.com are under an entirely separate license that
varies according to exchange rules, etc.  It is your responsibility to
follow the opentick.com and exchange license agreements with the data.

Further details are available on L<http://www.opentick.com/>.

=cut

