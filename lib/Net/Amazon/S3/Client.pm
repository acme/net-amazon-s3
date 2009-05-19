package Net::Amazon::S3::Client;
use Moose;
use HTTP::Status qw(is_error status_message);
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;

type 'Etag' => where { $_ =~ /^[a-z0-9]{32}$/ };

type 'OwnerId' => where { $_ =~ /^[a-z0-9]{64}$/ };

has 's3' => ( is => 'ro', isa => 'Net::Amazon::S3', required => 1 );

__PACKAGE__->meta->make_immutable;

sub buckets {
    my $self = shift;
    my $s3   = $self->s3;

    my $http_request
        = Net::Amazon::S3::Request::ListAllMyBuckets->new( s3 => $s3 )
        ->http_request;

    my $xpc = $self->_send_request_xpc($http_request);

    my $owner_id
        = $xpc->findvalue('/s3:ListAllMyBucketsResult/s3:Owner/s3:ID');
    my $owner_display_name = $xpc->findvalue(
        '/s3:ListAllMyBucketsResult/s3:Owner/s3:DisplayName');

    my @buckets;
    foreach my $node (
        $xpc->findnodes('/s3:ListAllMyBucketsResult/s3:Buckets/s3:Bucket') )
    {
        push @buckets,
            Net::Amazon::S3::Client::Bucket->new(
            {   client => $self,
                name   => $xpc->findvalue( './s3:Name', $node ),
                creation_date =>
                    $xpc->findvalue( './s3:CreationDate', $node ),
                owner_id           => $owner_id,
                owner_display_name => $owner_display_name,
            }
            );

    }
    return @buckets;
}

sub create_bucket {
    my ( $self, %conf ) = @_;

    my $bucket = Net::Amazon::S3::Client::Bucket->new(
        client => $self,
        name   => $conf{name},
    );
    $bucket->_create(
        acl_short           => $conf{acl_short},
        location_constraint => $conf{location_constraint},
    );
    return $bucket;
}

sub bucket {
    my ( $self, %conf ) = @_;
    return Net::Amazon::S3::Client::Bucket->new(
        client => $self,
        %conf,
    );
}

sub _send_request {
    my ( $self, $http_request, $filename ) = @_;

    my $http_response = $self->s3->ua->request( $http_request, $filename );

    my $content      = $http_response->content;
    my $content_type = $http_response->content_type;
    my $code         = $http_response->code;

    if ( is_error($code) ) {
        if ( $content_type eq 'application/xml' ) {
            my $doc = $self->s3->libxml->parse_string($content);
            my $xpc = XML::LibXML::XPathContext->new($doc);
            $xpc->registerNs( 's3',
                'http://s3.amazonaws.com/doc/2006-03-01/' );

            if ( $xpc->findnodes('/Error') ) {
                my $code    = $xpc->findvalue('/Error/Code');
                my $message = $xpc->findvalue('/Error/Message');
                confess("$code: $message");
            } else {
                confess status_message($code);
            }
        } else {
            confess status_message($code);
        }
    }
    return $http_response;
}

sub _send_request_content {
    my ( $self, $http_request, $filename ) = @_;
    my $http_response = $self->_send_request( $http_request, $filename );
    return $http_response->content;
}

sub _send_request_xpc {
    my ( $self, $http_request, $filename ) = @_;
    my $http_response = $self->_send_request( $http_request, $filename );

    my $doc = $self->s3->libxml->parse_string( $http_response->content );
    my $xpc = XML::LibXML::XPathContext->new($doc);
    $xpc->registerNs( 's3', 'http://s3.amazonaws.com/doc/2006-03-01/' );

    return $xpc;
}

1;

__END__

=head1 NAME

Net::Amazon::S3::Client - An easy-to-use Amazon S3 client

=head1 SYNOPSIS

  my $s3 = Net::Amazon::S3->new(
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    retry                 => 1,
  );
  my $client = Net::Amazon::S3::Client->new( s3 => $s3 );

  # list all my buckets
  # returns a list of L<Net::Amazon::S3::Client::Bucket> objects
  my @buckets = $client->buckets;
  foreach my $bucket (@buckets) {
    print $bucket->name . "\n";
  }

  # create a new bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->create_bucket(
    name                => $bucket_name,
    acl_short           => 'private',
    location_constraint => 'US',
  );

  # or use an existing bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->bucket( name => $bucket_name );

=head1 DESCRIPTION

The L<Net::Amazon::S3> module was written when the Amazon S3 service
had just come out and it is a light wrapper around the APIs. Some
bad API decisions were also made. The 
L<Net::Amazon::S3::Client>, L<Net::Amazon::S3::Client::Bucket> and 
L<Net::Amazon::S3::Client::Object> classes are designed after years
of usage to be easy to use for common tasks.

These classes throw an exception when a fatal error occurs. It
also is very careful to pass an MD5 of the content when uploaded
to S3 and check the resultant ETag.

WARNING: This is an early release of the Client classes, the APIs
may change.

=head1 METHODS

=head2 buckets

  # list all my buckets
  # returns a list of L<Net::Amazon::S3::Client::Bucket> objects
  my @buckets = $client->buckets;
  foreach my $bucket (@buckets) {
    print $bucket->name . "\n";
  }

=head2 create_bucket

  # create a new bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->create_bucket(
    name                => $bucket_name,
    acl_short           => 'private',
    location_constraint => 'US',
  );

=head2 bucket

  # or use an existing bucket
  # returns a L<Net::Amazon::S3::Client::Bucket> object
  my $bucket = $client->bucket( name => $bucket_name );

