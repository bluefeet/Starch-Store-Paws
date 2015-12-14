package Starch::Store::Paws::DynamoDB;

=head1 NAME

Starch::Store::Paws::DynamoDB - Starch storage backend using Paws::DynamoDB.

=head1 SYNOPSIS

    my $starch = Starch->new(
        store => {
            class => '::Paws::DynamoDB',
            region => 'us-west-2',
        },
    );

=head1 DESCRIPTION

This L<Starch> store uses L<Paws::DynamoDB> to set and get state data.

This module is meant to be a more robust replacement for
L<Starch::Store::Amazon::DynamoDB> for several reasons:

=over

=item *

L<Amazon::DynamoDB> lacks many features and it does not appear like
this will change any time soon.

=item *

L<Paws> appears to be the king of AWS API in Perl, likely deprecating
many of the existing AWS modules on CPAN.

=back

=head1 WARNING

L<Paws> is not yet stable as it is being actively developed and no promises
are being made in regards to API stability or quality of the software.

Thus, this module also does not make any such promises.  Once Paws reaches
version 1 this will change.

=head1 OPTIMIZATION

You should probably run the following code as early as possible:

    use Paws;
    Paws->default_config->immutable(1);

This will ensure that you get the most run-time performance at a trade
of minimal compile time from Paws.  See more at L<Paws/Optimization>.

This module automatically preloads the C<PutItem>, C<GetItem>, and
C<DeleteItem> methods of the L<Paws::DynamoDB> class.

=cut

use Paws;
BEGIN {
    Paws->preload_service(
        DynamoDB => qw( PutItem GetItem DeleteItem ),
    );
}

use Types::Standard -types;
use Types::Common::String -types;
use Scalar::Util qw( blessed );
use JSON::MaybeXS qw();

use Moo;
use strictures 2;
use namespace::clean;

with qw(
    Starch::Store
);

my $json = JSON::MaybeXS->new( utf8=>1, allow_nonref=>1 );

after BUILD => sub{
    my ($self) = @_;

    # Get this loaded as early as possible.
    $self->ddb();

    if ($self->connect_on_create()) {
        $self->get(
            'starch-store-dynamodb-initialization', [],
        );
    }

    return;
};

=head1 OPTIONAL ARGUMENTS

=head2 region

This is the AWS region which will be used when building the L</paws>
object.  If you specify your own L</paws> object (or aguments) then
this will be ignored.  Defaults to C<us-east-1>.

=cut

has region => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'us-east-1',
);

=head2 ddb

This must be set to either hash ref arguments for L<Paws::DynamoDB>
or a pre-built object (often retrieved using a method proxy).

When configuring Starch from static configuration files using a
L<method proxy|Starch/METHOD PROXIES>
is a good way to link your existing L<Paws::DynamoDB> object
constructor in with Starch so that starch doesn't build its own.

=cut

has _ddb_arg => (
    is       => 'ro',
    isa      => (HasMethods[ 'PutItem', 'GetItem', 'DeleteItem' ]) | HashRef,
    init_arg => 'ddb',
);

has ddb => (
    is       => 'lazy',
    isa      => HasMethods[ 'PutItem', 'GetItem', 'DeleteItem' ],
    init_arg => undef,
);
sub _build_ddb {
    my ($self) = @_;

    my $ddb = $self->_ddb_arg();
    return $ddb if blessed $ddb;

    $ddb = {} if !defined $ddb;
    return $self->paws->service('DynamoDB', %$ddb);
}

=head2 paws

The L<Paws> object, which will be used to construct the L</ddb> object.

If this is sepecified as a HashRef then a new L<Paws> object will be
created with the HashRef used as the C<config> argumet.

See more at L<Paws/CONFIGURATION>.

=cut

has _paws_arg => (
    is       => 'ro',
    isa      => (HasMethods[ 'service' ]) | HashRef,
    init_arg => 'paws',
);

has paws => (
    is       => 'lazy',
    isa      => HasMethods[ 'service' ],
    init_arg => undef,
);
sub _build_paws {
    my ($self) = @_;

    my $paws = $self->_paws_arg();
    return $paws if blessed $paws;

    $paws = { region=>$self->region() } if !defined $paws;

    return Paws->new( config=>{ %$paws } );
}

=head2 consistent_read

When C<true> this sets the C<ConsistentRead> flag when calling
L<GetItem> on the L</ddb>.  Defaults to C<true>.

=cut

has consistent_read => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

=head2 table

The DynamoDB table name where states are stored. Defaults to C<starch_states>.

=cut

has table => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'starch_states',
);

=head2 key_field

The field in the L</table> where the state ID is stored.
Defaults to C<__STARCH_KEY__>.

=cut

has key_field => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => '__STARCH_KEY__',
);

=head2 expiration_field

The field in the L</table> which will hold the epoch
time when the state should be expired.  Defaults to C<__STARCH_EXPIRATION__>.

=cut

has expiration_field => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => '__STARCH_EXPIRATION__',
);

=head2 connect_on_create

By default when this store is first created it will issue an L</get>.
This initializes all the LWP and other code so that, in a forked
environment (such as a web server) this initialization only happens
once, not on every child's first request.

Defaults to C<1> (true).  Set this to false if you don't want this feature.

=cut

has connect_on_create => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

=head1 METHODS

=head2 create_table_args

Returns the appropriate arguments to use for calling C<CreateTable>
on the L</ddb> object.  By default it will look like this:

    {
        TableName => 'starch_states',
        ProvisionedThroughput => {
            ReadCapacityUnits  => 1,
            WriteCapacityUnits => 1,
        },
        AttributeDefinitions => [{
            AttributeName => $key_field,
            AttributeType => 'S',
        }],
        KeySchema => [{
            AttributeName => $key_field,
            KeyType       => 'HASH',
        }],
    }

Any arguments you pass will override those in the returned arguments,
which means you could, for example, do something like this to override
the provisioned units:

    my $args = $store->create_table_args(
        ProvisionedThroughput => {
            ReadCapacityUnits  => 100,
            WriteCapacityUnits => 20,
        },
    );

=cut

sub create_table_args {
    my $self = shift;

    my $key_field = $self->key_field();

    return {
        TableName => $self->table(),
        ProvisionedThroughput => {
            ReadCapacityUnits  => 1,
            WriteCapacityUnits => 1,
        },
        AttributeDefinitions => [{
            AttributeName => $key_field,
            AttributeType => 'S',
        }],
        KeySchema => [{
            AttributeName => $key_field,
            KeyType       => 'HASH',
        }],
        @_,
    };
}

=head2 create_table

Creates the L</table> by passing any arguments to L</create_table_args>
and calling the C<CreateTable> method on the L</ddb> object.

This method will not return until the new table is in an C<ACTIVE> state.

If no exceptions are thrown a L<Paws::DynamoDB::TableDescription> object
is returned.

=cut

sub create_table {
    my $self = shift;

    my $ddb = $self->ddb();
    my $args = $self->create_table_args( @_ );

    # This will throw an exception if there were any problems.
    my $output = $ddb->CreateTable( %$args );

    my $table_name = $output->TableDescription->TableName();

    my $table;
    my $wait = 1;
    while (1) {
        sleep $wait;
        $table = $ddb->DescribeTable( TableName=>$table_name )->Table();
        last if $table->TableStatus() eq 'ACTIVE';
        $wait *= 2; # Double the sleep time each time through.
    }

    return $table;
}

=head2 set

Set L<Starch::Store/set>.

=head2 get

Set L<Starch::Store/get>.

=head2 remove

Set L<Starch::Store/remove>.

=cut

sub set {
    my ($self, $id, $namespace, $data, $expires) = @_;

    my $key = $self->stringify_key( $id, $namespace );

    $expires += time() if $expires;

    $data = {
        %$data,
        $self->key_field() => $key,
        $self->expiration_field() => $expires,
    };

    $self->ddb->PutItem(
        TableName => $self->table(),
        Item => {
            map {
                $_ => {S => $json->encode( $data->{$_} )},
            }
            grep { defined $data->{$_} }
            keys( %$data )
        },
    );

    return;
}

sub get {
    my ($self, $id, $namespace) = @_;

    my $key = $self->stringify_key( $id, $namespace );

    my $item = $self->ddb->GetItem(
        TableName => $self->table(),
        $self->consistent_read() ? (ConsistentRead => 1) : (),
        Key => {
            $self->key_field() => {S => $json->encode( $key )},
        },
    )->Item();

    return undef if !$item;
    my $map = $item->Map();

    return {
        map {
            $_->[0] => $json->decode( $_->[1] )
        }
        grep { defined $_->[1] }
        map { [ $_, $map->{$_}->S() ] }
        keys( %$map )
    };
}

sub remove {
    my ($self, $id, $namespace) = @_;

    my $key = $self->stringify_key( $id, $namespace );

    $self->ddb->DeleteItem(
        TableName => $self->table(),
        Key => {
            $self->key_field() => {'S', $json->encode( $key )},
        },
    );

    return;
}

1;
__END__

=head1 SUPPORT

Please submit bugs and feature requests to the
Starch-Store-Paws-DynamoDB GitHub issue tracker:

L<https://github.com/bluefeet/Starch-Store-Paws-DynamoDB/issues>

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

