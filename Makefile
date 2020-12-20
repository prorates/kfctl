# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
GCLOUD_PROJECT       ?= kubeflow-images-public
GOLANG_VERSION       ?= 1.15.6
GOPATH               ?= $(HOME)/go
KFCTL_IMG            ?= gcr.io/$(GCLOUD_PROJECT)/kfctl
TAG                  ?= $(eval TAG := $(shell git describe --tags --long --always))$(TAG)
REPO                 ?= $(shell echo $$(cd ../kubeflow && git config --get remote.origin.url) | sed 's/git@\(.*\):\(.*\).git$$/https:\/\/\1\/\2/')
BRANCH               ?= $(shell cd ../kubeflow && git branch | grep '^*' | awk '{print $$2}')
KFCTL_TARGET         ?= kfctl
MOUNT_KUBE           ?=  -v $(HOME)/.kube:/root/.kube
MOUNT_GCP            ?=  -v $(HOME)/.config:/root/.config
# set to -V
VERBOSE              ?=
PLUGINS_ENVIRONMENT  ?= $(GOPATH)/src/github.com/kubeflow/kfctl/bin
export GO111MODULE = on
export GO = go
ARCH                 ?= $(shell ${GO} env|grep GOOS|cut -d'=' -f2|tr -d '"')
OPERATOR_IMG         ?= kubeflow-operator
IMAGE_BUILDER        ?= docker
DOCKERFILE           ?= Dockerfile
DOCKER_BUILD_OPTS    ?= --network=host
OPERATOR_BINARY_NAME ?= $(shell basename ${PWD})

BINDIR               := bin
TOOLS_DIR            := tools
TOOLS_BIN_DIR        := $(TOOLS_DIR)/bin

# Binaries.
DEEPCOPY_GEN         := $(TOOLS_BIN_DIR)/deepcopy-gen
CONTROLLER_GEN       := $(TOOLS_BIN_DIR)/controller-gen
GOLANGCI_LINT        := $(TOOLS_BIN_DIR)/golangci-lint
KIND                 := $(TOOLS_BIN_DIR)/kind

# Location of junit file
JUNIT_FILE ?= /tmp/report.xml

%.so:
	cd cmd/plugins/$* && \
	${GO} build -i -gcflags '-N -l' -o ../../../bin/$*.so -buildmode=plugin $*.go

%.init:
	@echo kfctl init test/$* $(VERBOSE) --platform $* --project $(GCLOUD_PROJECT) --version master && \
	PLUGINS_ENVIRONMENT=$(PLUGINS_ENVIRONMENT) kfctl init $(PWD)/test/$* $(VERBOSE) --platform $* --project $(GCLOUD_PROJECT) --version master

%.init-no-platform:
	@echo kfctl init test/$* $(VERBOSE) --version master && \
	kfctl init $(PWD)/test/$* $(VERBOSE) --version master

%.generate:
	@echo kfctl generate all $(VERBOSE) '(--platform '$*')' && \
	cd test/$* && \
	PLUGINS_ENVIRONMENT=$(PLUGINS_ENVIRONMENT) kfctl generate all $(VERBOSE) --mount-local --email gcp-deploy@$(GCLOUD_PROJECT).iam.gserviceaccount.com

%.md:

all: build

auth:
	gcloud auth configure-docker

# Run go fmt against code
fmt:
	@${GO} fmt ./config ./cmd/... ./pkg/...

# Run go vet against code
vet:
	@${GO} vet ./config ./cmd/... ./pkg/...

generate:
	@${GO} generate ./config ./pkg/apis/apps/kfdef/... ./pkg/utils/... ./pkg/kfapp/minikube ./pkg/kfapp/gcp/... ./cmd/kfctl/...

## --------------------------------------
## Tooling Binaries
## --------------------------------------

$(DEEPCOPY_GEN): $(TOOLS_DIR)/go.mod # Build deepcopy-gen from tools folder.
	cd $(TOOLS_DIR); go build -tags=tools -o $(BINDIR)/deepcopy-gen k8s.io/code-generator/cmd/deepcopy-gen

$(CONTROLLER_GEN): $(TOOLS_DIR)/go.mod # Build controller-gen from tools folder.
	cd $(TOOLS_DIR); go build -tags=tools -o $(BINDIR)/controller-gen sigs.k8s.io/controller-tools/cmd/controller-gen

$(GOLANGCI_LINT): $(TOOLS_DIR)/go.mod # Build golangci-lint from tools folder.
	cd $(TOOLS_DIR); go build -tags=tools -o $(BINDIR)/golangci-lint github.com/golangci/golangci-lint/cmd/golangci-lint

$(KIND): $(TOOLS_DIR)/go.mod # Build kind from tools folder.
	cd $(TOOLS_DIR); go build -tags=tools -o $(BINDIR)/kind sigs.k8s.io/kind

.PHONY: install-tools
install-tools: $(DEEPCOPY_GEN) $(CONTROLLER_GEN) $(GOLANGCI_LINT) $(KIND)

## --------------------------------------
## Generate
## --------------------------------------

# ${GOPATH}/bin/deepcopy-gen -h hack/boilerplate.go.txt -i github.com/kubeflow/kfctl/v3/config -O zz_generated.deepcopy \

.PHONY: deepcopy
deepcopy: $(CONTROLLER_GEN)
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./config output:object:dir=./config output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/kfupgrade/v1alpha1 output:object:dir=./pkg/apis/apps/kfupgrade/v1alpha1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/kfconfig output:object:dir=./pkg/apis/apps/kfconfig output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/kfdef/v1alpha1 output:object:dir=./pkg/apis/apps/kfdef/v1alpha1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/kfdef/v1beta1 output:object:dir=./pkg/apis/apps/kfdef/v1beta1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/kfdef/v1 output:object:dir=./pkg/apis/apps/kfdef/v1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/plugins/aws/v1alpha1 output:object:dir=./pkg/apis/apps/plugins/aws/v1alpha1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/apps/plugins/gcp/v1alpha1 output:object:dir=./pkg/apis/apps/plugins/gcp/v1alpha1 output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/kfconfig output:object:dir=./pkg/kfconfig output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/kfconfig/awsplugin output:object:dir=./pkg/kfconfig/awsplugin output:none
	GO111MODULE=on $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/kfconfig/gcpplugin output:object:dir=./pkg/kfconfig/gcpplugin output:none

build: build-kfctl

build-kfctl: deepcopy fmt vet
	# TODO(swiftdiaries): figure out import conflict errors for windows
	#CGO_ENABLED=0 GOOS=windows GOARCH=amd64 ${GO} build -gcflags '-N -l' -ldflags "-X main.VERSION=$(TAG)" -o bin/windows/kfctl.exe cmd/kfctl/main.go
	#CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 ${GO} build -gcflags '-N -l' -ldflags "-X main.VERSION=${TAG}" -o bin/darwin/kfctl cmd/kfctl/main.go
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 ${GO} build -gcflags '-N -l' -ldflags "-X main.VERSION=$(TAG)" -o bin/linux/kfctl cmd/kfctl/main.go
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 ${GO} build -gcflags '-N -l' -ldflags "-X main.VERSION=$(TAG)" -o bin/arm64/kfctl cmd/kfctl/main.go
	cp bin/$(ARCH)/kfctl bin/kfctl

# Fast rebuilds useful for development.
# Does not regenerate code; assumes you already ran build-kfctl once.
build-kfctl-fast: fmt vet
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 ${GO} build -gcflags '-N -l' -ldflags "-X main.VERSION=$(TAG)" -o bin/linux/kfctl cmd/kfctl/main.go

# Release tarballs suitable for upload to GitHub release pages
build-kfctl-tgz: build-kfctl
	chmod a+rx ./bin/kfctl
	rm -f bin/*.tgz
	cd bin/linux && tar -cvzf kfctl_$(TAG)_linux.tar.gz ./kfctl
	cd bin/darwin && tar -cvzf kfctl_${TAG}_darwin.tar.gz ./kfctl
	cd bin/arm64 && tar -cvzf kfctl_${TAG}_arm64.tar.gz ./kfctl

build-and-push-operator: build-operator push-operator
build-push-update-operator: build-operator push-operator update-operator-image

# Build operator image
build-operator:
	go mod vendor
	# Fix duplicated logrus library (Sirupsen/logrus and sirupsen/logrus) bug
	# due to the two different logrus versions that kfctl is using.
	pushd vendor/github.com/Sirupsen/logrus/ && \
	echo '\
	// +build linux aix\n\
	package logrus\n\
	import "golang.org/x/sys/unix"\n\
	func isTerminal(fd int) bool {\n\
		_, err := unix.IoctlGetTermios(fd, unix.TCGETS)\n\
		return err == nil\n\
	} ' > terminal_check_unix.go && \
	popd
ifneq ($(DOCKERFILE), Dockerfile)
	pushd build &&\
	cp Dockerfile Dockerfile.bckp &&\
	cp ${DOCKERFILE} Dockerfile &&\
	popd
endif
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 ${GO} build -a -o build/_output/bin/$(OPERATOR_BINARY_NAME) cmd/manager/main.go
	${IMAGE_BUILDER} build build -t ${OPERATOR_IMG}
ifneq ($(DOCKERFILE), Dockerfile)
	pushd build &&\
	cp Dockerfile.bckp Dockerfile &&\
	popd
endif

# push operator image and update deployment files.
push-operator:
	${IMAGE_BUILDER} push ${OPERATOR_IMG}

update-operator-image:
	# Use perl instead of sed to avoid OSX/Linux compatibility issue:
	# https://stackoverflow.com/questions/34533893/sed-command-creating-unwanted-duplicates-of-file-with-e-extension
	perl -pi -e 's@image: .*@image: '"${OPERATOR_IMG}"'@' ./deploy/operator.yaml

# push the releases to a GitHub page
push-to-github-release: build-kfctl-tgz
	github-release upload \
	    --user kubeflow \
	    --repo kubeflow \
	    --tag $(TAG) \
	    --name "kfctl_$(TAG)_linux.tar.gz" \
	    --file bin/linux/kfctl_$(TAG)_linux.tar.gz
	github-release upload \
	    --user kubeflow \
	    --repo kubeflow \
	    --tag $(TAG) \
	    --name "kfctl_$(TAG)_darwin.tar.gz" \
	    --file bin/darwin/kfctl_$(TAG)_darwin.tar.gz
	github-release upload \
            --user kubeflow \
            --repo kubeflow \
            --tag $(TAG) \
            --name "kfctl_$(TAG)_arm64.tar.gz" \
            --file bin/arm64/kfctl_$(TAG)_arm64.tar.gz

build-kfctl-container:
	DOCKER_BUILDKIT=1 docker build \
                $(DOCKER_BUILD_OPTS) \
                --build-arg REPO="$(REPO)" \
                --build-arg BRANCH=$(BRANCH) \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg VERSION=$(TAG) \
		--target=$(KFCTL_TARGET) \
		--tag $(KFCTL_IMG)/builder:$(TAG) .
	@echo Built $(KFCTL_IMG)/builder:$(TAG)
	mkdir -p bin
	docker create \
		--name=temp_kfctl_container \
		$(KFCTL_IMG)/builder:$(TAG)
	docker cp temp_kfctl_container:/usr/local/bin/kfctl ./bin/kfctl
	docker rm temp_kfctl_container
	@echo Exported kfctl binary to bin/kfctl

# build containers using GCLOUD_PROJECT
build-gcb:
	gcloud --project=$(GCLOUD_PROJECT)\
		builds submit \
		--machine-type=n1-highcpu-32 \
		--substitutions=TAG_NAME=$(TAG)
		--config=cloudbuild.yaml .


# Build but don't attach the latest tag. This allows manual testing/inspection of the image
# first.
push: build
	docker push $(BOOTSTRAPPER_IMG):$(TAG)
	@echo Pushed $(BOOTSTRAPPER_IMG):$(TAG)

push-latest: push
	gcloud container images add-tag --quiet $(BOOTSTRAPPER_IMG):$(TAG) $(BOOTSTRAPPER_IMG):latest --verbosity=info
	echo created $(BOOTSTRAPPER_IMG):latest

push-kfctl-container: build-kfctl-container
	docker push $(KFCTL_IMG):$(TAG)
	@echo Pushed $(KFCTL_IMG):$(TAG)

push-kfctl-container-latest: push-kfctl-container
	gcloud container images add-tag --quiet $(KFCTL_IMG):$(TAG) $(KFCTL_IMG):latest --verbosity=info
	@echo created $(KFCTL_IMG):latest

install: build-kfctl dockerfordesktop.so
	@echo copying bin/kfctl to /usr/local/bin
	@cp bin/kfctl /usr/local/bin

run-kfctl-container: build-kfctl-container
	docker run $(MOUNT_KUBE) $(MOUNT_GCP) --entrypoint /bin/sh -it $(KFCTL_IMG):$(TAG)

#***************************************************************************************************
# Build a docker container that can be used to build kfctl
#
# The rules in this section are used to build the docker image that provides
# a suitable go build environment for kfctl

build-builder-container:
	docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--target=builder \
		--tag $(KFCTL_IMG):$(TAG) .
	@echo Built $(KFCTL_IMG):$(TAG)

# build containers using GCLOUD_PROJECT
build-builder-container-gcb:
	gcloud --project=$(GCLOUD_PROJECT) \
		builds submit \
		--machine-type=n1-highcpu-32 \
		--substitutions=TAG_NAME=$(TAG),_TARGET=builder \
		--config=cloudbuild.yaml .

#***************************************************************************************************

clean:
	rm -rf test && mkdir test

doc:
	doctoc ./cmd/kfctl/README.md README.md k8sSpec/README.md developer_guide.md


#**************************************************************************************************
# checks licenses
check-licenses:
	./third_party/check-license.sh
# rules to run unittests
#
test: build-kfctl check-licenses
	go test ./... -v

# Unit test invoked by Github Action
go-unittests-junit:
	echo Running tests ... junit_file=$(JUNIT_FILE)
	mkdir -p $(JUNIT_DIR)
	go test ./... -v 2>&1 | go-junit-report > $(JUNIT_FILE) --set-exit-code

#***************************************************************************************************
test-init: clean install dockerfordesktop.init minikube.init gcp.init none.init-no-platform

test-generate: test-init dockerfordesktop.generate minikube.generate gcp.generate none.generate

test-apply: test-generate dockerfordesktop.apply minikube.apply gcp.apply none.apply

