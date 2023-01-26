# Copyright (c) Cloud Software Group, Inc.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   1) Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
#   2) Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.

ifeq ($(CYGWIN), 1)
	CYGWIN_LIBXML = -L/bin -lxml2-2
	CYGWIN_CURL = -L/bin -lcurl-4
	POS_FLAG = -U__STRICT_ANSI__
	XS_LDFLAG = -L/usr/local/lib -llibxenserver
else
	POS_FLAG = -fPIC
	XS_LDFLAG = -L . -lxenserver
endif

CFLAGS = -g -Iinclude \
	$(shell xml2-config --cflags) \
	$(shell curl-config --cflags) \
	-W -Wall -Wmissing-prototypes -Werror -std=c99 $(POS_FLAG) $(CYGWIN_CURL)

LDFLAGS = -g $(shell xml2-config --libs) \
	$(shell curl-config --libs) \
	-Wl,-rpath,$(shell pwd) $(CYGWIN_LIBXML) $(XS_LDFLAG)

SAMPLES = $(patsubst %.c, %, $(wildcard *.c))

%.o: %.c
	$(CC) -o $@ $<

%: %.o
	$(CC) -o $@ $< $(LDFLAGS)

build: $(SAMPLES)

clean:
	rm -f $(SAMPLES)
	rm -f `find -name *.o`

.PHONY: clean build
.DEFAULT_GOAL := build