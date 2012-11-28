package Net::Amazon::S3::Request::CompleteMultipartUpload;
use Moose 0.85;

use Digest::MD5 qw/md5 md5_hex/;
use MIME::Base64;
use Carp qw/croak/;
use XML::LibXML;

extends 'Net::Amazon::S3::Request';

has 'bucket'        => ( is => 'ro', isa => 'BucketName', required => 1 );
has 'etags'         => ( is => 'ro', isa => 'ArrayRef',   required => 1 );
has 'key'           => ( is => 'ro', isa => 'Str',        required => 1 );
has 'part_numbers'  => ( is => 'ro', isa => 'ArrayRef',   required => 1 );
has 'upload_id'     => ( is => 'ro', isa => 'Str',    required => 1 );

__PACKAGE__->meta->make_immutable;

sub http_request {
    my $self = shift;

    croak "must have an equally sized list of etags and part numbers"
        unless scalar(@{$self->part_numbers}) == scalar(@{$self->etags});

    #build XML doc
    my $xml_doc = XML::LibXML::Document->new('1.0','UTF-8');
    my $root_element = $xml_doc->createElement('CompleteMultipartUpload');
    $xml_doc->addChild($root_element);

    #add content
    for(my $i = 0; $i < scalar(@{$self->part_numbers}); $i++ ){
        my $part = $xml_doc->createElement('Part');
        $part->appendTextChild('PartNumber' => $self->part_numbers->[$i]);
        $part->appendTextChild('ETag' => $self->etags->[$i]);
        $root_element->addChild($part);
    }

    my $content = $xml_doc->toString;

    my $md5        = md5($content);

    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;

    my $header_spec = {
        'Content-MD5'    => $md5_base64,
        'Content-Length' => length $content,
        'Content-Type'   => 'application/xml'
    };

    #build signed request
    return Net::Amazon::S3::HTTPRequest->new( #See patch below
        s3      => $self->s3,
        method  => 'POST',
        path    => $self->_uri( $self->key ). '?uploadId='.$self->upload_id,
        content => $content,
        headers => $header_spec,
    )->http_request;
}

1;

__END__

# ABSTRACT: An internal class to complete a multipart upload

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::Request::CompleteMultipartUpload->new(
    s3                  => $s3,
    bucket              => $bucket,
    etags               => \@etags,
    part_numbers        => \@part_numbers,
  )->http_request;

=head1 DESCRIPTION

This module completes a multipart upload.

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.
