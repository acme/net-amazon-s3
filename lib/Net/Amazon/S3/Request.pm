package Net::Amazon::S3::Request;
use Moose;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;
use Regexp::Common qw /net/;

enum 'AclShort' =>
    qw(private public-read public-read-write authenticated-read);
enum 'LocationConstraint' => ( 'US', 'EU' );

# To comply with Amazon S3 requirements, bucket names must:
# Contain lowercase letters, numbers, periods (.), underscores (_), and dashes (-)
# Start with a number or letter
# Be between 3 and 255 characters long
# Not be in an IP address style (e.g., "192.168.5.4")

subtype 'BucketName1' => as 'Str' => where {
    $_ =~ /^[a-zA-Z0-9._-]+$/;
} => message {
    "Bucket name ($_) must contain lowercase letters, numbers, periods (.), underscores (_), and dashes (-)";
};

subtype 'BucketName2' => as 'BucketName1' => where {
    $_ =~ /^[a-zA-Z0-9]/;
} => message {
    "Bucket name ($_) must start with a number or letter";
};

subtype 'BucketName3' => as 'BucketName2' => where {
    length($_) >= 3 && length($_) <= 255;
} => message {
    "Bucket name ($_) must be between 3 and 255 characters long";
};

subtype 'BucketName' => as 'BucketName3' => where {
    $_ !~ /^$RE{net}{IPv4}$/;
} => message {
    "Bucket name ($_) must not be in an IP address style (e.g., '192.168.5.4')";
};

has 's3' => ( is => 'ro', isa => 'Net::Amazon::S3', required => 1 );

__PACKAGE__->meta->make_immutable;

sub _uri {
    my ( $self, $key ) = @_;
    return ($key)
        ? $self->bucket . "/" . $self->s3->_urlencode($key)
        : $self->bucket . "/";
}

1;

__END__

=head1 NAME

Net::Amazon::S3::Request - Base class for request objects

=head1 SYNOPSIS

  # do not instantiate directly

=head1 DESCRIPTION

This module is a base class for all the Net::Amazon::S3::Request::*
classes.
