# docker build --build-arg BASE_IMAGE_TAG=${BASE_IMAGE_TAG}
ARG BASE_IMAGE_TAG

FROM wodby/drupal-php:${BASE_IMAGE_TAG}

USER root
RUN composer self-update 1.10.1
RUN wget -qP / 'https://storage.googleapis.com/ewise-public-files/gke/cloud_sql_proxy'
COPY --chown=wodby:wodby gke/cron.sh gke/buildscript.sh /app/gke/
RUN crontab -l | { cat; echo "*/15       *       *       *       *       /app/gke/cron.sh"; } | crontab -

USER wodby
WORKDIR /app
COPY composer.* scripts patches /app/
RUN gke/buildscript.sh
COPY . /app/
RUN composer dump-autoload --no-scripts --optimize