FROM golang:1.10 AS builder

RUN apt-get update -y
RUN apt-get install -y ca-certificates
RUN apt-get upgrade -y ca-certificates
RUN update-ca-certificates

# Download and install the latest release of dep
RUN go get -u github.com/golang/dep/cmd/dep

ARG BUILD_PKG

# Copy the code from the host and compile it
WORKDIR $GOPATH/src/$BUILD_PKG
COPY . ./
RUN make vendor
RUN CGO_ENABLED=0 GOOS=linux go build -i -tags 'release' -a -installsuffix nocgo -o /$BUILD_PKG .

FROM alpine
ARG BUILD_PKG
ARG BUILD_PORT
COPY --from=builder /$BUILD_PKG ./
ENV PORT $BUILD_PORT
EXPOSE $BUILD_PORT
ENTRYPOINT ["/"$BUILD_PKG]
