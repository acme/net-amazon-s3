package Net::Amazon::S3::Client::Object;
use Moose 0.85;
use MooseX::StrictConstructor 0.16;
use DateTime::Format::HTTP;
use Digest::MD5 qw(md5 md5_hex);
use Digest::MD5::File qw(file_md5 file_md5_hex);
use File::stat;
use MIME::Base64;
use Moose::Util::TypeConstraints;
use MooseX::Types::DateTime::MoreCoercions 0.07 qw( DateTime );
use IO::File 1.14;

# ABSTRACT: An easy-to-use Amazon S3 client object

enum 'AclShort' =>
    qw(private public-read public-read-write authenticated-read);

has 'client' =>
    ( is => 'ro', isa => 'Net::Amazon::S3::Client', required => 1 );
has 'bucket' =>
    ( is => 'ro', isa => 'Net::Amazon::S3::Client::Bucket', required => 1 );
has 'key'  => ( is => 'ro', isa => 'Str',  required => 1 );
has 'etag' => ( is => 'ro', isa => 'Etag', required => 0 );
has 'size' => ( is => 'ro', isa => 'Int',  required => 0 );
has 'last_modified' =>
    ( is => 'ro', isa => DateTime, coerce => 1, required => 0 );
has 'expires' => ( is => 'rw', isa => DateTime, coerce => 1, required => 0 );
has 'acl_short' =>
    ( is => 'ro', isa => 'AclShort', required => 0, default => 'private' );
has 'content_type' => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
    default  => 'binary/octet-stream'
);
has 'content_disposition' => (
    is => 'ro',
    isa => 'Str',
    required => 0,
);
has 'content_encoding' => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
);

__PACKAGE__->meta->make_immutable;

sub exists {
    my $self = shift;

    my $http_request = Net::Amazon::S3::Request::GetObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
        method => 'HEAD',
    )->http_request;

    my $http_response = $self->client->_send_request_raw($http_request);
    return $http_response->code == 200 ? 1 : 0;
}

sub get {
    my $self = shift;

    my $http_request = Net::Amazon::S3::Request::GetObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
        method => 'GET',
    )->http_request;

    my $http_response = $self->client->_send_request($http_request);
    my $content       = $http_response->content;

    my $md5_hex = md5_hex($content);
    my $etag = $self->etag || $self->_etag($http_response);
    confess 'Corrupted download'
      if( !$self->_is_multipart_etag($etag) && $etag ne $md5_hex);

    return $content;
}

sub get_filename {
    my ($self, $filename) = @_;

    my $http_request = Net::Amazon::S3::Request::GetObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
        method => 'GET',
    )->http_request;

    my $http_response
        = $self->client->_send_request($http_request, $filename);

    my $md5_hex = file_md5_hex($filename);

    my $etag = $self->etag || $self->_etag($http_response);
    confess
      'Corrupted download' if(!$self->_is_multipart_etag($etag) && $etag ne $md5_hex);
}

sub put {
    my ( $self, $value ) = @_;
    my $md5        = md5($value);
    my $md5_hex    = unpack( 'H*', $md5 );
    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;

    my $conf = {
        'Content-MD5'    => $md5_base64,
        'Content-Length' => length $value,
        'Content-Type'   => $self->content_type,
    };

    if ( $self->expires ) {
        $conf->{Expires}
            = DateTime::Format::HTTP->format_datetime( $self->expires );
    }
    if ( $self->content_encoding ) {
        $conf->{'Content-Encoding'} = $self->content_encoding;
    }
    if ( $self->content_disposition ) {
        $conf->{'Content-Disposition'} = $self->content_disposition;
    }

    my $http_request = Net::Amazon::S3::Request::PutObject->new(
        s3        => $self->client->s3,
        bucket    => $self->bucket->name,
        key       => $self->key,
        value     => $value,
        headers   => $conf,
        acl_short => $self->acl_short,
    )->http_request;

    my $http_response = $self->client->_send_request($http_request);

    confess 'Error uploading' if $http_response->code != 200;

    my $etag = $self->_etag($http_response);

    confess 'Corrupted upload' if $etag ne $md5_hex;
}

sub put_filename {
    my ( $self, $filename ) = @_;

    my $md5_hex = $self->etag || file_md5_hex($filename);
    my $size = $self->size;
    unless ($size) {
        my $stat = stat($filename) || confess("No $filename: $!");
        $size = $stat->size;
    }

    my $md5 = pack( 'H*', $md5_hex );
    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;

    my $conf = {
        'Content-MD5'    => $md5_base64,
        'Content-Length' => $size,
        'Content-Type'   => $self->content_type,
    };

    if ( $self->expires ) {
        $conf->{Expires}
            = DateTime::Format::HTTP->format_datetime( $self->expires );
    }
    if ( $self->content_encoding ) {
        $conf->{'Content-Encoding'} = $self->content_encoding;
    }
    if ( $self->content_disposition ) {
        $conf->{'Content-Disposition'} = $self->content_disposition;
    }


    my $http_request = Net::Amazon::S3::Request::PutObject->new(
        s3        => $self->client->s3,
        bucket    => $self->bucket->name,
        key       => $self->key,
        value     => $self->_content_sub($filename),
        headers   => $conf,
        acl_short => $self->acl_short,
    )->http_request;

    my $http_response = $self->client->_send_request($http_request);

    confess 'Error uploading' . $http_response->as_string
        if $http_response->code != 200;

    confess 'Corrupted upload' if $self->_etag($http_response) ne $md5_hex;
}

sub delete {
    my $self = shift;

    my $http_request = Net::Amazon::S3::Request::DeleteObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
    )->http_request;

    $self->client->_send_request($http_request);
}

sub initiate_multipart_upload {
    my $self = shift;
    my $http_request = Net::Amazon::S3::Request::InitiateMultipartUpload->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
    )->http_request;
    my $xpc = $self->client->_send_request_xpc($http_request);
    my $upload_id = $xpc->findvalue('//s3:UploadId');
    confess "Couldn't get upload id from initiate_multipart_upload response XML"
      unless $upload_id;

    return $upload_id;
}

sub complete_multipart_upload {
    my $self = shift;

    my %args = ref($_[0]) ? %{$_[0]} : @_;

    #set default args
    $args{s3}       = $self->client->s3;
    $args{key}      = $self->key;
    $args{bucket}   = $self->bucket->name;

    my $http_request =
      Net::Amazon::S3::Request::CompleteMultipartUpload->new(%args)->http_request;
    return $self->client->_send_request($http_request);
}

sub put_part {
    my $self = shift;

    my %args = ref($_[0]) ? %{$_[0]} : @_;

    #set default args
    $args{s3}       = $self->client->s3;
    $args{key}      = $self->key;
    $args{bucket}   = $self->bucket->name;
    #work out content length header
    $args{headers}->{'Content-Length'} = length $args{value}
      if(defined $args{value});

    my $http_request =
      Net::Amazon::S3::Request::PutPart->new(%args)->http_request;
    return $self->client->_send_request($http_request);
}

sub list_parts {
    confess "Not implemented";
    # TODO - Net::Amazon::S3::Request:ListParts is implemented, but need to
    # define better interface at this level. Currently returns raw XML.
}

sub uri {
    my $self = shift;
    return Net::Amazon::S3::Request::GetObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
        method => 'GET',
    )->http_request->uri;
}

sub query_string_authentication_uri {
    my $self = shift;
    return Net::Amazon::S3::Request::GetObject->new(
        s3     => $self->client->s3,
        bucket => $self->bucket->name,
        key    => $self->key,
        method => 'GET',
    )->query_string_authentication_uri( $self->expires->epoch );
}

sub _content_sub {
    my $self      = shift;
    my $filename  = shift;
    my $stat      = stat($filename);
    my $remaining = $stat->size;
    my $blksize   = $stat->blksize || 4096;

    confess "$filename not a readable file with fixed size"
        unless -r $filename and ( -f _ || $remaining );
    my $fh = IO::File->new( $filename, 'r' )
        or confess "Could not open $filename: $!";
    $fh->binmode;

    return sub {
        my $buffer;

        # upon retries the file is closed and we must reopen it
        unless ( $fh->opened ) {
            $fh = IO::File->new( $filename, 'r' )
                or confess "Could not open $filename: $!";
            $fh->binmode;
            $remaining = $stat->size;
        }

        # warn "read remaining $remaining";
        unless ( my $read = $fh->read( $buffer, $blksize ) ) {

#                       warn "read $read buffer $buffer remaining $remaining";
            confess
                "Error while reading upload content $filename ($remaining remaining) $!"
                if $! and $remaining;

            # otherwise, we found EOF
            $fh->close
                or confess "close of upload content $filename failed: $!";
            $buffer ||= ''
                ;    # LWP expects an emptry string on finish, read returns 0
        }
        $remaining -= length($buffer);
        return $buffer;
    };
}

sub _etag {
    my ( $self, $http_response ) = @_;
    my $etag = $http_response->header('ETag');
    if ($etag) {
        $etag =~ s/^"//;
        $etag =~ s/"$//;
    }
    return $etag;
}

sub _is_multipart_etag {
    my ( $self, $etag ) = @_;
    return 1 if($etag =~ /\-\d+$/);
}

1;

__END__

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  # show the key
  print $object->key . "\n";

  # show the etag of an existing object (if fetched by listing
  # a bucket)
  print $object->etag . "\n";

  # show the size of an existing object (if fetched by listing
  # a bucket)
  print $object->size . "\n";

  # to create a new object
  my $object = $bucket->object( key => 'this is the key' );
  $object->put('this is the value');

  # to get the vaue of an object
  my $value = $object->get;

  # to see if an object exists
  if ($object->exists) { ... }

  # to delete an object
  $object->delete;

  # to create a new object which is publically-accessible with a
  # content-type of text/plain which expires on 2010-01-02
  my $object = $bucket->object(
    key          => 'this is the public key',
    acl_short    => 'public-read',
    content_type => 'text/plain',
    expires      => '2010-01-02',
  );
  $object->put('this is the public value');

  # return the URI of a publically-accessible object
  my $uri = $object->uri;

  # upload a file
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    content_type => 'image/jpeg',
  );
  $object->put_filename('hat.jpg');

  # upload a file if you already know its md5_hex and size
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    content_type => 'image/jpeg',
    etag         => $md5_hex,
    size         => $size,
  );
  $object->put_filename('hat.jpg');

  # download the value of the object into a file
  my $object = $bucket->object( key => 'images/my_hat.jpg' );
  $object->get_filename('hat_backup.jpg');

  # use query string authentication
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    expires      => '2009-03-01',
  );
  my $uri = $object->query_string_authentication_uri();

=head1 DESCRIPTION

This module represents objects in buckets.

=head1 METHODS

=head2 etag

  # show the etag of an existing object (if fetched by listing
  # a bucket)
  print $object->etag . "\n";

=head2 delete

  # to delete an object
  $object->delete;

=head2 exists

  # to see if an object exists
  if ($object->exists) { ... }

=head2 get

  # to get the vaue of an object
  my $value = $object->get;

=head2 get_filename

  # download the value of the object into a file
  my $object = $bucket->object( key => 'images/my_hat.jpg' );
  $object->get_filename('hat_backup.jpg');

=head2 key

  # show the key
  print $object->key . "\n";

=head2 put

  # to create a new object
  my $object = $bucket->object( key => 'this is the key' );
  $object->put('this is the value');

  # to create a new object which is publically-accessible with a
  # content-type of text/plain
  my $object = $bucket->object(
    key          => 'this is the public key',
    acl_short    => 'public-read',
    content_type => 'text/plain',
  );
  $object->put('this is the public value');

You may also set Content-Encoding using content_encoding, and
Content-Disposition using content_disposition.

=head2 put_filename

  # upload a file
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    content_type => 'image/jpeg',
  );
  $object->put_filename('hat.jpg');

  # upload a file if you already know its md5_hex and size
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    content_type => 'image/jpeg',
    etag         => $md5_hex,
    size         => $size,
  );
  $object->put_filename('hat.jpg');

You may also set Content-Encoding using content_encoding, and
Content-Disposition using content_disposition.

=head2 query_string_authentication_uri

  # use query string authentication
  my $object = $bucket->object(
    key          => 'images/my_hat.jpg',
    expires      => '2009-03-01',
  );
  my $uri = $object->query_string_authentication_uri();

=head2 size

  # show the size of an existing object (if fetched by listing
  # a bucket)
  print $object->size . "\n";

=head2 uri

  # return the URI of a publically-accessible object
  my $uri = $object->uri;

=head2 initiate_multipart_upload

  #initiate a new multipart upload for this object
  my $object = $bucket->object(
    key         => 'massive_video.avi'
  );
  my $upload_id = $object->initiate_multipart_upload;

=head2 put_part

  #add a part to a multipart upload
  my $put_part_response = $object->put_part(
     upload_id      => $upload_id,
     part_number    => 1,
     value          => $chunk_content,
  );
  my $part_etag = $put_part_response->header('ETag')

  Returns an L<HTTP::Response> object. It is necessary to keep the ETags for
  each part, as these are required to complete the upload.

=head2 complete_multipart_upload

  #complete a multipart upload
  $object->complete_multipart_upload(
    upload_id       => $upload_id,
    etags           => [$etag_1, $etag_2],
    part_numbers    => [$part_number_1, $part_number2],
  );

  The etag and part_numbers parameters are ordered lists specifying the part
  numbers and ETags for each individual part of the multipart upload.
