package Net::Amazon::S3::Request::GetBucketLocationConstraint;
use Moose;
use MooseX::StrictConstructor;
extends 'Net::Amazon::S3::Request';

has 'bucket' => ( is => 'ro', isa => 'BucketName', required => 1 );

__PACKAGE__->meta->make_immutable;

sub http_request {
    my $self = shift;

    return Net::Amazon::S3::HTTPRequest->new(
        s3     => $self->s3,
        method => 'GET',
        path   => $self->_uri('') . '?location',
    )->http_request;
}

1;

__END__

=head1 NAME

Net::Amazon::S3::Request::GetBucketLocationConstraint - An internal class to get a bucket's location constraint

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::Request::GetBucketLocationConstraint->new(
    s3     => $s3,
    bucket => $bucket,
  )->http_request;

=head1 DESCRIPTION

This module gets a bucket's location constraint.

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.

