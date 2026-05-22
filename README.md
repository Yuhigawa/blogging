# blogging — a tiny gleam blog engine

A live HTTP server that renders a personal blog from a directory of markdown files.

## How it works

Each markdown file under `src/assets/posts/<group>/<leaf>.md` becomes a sidebar entry. The directory is the menu — no config file. On every request the server scans the directory, renders each post to HTML, and splices the result into `src/assets/index.html` via the `<!-- {{menu}} -->` and `<!-- {{templates}} -->` placeholders. The browser's `<template>` cloning JS swaps the active post into `#dynamic-content`.

## Add a post

Create a file. That's it.

    src/assets/posts/estudos/intro.md

It appears in the `estudos` group as `intro`. Slug rules: the `id=` attribute is the filename lowercased, whitespace → `-`, any char outside `[a-z0-9_-]` dropped. Files starting with `.` and `README.md` are ignored. Groups with no `.md` files are hidden.

## Markdown subset

Headings 1-6, paragraphs, `**bold**`, `*italic*`, `` `code` ``, `[text](url)`, ordered + unordered lists, fenced ``` ``` ``` ```, `> blockquote`, `---` hr, backslash escape. All text and code is HTML-escaped — `<script>` in a post is rendered literally.

## Static files

Anything under `src/assets/static/` is served at `/static/<name>` with MIME inferred from the extension.

## Run

    docker compose up blogging
    # http://localhost:3000

## Test

    docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam test
    docker compose run --rm --no-deps -v "$(pwd):/app" blogging gleam format --check src test

Snapshot tests live under `test/snapshots/`. To regenerate after an intentional change, run the test and copy the printed `actual` output into the snapshot file. Updates are never auto-applied — they require a commit.

## Status

Local-MD phase. Gist integration, caching, per-post URLs, and syntax highlighting are deferred.
