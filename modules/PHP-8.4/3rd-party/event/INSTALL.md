INSTALLATION OF EVENT PECL EXTENSION
====================================

Tested exclusively on Linux, but it is probable that it will function on other
platforms as well. The information provided here pertains specifically to
Linux. If you discover the need to share instructions for alternative
platforms, kindly inform me.

PRELIMINARIES
-------------

The event extension supports libevent version 2.0 and later. It requires the
installation of at least the `libevent_core.so` library. For additional
functions, the `libevent_extra.so` library is also necessary. However, starting
from libevent 2.0, both libraries should be included with the libevent
distribution.

Note that `libevent.so` is a deprecated library that has been split into two
separate libraries: `libevent_core.so` and `libevent_extra.so`. Therefore, using
`libevent.so` is unreliable, as this file may be discontinued in future releases.

Many operating system distributions include the `libevent` package in their
repositories. For instance, here's how it can be installed on some commonly used
distributions:

- Debian-based (e.g. Ubuntu): `apt-get install libevent libevent-dev`
- OpenSUSE: `zypper in libevent libevent-devel`
- RHEL/Fedora: `dnf install libevent libevent-devel`
- Gentoo: `USE=ssl emerge dev-libs/libevent`

Libevent can also be compiled from source, and the source code is available its
[homepage](http://libevent.org/).

AUTOMATIC INSTALLATION
----------------------

Run the following as `root`:

```
pecl install package.xml
```


MANUAL INSTALLATION
-------------------

Clone the project or download it as archive. In the package directory run:

```
phpize
./configure --with-event-core --with-event-extra
make
```
(Run `./configure --help` for more options.)

Optionally, run tests:

```
make test
```

Install the compiled files on behalf of the `root` user:

```
make install
```

## NOTES

The methods of the Event extension accept various types of resources that
contain a file descriptor: a castable PHP stream, a socket resource, or simply a
number representing the file descriptor itself. If you don't have the 'sockets'
extension installed, or if you don't plan to use the standard PHP sockets, you
can configure Event with the `--disable-event-sockets` option. Alternatively,
choose 'n' (No) when the PEAR installer asks whether 'sockets' support is
required.


FINALLY
-------

In the `php.ini` file, or an included configuration file like
`/usr/local/etc/php/conf.d/999-event.ini`, add the following:

```
extension=event.so
```
