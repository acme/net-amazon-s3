package Net::Amazon::S3::HTTPRequest;
use Moose 0.85;
use MooseX::StrictConstructor 0.16;
use HTTP::Date;
use MIME::Base64 qw( encode_base64 );
use Moose::Util::TypeConstraints;
use URI::Escape qw( uri_escape_utf8 );
use URI::QueryParam;
use URI;

# ABSTRACT: Create a signed HTTP::Request

my $METADATA_PREFIX      = 'x-amz-meta-';
my $AMAZON_HEADER_PREFIX = 'x-amz-';

enum 'HTTPMethod' => qw(DELETE GET HEAD PUT POST);

has 's3'     => ( is => 'ro', isa => 'Net::Amazon::S3', required => 1 );
has 'method' => ( is => 'ro', isa => 'HTTPMethod',      required => 1 );
has 'path'   => ( is => 'ro', isa => 'Str',             required => 1 );
has 'headers' =>
    ( is => 'ro', isa => 'HashRef', required => 0, default => sub { {} } );
has 'content' =>
    ( is => 'ro', isa => 'Str|CodeRef', required => 0, default => '' );
has 'metadata' =>
    ( is => 'ro', isa => 'HashRef', required => 0, default => sub { {} } );

__PACKAGE__->meta->make_immutable;

# make the HTTP::Request object
sub http_request {
    my $self     = shift;
    my $method   = $self->method;
    my $path     = $self->path;
    my $headers  = $self->headers;
    my $content  = $self->content;
    my $metadata = $self->metadata;

    my $http_headers = $self->_merge_meta( $headers, $metadata );

    $self->_add_auth_header( $http_headers, $method, $path )
        unless exists $headers->{Authorization};
    my $protocol = $self->s3->secure ? 'https' : 'http';
    my $uri = "$protocol://s3.amazonaws.com/$path";
    if ( $path =~ m{^([^/?]+)(.*)} && _is_dns_bucket($1) ) {
        $uri = "$protocol://$1.s3.amazonaws.com$2";
    }

    my $request
        = HTTP::Request->new( $method, $uri, $http_headers, $content );

    # my $req_as = $request->as_string;
    # $req_as =~ s/[^\n\r\x20-\x7f]/?/g;
    # $req_as = substr( $req_as, 0, 1024 ) . "\n\n";
    # warn $req_as;

    return $request;
}

sub query_string_authentication_uri {
    my ( $self, $expires ) = @_;
    my $method  = $self->method;
    my $path    = $self->path;
    my $headers = $self->headers;

    my $aws_access_key_id     = $self->s3->aws_access_key_id;
    my $aws_secret_access_key = $self->s3->aws_secret_access_key;
    my $canonical_string
        = $self->_canonical_string( $method, $path, $headers, $expires );
    my $encoded_canonical
        = $self->_encode( $aws_secret_access_key, $canonical_string );

    my $protocol = $self->s3->secure ? 'https' : 'http';
    my $uri = "$protocol://s3.amazonaws.com/$path";
    if ( $path =~ m{^([^/?]+)(.*)} && _is_dns_bucket($1) ) {
        $uri = "$protocol://$1.s3.amazonaws.com$2";
    }
    $uri = URI->new($uri);

    $uri->query_param( AWSAccessKeyId => $aws_access_key_id );
    $uri->query_param( Expires        => $expires );
    $uri->query_param( Signature      => $encoded_canonical );

    return $uri;
}

sub _add_auth_header {
    my ( $self, $headers, $method, $path ) = @_;
    my $aws_access_key_id     = $self->s3->aws_access_key_id;
    my $aws_secret_access_key = $self->s3->aws_secret_access_key;
    my $aws_session_token     = $self->s3->aws_session_token;

    if ( not $headers->header('Date') ) {
        $headers->header( Date => time2str(time) );
    }

    if ( not $headers->header('x-amz-security-token') and
         defined $aws_session_token ) {
        $headers->header( 'x-amz-security-token' => $aws_session_token );
    }

    my $canonical_string
        = $self->_canonical_string( $method, $path, $headers );
    my $encoded_canonical
        = $self->_encode( $aws_secret_access_key, $canonical_string );
    $headers->header(
        Authorization => "AWS $aws_access_key_id:$encoded_canonical" );
}

# generate a canonical string for the given parameters.  expires is optional and is
# only used by query string authentication.
sub _canonical_string {
    my ( $self, $method, $path, $headers, $expires ) = @_;
    my %interesting_headers = ();
    while ( my ( $key, $value ) = each %$headers ) {
        my $lk = lc $key;
        if (   $lk eq 'content-md5'
            or $lk eq 'content-type'
            or $lk eq 'date'
            or $lk =~ /^$AMAZON_HEADER_PREFIX/ )
        {
            $interesting_headers{$lk} = $self->_trim($value);
        }
    }

    # these keys get empty strings if they don't exist
    $interesting_headers{'content-type'} ||= '';
    $interesting_headers{'content-md5'}  ||= '';

    # just in case someone used this.  it's not necessary in this lib.
    $interesting_headers{'date'} = ''
        if $interesting_headers{'x-amz-date'};

    # if you're using expires for query string auth, then it trumps date
    # (and x-amz-date)
    $interesting_headers{'date'} = $expires if $expires;

    my $buf = "$method\n";
    foreach my $key ( sort keys %interesting_headers ) {
        if ( $key =~ /^$AMAZON_HEADER_PREFIX/ ) {
            $buf .= "$key:$interesting_headers{$key}\n";
        } else {
            $buf .= "$interesting_headers{$key}\n";
        }
    }

    # don't include anything after the first ? in the resource...
    $path =~ /^([^?]*)/;
    $buf .= "/$1";

    # ...unless there any parameters we're interested in...
    if ( $path =~ /[&?](acl|torrent|location|uploads|delete)($|=|&)/ ) {
        $buf .= "?$1";
    } elsif ( my %query_params = URI->new($path)->query_form ){
        #see if the remaining parsed query string provides us with any query string or upload id
        if($query_params{partNumber} && $query_params{uploadId}){
            #re-evaluate query string, the order of the params is important for request signing, so we can't depend on URI to do the right thing
            $buf .= sprintf("?partNumber=%s&uploadId=%s", $query_params{partNumber}, $query_params{uploadId});
        }
        elsif($query_params{uploadId}){
            $buf .= sprintf("?uploadId=%s",$query_params{uploadId});
        }
    }

    return $buf;
}

# finds the hmac-sha1 hash of the canonical string and the aws secret access key and then
# base64 encodes the result (optionally urlencoding after that).
sub _encode {
    my ( $self, $aws_secret_access_key, $str, $urlencode ) = @_;
    my $hmac = Digest::HMAC_SHA1->new($aws_secret_access_key);
    $hmac->add($str);
    my $b64 = encode_base64( $hmac->digest, '' );
    if ($urlencode) {
        return $self->_urlencode($b64);
    } else {
        return $b64;
    }
}

# EU buckets must be accessed via their DNS name. This routine figures out if
# a given bucket name can be safely used as a DNS name.
sub _is_dns_bucket {
    my $bucketname = $_[0];

    if ( length $bucketname > 63 ) {
        return 0;
    }
    if ( length $bucketname < 3 ) {
        return;
    }
    return 0 unless $bucketname =~ m{^[a-z0-9][a-z0-9.-]+$};
    my @components = split /\./, $bucketname;
    for my $c (@components) {
        return 0 if $c =~ m{^-};
        return 0 if $c =~ m{-$};
        return 0 if $c eq '';
    }
    return 1;
}

# generates an HTTP::Headers objects given one hash that represents http
# headers to set and another hash that represents an object's metadata.
sub _merge_meta {
    my ( $self, $headers, $metadata ) = @_;
    $headers  ||= {};
    $metadata ||= {};

    my $http_header = HTTP::Headers->new;
    while ( my ( $k, $v ) = each %$headers ) {
        $http_header->header( $k => $v );
    }
    while ( my ( $k, $v ) = each %$metadata ) {
        $http_header->header( "$METADATA_PREFIX$k" => $v );
    }

    return $http_header;
}

sub _trim {
    my ( $self, $value ) = @_;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    return $value;
}

sub _urlencode {
    my ( $self, $unencoded ) = @_;
    return uri_escape_utf8( $unencoded, '^A-Za-z0-9_-' );
}

1;

__END__

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::HTTPRequest->new(
    s3      => $self->s3,
    method  => 'PUT',
    path    => $self->bucket . '/',
    headers => $headers,
    content => $content,
  )->http_request;

=head1 DESCRIPTION

This module creates an HTTP::Request object that is signed
appropriately for Amazon S3.

=head1 METHODS

=head2 http_request

This method creates, signs and returns a HTTP::Request object.

=head2 query_string_authentication_uri

This method creates, signs and returns a query string authentication
URI.
