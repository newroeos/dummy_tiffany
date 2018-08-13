PACKAGE = tiffanyBlue
DATE    ?= $(shell date +%FT%T%z)
VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
			cat $(CURDIR)/.version 2> /dev/null || echo v0)
GOPATH  = $(CURDIR)/.gopath
BIN		= $(GOPATH)/bin
DESTDIR = /opt/$(PACKAGE)
BASE    = $(GOPATH)/src/$(PACKAGE)

PKGS     = $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... 2>&1 | grep -v "^$(PACKAGE)/vendor/" | grep -v nocompile | grep -v logs))

#GOENV   = CGO_LDFLAGS_ALLOW='-fopenmp'
#GOENV   = CGO_ENABLED=0 GOOS=linux
GO      = go
GODOC   = godoc
#GOFMT   = goreturns
TIMEOUT = 15
V = 0
Q = $(if $(filter 1,$V),,@)
M = $(shell printf "\033[34;1m▶\033[0m")
GOV = $(shell $(GO) version)
SUDO = ""
ifneq ($(shell id -u -r),0)
SUDO = sudo
endif

BUILDTAG=-tags 'release'

.PHONY: all
all: vendor | $(BASE) ; $(info $(M) building executable… ) @ ## Build program binary
	$Q cd $(BASE) && $(GO) build -i \
		$(BUILDTAG) \
		-ldflags '-X main.Version=$(VERSION) -X main.BuildDate=$(DATE)' \
		-o $(BASE)/bin/$(PACKAGE)

.PHONY: docker
docker: ; $(info $(M) building docker image… ) @ ## Build for docker image
	$Q $(SUDO) docker build --cache-from eosdaq/$(PACKAGE):latest --build-arg VERSION=$(VERSION) --build-arg BUILD_DATE=$(DATE) -t eosdaq/$(PACKAGE) .


.PHONY: gobuild
gobuild: ; $(info $(M) building gobuild image… ) @ ## Build for gobuild image
	$Q $(SUDO) docker build --cache-from eosdaq/gobuild:latest -f Dockerfile_for_gobuild -t eosdaq/gobuild .

$(BASE): ; $(info $(M) setting GOPATH…)
	@mkdir -p $(dir $@)
	@ln -sf $(CURDIR) $@


# Tools

$(BIN):
	@mkdir -p $@
$(BIN)/%: $(BIN) | $(BASE) ; $(info $(M) building $(REPOSITORY)…)
	$Q tmp=$$(mktemp -d); \
		(GOPATH=$$tmp $(GO) get $(REPOSITORY) && cp $$tmp/bin/* $(BIN)/.) || ret=$$?; \
		rm -rf $$tmp ; exit $$ret

GODEP = $(BIN)/dep
$(BIN)/dep: | $(BASE) ; $(info $(M) building dep…)
	$Q $(GO) get github.com/golang/dep/cmd/dep

GOLINT = $(BIN)/golint
$(BIN)/golint: | $(BASE) ; $(info $(M) building golint…)
	$Q $(GO) get github.com/golang/lint/golint

GOFMT = $(BIN)/goreturns
$(BIN)/goreturns: | $(BASE) ; $(info $(M) building goreturns…)
	$Q $(GO) get github.com/sqs/goreturns

GOCOVMERGE = $(BIN)/gocovmerge
$(BIN)/gocovmerge: | $(BASE) ; $(info $(M) building gocovmerge…)
	$Q $(GO) get github.com/wadey/gocovmerge

GOCOV = $(BIN)/gocov
$(BIN)/gocov: | $(BASE) ; $(info $(M) building gocov…)
	$Q $(GO) get github.com/axw/gocov/...

GOCOVXML = $(BIN)/gocov-xml
$(BIN)/gocov-xml: | $(BASE) ; $(info $(M) building gocov-xml…)
	$Q $(GO) get github.com/AlekSi/gocov-xml

GO2XUNIT = $(BIN)/go2xunit
$(BIN)/go2xunit: | $(BASE) ; $(info $(M) building go2xunit…)
	$Q $(GO) get github.com/tebeka/go2xunit

GOSWAGGER = $(BIN)/swagger
$(BIN)/swagger: | $(BASE) ;  $(info $(M) building goswagger…)
	$Q $(GO) get github.com/go-swagger/go-swagger/cmd/swagger

GOCHECK = $(BIN)/megacheck
$(BIN)/megacheck: | $(BASE) ;  $(info $(M) building gocheck…)
	$Q $(GO) get honnef.co/go/tools/cmd/megacheck


# Tests

.PHONY: test
test: | $(BASE) ; $(info $(M) running go test…) @ ## Run go test on all source files
	$Q cd $(BASE) && ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... 2>&1 | grep -v /vendor/ | grep -v nocompile); do \
		cd $$d ; \
		$(GO) test -race -cover $(BUILDTAG) || ret=$$? ; \
		cd .. ; \
	 done ; exit $$ret

.PHONY: lint
lint: $(BASE) $(GOLINT) ; $(info $(M) running golint…) @ ## Run golint
	$Q cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GOLINT) $$pkg | tee /dev/stderr)" || ret=1 ; \
	 done ; exit $$ret

.PHONY: vet
vet: ; $(info $(M) running go vet…) @ ## Run go vet on all source files
	$Q cd $(BASE) && ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... 2>&1 | grep -v /vendor/ | grep -v nocompile); do \
		cd $$d ; \
		$(GO) vet $(BUILDTAG) || ret=$$? ; \
		cd .. ; \
	 done ; exit $$ret

.PHONY: fmt
fmt: $(GOFMT) ; $(info $(M) running gofmt…) @ ## Run gofmt on all source files
	@ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... 2>&1 | grep -v /vendor/ | grep -v nocompile); do \
		$(GOFMT) -l -w $$d/*.go || ret=$$? ; \
	 done ; exit $$ret

.PHONY: megacheck
megacheck: $(GOCHECK) ; $(info $(M) running gocheck…) @ ## Run gocheck on all source files
	$Q cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GOCHECK) $$pkg | tee /dev/stderr)" || ret=1 ; \
	 done ; exit $$ret


# Dependency management

.PHONY: swagger
swagger: $(GOSWAGGER) ; $(info $(M) generate swagger.json file…)
	$Q cd $(BASE)/api && $(GOSWAGGER) generate spec -o swagger.json

.PHONY: vendor-check
vendor-check: $(BASE) $(GODEP) ; $(info $(M) Gopkg.toml Gopkg.lock file…)
ifneq (,$(wildcard $(CURDIR)/Gopkg.toml))
	$(info $(M) no needs dep init…)
else
	$(info $(M) dep init…)
	$Q cd $(BASE) && $(GODEP) init
endif

vendor: vendor-check Gopkg.toml Gopkg.lock | $(BASE) $(GODEP) ; $(info $(M) $(GOV) retrieving dependencies…)
	$Q cd $(BASE) && $(GODEP) ensure
	@touch $@

.PHONY: vendor-update
vendor-update: vendor | $(BASE) $(GODEP)
ifeq "$(origin PKG)" "command line"
	$(info $(M) updating $(PKG) dependency…)
	$Q cd $(BASE) && $(GODEP) ensure -update $(PKG)
else
	$(info $(M) updating all dependencies…)
	$Q cd $(BASE) && $(GODEP) ensure -update
endif
	@touch vendor


# Misc

.PHONY: install
install: ; $(info $(M) installing…)	@
	@mkdir -p $(DESTDIR)
	@cp -fp bin/$(PACKAGE) $(DESTDIR)/.
	@cp -fp bin/logrotate $(DESTDIR)/$(PACKAGE)_logrotate
	@cp -fp bin/rsyslog.conf $(DESTDIR)/$(PACKAGE)_rsyslog.conf
	@cp -fp bin/service.template $(DESTDIR)/$(PACKAGE)_service.template
	@cp -fp conf/.env.json $(DESTDIR)/.env.json

.PHONY: clean
clean: ; $(info $(M) cleaning…)	@ ## Cleanup everything
	@rm -rf $(GOPATH)
	@rm -rf bin
	@rm -rf test/tests.* test/coverage.*

.PHONY: help
help:
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: version
version:
	@echo $(VERSION)
