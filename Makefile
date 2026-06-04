IMAGE := s4s-pc-builder:amd64

.PHONY: help image check build shell clean

help:
	@echo "s4s-pc — custom Ubuntu 24.04 GNOME live ISO (BIOS+UEFI) with Vaultwarden"
	@echo ""
	@echo "  make check    Sanity-check the builder (tools + scripts parse), no ISO"
	@echo "  make build    Build the ISO -> out/s4s-pc-noble-amd64.iso"
	@echo "  make image    Build only the Docker builder image"
	@echo "  make shell    Root shell inside the builder image (debugging)"
	@echo "  make clean    Remove build output"
	@echo ""
	@echo "On Apple Silicon the build is emulated (slow). For a fast amd64 build,"
	@echo "push to GitHub and run the Actions workflow on a native x86_64 runner."

image:
	docker build --platform=linux/amd64 -t $(IMAGE) .

check:
	./build.sh check

build:
	./build.sh build

shell: image
	docker run --rm -it --platform=linux/amd64 --privileged \
	  -v $(PWD)/out:/build/out --entrypoint /bin/bash $(IMAGE)

clean:
	rm -rf out/*.iso out/*.log work/
