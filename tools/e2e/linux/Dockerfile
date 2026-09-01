# Image for running the Garmin BDD e2e suite headlessly on
# Linux (see tools/e2e/platform-linux.ts and README.md in this directory).
#
# Contains no Garmin SDK content of its own: the base image supplies
# monkeyc/monkeydo/simulator, the device files, and - since v2.10.0 - the
# device FONTS, without which the simulator draws nothing and OCR has
# nothing to read. This layer only adds open-source packages on top.
#
# The fonts arriving upstream is what removed the need to mount a locally
# licensed copy, and with it the need for Garmin credentials in CI. That is
# matco's call to make as the image's publisher; this repo only consumes it.
#
# Pinned rather than :latest. The font change landed in a floating tag and
# would have reached CI unannounced, which is a good argument either way but
# a better one for knowing which image a green run was green on.
FROM ghcr.io/matco/connectiq-tester:v2.10.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        xdotool \
        imagemagick \
        tesseract-ocr \
        openbox \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node 22+ for the e2e driver itself (tools/e2e/*.ts, run with
# --experimental-strip-types). The base image has no Node at all - it was
# only ever meant to compile and unit-test Monkey C.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
