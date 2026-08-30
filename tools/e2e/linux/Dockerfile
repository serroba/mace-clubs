# Image for running the Garmin BDD e2e suite headlessly on
# Linux (see tools/e2e/platform-linux.ts and README.md in this directory).
#
# Deliberately contains NO Garmin SDK content of its own - the base image
# already bundles monkeyc/monkeydo/simulator/device files (a pre-existing
# choice from this repo's CI, not introduced here), and this layer only
# adds open-source packages on top of it. Garmin's Connect IQ SDK EULA
# ("No Other Permitted Uses") forbids redistributing the SDK, in whole or
# in part - so device FONTS (needed for any real on-screen text, which is
# what makes OCR possible) are deliberately NOT copied into this image.
# Mount them read-only at `docker run` time from a locally-licensed SDK
# install instead - see README.md in this directory.
FROM ghcr.io/matco/connectiq-tester:latest

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
