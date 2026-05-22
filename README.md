# blogging — a tiny gleam blog engine

A live HTTP server that renders a personal blog from a GitHub user's public gists.

## How it works

Posts live in the configured user's public GitHub gists. Any file inside any of
those gists whose name matches `blog:<group>:<leaf>.md` becomes a sidebar entry
under `<group>` with label `<leaf>` and content rendered from the file body.
Files not matching the pattern are silently ignored.

The server reads `BLOG_GIST_USER` at boot. On every request to `/`, it fetches
`GET https://api.github.com/users/<user>/gists` (1 call, anonymous quota of
60/hr per server IP), then fetches each matching file body via
`gist.githubusercontent.com/<user>/<id>/raw/<filename>` (no quota). The page
always reflects the live state of the gists.

If GitHub is unreachable, the page still loads with an empty menu and a small
banner in the sidebar; the status code stays 200.

## Add a post

Create a file in any of your public gists named `blog:<group>:<leaf>.md`.
That's it. One gist can hold multiple `blog:*` files.

## Configure

Set `BLOG_GIST_USER` to your GitHub username in `docker-compose.yml`:

```yaml
environment:
  BLOG_GIST_USER: <your-github-username>
```

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

Gist phase. Caching, per-post URLs, syntax highlighting, and authenticated
fetch (private gists, raised rate limit) are deferred.
