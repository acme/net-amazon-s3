package Net::Amazon::S3::Request::ListAllMyBuckets;
use Moose 0.85;
use MooseX::StrictConstructor 0.16;
extends 'Net::Amazon::S3::Request';

# ABSTRACT: An internal class to list all buckets

__PACKAGE__->meta->make_immutable;

sub http_request {
    my $self    = shift;
    return Net::Amazon::S3::HTTPRequest->new(
        s3     => $self->s3,
        method => 'GET',
        path   => '',
    )->http_request;
}

1;

__END__

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  my $http_request
    = Net::Amazon::S3::Request::ListAllMyBuckets->new( s3 => $s3 )
    ->http_request;

=head1 DESCRIPTION

This module lists all buckets.

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.

