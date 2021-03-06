export GO15VENDOREXPERIMENT := 1

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    HASH := md5
else
    HASH := md5sum
endif

all: build manifests

generate: sync
	find pkg/ -name "*generated*.go" -exec rm {} -f \;
	./hack/build-go.sh generate ${WHAT}
	goimports -w -local kubevirt.io cmd/ pkg/ tests/
	./hack/bootstrap-ginkgo.sh
	(cd tools/openapispec/ && go build)
	tools/openapispec/openapispec --dump-api-spec-path api/openapi-spec/swagger.json

apidocs: generate
	docker run -u `stat -c "%u" hack/gen-swagger-doc/` --rm \
		-v ${PWD}:/home/gradle/kubevirt:rw,z \
		-w /home/gradle/kubevirt \
		gradle \
		bash hack/gen-swagger-doc/gen-swagger-docs.sh v1 html

build: checksync fmt vet compile

compile:
	./hack/build-go.sh install ${WHAT}

vet:
	./hack/build-go.sh vet ${WHAT}

fmt:
	goimports -w -local kubevirt.io cmd/ pkg/ tests/

test: build
	./hack/build-go.sh test ${WHAT}

functest:
	./hack/build-go.sh functest ${WHAT}

clean:
	./hack/build-go.sh clean ${WHAT}
	rm ./bin -rf
	rm tools/openapispec/openapispec -rf

distclean: clean
	find manifests -name "*.yaml" -type f -delete
	rm -rf vendor/
	rm -f .glide.*.hash
	glide cc

checksync:
	test -f .glide.yaml.hash || ${HASH} glide.yaml > .glide.yaml.hash
	if [ "`${HASH} glide.yaml`" != "`cat .glide.yaml.hash`" ]; then \
		glide cc; \
		glide update --strip-vendor; \
		${HASH} glide.yaml > .glide.yaml.hash; \
		${HASH} glide.lock > .glide.lock.hash; \
	elif [ "`${HASH} glide.lock`" != "`cat .glide.lock.hash`" ]; then \
 		make sync; \
 	fi
 
sync:
	glide install --strip-vendor
	${HASH} glide.lock > .glide.lock.hash
 

docker: build
	./hack/build-docker.sh build ${WHAT}

publish: docker
	./hack/build-docker.sh push ${WHAT}

manifests:
	./hack/build-manifests.sh

check: check-bash vet
	test -z "`./hack/build-go.sh fmt`"

check-bash:
	find . -name \*.sh -exec bash -n \{\} \;

vagrant-sync-config:
	./cluster/vagrant/sync_config.sh

vagrant-sync-build: build
	./cluster/vagrant/sync_build.sh

vagrant-sync-optional:
	./cluster/vagrant/sync_build.sh 'build optional'

vagrant-deploy: vagrant-sync-config vagrant-sync-build
	export KUBECTL="cluster/kubectl.sh --core" && ./cluster/deploy.sh

.release-functest:
	make functest > .release-functest 2>&1

release-announce: .release-functest
	./hack/release-announce.sh $(RELREF) $(PREREF)

.PHONY: build fmt test clean distclean checksync sync docker manifests vet publish vagrant-sync-config vagrant-sync-build vagrant-deploy functest release-announce
