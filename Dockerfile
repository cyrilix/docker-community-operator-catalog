FROM --platform=$BUILDPLATFORM golang:1.15-alpine AS builder-git

ARG BUILDPLATFORM

RUN apk add -U git





FROM --platform=$BUILDPLATFORM quay.io/operator-framework/upstream-registry-builder:v1.13.3 as builder-bundles

ARG BUILDPLATFORM
ARG PERMISSIVE_LOAD=true

WORKDIR /opt
RUN git clone https://github.com/operator-framework/community-operators.git

WORKDIR /opt/community-operators

RUN cp -r upstream-community-operators manifests
RUN if [ $PERMISSIVE_LOAD = "true" ] ; then /bin/initializer --permissive -o ./bundles.db ; else /bin/initializer -o ./bundles.db ; fi





FROM --platform=$BUILDPLATFORM builder-git AS builder-registry-server-src

ARG version="v1.15.3"

ARG BUILDPLATFORM

WORKDIR /opt
RUN git clone https://github.com/operator-framework/operator-registry.git
WORKDIR /opt/operator-registry
RUN git checkout ${version}





FROM --platform=$BUILDPLATFORM builder-registry-server-src AS builder-registry-server

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN GOOS=$(echo $TARGETPLATFORM | cut -f1 -d/) && \
    GOARCH=$(echo $TARGETPLATFORM | cut -f2 -d/) && \
    GOARM=$(echo $TARGETPLATFORM | cut -f3 -d/ | sed "s/v//" ) && \
    CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} GOARM=${GOARM} go build -mod=vendor -v -ldflags '-w -extldflags "-static"' -tags "json1" ./cmd/registry-server




FROM --platform=$BUILDPLATFORM builder-git AS builder-grpc-health-probe-src

ARG version="v0.3.5"

ARG BUILDPLATFORM

WORKDIR /opt
RUN git clone https://github.com/grpc-ecosystem/grpc-health-probe.git
WORKDIR /opt/grpc-health-probe
RUN git checkout ${version}



FROM --platform=$BUILDPLATFORM builder-grpc-health-probe-src AS builder-grpc-health-probe

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN GOOS=$(echo $TARGETPLATFORM | cut -f1 -d/) && \
    GOARCH=$(echo $TARGETPLATFORM | cut -f2 -d/) && \
    GOARM=$(echo $TARGETPLATFORM | cut -f3 -d/ | sed "s/v//" ) && \
    CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} GOARM=${GOARM} go build -v -a -tags netgo -ldflags=-w -o grpc_health_probe




FROM scratch
COPY --from=builder-bundles /opt/community-operators/bundles.db /bundles.db
COPY --from=builder-registry-server /opt/operator-registry/registry-server /registry-server
COPY --from=builder-grpc-health-probe /opt/grpc-health-probe/grpc_health_probe /bin/grpc_health_probe
EXPOSE 50051
ENTRYPOINT ["/registry-server"]
CMD ["--database", "/bundles.db"]
