requires 'Starch' => 0.05;
requires 'Paws'   => 0.20;
#requires 'strictures'       => 2.000000;
#requires 'namespace::clean' => 0.24;
#requires 'Moo'              => 2.000000;
#requires 'Type::Tiny'       => 1.000005;
#requires 'Try::Tiny'        => 0.18;
#requires 'Data::Serializer' => 0.60;
#requires 'Carp'             => 0;
#requires 'Scalar::Util'     => 0;

on test => sub {
    requires 'Test::Simple' => 0.96;
#    requires 'Test::Fatal'  => 0;
#    requires 'JSON'         => 2;
};
