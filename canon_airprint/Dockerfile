ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm
FROM ${BUILD_FROM}

ENV DEBIAN_FRONTEND=noninteractive

# CUPS, AirPrint announcements (Avahi), filters, and the libraries Canon's
# UFRII LT driver needs. The Canon driver itself is NOT included here: its
# license forbids redistribution, so the add-on downloads it on first start.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        cups cups-client cups-bsd cups-filters cups-ipp-utils \
        avahi-daemon avahi-utils libnss-mdns dbus \
        ghostscript poppler-utils \
        libxml2 libjbig0 libglib2.0-0 libgtk2.0-0 libcups2 libcupsimage2 \
        curl ca-certificates jq tar gzip procps iproute2 gawk snmp \
    && rm -rf /var/lib/apt/lists/*

COPY cupsd.conf /etc/cups/cupsd.conf
COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY trim_ppd.awk /trim_ppd.awk
COPY run.sh /run.sh
COPY status.sh /status.sh
COPY print_job.sh /print_job.sh
COPY make_attrs.sh /make_attrs.sh
RUN chmod a+x /run.sh /status.sh /print_job.sh /make_attrs.sh

CMD [ "/run.sh" ]
