package Net::Amazon::S3::Request::PutObject;
use Moose;
use MooseX::StrictConstructor;
extends 'Net::Amazon::S3::Request';

has 'bucket'    => ( is => 'ro', isa => 'BucketName',      required => 1 );
has 'key'       => ( is => 'ro', isa => 'Str',             required => 1 );
has 'value'     => ( is => 'ro', isa => 'Str|CodeRef',     required => 1 );
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
        method  => 'PUT',
        path    => $self->_uri( $self->key ),
        headers => $self->headers,
        content => $self->value,
    )->http_request;
}

1;

__END__

=head1 NAME

Net::Amazon::S3::Request::PutObject - An internal class to put an object

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::Request::PutObject->new(
    s3        => $s3,
    bucket    => $bucket,
    key       => $key,
    value     => $value,
    acl_short => $acl_short,
    headers   => $conf,
  )->http_request;

=head1 DESCRIPTION

This module puts an object.

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.

