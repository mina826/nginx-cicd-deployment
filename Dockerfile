FROM nginx:alpine

ARG VERSION=dev
ARG COMMIT_SHA=unknown
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.title="nginx-cicd-demo"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIME}"

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY site/index.html /tmp/index.html
RUN nginx -t

RUN sed \
      -e "s|__VERSION__|${VERSION}|g" \
      -e "s|__COMMIT_SHA__|${COMMIT_SHA}|g" \
      -e "s|__BUILD_TIME__|${BUILD_TIME}|g" \
      /tmp/index.html \
      > /usr/share/nginx/html/index.html \
    && rm /tmp/index.html

HEALTHCHECK \
  --interval=10s \
  --timeout=3s \
  --start-period=5s \
  --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/health || exit 1
