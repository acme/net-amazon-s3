#!perl
use strict;
use warnings;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'Net::Amazon::S3',
    VERSION_FROM => 'lib/Net/Amazon/S3.pm',
    AUTHOR       => 'Pedro Figueiredo <me@pedrofigueiredo.org>',
    ABSTRACT     => 'Use the Amazon S3 - Simple Storage Service',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'Class::MOP'                 => '0.88',
        'Data::Stream::Bulk'         => '0.06',
        'DateTime::Format::HTTP'     => '0',
        'DateTime::Format::ISO8601'  => '0',
        'Digest::HMAC_SHA1'          => '0',
        'Digest::MD5'                => '0',
        'Digest::MD5::File'          => '0',
        'File::stat'                 => '0',
        'HTTP::Date'                 => '0',
        'HTTP::Status'               => '0',
        'IO::File'                   => '1.14',
        'LWP::UserAgent::Determined' => '0',
        'MIME::Base64'               => '0',
        'Moose'                      => '0.85',
        'MooseX::StrictConstructor'  => '0.16',
        'Test::More'                 => '0.01',
        'Regexp::Common'             => '0',
        'XML::LibXML'                => '0',
        'XML::LibXML::XPathContext'  => '0',
        'URI::Escape'                => '0',
        'MooseX::Types::DateTime::MoreCoercions' => '0.07',
    }
);

