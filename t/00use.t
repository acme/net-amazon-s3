#!perl
use warnings;
use strict;

use lib 'lib';

use Test::More tests => 4;

use_ok( 'Net::Amazon::S3' );
use_ok( 'Net::Amazon::S3::Client' );
use_ok( 'Net::Amazon::S3::Client::Bucket' );
use_ok( 'Net::Amazon::S3::Client::Object' );
