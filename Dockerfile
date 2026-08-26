FROM golang:1-alpine AS builder

ARG HYSTERIA_REPOSITORY=https://github.com/HyNetworks/hysteria.git
ARG HYSTERIA_COMMIT
ARG HYSTERIA_RELEASE

RUN apk add --no-cache bash build-base git python3
RUN test -n "${HYSTERIA_COMMIT}" && test -n "${HYSTERIA_RELEASE}" && \
    git init /src && \
    git -C /src remote add origin "${HYSTERIA_REPOSITORY}" && \
    git -C /src fetch --depth 1 origin \
      "refs/tags/${HYSTERIA_RELEASE}:refs/tags/${HYSTERIA_RELEASE}" && \
    git -C /src checkout --detach "${HYSTERIA_COMMIT}" && \
    test "$(git -C /src rev-parse HEAD)" = "${HYSTERIA_COMMIT}"
WORKDIR /src
RUN python3 hyperbole.py build -r && \
    mv ./build/hysteria-* /usr/local/bin/hysteria

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /usr/local/bin/hysteria /usr/local/bin/hysteria
ENTRYPOINT ["/usr/local/bin/hysteria"]
