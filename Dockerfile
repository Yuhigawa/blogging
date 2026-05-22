FROM ghcr.io/gleam-lang/gleam:v1.16.0-erlang-alpine

WORKDIR /app

COPY gleam.toml manifest.toml ./
RUN gleam deps download

COPY src ./src

RUN gleam build

EXPOSE 3000

CMD ["gleam", "run"]
