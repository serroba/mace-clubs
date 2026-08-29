# Feasibility image for running the Garmin BDD e2e suite headlessly on
# Linux instead of the macOS-only driver in tools/e2e/simulator.ts.
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
    && rm -rf /var/lib/apt/lists/*
