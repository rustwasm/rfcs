- Start Date: 2018-01-08
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Add the ability for `#[wasm_bindgen]` to process, load, and handle dependencies
on local JS files.

* A new attribute for this will be added:

  ```rust
  #[wasm_bindgen(file = "foo.js")]
  extern "C" {
      // ...
  }
  ```

* The `--browser` flag is repurposed to generate an ES module for the browser
  and `--no-modules` is deprecated in favor of this flag.

* The `--nodejs` will not immediately support local JS snippets, but will do so
  in the future.

# Motivation
[motivation]: #motivation

The goal of `wasm-bindgen` is to enable easy interoperation between Rust and JS.
While it's very easy to write custom Rust code, it's actually pretty difficult
to write custom JS and hook it up with `#[wasm_bindgen]` (see
[rustwasm/wasm-bindgen#224][issue]). The `#[wasm_bindgen]`
attribute currently only supports importing functions from ES modules, but even
then the support is limited and simply assumes that the ES module string exists
in the final application build step.

[issue]: https://github.com/rustwasm/wasm-bindgen/issues/224

Currently there is no composable way for a crate to have some auxiliary JS that
it is built with which ends up seamlessly being included into a final built
application. For example the `rand` crate can't easily include local JS (perhaps
to detect what API for randomness it's supposed to use) without imposing strong
requirements on the final artifact.

Ergonomically support imports from custom JS files also looks to be required by
frameworks like `stdweb` to build a macro like `js!`. This involves generating
snippets of JS at compile time which need to be included into the final bundle,
which is intended to be powered by this new attribute.

# Stakeholders
[stakeholders]: #stakeholders

Some major stakeholders in this RFC are:

* Users of `#[wasm_bindgen]`
* Crate authors wishing to add wasm support to their crate.
* The `stdweb` authors
* Bundler (webpack) and `wasm-bindgen` integration folks.

Most of the various folks here will be cc'd onto the RFC, and reaching out to
more is always welcome!

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

This proposal involves a number of moving pieces, all of which are intended to
work in concert to provide a streamlined story to including local JS files into
a final `#[wasm_bindgen]` artifact. We'll take a look at each piece at a time
here.

### New Syntactical Features

The most user-facing change proposed here is the addition of a new attribute
inside of `#[wasm_bindgen]`, the `file` attribute. This configured like so:

```rust
#[wasm_bindgen(file = "foo.js")]
extern "C" {
    // ... definitions
}
```

This declaration says that the block of functions and types and such are all
imported from the `foo.js` file. The `foo.js` file is resolved relative to the
crate root (where this is relative to is also discussed in the drawbacks section
below). For example a procedural macro will simply `File::open` (morally)
with the path provided to the attribute.

The `file` attribute is mutually exclusive with the `module` attribute. Only one
can be specified.

### Format of imported JS

All imported JS is required to written with ES module syntax. Initially the JS
must be hand-written and cannot be postprocessed. For example the JS cannot be
written with TypeScript, nor can it be compiled by Babel or similar.

As an example, a library may contain:

```rust
// src/lib.rs
#[wasm_bindgen(file = "js/foo.js")]
extern "C" {
    fn call_js();
}
```

accompanied with:

```js
// js/foo.js

export function call_js() {
    // ...
}
```

Note that `js/foo.js` uses ES module syntax to export the function `call_js`.
When `call_js` is called from Rust it will call the `call_js` function in
`foo.js`.

### Propagation Through Dependencies

The purpose of the `file` attribute is to work seamlessly with dependencies.
When building a project with `#[wasm_bindgen]` you shouldn't be required to know
whether your dependencies are using local JS snippets or not!

The `#[wasm_bindgen]` macro, at compile time, will read the contents of the file
provided, if any. This file will be serialized into the wasm-bindgen custom
sections in a wasm-bindgen specific format. The final wasm artifact produced by
rustc will contain all referenced JS file contents in its custom sections.

The `wasm-bindgen` CLI tool will extract all this JS and write it out to the
filesystem. The wasm file (or the wasm-bindgen-generated shim JS file) emitted
will import all the emitted JS files with relative imports.

### Updating `wasm-bindgen` output modes

The `wasm-bindgen` has a few modes of output generation today. This PR
proposes repurposing the existing `--browser` flag, deprecating the
`--no-modules` flag, and canonicalizing the output in three modes. All
modes will operate as follows:

* **Default** - by default `wasm-bindgen` emits output that assumes the wasm
  module itself is an ES module. This will naturally work with custom JS
  snippets that are themselves ES modules, as they'll just be more modules in
  the graph all found in the local output directory.

* **`--no-modules`** - the `--no-modules` flag to `wasm-bindgen` is incompatible
  with ES modules because it's intended to be included via a `<script>` tag
  which is not a module. This mode, like today, will fail to work if upstream
  crates contain local JS snippets. As a result, the `--no-modules` flag will
  essentially be deprecated as a result of this change.

* **`--nodejs`** - this flag to `wasm-bindgen` indicates that the output should
  be tailored for Node.js, notably using CommonJS module conventions. This mode
  will, in the immediate term, fail if the crate graph includes any local JS
  snippets. This failure mode is intended to be a temporary measure. Eventually
  it should be relatively trivial with a JS parser in Rust to rewrite ES syntax
  of locally imported JS modules into CommonJS syntax.

* **`--browser`** - currently this flag is the same as the default output mode
  except that the output is tailored slightly for a browser environment (such as
  assuming that `TextEncoder` is ambiently available). This RFC proposes
  repurposing this flag (breaking it) to instead generate an ES module natively
  loadable inside the web browser, but otherwise having a similar interface to
  `--no-modules` today, detailed below.

In summary, the three modes of output for `wasm-bindgen` will be:

* Bundler-oriented (no flags passed) intended for consumption by bundlers like
  Webpack which consider the wasm module a full-fledged ES module.

* Node.js-oriented (`--nodejs`) intended for consumption only in Node.js itself.

* Browser-oriented without a bundler (`--browser`) intended for consumption in
  any web browser supporting JS ES modules that also supports wasm. This mode is
  explicitly not intended to be usable with bundlers like webpack.

The `--no-modules` flag doesn't really fit any more as the `--browser` use case
is intended to subsume that. Note that the this RFC proposes only having the
bundler-oriented and browser-oriented modes supporting local JS snippets for
now, while paving a way forward to eventually support local JS snippets in
Node.js. The `--no-modules` could eventually also be supported in the same
manner as Node.js is (once we're parsing the JS file and rewriting the exports),
but it's proposed here to generally move away from `--no-modules` towards
`--browser`.

For some more detail about the `--browser` output, it's intended to look from
the outside like `--no-modules` does today. When using `--browser` a single
`wasm_bindgen` function will be exported from the module. This function takes
either a path to the wasm file or the `WebAssembly.Module` itself, and then it
returns a promise which resolves to a JS object that has the full wasm-bindgen
interface on it.

### JS files depending on other JS files

One tricky point about this RFC is when a local JS snippet depends on other JS
files. For example your JS might look like:

```js
// js/foo.js

import { foo } from '@some/npm-package';
import { bar } from './bar.js'

// ...
```

As designed above, these imports would not work. It's intended that we
explicitly say this is an initial limitation of this design. We won't support
imports between JS snippets just yet, but we should eventually be able to do so.

In the long run to support `--nodejs` we'll need some level of ES module parser
for JS. Once we can parse the imports themselves it would be relatively
straightforward for `#[wasm_bindgen]`, during expansion, to load transitively
included files. For example in the file above we'd include `./bar.js` into the
wasm custom section. In this future world we'd just rewrite `./bar.js` (if
necessary) when the final output artifact is emitted. Additionally with NPM
package support in `wasm-pack` and `wasm-bindgen` (a future goal) we could
automatically add entries to `package.json` (or validate they're already
present) based on the imports found.

# Drawbacks
[drawbacks]: #drawbacks

* The initial RFC is fairly conservative. It doesn't work with `--nodejs` out of
  the gate nor `--no-modules`. Additionally it doesn't support JS snippets
  importing other JS initially. Note that all of these are intended to be
  supported in the future, it's just thought that it may take more design than
  we need at the get-go for now.

* JS snippets must be written in vanilla ES module JS syntax. Common
  preprocessors like TypeScript can't be used. It's unclear how such
  preprocessed JS would be imported. It's hoped that JS snippets are small
  enough that this isn't too much of a problem. Larger JS snippets can always be
  extracted to an NPM package and postprocessed there.

* The relatively popular `--no-modules` flag is proposed to be deprecated in
  favor of a `--browser` flag, which itself will have a breaking change relative
  to today. It's thought though that `--browser` is only very rarely used so is
  safe to break, and it's also thought that we'll want to avoid breaking
  `--no-modules` as-is today.

* JS files are imported relative to the crate root rather than the file doing
  the importing, unlike `mod` statements in Rust. It's thought that we can't get
  file-relative imports working with stable `proc_macro` APIs today, but if the
  implementation can manage to finesse it this RFC would propose instead making
  file imports relative to the current file instead of crate root.

* Local JS snippets are required to be written in ES module syntax. This may be
  a somewhat opinionated stance, but it's intended to make it easier to add
  future features to `wasm-bindgen` while continuing to work with JS.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

Currently there aren't any competing designs solving this problem, so there
aren't many known major alternatives. There's a number of alternatives to
various smaller decisions in this RFC, but it's hoped that the various
alternatives are listed or discussed inlined.

The major rationale for this RFC is empowering this use case of "seamless local
JS snippets" **at all**. The RFC proposes to start out with only including files
as opposed to small JS snippets themselves (like `stdweb`'s own `js!` macro)
because files are structured as ES modules which is what `#[wasm_bindgen]`
already supports well and will also eventually have support natively in
WebAssembly itself. While `#[wasm_bindgen]` may one day have a `js!`-like macro
built-in, it's hoped that we can start out with a purely library-based solution
like `stdweb`, iterate on it, and consider this question later.

# Unresolved Questions
[unresolved]: #unresolved-questions

- Is it necessary to support `--nodejs` initially?

- Is it necessary to support local JS imports in local JS snippets initially?

- Are there known parsers of JS ES modules today? Are we forced to include a
  full JS parser or can we have a minimal one which only deals with ES syntax?
