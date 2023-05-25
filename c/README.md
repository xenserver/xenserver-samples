# libxenserver usage examples

## Dependencies

The examples need `libxenserver` which is dependent upon the
[XML toolkit](http://xmlsoft.org) from the GNOME project, by Daniel Veillard, et
al. This is packaged as `libxml2-devel` on CentOS and `libxml2-dev` on Debian.

The examples are dependent also upon [curl](http://curl.haxx.se), by Daniel
Stenberg, et al. It is packaged as `libcurl-devel` on CentOS and `libcurl3-dev`
on Debian. You may choose to use `curl` in your application, just as we have for
these test programs, though it is not required to do so, and you may use a
different network layer if you prefer.

## How to compile

Once you have installed libxenserver, run `make` in this folder.

To build on Windows with [cygwin](https://www.cygwin.com) run `make CYGWIN=1`.
(Remember that cygwin expects a libxenserver.dll, so ensure you have installed
the library by running `make install CYGWIN=1`).

To run any of the tests, for example the `test_vm_ops`, type:

```
./test_vm_ops <url> <sr-name> <username> <password>
```

The `<url>` should be of the form: https://hostname.domain/

You can obtain a suitable `<sr-name>` by running `xe sr-list` on the host.