package Net::Amazon::S3::Bucket;
use Moose 0.85;
use MooseX::StrictConstructor 0.16;
use Carp;
use File::stat;
use IO::File 1.14;

has 'account' => ( is => 'ro', isa => 'Net::Amazon::S3', required => 1 );
has 'bucket'  => ( is => 'ro', isa => 'Str',             required => 1 );
has 'creation_date' => ( is => 'ro', isa => 'Maybe[Str]', required => 0 );

__PACKAGE__->meta->make_immutable;

# ABSTRACT: convenience object for working with Amazon S3 buckets

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  use Net::Amazon::S3;

  my $bucket = $s3->bucket("foo");

  ok($bucket->add_key("key", "data"));
  ok($bucket->add_key("key", "data", {
     content_type => "text/html",
    'x-amz-meta-colour' => 'orange',
  }));

  # the err and errstr methods just proxy up to the Net::Amazon::S3's
  # objects err/errstr methods.
  $bucket->add_key("bar", "baz") or
      die $bucket->err . $bucket->errstr;

  # fetch a key
  $val = $bucket->get_key("key");
  is( $val->{value},               'data' );
  is( $val->{content_type},        'text/html' );
  is( $val->{etag},                'b9ece18c950afbfa6b0fdbfa4ff731d3' );
  is( $val->{'x-amz-meta-colour'}, 'orange' );

  # returns undef on missing or on error (check $bucket->err)
  is(undef, $bucket->get_key("non-existing-key"));
  die $bucket->errstr if $bucket->err;

  # fetch a key's metadata
  $val = $bucket->head_key("key");
  is( $val->{value},               '' );
  is( $val->{content_type},        'text/html' );
  is( $val->{etag},                'b9ece18c950afbfa6b0fdbfa4ff731d3' );
  is( $val->{'x-amz-meta-colour'}, 'orange' );

  # delete a key
  ok($bucket->delete_key($key_name));
  ok(! $bucket->delete_key("non-exist-key"));

  # delete the entire bucket (Amazon requires it first be empty)
  $bucket->delete_bucket;

=head1 DESCRIPTION

This module represents an S3 bucket.  You get a bucket object
from the Net::Amazon::S3 object.

=head1 METHODS

=head2 new

Create a new bucket object. Expects a hash containing these two arguments:

=over

=item bucket

=item account

=back

=cut

sub _uri {
    my ( $self, $key ) = @_;
    return ($key)
        ? $self->bucket . "/" . $self->account->_urlencode($key)
        : $self->bucket . "/";
}

sub _conf_to_headers {
    my ( $self, $conf ) = @_;
    $conf = {} unless defined $conf;
    $conf = {%$conf};    # clone it so as not to clobber the caller's copy

    if ( $conf->{acl_short} ) {
        $self->account->_validate_acl_short( $conf->{acl_short} );
        $conf->{'x-amz-acl'} = $conf->{acl_short};
        delete $conf->{acl_short};
    }

    return $conf;
}

=head2 add_key

Takes three positional parameters:

=over

=item key

=item value

=item configuration

A hash of configuration data for this key. (See synopsis);

=back

Returns a boolean.

=cut

# returns bool
sub add_key {
    my ( $self, $key, $value, $conf ) = @_;

    if ( ref($value) eq 'SCALAR' ) {
        $conf->{'Content-Length'} ||= -s $$value;
        $value = _content_sub($$value);
    } else {
        $conf->{'Content-Length'} ||= length $value;
    }

    my $acl_short;
    if ( $conf->{acl_short} ) {
        $acl_short = $conf->{acl_short};
        delete $conf->{acl_short};
    }

    my $http_request = Net::Amazon::S3::Request::PutObject->new(
        s3        => $self->account,
        bucket    => $self->bucket,
        key       => $key,
        value     => $value,
        acl_short => $acl_short,
        headers   => $conf,
    )->http_request;

    # If we're pushing to a bucket that's under DNS flux, we might get a 307
    # Since LWP doesn't support actually waiting for a 100 Continue response,
    # we'll just send a HEAD first to see what's going on

    if ( ref($value) ) {
        return $self->account->_send_request_expect_nothing_probed($http_request);
    } else {
        return $self->account->_send_request_expect_nothing($http_request);
    }
}

=head2 add_key_filename

Use this to upload a large file to S3. Takes three positional parameters:

=over

=item key

=item filename

=item configuration

A hash of configuration data for this key. (See synopsis);

=back

Returns a boolean.

=cut

sub add_key_filename {
    my ( $self, $key, $value, $conf ) = @_;
    return $self->add_key( $key, \$value, $conf );
}

=head2 copy_key

Creates (or replaces) a key, copying its contents from another key elsewhere in S3.
Takes the following parameters:

=over

=item key

The key to (over)write

=item source

Where to copy the key from. Should be in the form C</I<bucketname>/I<keyname>>/.

=item conf

Optional configuration hash. If present and defined, the configuration (ACL
and headers) there will be used for the new key; otherwise it will be copied
from the source key.

=back

=cut

sub copy_key {
    my ( $self, $key, $source, $conf ) = @_;

    my $acl_short;
    if ( defined $conf ) {
        if ( $conf->{acl_short} ) {
            $acl_short = $conf->{acl_short};
            delete $conf->{acl_short};
        }
        $conf->{'x-amz-metadata-directive'} = 'REPLACE';
    } else {
        $conf = {};
    }

    $conf->{'x-amz-copy-source'} = $source;

    my $acct    = $self->account;
    my $http_request = Net::Amazon::S3::Request::PutObject->new(
        s3        => $self->account,
        bucket    => $self->bucket,
        key       => $key,
        value     => '',
        acl_short => $acl_short,
        headers   => $conf,
    )->http_request;

    my $response = $acct->_do_http( $http_request );
    my $xpc      = $acct->_xpc_of_content( $response->content );

    if ( !$response->is_success || !$xpc || $xpc->findnodes("//Error") ) {
        $acct->_remember_errors( $response->content );
        return 0;
    }

    return 1;
}

=head2 edit_metadata

Changes the metadata associated with an existing key. Arguments:

=over

=item key

The key to edit

=item conf

The new configuration hash to use

=back

=cut

sub edit_metadata {
    my ( $self, $key, $conf ) = @_;
    croak "Need configuration hash" unless defined $conf;

    return $self->copy_key( $key, "/" . $self->bucket . "/" . $key, $conf );
}

=head2 head_key KEY

Takes the name of a key in this bucket and returns its configuration hash

=cut

sub head_key {
    my ( $self, $key ) = @_;
    return $self->get_key( $key, "HEAD" );
}

=head2 get_key $key_name [$method]

Takes a key name and an optional HTTP method (which defaults to C<GET>.
Fetches the key from AWS.

On failure:

Returns undef on missing content, throws an exception (dies) on server errors.

On success:

Returns a hashref of { content_type, etag, value, @meta } on success. Other
values from the server are there too, with the key being lowercased.

=cut

sub get_key {
    my ( $self, $key, $method, $filename ) = @_;
    $filename = $$filename if ref $filename;
    my $acct = $self->account;

    my $http_request = Net::Amazon::S3::Request::GetObject->new(
        s3     => $acct,
        bucket => $self->bucket,
        key    => $key,
        method => $method || 'GET',
    )->http_request;

    my $response = $acct->_do_http( $http_request, $filename );

    if ( $response->code == 404 ) {
        return undef;
    }

    $acct->_croak_if_response_error($response);

    my $etag = $response->header('ETag');
    if ($etag) {
        $etag =~ s/^"//;
        $etag =~ s/"$//;
    }

    my $return;
    foreach my $header ( $response->headers->header_field_names ) {
        $return->{ lc $header } = $response->header($header);
    }
    $return->{content_length} = $response->content_length || 0;
    $return->{content_type}   = $response->content_type;
    $return->{etag}           = $etag;
    $return->{value}          = $response->content;

    return $return;

}

=head2 get_key_filename $key_name $method $filename

Use this to download large files from S3. Takes a key name and an optional
HTTP method (which defaults to C<GET>. Fetches the key from AWS and writes
it to the filename. THe value returned will be empty.

On failure:

Returns undef on missing content, throws an exception (dies) on server errors.

On success:

Returns a hashref of { content_type, etag, value, @meta } on success

=cut

sub get_key_filename {
    my ( $self, $key, $method, $filename ) = @_;
    return $self->get_key( $key, $method, \$filename );
}

=head2 delete_key $key_name

Removes C<$key> from the bucket. Forever. It's gone after this.

Returns true on success and false on failure

=cut

# returns bool
sub delete_key {
    my ( $self, $key ) = @_;
    croak 'must specify key' unless defined $key && length $key;

    my $http_request = Net::Amazon::S3::Request::DeleteObject->new(
        s3     => $self->account,
        bucket => $self->bucket,
        key    => $key,
    )->http_request;

    return $self->account->_send_request_expect_nothing($http_request);
}

=head2 delete_bucket

Delete the current bucket object from the server. Takes no arguments.

Fails if the bucket has anything in it.

This is an alias for C<< $s3->delete_bucket($bucket) >>

=cut

sub delete_bucket {
    my $self = shift;
    croak "Unexpected arguments" if @_;
    return $self->account->delete_bucket($self);
}

=head2 list

List all keys in this bucket.

see L<Net::Amazon::S3/list_bucket> for documentation of this method.

=cut

sub list {
    my $self = shift;
    my $conf = shift || {};
    $conf->{bucket} = $self->bucket;
    return $self->account->list_bucket($conf);
}

=head2 list_all

List all keys in this bucket without having to worry about
'marker'. This may make multiple requests to S3 under the hood.

see L<Net::Amazon::S3/list_bucket_all> for documentation of this method.

=cut

sub list_all {
    my $self = shift;
    my $conf = shift || {};
    $conf->{bucket} = $self->bucket;
    return $self->account->list_bucket_all($conf);
}

=head2 get_acl

Takes one optional positional parameter

=over

=item key (optional)

If no key is specified, it returns the acl for the bucket.

=back

Returns an acl in XML format.

=cut

sub get_acl {
    my ( $self, $key ) = @_;
    my $account = $self->account;

    my $http_request;
    if ($key) {
        $http_request = Net::Amazon::S3::Request::GetObjectAccessControl->new(
            s3     => $account,
            bucket => $self->bucket,
            key    => $key,
        )->http_request;
    } else {
        $http_request = Net::Amazon::S3::Request::GetBucketAccessControl->new(
            s3     => $account,
            bucket => $self->bucket,
        )->http_request;
    }

    my $response = $account->_do_http($http_request);

    if ( $response->code == 404 ) {
        return undef;
    }

    $account->_croak_if_response_error($response);

    return $response->content;
}

=head2 set_acl

Takes a configuration hash_ref containing:

=over

=item acl_xml (cannot be used in conjunction with acl_short)

An XML string which contains access control information which matches
Amazon's published schema.  There is an example of one of these XML strings
in the tests for this module.

=item acl_short (cannot be used in conjunction with acl_xml)

You can use the shorthand notation instead of specifying XML for
certain 'canned' types of acls.

(from the Amazon API documentation)

private: Owner gets FULL_CONTROL. No one else has any access rights.
This is the default.

public-read:Owner gets FULL_CONTROL and the anonymous principal is granted
READ access. If this policy is used on an object, it can be read from a
browser with no authentication.

public-read-write:Owner gets FULL_CONTROL, the anonymous principal is
granted READ and WRITE access. This is a useful policy to apply to a bucket,
if you intend for any anonymous user to PUT objects into the bucket.

authenticated-read:Owner gets FULL_CONTROL, and any principal authenticated
as a registered Amazon S3 user is granted READ access.

=item key (optional)

If the key is not set, it will apply the acl to the bucket.

=back

Returns a boolean.

=cut

sub set_acl {
    my ( $self, $conf ) = @_;
    $conf ||= {};

    my $key = $conf->{key};
    my $http_request;
    if ($key) {
        $http_request = Net::Amazon::S3::Request::SetObjectAccessControl->new(
            s3        => $self->account,
            bucket    => $self->bucket,
            key       => $key,
            acl_short => $conf->{acl_short},
            acl_xml   => $conf->{acl_xml},
        )->http_request;
    } else {
        $http_request = Net::Amazon::S3::Request::SetBucketAccessControl->new(
            s3     => $self->account,
            bucket => $self->bucket,

            acl_short => $conf->{acl_short},
            acl_xml   => $conf->{acl_xml},
        )->http_request;
    }

    return $self->account->_send_request_expect_nothing($http_request);

}

=head2 get_location_constraint

Retrieves the location constraint set when the bucket was created. Returns a
string (eg, 'EU'), or undef if no location constraint was set.

=cut

sub get_location_constraint {
    my ($self) = @_;

    my $http_request = Net::Amazon::S3::Request::GetBucketLocationConstraint->new(
        s3     => $self->account,
        bucket => $self->bucket,
    )->http_request;

    my $xpc = $self->account->_send_request($http_request);
    return undef unless $xpc && !$self->account->_remember_errors($xpc);

    my $lc = $xpc->findvalue("//s3:LocationConstraint");
    if ( defined $lc && $lc eq '' ) {
        $lc = undef;
    }
    return $lc;
}

# proxy up the err requests

=head2 err

The S3 error code for the last error the object ran into

=cut

sub err { $_[0]->account->err }

=head2 errstr

A human readable error string for the last error the object ran into

=cut

sub errstr { $_[0]->account->errstr }

sub _content_sub {
    my $filename  = shift;
    my $stat      = stat($filename);
    my $remaining = $stat->size;
    my $blksize   = $stat->blksize || 4096;

    croak "$filename not a readable file with fixed size"
        unless -r $filename and ( -f _ || $remaining );
    my $fh = IO::File->new( $filename, 'r' )
        or croak "Could not open $filename: $!";
    $fh->binmode;

    return sub {
        my $buffer;

        # upon retries the file is closed and we must reopen it
        unless ( $fh->opened ) {
            $fh = IO::File->new( $filename, 'r' )
                or croak "Could not open $filename: $!";
            $fh->binmode;
            $remaining = $stat->size;
        }

        # warn "read remaining $remaining";
        unless ( my $read = $fh->read( $buffer, $blksize ) ) {

#                       warn "read $read buffer $buffer remaining $remaining";
            croak
                "Error while reading upload content $filename ($remaining remaining) $!"
                if $! and $remaining;

            # otherwise, we found EOF
            $fh->close
                or croak "close of upload content $filename failed: $!";
            $buffer ||= ''
                ;    # LWP expects an emptry string on finish, read returns 0
        }
        $remaining -= length($buffer);
        return $buffer;
    };
}

1;

__END__

=head1 SEE ALSO

L<Net::Amazon::S3>

