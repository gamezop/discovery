ARG MIX_ENV="develop"

FROM hexpm/elixir:1.12.2-erlang-24.0.5-alpine-3.14.0 as build

# install build dependencies
RUN apk add --no-cache build-base git npm python3 curl


# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force


# set build ENV
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix do deps.get, deps.compile

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets
RUN npm install --prefix ./assets
RUN npm rebuild node-sass
RUN mix assets.deploy

# uncomment COPY if rel/ exists

RUN mix compile
# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix release

# prepare release image
FROM alpine:3.14.0 AS app

RUN apk add --no-cache openssl ncurses-libs libgcc libstdc++

ARG MIX_ENV
ENV USER="elixir"

WORKDIR "/home/${USER}/app"

# Creates an unprivileged user to be used exclusively to run the Phoenix app
# RUN \
  # addgroup \
  #  -g 1000 \
  #  -S "${USER}" \
  # && adduser \
  #  -s /bin/sh \
  #  -u 1000 \
  #  -G "${USER}" \
  #  -h "/home/${USER}" \
  #  -D "${USER}" \
  # && su "${USER}"

# Creates super privileged user

RUN chown root:root /home/elixir/app

# Everything from this line onwards will run in the context of the unprivileged user.
# USER "${USER}"

# Everything from this line onwards will run in the context of the super privileged user.

USER root:root

COPY --from=build --chown=root:root /app/_build/"${MIX_ENV}"/rel/discovery ./

COPY entrypoint.sh .

# Run the Phoenix app
CMD ["sh", "./entrypoint.sh"]