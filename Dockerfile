#
# Pareto event consumer that publishes to MQTT and/or Elasticsearch
#
# http://github.com/tenstartups/pareto-event-router
#

FROM tenstartups/alpine:latest

LABEL maintainer="Marc Lennox <marc.lennox@gmail.com>"

# Set environment variables.
ENV \
  RUBYLIB=/usr/local/lib/ruby \
  PAGER=more

# Install packages.
RUN \
  apk --update add \
    build-base \
    git \
    libxml2-dev \
    libxslt-dev \
    ruby \
    ruby-bigdecimal \
    ruby-bundler \
    ruby-dev \
    ruby-irb \
    ruby-io-console \
    ruby-json \
    zlib-dev && \
  rm -rf /var/cache/apk/*

# Install gems.
RUN \
  gem install --no-document \
    activesupport \
    awesome_print \
    bunny \
    colorize \
    elasticsearch \
    mqtt \
    pry \
    socket.io-client-simple \
    typhoeus \
    uuidtools

# Add files to the container.
COPY lib ${RUBYLIB}
COPY entrypoint.rb /docker-entrypoint

# Set the entrypoint script.
ENTRYPOINT ["/docker-entrypoint"]
