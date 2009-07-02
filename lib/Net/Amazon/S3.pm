package Net::Amazon::S3;
use Moose;
use MooseX::StrictConstructor;

=head1 NAME

Net::Amazon::S3 - Use the Amazon S3 - Simple Storage Service

=head1 SYNOPSIS

  use Net::Amazon::S3;
  my $aws_access_key_id     = 'fill me in';
  my $aws_secret_access_key = 'fill me in too';

  my $s3 = Net::Amazon::S3->new(
      {   aws_access_key_id     => $aws_access_key_id,
          aws_secret_access_key => $aws_secret_access_key,
          retry                 => 1,
      }
  );

  # a bucket is a globally-unique directory
  # list all buckets that i own
  my $response = $s3->buckets;
  foreach my $bucket ( @{ $response->{buckets} } ) {
      print "You have a bucket: " . $bucket->bucket . "\n";
  }

  # create a new bucket
  my $bucketname = 'acmes_photo_backups';
  my $bucket = $s3->add_bucket( { bucket => $bucketname } )
      or die $s3->err . ": " . $s3->errstr;

  # or use an existing bucket
  $bucket = $s3->bucket($bucketname);

  # store a file in the bucket
  $bucket->add_key_filename( '1.JPG', 'DSC06256.JPG',
      { content_type => 'image/jpeg', },
  ) or die $s3->err . ": " . $s3->errstr;

  # store a value in the bucket
  $bucket->add_key( 'reminder.txt', 'this is where my photos are backed up' )
      or die $s3->err . ": " . $s3->errstr;

  # list files in the bucket
  $response = $bucket->list_all
      or die $s3->err . ": " . $s3->errstr;
  foreach my $key ( @{ $response->{keys} } ) {
      my $key_name = $key->{key};
      my $key_size = $key->{size};
      print "Bucket contains key '$key_name' of size $key_size\n";
  }

  # fetch file from the bucket
  $response = $bucket->get_key_filename( '1.JPG', 'GET', 'backup.jpg' )
      or die $s3->err . ": " . $s3->errstr;

  # fetch value from the bucket
  $response = $bucket->get_key('reminder.txt')
      or die $s3->err . ": " . $s3->errstr;
  print "reminder.txt:\n";
  print "  content length: " . $response->{content_length} . "\n";
  print "    content type: " . $response->{content_type} . "\n";
  print "            etag: " . $response->{content_type} . "\n";
  print "         content: " . $response->{value} . "\n";

  # delete keys
  $bucket->delete_key('reminder.txt') or die $s3->err . ": " . $s3->errstr;
  $bucket->delete_key('1.JPG')        or die $s3->err . ": " . $s3->errstr;

  # and finally delete the bucket
  $bucket->delete_bucket or die $s3->err . ": " . $s3->errstr;

=head1 DESCRIPTION

This module provides a Perlish interface to Amazon S3. From the
developer blurb: "Amazon S3 is storage for the Internet. It is
designed to make web-scale computing easier for developers. Amazon S3
provides a simple web services interface that can be used to store and
retrieve any amount of data, at any time, from anywhere on the web. It
gives any developer access to the same highly scalable, reliable,
fast, inexpensive data storage infrastructure that Amazon uses to run
its own global network of web sites. The service aims to maximize
benefits of scale and to pass those benefits on to developers".

To find out more about S3, please visit: http://s3.amazonaws.com/

To use this module you will need to sign up to Amazon Web Services and
provide an "Access Key ID" and " Secret Access Key". If you use this
module, you will incurr costs as specified by Amazon. Please check the
costs. If you use this module with your Access Key ID and Secret
Access Key you must be responsible for these costs.

I highly recommend reading all about S3, but in a nutshell data is
stored in values. Values are referenced by keys, and keys are stored
in buckets. Bucket names are global.

Note: This is the legacy interface, please check out
L<Net::Amazon::S3::Client> instead.

Development of this code happens here: http://github.com/acme/net-amazon-s3

=cut

use Carp;
use Digest::HMAC_SHA1;

use Net::Amazon::S3::Bucket;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Bucket;
use Net::Amazon::S3::Client::Object;
use Net::Amazon::S3::HTTPRequest;
use Net::Amazon::S3::Request;
use Net::Amazon::S3::Request::CreateBucket;
use Net::Amazon::S3::Request::DeleteBucket;
use Net::Amazon::S3::Request::DeleteObject;
use Net::Amazon::S3::Request::GetBucketAccessControl;
use Net::Amazon::S3::Request::GetBucketLocationConstraint;
use Net::Amazon::S3::Request::GetObject;
use Net::Amazon::S3::Request::GetObjectAccessControl;
use Net::Amazon::S3::Request::ListAllMyBuckets;
use Net::Amazon::S3::Request::ListBucket;
use Net::Amazon::S3::Request::PutObject;
use Net::Amazon::S3::Request::SetBucketAccessControl;
use Net::Amazon::S3::Request::SetObjectAccessControl;
use LWP::UserAgent::Determined;
use URI::Escape qw(uri_escape_utf8);
use XML::LibXML;
use XML::LibXML::XPathContext;

has 'aws_access_key_id'     => ( is => 'ro', isa => 'Str', required => 1 );
has 'aws_secret_access_key' => ( is => 'ro', isa => 'Str', required => 1 );
has 'secure' => ( is => 'ro', isa => 'Bool', required => 0, default => 0 );
has 'timeout' => ( is => 'ro', isa => 'Num',  required => 0, default => 30 );
has 'retry'   => ( is => 'ro', isa => 'Bool', required => 0, default => 0 );

has 'libxml' => ( is => 'rw', isa => 'XML::LibXML',    required => 0 );
has 'ua'     => ( is => 'rw', isa => 'LWP::UserAgent', required => 0 );
has 'err'    => ( is => 'rw', isa => 'Maybe[Str]',     required => 0 );
has 'errstr' => ( is => 'rw', isa => 'Maybe[Str]',     required => 0 );

__PACKAGE__->meta->make_immutable;

our $VERSION = '0.52';

my $KEEP_ALIVE_CACHESIZE = 10;

=head1 METHODS

=head2 new 

Create a new S3 client object. Takes some arguments:

=over

=item aws_access_key_id 

Use your Access Key ID as the value of the AWSAccessKeyId parameter
in requests you send to Amazon Web Services (when required). Your
Access Key ID identifies you as the party responsible for the
request.

=item aws_secret_access_key 

Since your Access Key ID is not encrypted in requests to AWS, it
could be discovered and used by anyone. Services that are not free
require you to provide additional information, a request signature,
to verify that a request containing your unique Access Key ID could
only have come from you.

DO NOT INCLUDE THIS IN SCRIPTS OR APPLICATIONS YOU DISTRIBUTE. YOU'LL BE SORRY

=item secure 

Set this to C<1> if you want to use SSL-encrypted connections when talking
to S3. Defaults to C<0>.

=item timeout

How many seconds should your script wait before bailing on a request to S3? Defaults
to 30.

=item retry

If this library should retry upon errors. This option is recommended.
This uses exponential backoff with retries after 1, 2, 4, 8, 16, 32 seconds, 
as recommended by Amazon. Defaults to off.

=back

=cut

sub BUILD {
    my $self = shift;

    my $ua;
    if ( $self->retry ) {
        $ua = LWP::UserAgent::Determined->new(
            keep_alive            => $KEEP_ALIVE_CACHESIZE,
            requests_redirectable => [qw(GET HEAD DELETE PUT)],
        );
        $ua->timing('1,2,4,8,16,32');
    } else {
        $ua = LWP::UserAgent->new(
            keep_alive            => $KEEP_ALIVE_CACHESIZE,
            requests_redirectable => [qw(GET HEAD DELETE PUT)],
        );
    }

    $ua->timeout( $self->timeout );
    $ua->env_proxy;

    $self->ua($ua);
    $self->libxml( XML::LibXML->new );
}

=head2 buckets

Returns undef on error, else hashref of results

=cut

sub buckets {
    my $self = shift;

    my $http_request
        = Net::Amazon::S3::Request::ListAllMyBuckets->new( s3 => $self )
        ->http_request;

    # die $request->http_request->as_string;

    my $xpc = $self->_send_request($http_request);

    return undef unless $xpc && !$self->_remember_errors($xpc);

    my $owner_id          = $xpc->findvalue("//s3:Owner/s3:ID");
    my $owner_displayname = $xpc->findvalue("//s3:Owner/s3:DisplayName");

    my @buckets;
    foreach my $node ( $xpc->findnodes(".//s3:Bucket") ) {
        push @buckets,
            Net::Amazon::S3::Bucket->new(
            {   bucket => $xpc->findvalue( ".//s3:Name", $node ),
                creation_date =>
                    $xpc->findvalue( ".//s3:CreationDate", $node ),
                account => $self,
            }
            );

    }
    return {
        owner_id          => $owner_id,
        owner_displayname => $owner_displayname,
        buckets           => \@buckets,
    };
}

=head2 add_bucket 

Takes a hashref:

=over

=item bucket

The name of the bucket you want to add

=item acl_short (optional)

See the set_acl subroutine for documenation on the acl_short options

=item location_constraint (option)

Sets the location constraint of the new bucket. If left unspecified, the
default S3 datacenter location will be used. Otherwise, you can set it
to 'EU' for a European data center - note that costs are different.

=back

Returns 0 on failure, Net::Amazon::S3::Bucket object on success

=cut

sub add_bucket {
    my ( $self, $conf ) = @_;

    my $http_request = Net::Amazon::S3::Request::CreateBucket->new(
        s3                  => $self,
        bucket              => $conf->{bucket},
        acl_short           => $conf->{acl_short},
        location_constraint => $conf->{location_constraint},
    )->http_request;

    return 0
        unless $self->_send_request_expect_nothing($http_request);

    return $self->bucket( $conf->{bucket} );
}

=head2 bucket BUCKET

Takes a scalar argument, the name of the bucket you're creating

Returns an (unverified) bucket object from an account. Does no network access.

=cut

sub bucket {
    my ( $self, $bucketname ) = @_;
    return Net::Amazon::S3::Bucket->new(
        { bucket => $bucketname, account => $self } );
}

=head2 delete_bucket

Takes either a L<Net::Amazon::S3::Bucket> object or a hashref containing 

=over

=item bucket

The name of the bucket to remove

=back

Returns false (and fails) if the bucket isn't empty.

Returns true if the bucket is successfully deleted.

=cut

sub delete_bucket {
    my ( $self, $conf ) = @_;
    my $bucket;
    if ( eval { $conf->isa("Net::S3::Amazon::Bucket"); } ) {
        $bucket = $conf->bucket;
    } else {
        $bucket = $conf->{bucket};
    }
    croak 'must specify bucket' unless $bucket;

    my $http_request = Net::Amazon::S3::Request::DeleteBucket->new(
        s3     => $self,
        bucket => $bucket,
    )->http_request;

    return $self->_send_request_expect_nothing($http_request);
}

=head2 list_bucket

List all keys in this bucket.

Takes a hashref of arguments:

MANDATORY

=over

=item bucket

The name of the bucket you want to list keys on

=back

OPTIONAL

=over

=item prefix

Restricts the response to only contain results that begin with the
specified prefix. If you omit this optional argument, the value of
prefix for your query will be the empty string. In other words, the
results will be not be restricted by prefix.

=item delimiter

If this optional, Unicode string parameter is included with your
request, then keys that contain the same string between the prefix
and the first occurrence of the delimiter will be rolled up into a
single result element in the CommonPrefixes collection. These
rolled-up keys are not returned elsewhere in the response.  For
example, with prefix="USA/" and delimiter="/", the matching keys
"USA/Oregon/Salem" and "USA/Oregon/Portland" would be summarized
in the response as a single "USA/Oregon" element in the CommonPrefixes
collection. If an otherwise matching key does not contain the
delimiter after the prefix, it appears in the Contents collection.

Each element in the CommonPrefixes collection counts as one against
the MaxKeys limit. The rolled-up keys represented by each CommonPrefixes
element do not.  If the Delimiter parameter is not present in your
request, keys in the result set will not be rolled-up and neither
the CommonPrefixes collection nor the NextMarker element will be
present in the response.

=item max-keys 

This optional argument limits the number of results returned in
response to your query. Amazon S3 will return no more than this
number of results, but possibly less. Even if max-keys is not
specified, Amazon S3 will limit the number of results in the response.
Check the IsTruncated flag to see if your results are incomplete.
If so, use the Marker parameter to request the next page of results.
For the purpose of counting max-keys, a 'result' is either a key
in the 'Contents' collection, or a delimited prefix in the
'CommonPrefixes' collection. So for delimiter requests, max-keys
limits the total number of list results, not just the number of
keys.

=item marker

This optional parameter enables pagination of large result sets.
C<marker> specifies where in the result set to resume listing. It
restricts the response to only contain results that occur alphabetically
after the value of marker. To retrieve the next page of results,
use the last key from the current page of results as the marker in
your next request.

See also C<next_marker>, below. 

If C<marker> is omitted,the first page of results is returned. 

=back


Returns undef on error and a hashref of data on success:

The hashref looks like this:

  {
        bucket          => $bucket_name,
        prefix          => $bucket_prefix, 
        common_prefixes => [$prefix1,$prefix2,...]
        marker          => $bucket_marker, 
        next_marker     => $bucket_next_available_marker,
        max_keys        => $bucket_max_keys,
        is_truncated    => $bucket_is_truncated_boolean
        keys            => [$key1,$key2,...]
   }

Explanation of bits of that:

=over

=item common_prefixes

If list_bucket was requested with a delimiter, common_prefixes will
contain a list of prefixes matching that delimiter.  Drill down into
these prefixes by making another request with the prefix parameter.

=item is_truncated

B flag that indicates whether or not all results of your query were
returned in this response. If your results were truncated, you can
make a follow-up paginated request using the Marker parameter to
retrieve the rest of the results.


=item next_marker 

A convenience element, useful when paginating with delimiters. The
value of C<next_marker>, if present, is the largest (alphabetically)
of all key names and all CommonPrefixes prefixes in the response.
If the C<is_truncated> flag is set, request the next page of results
by setting C<marker> to the value of C<next_marker>. This element
is only present in the response if the C<delimiter> parameter was
sent with the request.

=back

Each key is a hashref that looks like this:

     {
        key           => $key,
        last_modified => $last_mod_date,
        etag          => $etag, # An MD5 sum of the stored content.
        size          => $size, # Bytes
        storage_class => $storage_class # Doc?
        owner_id      => $owner_id,
        owner_displayname => $owner_name
    }

=cut

sub list_bucket {
    my ( $self, $conf ) = @_;

    my $http_request = Net::Amazon::S3::Request::ListBucket->new(
        s3        => $self,
        bucket    => $conf->{bucket},
        delimiter => $conf->{delimiter},
        max_keys  => $conf->{max_keys},
        marker    => $conf->{marker},
        prefix    => $conf->{prefix},
    )->http_request;

    my $xpc = $self->_send_request($http_request);

    return undef unless $xpc && !$self->_remember_errors($xpc);

    my $return = {
        bucket      => $xpc->findvalue("//s3:ListBucketResult/s3:Name"),
        prefix      => $xpc->findvalue("//s3:ListBucketResult/s3:Prefix"),
        marker      => $xpc->findvalue("//s3:ListBucketResult/s3:Marker"),
        next_marker => $xpc->findvalue("//s3:ListBucketResult/s3:NextMarker"),
        max_keys    => $xpc->findvalue("//s3:ListBucketResult/s3:MaxKeys"),
        is_truncated => (
            scalar $xpc->findvalue("//s3:ListBucketResult/s3:IsTruncated") eq
                'true'
            ? 1
            : 0
        ),
    };

    my @keys;
    foreach my $node ( $xpc->findnodes(".//s3:Contents") ) {
        my $etag = $xpc->findvalue( ".//s3:ETag", $node );
        $etag =~ s/^"//;
        $etag =~ s/"$//;

        push @keys,
            {
            key           => $xpc->findvalue( ".//s3:Key",          $node ),
            last_modified => $xpc->findvalue( ".//s3:LastModified", $node ),
            etag          => $etag,
            size          => $xpc->findvalue( ".//s3:Size",         $node ),
            storage_class => $xpc->findvalue( ".//s3:StorageClass", $node ),
            owner_id      => $xpc->findvalue( ".//s3:ID",           $node ),
            owner_displayname =>
                $xpc->findvalue( ".//s3:DisplayName", $node ),
            };
    }
    $return->{keys} = \@keys;

    if ( $conf->{delimiter} ) {
        my @common_prefixes;
        my $strip_delim = qr/$conf->{delimiter}$/;

        foreach my $node ( $xpc->findnodes(".//s3:CommonPrefixes") ) {
            my $prefix = $xpc->findvalue( ".//s3:Prefix", $node );

            # strip delimiter from end of prefix
            $prefix =~ s/$strip_delim//;

            push @common_prefixes, $prefix;
        }
        $return->{common_prefixes} = \@common_prefixes;
    }

    return $return;
}

=head2 list_bucket_all

List all keys in this bucket without having to worry about
'marker'. This is a convenience method, but may make multiple requests
to S3 under the hood.

Takes the same arguments as list_bucket.

=cut

sub list_bucket_all {
    my ( $self, $conf ) = @_;
    $conf ||= {};
    my $bucket = $conf->{bucket};
    croak 'must specify bucket' unless $bucket;

    my $response = $self->list_bucket($conf);
    return $response unless $response->{is_truncated};
    my $all = $response;

    while (1) {
        my $next_marker = $response->{next_marker}
            || $response->{keys}->[-1]->{key};
        $conf->{marker} = $next_marker;
        $conf->{bucket} = $bucket;
        $response       = $self->list_bucket($conf);
        push @{ $all->{keys} }, @{ $response->{keys} };
        last unless $response->{is_truncated};
    }

    delete $all->{is_truncated};
    delete $all->{next_marker};
    return $all;
}

sub _compat_bucket {
    my ( $self, $conf ) = @_;
    return Net::Amazon::S3::Bucket->new(
        { account => $self, bucket => delete $conf->{bucket} } );
}

=head2 add_key 

DEPRECATED. DO NOT USE

=cut

# compat wrapper; deprecated as of 2005-03-23
sub add_key {
    my ( $self, $conf ) = @_;
    my $bucket = $self->_compat_bucket($conf);
    my $key    = delete $conf->{key};
    my $value  = delete $conf->{value};
    return $bucket->add_key( $key, $value, $conf );
}

=head2 get_key 

DEPRECATED. DO NOT USE

=cut

# compat wrapper; deprecated as of 2005-03-23
sub get_key {
    my ( $self, $conf ) = @_;
    my $bucket = $self->_compat_bucket($conf);
    return $bucket->get_key( $conf->{key} );
}

=head2 head_key 

DEPRECATED. DO NOT USE

=cut

# compat wrapper; deprecated as of 2005-03-23
sub head_key {
    my ( $self, $conf ) = @_;
    my $bucket = $self->_compat_bucket($conf);
    return $bucket->head_key( $conf->{key} );
}

=head2 delete_key 

DEPRECATED. DO NOT USE

=cut

# compat wrapper; deprecated as of 2005-03-23
sub delete_key {
    my ( $self, $conf ) = @_;
    my $bucket = $self->_compat_bucket($conf);
    return $bucket->delete_key( $conf->{key} );
}

sub _validate_acl_short {
    my ( $self, $policy_name ) = @_;

    if (!grep( { $policy_name eq $_ }
            qw(private public-read public-read-write authenticated-read) ) )
    {
        croak "$policy_name is not a supported canned access policy";
    }
}

# $self->_send_request($HTTP::Request)
# $self->_send_request(@params_to_make_request)
sub _send_request {
    my ( $self, $http_request ) = @_;

    # warn $http_request->as_string;

    my $response = $self->_do_http($http_request);
    my $content  = $response->content;

    return $content unless $response->content_type eq 'application/xml';
    return unless $content;
    return $self->_xpc_of_content($content);
}

# centralize all HTTP work, for debugging
sub _do_http {
    my ( $self, $http_request, $filename ) = @_;

    confess 'Need HTTP::Request object'
        if ( ref($http_request) ne 'HTTP::Request' );

    # convenient time to reset any error conditions
    $self->err(undef);
    $self->errstr(undef);
    return $self->ua->request( $http_request, $filename );
}

sub _send_request_expect_nothing {
    my ( $self, $http_request ) = @_;

    # warn $http_request->as_string;

    my $response = $self->_do_http($http_request);
    my $content  = $response->content;

    return 1 if $response->code =~ /^2\d\d$/;

    # anything else is a failure, and we save the parsed result
    $self->_remember_errors( $response->content );
    return 0;
}

# Send a HEAD request first, to find out if we'll be hit with a 307 redirect.
# Since currently LWP does not have true support for 100 Continue, it simply
# slams the PUT body into the socket without waiting for any possible redirect.
# Thus when we're reading from a filehandle, when LWP goes to reissue the request
# having followed the redirect, the filehandle's already been closed from the
# first time we used it. Thus, we need to probe first to find out what's going on,
# before we start sending any actual data.
sub _send_request_expect_nothing_probed {
    my ( $self, $http_request ) = @_;

    my $head = Net::Amazon::S3::HTTPRequest->new(
        s3     => $self,
        method => 'HEAD',
        path   => $http_request->uri->path,
    )->http_request;

    #my $head_request = $self->_make_request( $head );
    my $override_uri = undef;

    my $old_redirectable = $self->ua->requests_redirectable;
    $self->ua->requests_redirectable( [] );

    my $response = $self->_do_http($head);

    if ( $response->code =~ /^3/ && defined $response->header('Location') ) {
        $override_uri = $response->header('Location');
    }

    $http_request->uri($override_uri) if defined $override_uri;

    $response = $self->_do_http($http_request);
    $self->ua->requests_redirectable($old_redirectable);

    my $content = $response->content;

    return 1 if $response->code =~ /^2\d\d$/;

    # anything else is a failure, and we save the parsed result
    $self->_remember_errors( $response->content );
    return 0;
}

sub _croak_if_response_error {
    my ( $self, $response ) = @_;
    unless ( $response->code =~ /^2\d\d$/ ) {
        $self->err("network_error");
        $self->errstr( $response->status_line );
        croak "Net::Amazon::S3: Amazon responded with "
            . $response->status_line . "\n";
    }
}

sub _xpc_of_content {
    my ( $self, $content ) = @_;
    my $doc = $self->libxml->parse_string($content);

    # warn $doc->toString(1);

    my $xpc = XML::LibXML::XPathContext->new($doc);
    $xpc->registerNs( 's3', 'http://s3.amazonaws.com/doc/2006-03-01/' );

    return $xpc;
}

# returns 1 if errors were found
sub _remember_errors {
    my ( $self, $src ) = @_;

    # Do not try to parse non-xml
    unless ( ref $src || $src =~ m/^[[:space:]]*</ ) {
        ( my $code = $src ) =~ s/^[[:space:]]*\([0-9]*\).*$/$1/;
        $self->err($code);
        $self->errstr($src);
        return 1;
    }

    my $xpc = ref $src ? $src : $self->_xpc_of_content($src);
    if ( $xpc->findnodes("//Error") ) {
        $self->err( $xpc->findvalue("//Error/Code") );
        $self->errstr( $xpc->findvalue("//Error/Message") );
        return 1;
    }
    return 0;
}

sub _urlencode {
    my ( $self, $unencoded ) = @_;
    return uri_escape_utf8( $unencoded, '^A-Za-z0-9_-' );
}

1;

__END__

=head1 LICENSE

This module contains code modified from Amazon that contains the
following notice:

  #  This software code is made available "AS IS" without warranties of any
  #  kind.  You may copy, display, modify and redistribute the software
  #  code either by itself or as incorporated into your code; provided that
  #  you do not remove any proprietary notices.  Your use of this software
  #  code is at your own risk and you waive any claim against Amazon
  #  Digital Services, Inc. or its affiliates with respect to your use of
  #  this software code. (c) 2006 Amazon Digital Services, Inc. or its
  #  affiliates.

=head1 TESTING

Testing S3 is a tricky thing. Amazon wants to charge you a bit of 
money each time you use their service. And yes, testing counts as using.
Because of this, the application's test suite skips anything approaching 
a real test unless you set these three environment variables:

=over 

=item AMAZON_S3_EXPENSIVE_TESTS

Doesn't matter what you set it to. Just has to be set

=item AWS_ACCESS_KEY_ID 

Your AWS access key

=item AWS_ACCESS_KEY_SECRET

Your AWS sekkr1t passkey. Be forewarned that setting this environment variable
on a shared system might leak that information to another user. Be careful.

=back

=head1 AUTHOR

Leon Brocard <acme@astray.com> and unknown Amazon Digital Services programmers.

Brad Fitzpatrick <brad@danga.com> - return values, Bucket object

=head1 SEE ALSO

L<Net::Amazon::S3::Bucket>

