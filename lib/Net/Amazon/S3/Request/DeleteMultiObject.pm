package Net::Amazon::S3::Request::DeleteMultiObject;
use Moose 0.85;

use Digest::MD5 qw/md5 md5_hex/;
use MIME::Base64;
use Carp qw/croak/;

extends 'Net::Amazon::S3::Request';

has 'bucket'    => ( is => 'ro', isa => 'BucketName', required => 1 );
has 'keys'      => ( is => 'ro', isa => 'ArrayRef',   required => 1 );

__PACKAGE__->meta->make_immutable;

sub http_request {
    my $self = shift;

    #croak if we get a request for over 1000 objects
    croak "The maximum number of keys is 1000"
        if (scalar(@{$self->keys}) > 1000);

    #build XML doc
    my $xml_doc = XML::LibXML::Document->new('1.0','UTF-8');
    my $root_element = $xml_doc->createElement('Delete');
    $xml_doc->addChild($root_element);
    $root_element->appendTextChild('Quiet'=>'true');
    #add content
    foreach my $key (@{$self->keys}){
        my $obj_element = $xml_doc->createElement('Object');
        $obj_element->appendTextChild('Key' => $key);
        $root_element->addChild($obj_element);
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
    return Net::Amazon::S3::HTTPRequest->new(
        s3      => $self->s3,
        method  => 'POST',
        path    => $self->bucket . '/?delete',
        content => $content,
        headers => $header_spec,
    )->http_request;
}

1;

__END__

# ABSTRACT: An internal class to delete multiple objects from a bucket

=for test_synopsis
no strict 'vars'

=head1 SYNOPSIS

  my $http_request = Net::Amazon::S3::Request::DeleteMultiObject->new(
    s3                  => $s3,
    bucket              => $bucket,
    keys                => [$key1, $key2],
  )->http_request;

=head1 DESCRIPTION

This module deletes multiple objects from a bucket.

=head1 METHODS

=head2 http_request

This method returns a HTTP::Request object.
