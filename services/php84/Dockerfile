ARG PHP_VERSION
FROM ${PHP_VERSION}

ARG TZ
ARG PHP_EXTENSIONS
ARG CONTAINER_PACKAGE_URL

ENV TZ=${TZ}

# Set alpine mirror
RUN if [ "${CONTAINER_PACKAGE_URL}" != "" ] ; then \
        sed -i "s/dl-cdn.alpinelinux.org/${CONTAINER_PACKAGE_URL}/g" /etc/apk/repositories; \
    fi

# Install required packages
RUN apk --no-cache add tzdata curl \
    && cp "/usr/share/zoneinfo/$TZ" /etc/localtime \
    && echo "$TZ" > /etc/timezone

# Install PHP extensions
RUN curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions $(echo $PHP_EXTENSIONS | tr ',' ' ')

# Install composer and change its cache home
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
ENV COMPOSER_HOME=/tmp/composer

# DIY Install
RUN apk --no-cache add git

# Set work directory
WORKDIR /www
