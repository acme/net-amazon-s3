#!perl
use warnings;
use strict;
use lib 'lib';
use Digest::MD5::File qw(file_md5_hex);
use LWP::Simple;
use File::stat;
use Test::More;
use Test::Exception;
use File::Temp qw/ :seekable /;

unless ( $ENV{'AMAZON_S3_EXPENSIVE_TESTS'} ) {
    plan skip_all => 'Testing this module for real costs money.';
} else {
    plan tests => 48;
}

use_ok('Net::Amazon::S3');

my $aws_access_key_id     = $ENV{'AWS_ACCESS_KEY_ID'};
my $aws_secret_access_key = $ENV{'AWS_ACCESS_KEY_SECRET'};

my $s3 = Net::Amazon::S3->new(
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    retry                 => 1,
);

my $readme_size   = stat('README')->size;
my $readme_md5hex = file_md5_hex('README');

my $client = Net::Amazon::S3::Client->new( s3 => $s3 );

my @buckets = $client->buckets;

TODO: {
    local $TODO = "These tests only work if you're pedro";
    my $first_bucket = $buckets[0];
    like( $first_bucket->owner_id, qr/^c7483d612ac7f0c0/, 'have owner id' );
    is( $first_bucket->owner_display_name, 'pedro_figueiredo', 'have display name' );
    is( scalar @buckets, 6, 'have a bunch of buckets' );
}

my $bucket_name = 'net-amazon-s3-test-' . lc $aws_access_key_id;

my $bucket = $client->create_bucket(
    name                => $bucket_name,
    acl_short           => 'public-read',
    location_constraint => 'EU',
);

is( $bucket->name, $bucket_name, 'newly created bucket has correct name' );

like(
    $bucket->acl,
    qr{<AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>[a-z0-9]{64}</ID><DisplayName>.+?</DisplayName></Owner><AccessControlList><Grant><Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser"><ID>[a-z0-9]{64}</ID><DisplayName>.+?</DisplayName></Grantee><Permission>FULL_CONTROL</Permission></Grant><Grant><Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Group"><URI>http://acs.amazonaws.com/groups/global/AllUsers</URI></Grantee><Permission>READ</Permission></Grant></AccessControlList></AccessControlPolicy>},
    'newly created bucket is public-readable'
);

is( $bucket->location_constraint, 'EU', 'newly created bucket is in the EU' );

my $stream = $bucket->list;
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        $object->delete;
    }
}

my $count = 0;
$stream = $bucket->list;
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        $count++;
    }
}

is( $count, 0, 'newly created bucket has no objects' );

my $object = $bucket->object( key => 'this is the key' );

ok( !$object->exists, 'object does not exist yet' );

$object->put('this is the value');

ok( $object->exists, 'object now exists yet' );

my @objects;

@objects = ();
$stream = $bucket->list( { prefix => 'this is the key' } );
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        push @objects, $object;
    }
}
is( @objects, 1, 'bucket list with prefix finds key' );

@objects = ();
$stream = $bucket->list( { prefix => 'this is not the key' } );
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        push @objects, $object;
    }
}
is( @objects, 0, 'bucket list with different prefix does not find key' );

@objects = ();
$stream  = $bucket->list;
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        push @objects, $object;
    }
}
is( @objects, 1, 'bucket list finds newly created key' );

is( $objects[0]->key,
    'this is the key',
    'newly created object has the right key'
);
is( $objects[0]->etag,
    '94325a12f8db22ffb6934cc5f22f6698',
    'newly created object has the right etag'
);
is( $objects[0]->size, '17', 'newly created object has the right size' );

is( $object->get,
    'this is the value',
    'newly created object has the right value'
);

is( $bucket->object( key => 'this is the key' )->get,
    'this is the value',
    'newly created object fetched by name has the right value'
);

is( get( $object->uri ),
    undef, 'newly created object cannot be fetched by uri' );

$object->expires('2037-01-01');

is( get( $object->query_string_authentication_uri() ),
    'this is the value',
    'newly created object can be fetch by authentication uri'
);

$object->delete;

# upload a public object
$object = $bucket->object(
    key              => 'this is the public key',
    acl_short        => 'public-read',
    content_type     => 'text/plain',
    content_encoding => 'identity',
    expires          => '2001-02-03',
);
$object->put('this is the public value');
is( get( $object->uri ),
    'this is the public value',
    'newly created public object is publically accessible'
);
is( ( head( $object->uri ) )[0],
    'text/plain', 'newly created public object has the right content type' );
is( ( head( $object->uri ) )[3],
    $object->expires->epoch,
    'newly created public object has the right expires' );
$object->delete;

# delete a non-existant object

$object = $bucket->object( key => 'not here' );
throws_ok { $object->get } qr/NoSuchKey/,
    'getting non-existant object throws exception';

# upload a file with put_filename

$object = $bucket->object( key => 'the readme' );
$object->put_filename('README');

@objects = ();
$stream  = $bucket->list;
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        push @objects, $object;
    }
}

is( @objects, 1, 'have newly uploaded object' );
is( $objects[0]->key, 'the readme',
    'newly uploaded object has the right key' );
is( $objects[0]->etag, $readme_md5hex,
    'newly uploaded object has the right etag' );
is( $objects[0]->size, $readme_size,
    'newly created object has the right size' );

ok( $objects[0]->last_modified, 'newly created object has a last modified' );

$object->delete;

# upload a public object with put_filename

$object = $bucket->object(
    key       => 'the public readme',
    acl_short => 'public-read'
);
$object->put_filename('README');
is( length( get( $object->uri ) ),
    $readme_size, 'newly uploaded public object has the right size' );
$object->delete;

# upload a file with put_filename with known md5hex and size

$object = $bucket->object(
    key  => 'the new readme',
    etag => $readme_md5hex,
    size => $readme_size
);
$object->put_filename('README');

@objects = ();
$stream  = $bucket->list;
until ( $stream->is_done ) {
    foreach my $object ( $stream->items ) {
        push @objects, $object;
    }
}

is( @objects, 1, 'have newly uploaded object' );
is( $objects[0]->key,
    'the new readme',
    'newly uploaded object has the right key'
);
is( $objects[0]->etag, $readme_md5hex,
    'newly uploaded object has the right etag' );
is( $objects[0]->size, $readme_size,
    'newly created object has the right size' );
ok( $objects[0]->last_modified, 'newly created object has a last modified' );

# download an object with get_filename
my $tmp_fh = File::Temp->new();
$object->get_filename($tmp_fh->filename);
is( stat($tmp_fh->filename)->size,   $readme_size,   'download has right size' );
is( file_md5_hex($tmp_fh->filename), $readme_md5hex, 'download has right etag' );

$object->delete;

# upload a public object with put_filename with known md5hex and size
$object = $bucket->object(
    key       => 'the new public readme',
    etag      => $readme_md5hex,
    size      => $readme_size,
    acl_short => 'public-read'
);
$object->put_filename( 'README', $readme_md5hex, $readme_size );
is( length( get( $object->uri ) ),
    $readme_size, 'newly uploaded public object has the right size' );
$object->delete;


# upload an object using multipart upload
$object = $bucket->object(
    key       => 'new multipart file',
    acl_short => 'public-read'
);

my $upload_id;
ok($upload_id = $object->initiate_multipart_upload, "can initiate a new multipart upload");

#put part

my $put_part_response;
ok( $put_part_response = $object->put_part(part_number => 1, upload_id => $upload_id, value => 'x' x (5 * 1024 * 1024)), 'Got a successful response for PUT part' );
my @etags;
push @etags, $put_part_response->header('ETag');
ok( $put_part_response = $object->put_part(part_number => 2, upload_id => $upload_id, value => 'z' x (1024 * 1024)), 'Got a successful response for 2nd PUT part' );
push @etags, $put_part_response->header('ETag');

# TODO list part? - We've got this, but how to expose it nicely?

#complete multipart upload
my $complete_upload_response;
ok(
    $complete_upload_response = $object->complete_multipart_upload( upload_id => $upload_id, part_numbers => [1,2], etags => \@etags),
    "successful response for complete multipart upload"
);
#get the file and check that it looks like we expect
ok($object->exists, "object has now been created");

$tmp_fh = File::Temp->new();
$object->get_filename($tmp_fh->filename);
is( stat($tmp_fh->filename)->size, 6 * 1024 * 1024, "downloaded file has a size equivalent to the sum of it's parts");

$tmp_fh->seek((5 * 1024 * 1024) - 1, SEEK_SET);#jump to 5MB position
my $test_bytes;
read($tmp_fh, $test_bytes, 2);
is($test_bytes, "xz", "The second chunk of the file begins in the correct place");

$object->delete;

#test multi-object delete
#make 3 identical objects
@objects =();
for my $i(1..3){
    my $bulk_object = $bucket->object(
        key  => "bulk-readme-$i",
        etag => $readme_md5hex,
        size => $readme_size
    );
    $bulk_object->put_filename('README');
    push @objects, $bulk_object;
}
#now delete 2 of those objects
ok($bucket->delete_multi_object(@objects[0..1]), "executed multi delete operation");
ok( !grep($_->exists, @objects[0..1]), "target objects no longer exist");
ok( $objects[2]->exists, "object not included in multi-object delete still exists" );
$objects[2]->delete;

$bucket->delete;
