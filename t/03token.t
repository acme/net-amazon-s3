#!perl
use warnings;
use strict;
use lib 'lib';

use Test::More;
use Test::Exception;

unless ( $ENV{'AWS_ACCESS_KEY_ID'} and
         $ENV{'AWS_ACCESS_KEY_SECRET'} and
         $ENV{'AWS_ACCESS_TOKEN'} ) {
    plan skip_all =>
        'Need these vars in ENV: AWS_ACCESS_KEY_ID, ' .
        'AWS_ACCESS_KEY_SECRET, AWS_ACCESS_TOKEN';
} else {
    plan tests => 1 + 1;
}

use_ok('Net::Amazon::S3');

my $aws_access_key_id     = $ENV{'AWS_ACCESS_KEY_ID'};
my $aws_secret_access_key = $ENV{'AWS_ACCESS_KEY_SECRET'};
my $aws_session_token     = $ENV{'AWS_ACCESS_TOKEN'};

my $s3 = Net::Amazon::S3->new(
    {   aws_access_key_id     => $aws_access_key_id,
        aws_secret_access_key => $aws_secret_access_key,
        aws_session_token     => $aws_session_token,
        retry                 => 1,
    }
);

# list all buckets that i own
my $response = $s3->buckets;
ok($response, "Authentication with token succeded");
