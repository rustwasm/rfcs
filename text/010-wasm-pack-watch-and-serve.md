- Start Date: 2019-03-06
- RFC PR: https://github.com/rustwasm/rfcs/pull/10
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Add two new sub-commands to `wasm-pack`:

1. `watch`: watch the crate's files and automatically rebuild whenever they
   change.
2. `serve`: start an HTTP server for the crate directory on `localhost`.

# Motivation
[motivation]: #motivation

Enable a smooth and complete local development experience for users who are not
using a JavaScript bundler.

In particular, we would like to [remove the `npm` and bundler usage from our
Game of Life tutorial][no-bundler-in-docs] without requiring readers to install
any additional tools other than the Rust toolchain and `wasm-pack` when setting
up their development environment. The goal here being less moving parts to learn
and tools to wrangle when first exploring Rust and WebAssembly.

Additionally, we would like to make sure that the local development server uses
the `application/wasm` MIME type when serving Wasm binaries. This enables the
`WebAssembly.instantiateStreaming` fast-path for users.

[no-bundler-in-docs]: https://github.com/rustwasm/book/issues/150

# Stakeholders
[stakeholders]: #stakeholders

The stakeholders are primarily people that are doing Rust and Wasm development
without a JavaScript bundler, which potentially will include all of our new
users who are just starting the Game of Life tutorial. Most of this demographic
is probably not watching the RFCs repository, and only some are regularly coming
to working group meetings, so it makes sense to advertise this RFC in TWiRaWA
and on our @rustwasm Twitter account.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

We will add two new subcommands to `wasm-pack`:

1. `watch`
2. `serve`

## `wasm-pack watch`

The `watch` subcommand will observe the crate directory for changes and
automatically re-build when files change.

### Command Line Interface

The `watch` command takes an identical set of command line arguments as
`wasm-pack build` does.

```
USAGE:
    wasm-pack watch [FLAGS] [OPTIONS] [path] [-- <extra_options>...]

FLAGS:
        --dev              Create a development build. Enable debug info, and disable optimizations.
        --no-typescript    By default a *.d.ts file is generated for the generated JS file, but this flag will disable
                           generating this TypeScript file.
    -h, --help             Prints help information
        --profiling        Create a profiling build. Enable optimizations and debug info.
        --release          Create a release build. Enable optimizations and disable debug info.
    -V, --version          Prints version information

OPTIONS:
    -m, --mode <mode>          Sets steps to be run. [possible values: no-install, normal, force] [default: normal]
    -d, --out-dir <out_dir>    Sets the output directory with a relative path. [default: pkg]
    -s, --scope <scope>        The npm scope to use in package.json, if any.
    -t, --target <target>      Sets the target environment. [possible values: browser, nodejs, no-modules] [default:
                               browser]

ARGS:
    <path>                The path to the Rust crate.
    <extra_options>...    List of extra options to pass to `cargo build`
```

### Implementation

We can use [the `notify` crate][notify] to watch the filesystem for
changes. Initially, we will just watch the crate directory for
changes. Eventually, we can use [`cargo build --build-plan`][build-plan] to get
a list of files that we should be watching.

[notify]: https://crates.io/crates/notify
[build-plan]: https://github.com/rust-lang/cargo/issues/5579

## `wasm-pack serve`

The `serve` subcommand starts a local Web server in the crate directory, watches
for file changes, and re-builds the crate on changes.

### Command Line Interface

The `serve` subcommand takes a superset of the arguments that `wasm-pack build`
takes. Like other `wasm-pack` subcommands, it takes an optional path to the
crate directory as a positional argument, but if that is missing, then it
defaults to the current directory. It has the usual flags for controlling the
build profile, and the target environment. It takes extra options after `--`
that get passed through straight to `cargo build`.

Additionally, it has a `--no-watch` flag to disable watching the crate for
changes to kick off automatic re-builds, and a `--port` option to specifiy the
port the local server should bind to.

```
USAGE:
    wasm-pack serve [FLAGS] [OPTIONS] [path] [-- <extra_options>...]

FLAGS:
        --dev              Create a development build. Enable debug info, and disable optimizations.
        --no-typescript    By default a *.d.ts file is generated for the generated JS file, but this flag will disable
                           generating this TypeScript file.
    -h, --help             Prints help information
        --profiling        Create a profiling build. Enable optimizations and debug info.
        --release          Create a release build. Enable optimizations and disable debug info.
    -V, --version          Prints version information
        --no-watch         Do not watch the crate for changes to automaticaly rebuild.

OPTIONS:
    -m, --mode <mode>          Sets steps to be run. [possible values: no-install, normal, force] [default: normal]
    -d, --out-dir <out_dir>    Sets the output directory with a relative path. [default: pkg]
    -s, --scope <scope>        The npm scope to use in package.json, if any.
    -t, --target <target>      Sets the target environment. [possible values: browser, nodejs, no-modules] [default:
                               browser]
    -p, --port <port>          Bind to this port number with the local development HTTP server. [default: 8000]

ARGS:
    <path>                The path to the Rust crate.
    <extra_options>...    List of extra options to pass to `cargo build`
```

### Implementation

Rather than integrating an HTTP server into the `wasm-pack` binary itself, we
should leverage its ability to download and run other binaries. Exactly *which*
local HTTP server binary is left as an unresolved question.

The subcommand will start the local HTTP server and then execute the `watch`
subcommand (unless `--no-watch` is supplied).

# Drawbacks, Rationale, and Alternatives

The primary drawbacks are authoring and maintaining two more subcommands to
implement functionality that is already available in external, third-party
tools. We try to mitigate this downside by using existing local HTTP server
binaries rather than building an HTTP server directly into `wasm-pack` itself.

## Alternative: Build the HTTP Server into `wasm-pack`

An alternative design would be to build the HTTP server into `wasm-pack` itself,
using one of the existing crates for building Web servers like rocket, actix,
hyper, tide, etc:

* **Pros:**
  * The `wasm-pack serve` command is ready to roll immediately after `wasm-pack`
    is installed, and doesn't need to hit the network the first time you run
    it. This situation only arises when folks who already downloaded `wasm-pack`
    do their first build/serve offline, disconnected from the internet. This
    seems like a niche enough situation that we can take the trade off.
* **Cons:**
  * Building the HTTP server into the `wasm-pack` binary is less robust: by
    shelling out to an external binary for our local server, we get process
    isolation, which makes error recovery simpler.
  * More work to implement. `wasm-pack` already has plenty of infrastructure for
    downloading and working with external binaries, so using external HTTP
    servers should be fairly easy to implement.

## Alternative: Only `serve` and Don't `watch`

We could only implement the `serve` subcommand and not the `watch` subcommand or
the filesystem watching functionality.

My original motivation when writing this RFC was just to get a local server
story sorted out. But I realized that for most users, if their build tool starts
a local server, they expect new, post-`serve` file changes to be automatically
rebuilt and reflected in the served things. This is what `webpack`, `jekyll`,
`elm`, and `ember` CLIs do for a small selection. I think that this expectation
is large enough that we have to support file watching and automatic rebuild if
we support `serve` at all.

That said, we could avoid having a `watch` *subcommand* and only expose the file
watching functionality through the `serve` subcommand. At this point though,
supporting the `watch` subcommand is a trivial amount of work, and there are use
cases where it could be useful without the server: for example, JS bundler
plugins could use it to re-build wasm packages, but then they are already
running their own local server and are doing bundler-y stuff in-between the wasm
package build and serving the newest wasm, like minifying some JS.

## Alternative: Don't.

Are we fine with the status quo where `wasm-pack` can neither locally serve
files nor watch for file changes and auto rebuild? I think that *if* we want to
remove the npm and bundler usage from the Game of Life tutorial, then the answer
is "no". But maybe it isn't worth the hassle to port the Game of Life tutorial
and add these `wasm-pack` features?

# Unresolved Questions
[unresolved]: #unresolved-questions

* Which local HTTP server binary should we use?

  | Server                              | Windows/macOs/Linux Binary Releases? | `application/wasm` MIME type? |
  |-------------------------------------|--------------------------------------|-------------------------------|
  | [`miniserve`][miniserve]            | Yes                                  | Yes                           |
  | [`httplz`][https]                   | No                                   | Yes                           |
  | [`simple-http-server`][simple-http] | Yes                                  | No                            |

  There are probably even more options on crates.io than this, but these were
  the ones that I found in a quick search and seemed actively maintained.

  Given these results, I think we should pursue `miniserve` further: reach out
  to the maintainers to make sure they are cool with it and don't intend on
  ditching the project any time soon.

  We *could* also write our own local server binary using existing crates for
  writing Web servers, which shouldn't be *too* hard given our limited need for
  features. But ideally we shouldn't need to do this given that `miniserve`
  seems to fulfill all of our requirements.

[https]: https://crates.io/crates/https
[miniserve]: https://crates.io/crates/miniserve
[simple-http]: https://crates.io/crates/simple-http-server
