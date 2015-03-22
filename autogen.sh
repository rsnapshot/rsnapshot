#!/bin/sh -x

aclocal
autoconf
automake --add-missing --copy
