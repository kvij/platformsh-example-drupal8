# docker build --build-arg BASE_IMAGE_TAG=${BASE_IMAGE_TAG}
ARG BASE_IMAGE_TAG

FROM wodby/drupal-php:${BASE_IMAGE_TAG}

USER root
RUN composer self-update 1.10.1
COPY --chown=wodby:wodby . /app
RUN crontab -l | { cat; echo "*/15       *       *       *       *       /app/cron.sh"; } | crontab -
USER wodby
WORKDIR /app
RUN gke/buildscript.sh