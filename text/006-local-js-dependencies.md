- Start Date: 2018-01-08
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Add the ability for `#[wasm_bindgen]` to process, load, and handle dependencies
on local JS files.

* The `module` attribute can now be used to import files explicitly:

  ```rust
  #[wasm_bindgen(file = "/js/foo.js")]
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

The most user-facing change proposed here is the reinterpretation of the
`module` attribute inside of `#[wasm_bindgen]`. It can now be used to import
local files like so:

```rust
#[wasm_bindgen(module = "/js/foo.js")]
extern "C" {
    // ... definitions
}
```

This declaration says that the block of functions and types and such are all
imported from the `/js/foo.js` file, relative to the current file and rooted at
the crate root. The following rules are proposed for interpreting a `module`
attribute.

* If the string starts with `/`, `./`, or `../` then it's considered a path to a
  local file. If not, then it's passed through verbatim as the ES module import.

* All paths are resolved relative to the current file, like Rust's own
  `#[path]`, `include_str!`, etc. At this time, however, it's unknown how we'd
  actually do this for relative files. As a result all paths will be required to
  start with `/`. When `proc_macro` has a stable API (or we otherwise figure
  out how) we can start allowing `./` and `../`-prefixed paths.

This will hopefully roughly match what programmers expect as well as preexisting
conventions in browsers and bundlers.

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

The `wasm-bindgen` has a few modes of output generation today. These output
modes are largely centered around modules vs no modules and how modules are
defined. This RFC proposes that we move away from this moreso towards
*environments*, such as node.js-compatible vs browser-compatible code (which
involves more than only module format). This means that in cases where an
environment supports multiple module systems, or the module system is optional
(browsers support es modules and also no modules) `wasm-bindgen` will choose
what module system it thinks is best as long as it is compatible with that
environment.

The current output modes of `wasm-bindgen` are:

* **Default** - by default `wasm-bindgen` emits output that assumes the wasm
  module itself is an ES module. This will naturally work with custom JS
  snippets that are themselves ES modules, as they'll just be more modules in
  the graph all found in the local output directory. This output mode is
  currently only consumable by bundlers like Webpack, the default output cannot
  be loaded in either a web browser or Node.js.

* **`--no-modules`** - the `--no-modules` flag to `wasm-bindgen` is incompatible
  with ES modules because it's intended to be included via a `<script>` tag
  which is not a module. This mode, like today, will fail to work if upstream
  crates contain local JS snippets.

* **`--nodejs`** - this flag to `wasm-bindgen` indicates that the output should
  be tailored for Node.js, notably using CommonJS module conventions. In this
  mode `wasm-bindgen` will eventually use a JS parser in Rust to rewrite ES
  syntax of locally imported JS modules into CommonJS syntax.

* **`--browser`** - currently this flag is the same as the default output mode
  except that the output is tailored slightly for a browser environment (such as
  assuming that `TextEncoder` is ambiently available).

  This RFC proposes
  repurposing this flag (breaking it) to instead generate an ES module natively
  loadable inside the web browser, but otherwise having a similar interface to
  `--no-modules` today, detailed below.

This RFC proposes rethinking these output modes as follows:

| Target Environment      | CLI Flag    | Module Format | User Experience                          | How are Local JS Snippets Loaded?                                                            |
|-------------------------|-------------|---------------|------------------------------------------|----------------------------------------------------------------------------------------------|
| Node.js without bundler | `--nodejs`  | Common.js     | `require()` the main JS glue file        | Main JS glue file `require()`s crates' local JS snippets.                                    |
| Web without bundler     | `--browser` | ES Modules    | `<script>` pointing to main JS glue file, using `type=module` | `import` statements cause additional network requests for crates' local snippets.            |
| Web with bundler        | none        | ES Modules    | `<script>` pointing to main JS glue file | Bundler links crates' local snippets into main JS glue file. No additional network requests except for the `wasm` module itself. |

It is notable that browser with and without bundler is almost the same as far
as `wasm-bindgen` is concerned: the only difference is that if we assume a
bundler, we can rely on the bundler polyfilling wasm-as-ES-module for us.
Note the `--browser` here is relatively radically different today and as such
would be a breaking change. It's thought that the usage of `--browser` is small
enough that we can get away with this, but feedback is always welcome on this
point!

The `--no-modules` flag doesn't really fit any more as the `--browser` use case
is intended to subsume that. Note that the this RFC proposes only having the
bundler-oriented and browser-oriented modes supporting local JS snippets for
now, while paving a way forward to eventually support local JS snippets in
Node.js. The `--no-modules` could eventually also be supported in the same
manner as Node.js is (once we're parsing the JS file and rewriting the exports),
but it's proposed here to generally move away from `--no-modules` towards
`--browser`.


The `--browser` output is currently considered to export an initialization
function which, after called and the returned promise is resolved (like
`--no-modules` today) will cause all exports to work when called. Before the
promise resolves all exports will throw an error when called.

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
validate entries in `package.json` are present for imports found.

### Accessing wasm Memory/Table

JS snippets interacting with the wasm module may commonly need to work with the
`WebAssembly.Memory` and `WebAssembly.Table` instances associated with the wasm
module. This RFC proposes using the wasm itself to pass along these objects,
like so:

```rust
// lib.rs

#[wasm_bindgen(file = "local-snippet.js")]
extern {
    fn take_u8_slice(memory: &JsValue, ptr: u32, len: u32);
}

#[wasm_bindgen]
pub fn call_local_snippet() {
    let vec = vec![0,1,2,3,4];
    let mem = wasm_bindgen::memory();
    take_u8_slice(&mem, vec.as_ptr() as usize as u32, vec.len() as u32);
}
```

```js
// local-snippet.js

export function take_u8_slice(memory, ptr, len) {
    let slice = new UInt8Array(memory.arrayBuffer, ptr, len);
    // ...
}
```

Here the `wasm_bindgen::memory()` existing intrinsic is used to pass along the
memory object to the imported JS snippet. To mirror this we'll add
`wasm_bindgen::function_table()` as well to access the function table.

Eventually we may want a more explicit way to import the memory/table, but for
now this should be sufficient for expressiveness.

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
  extracted to an NPM package and postprocessed there. Note that it's always
  possible for authors to manually run the TypeScript compiler by hand for these
  use cases, though.

* The relatively popular `--no-modules` flag is proposed to be deprecated in
  favor of a `--browser` flag, which itself will have a breaking change relative
  to today. It's thought though that `--browser` is only very rarely used so is
  safe to break, and it's also thought that we'll want to avoid breaking
  `--no-modules` as-is today.

* Local JS snippets are required to be written in ES module syntax. This may be
  a somewhat opinionated stance, but it's intended to make it easier to add
  future features to `wasm-bindgen` while continuing to work with JS. The ES
  module system, however, is the only known official standard throughout the
  ecosystem, so it's hoped that this is a clear choice for writing local JS
  snippets.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

The primary alternative to this system is a macro like `js!` from stdweb. This
allows written small snippets of JS code directly in Rust code, and then
`wasm-bindgen` would have the knowledge to generate appropriate shims. This RFC
proposes recognizing `module` paths instead of this approach as it's thought to
be a more general approach. Additionally it's intended that the `js!` macro can
be built on the `module` directive including local file paths. The
`wasm-bindgen` crate may grow a `js!`-like macro one day, but it's thought that
it's best to start with a more conservative approach.

One alternative for ES modules is to simply concatenate all JS together. This
way we wouldn't have to parse anything but we'd instead just throw everything
into one file. The downside of this approach, however, is that it can easily
lead to namespacing conflicts and it also forces everyone to agree on module
formats and runs the risk of forcing the module format of the final product.

Another alternative to emitting small files at wasm-bindgen time is to instead
unpack all files at *runtime* by leaving them in custom sections of the wasm
executable. This in turn, however, may violate some CSP settings (particularly
strict ones).

# Unresolved Questions
[unresolved]: #unresolved-questions

- Is it necessary to support `--nodejs` initially?

- Is it necessary to support local JS imports in local JS snippets initially?

- Are there known parsers of JS ES modules today? Are we forced to include a
  full JS parser or can we have a minimal one which only deals with ES syntax?

- How would we handle other assets like CSS, HTML, or images that want to be
  referenced by the final wasm file?
