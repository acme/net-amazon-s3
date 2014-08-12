package Net::Amazon::S3::Request::InitiateMultipartUpload;

use Moose 0.85;
use MooseX::StrictConstructor 0.16;
extends 'Net::Amazon::S3::Request';

has 'bucket'    => ( is => 'ro', isa => 'BucketName',      required => 1 );
has 'key'       => ( is => 'ro', isa => 'Str',             required => 1 );
has 'acl_short' => ( is => 'ro', isa => 'Maybe[AclShort]', required => 0 );
has 'headers' =>
    ( is => 'ro', isa => 'HashRef', required => 0, default => sub { {} } );

__PACKAGE__->meta->make_immutable;

sub http_request {
    my $self    = shift;
    my $headers = $self->headers;

    if ( $self->acl_short ) {
        $headers->{'x-amz-acl'} = $self->acl_short;
    }

    return Net::Amazon::S3::HTTPRequest->new(
        s3      => $self->s3,
        method  => 'POST',
        path    => $self->_uri( $self->key ).'?uploads',
        headers => $self->headers,
    )->http_request;
}

1;

__END__

#ABSTRACT: An internal class to begin a multipart upload

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::Request::InitiateMultipartUpload->new(
    s3                  => $s3,
    bucket              => $bucket,
    keys                => $key,
  )->http_request;

=head1 DESCRIPTION

This module begins a multipart upload

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.
