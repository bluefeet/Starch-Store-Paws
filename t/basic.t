#!/usr/bin/env perl
use strictures 2;

use Test::More;
use Test::Starch;

if (!$ENV{PAWS_DYNAMODB_LOCAL_TESTS}) {
    plan skip_all => 'Run a Local DynamoDB and set PAWS_DYNAMODB_LOCAL_TESTS=1 to run this test.';
}

my $tester = Test::Starch->new(
    store => {
        class  => '::Paws::DynamoDB',
        table => "sessions-$$-$<-" . time(),
        region => 'local',

        # Can't do this since the table doesn't exist yet.
        connect_on_create => 0,
    },
);

$tester->new_manager->store->create_table();

$tester->test();

done_testing();
