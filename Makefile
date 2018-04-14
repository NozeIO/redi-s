# Makefile

CONFIGURATION=release

all :
	swift build -c $(CONFIGURATION)

clean :
	swift package -c $(CONFIGURATION) clean

distclean :
	rm -rf .build* Package.resolved


# Some Docker testing

DOCKER_SWIFT_VERSION=4.1

build-in-docker:
	docker run --rm \
		-v $(PWD):/src \
		-v $(PWD)/.build-linux-$(DOCKER_SWIFT_VERSION):/src/.build \
		swift:$(DOCKER_SWIFT_VERSION) \
		bash -c "cd src && swift build -c $(CONFIGURATION)"

# Hm, this doesn't actually work on my machine. Maybe because we bind to
# localhost?
run-in-docker:
	docker run -t --rm \
		-p 8888:8888 \
		-v $(PWD):/src \
		-v $(PWD)/.build-linux-$(DOCKER_SWIFT_VERSION):/src/.build \
		swift:$(DOCKER_SWIFT_VERSION) \
		/src/.build/x86_64-unknown-linux/release/redi-s -p 8888
