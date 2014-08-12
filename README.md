# DESCRIPTION

This module provides a Perlish interface to Amazon S3. From the
developer blurb: "Amazon S3 is storage for the Internet. It is designed
to make web-scale computing easier for developers. Amazon S3 provides a
simple web services interface that can be used to store and retrieve any
amount of data, at any time, from anywhere on the web. It gives any
developer access to the same highly scalable, reliable, fast,
inexpensive data storage infrastructure that Amazon uses to run its own
global network of web sites. The service aims to maximize benefits of
scale and to pass those benefits on to developers".

To find out more about S3, please visit: http://s3.amazonaws.com/

To use this module you will need to sign up to Amazon Web Services and
provide an "Access Key ID" and " Secret Access Key". If you use this
module, you will incurr costs as specified by Amazon. Please check the
costs. If you use this module with your Access Key ID and Secret Access
Key you must be responsible for these costs.

I highly recommend reading all about S3, but in a nutshell data is
stored in values. Values are referenced by keys, and keys are stored in
buckets. Bucket names are global.

Note: This is the legacy interface, please check out
Net::Amazon::S3::Client instead.

Development of this code happens here:
http://github.com/pfig/net-amazon-s3/

Homepage for the project (just started) is at
http://pfig.github.com/net-amazon-s3/

# LICENSE

This module contains code modified from Amazon that contains the
following notice:

> This software code is made available "AS IS" without warranties of any
> kind.  You may copy, display, modify and redistribute the software
> code either by itself or as incorporated into your code; provided that
> you do not remove any proprietary notices.  Your use of this software
> code is at your own risk and you waive any claim against Amazon
> Digital Services, Inc. or its affiliates with respect to your use of
> this software code. (c) 2006 Amazon Digital Services, Inc. or its
> affiliates.

# AUTHOR

* Leon Brocard <acme@astray.com> and unknown Amazon Digital Services programmers.

* Brad Fitzpatrick <brad@danga.com> - return values, Bucket object.

* Pedro Figueiredo <me@pedrofigueiredo.org> - since 0.54.
