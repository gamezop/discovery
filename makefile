VERSION_DEV = 0.1.35
VERSION_PROD = 0.1.0

commit:
	mix test
	mix format
	mix credo --strict
	git add .
	git cz

commit-release-major:
	mix bump_release major
	mix test
	mix format
	mix credo --strict
	git add .
	git cz

commit-release-minor:
	mix bump_release minor
	mix test
	mix format
	mix credo --strict
	git add .
	git cz

commit-release-patch:
	mix bump_release patch
	mix test
	mix format
	mix credo --strict
	git add .
	git cz

dev-release:
	mix deps.get
	mix compile
	mix release

builddockerprod: 
	docker build --tag gamezop/discovery .
	docker tag gamezop/discovery gamezop/discovery:$(VERSION_PROD)

builddockerdev: 
	docker build --file dev.Dockerfile --tag gamezop/discovery .
	docker tag gamezop/discovery gamezop/discovery:$(VERSION_DEV)

pushdockerdev: builddockerdev
	docker push gamezop/discovery:$(VERSION_DEV)

# pushdockerprod: builddockerprod
# 	docker push gamezop/discovery:$(VERSION_PROD)

rundockerprod: 
	docker run --name discovery-$(VERSION_PROD) --publish 6968:6968 --detach --env DISCOVERY_PORT=6968 \
	--env SECRET_KEY_BASE=${SECRET_KEY_BASE} gamezop/discovery:$(VERSION_PROD)

rundockerdev: builddockerdev
	docker run --name discovery-$(VERSION_DEV) --publish 6966:6966 --detach --env DISCOVERY_PORT=6966 \
	--env SECRET_KEY_BASE=${SECRET_KEY_BASE} gamezop/discovery:$(VERSION_DEV)