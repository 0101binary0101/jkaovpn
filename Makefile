OVPN_SNAME ?= openvpn
OVPN_RNAME ?= jkastuff/$(OVPN_SNAME)
OVPN_ONAME ?= jkawork/$(OVPN_SNAME)
OVPN_EPORT ?= 1194
OVPN_VER ?= `cat VERSION`
OVPN_CMD ?=
BASE ?= latest
BASENAME ?= alpine:$(BASE)
TARGET_PLATFORM ?= linux/amd64,linux/arm64,linux/ppc64le,linux/s390x,linux/386,linux/arm/v7,linux/arm/v6
# linux/amd64,linux/arm64,linux/ppc64le,linux/s390x,linux/arm/v7,linux/arm/v6
NO_CACHE ?= 
# NO_CACHE ?= --no-cache
#MODE ?= debug
OVPN_MODE ?= $(OVPN_VER)
OVPN_DATA ?= ovpn-data
OVPN_SERVERNAME ?= foo.twiddlingthumbs.com
OVPN_CLIENTNAME ?= CLIENTNAME

# HELP
# This will output the help for each task

.PHONY: help

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

vars: ## Show the configurable variables, e.g. 'OVN_CLIENTNAME=2HOME-jka-laptop make client'
	$(foreach v, $(filter OVPN_%,$(.VARIABLES)), $(info $(v) = $($(v))))

# DOCKER TASKS

# Build image

next: ## Build the next container to compare with the latest 
	docker run -it --rm --entrypoint "/bin/ash" $(OVPN_RNAME):latest -c 'apk list;ls -l /usr/local/bin/'|grep -v easyrsa > latest-listing
	if [ "`docker rmi $(OVPN_RNAME):next`" != "0" ]; then \
		 OVPN_VER=`date +"%y%m%d"`; \
	else \
		 OVPN_VER=unknown; \
	fi	

	docker build -t $(OVPN_RNAME):next \
	--build-arg BASEIMAGE=$(BASENAME) \
	--build-arg VERSION=$${OVPN_VER} .
	docker run -it --rm --entrypoint "/bin/ash" $(OVPN_RNAME):next -c 'apk list;ls -l /usr/local/bin/'|grep -v easyrsa > next-listing
	
	if [ "`diff -q latest-listing next-listing;echo $$?`" != "0" ]; then \
		OVPN_VER=`grep openvpn next-listing | grep -v -e ^docker -e pam | awk '{ print $$1 }' | awk -F '-' '{ print $$2 }'`; \
		echo $${OVPN_VER}-`date +"%y%m%d"`>VERSION; \
		echo ${OVPN_VER}; \
	else \
		echo ${OVPN_VER}; \
	fi	

build: ## Build the container
	mkdir -p builds
	docker build $(NO_CACHE) -t $(OVPN_RNAME):$(OVPN_VER) -t $(OVPN_RNAME):latest \
	--build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
	--build-arg BASEIMAGE=$(BASENAME) \
	--build-arg VERSION=$(OVPN_VER) \
	. > builds/$(OVPN_VER)_`date +"%Y%m%d_%H%M%S"`.txt
bootstrap: ## Start multicompiler
	docker buildx inspect --bootstrap

# Operations

console: ## Start console in container
	docker run -it --rm --entrypoint "/bin/ash" $(OVPN_RNAME):$(OVPN_MODE) $(OVPN_CMD)
volume: ## Create OVPN_DATA Volume
	docker volume create --name $(OVPN_DATA)
config: ## Generate openvpn server configuration
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm $(OVPN_RNAME):$(OVPN_MODE) ovpn_genconfig -u udp://$(OVPN_SERVERNAME)
pki: ## Init PKI - Create your CA certificates
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm -it $(OVPN_RNAME):$(OVPN_MODE) touch /etc/openvpn/vars
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm -it $(OVPN_RNAME):$(OVPN_MODE) ovpn_initpki
init: volume config pki ## Execute volume, config, pki all together
start: ## Start VPN Server on the External OVPN_EPORT 
	docker run --restart=always --name myopenvpn -v $(OVPN_DATA):/etc/openvpn -d -p $(OVPN_EPORT):1194/udp --cap-add=NET_ADMIN $(OVPN_RNAME):$(OVPN_MODE)
stop: ##  Stop and remove the VPN Server  
	docker stop myopenvpn
	docker rm myopenvpn
status: ## Examine the status of connected clients
	docker exec -ti myopenvpn ovpn_status

client: ## Create ovpn client file using the name from CLIENTNAME
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm -it $(OVPN_RNAME):$(OVPN_MODE) easyrsa build-client-full $(OVPN_CLIENTNAME) nopass
retrieve: ## Retrieve ovpn client file using the name from CLIENTNAME and output into current directory
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm $(OVPN_RNAME):$(OVPN_MODE) ovpn_getclient $(OVPN_CLIENTNAME) > $(OVPN_CLIENTNAME).ovpn
list: ## List ovpn client files
	docker run -v $(OVPN_DATA):/etc/openvpn --log-driver=none --rm $(OVPN_RNAME):$(OVPN_MODE) ovpn_listclients


