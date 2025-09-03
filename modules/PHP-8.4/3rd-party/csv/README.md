# PHP CSV Extension

A small PHP extension to add/improve the handling of CSV strings which follows
[RFC 4180](https://tools.ietf.org/html/rfc4180)

> This extension is considered in an Alpha/Beta state and is subject to major
> changes between versions.

## Sponsor this project

Via [GitHub Sponsors](https://github.com/sponsors/Girgias)

## Requirement

PHP 8.0 is required as of version 0.4.0 of this extension due to the usage
of new Zend APIs.

## Functionality
This extension provides a `CSV` class which contains five static methods:

 - ``CSV::arrayToRow()``
 - ``CSV::rowToArray()``
 - ``CSV::collectionToBuffer()``
 - ``CSV::bufferToCollection()``
 - ``CSV::bufferToCollectionLax()``

They are inspired from the already existing ``fputcsv()`` and
``fgetcsv()`` functions.

These functions are binary safe (i.e. accept nul bytes) and accept multi-bytes
strings as the delimiter, enclosure, and the EOL sequence.

The reason for being able to set these three arguments is that it allows the
support of non ASCII compatible character encodings (e.g. UTF-16).
Indeed, it's possible to provide the multi-byte sequence for each of the
corresponding components such that it can treat a file in a different encoding
(or write to a file of different encoding).

```php
function CSV::arrayToRow(array $fields, string $delimiter = ',', string $enclosure = '"', string $eolSequence = "\r\n"): string
```
Formats a CSV row with the given delimiter, enclosure (the field escape
sequence), and the EOL sequence.

```php
function CSV::collectionToBuffer(iterable $collection, string $delimiter = ',', string $enclosure = '"', string $eolSequence = "\r\n"): string
```
Formats a collection (an iterable of arrays) into valid RFC 4180 CSV buffer
which can be written to a file.
It checks that each subarray has the same number of fields as the
previous ones. If not it throws a ``ValueError``.

```php
function CSV::rowToArray(string $row, string $delimiter = ',', string $enclosure = '"', string $eolSequence = "\r\n"): array
```
Returns an array containing the fields provided from the ``$row`` string.
This string should follow RFC 4180.

```php
function CSV::bufferToCollection(string $buffer, string $delimiter = ',', string $enclosure = '"', string $eolSequence = "\r\n"): array
```
Returns a collection (an array of arrays) containing the fields of each row
from the string ``$buffer``. This buffer should follow RFC 4180.
This function will check that each row has the same number of fields, if not
it will throw a ``ValueError`` indicating the offending line.

If parsing of a buffer with possible differing number of fields, and an error
is not suitable, the ``CSV::bufferToCollectionLax()`` method can be used
instead.

## Future scope

Improvements and feature requests can be proposed on the GitLab issue tracker.

The plan is to propose an RFC and add this extension to the core of PHP with
a timeline on deprecating the non-compliant ``str_getcsv()``, ``fputcsv()``,
and ``fgetcsv()`` functions.

## Bug reports

To report a bug, please provide a reproducible test script, in preference as a
PHPT test file and open an issue on Gitlab at
https://gitlab.com/Girgias/csv-php-extension/issues

For security issues please email me directly at <girgias@php.net>
