- Start Date: 2018-02-14
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Enable Rust crates to transparently depend on packages in the npm ecosystem.
These dependencies will, like normal Rust dependencies through Cargo, work
seamlessly when consumed by other crates.

# Motivation
[motivation]: #motivation

The primary goal of `wasm-bindgen` and `wasm-pack` is to enable seamless
integration of Rust with JS. A massive portion of the JS ecosystem, npm, however
currently has little support in `wasm-bindgen` and `wasm-pack`, making it
difficult to access this rich resource that JS offers!

The goal of this RFC is to enable these dependencies to exist. Rust crates
should be able to require functionality from NPM, just like how NPM can require
Rust crates compiled to wasm. Any workflow which currently uses NPM packages
(such as packaging WebAssembly with a bundler) should continue to work but also
allow pulling in "custom" NPM packages as well as requested by Rust
dependencies.

# Stakeholders
[stakeholders]: #stakeholders

This RFC primarily affects uses of `wasm-pack` and `wasm-bindgen` who are also
currently using bundlers like Webpack. This also affects, however, developers of
core foundational crates in the Rust ecosystem who want to be concious of the
ability to pull in NPM dependencies and such.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

Adding an NPM dependency to a Rust project will look very similar to adding an
NPM dependency to a normal JS project. First the dependency, and its version
requirement, need to be declare. This RFC proposes doing this in a
`package.json` file adjacent to the crate's `Cargo.toml` file:

```json
 {
  "dependencies": {
    "foo": "^1.0.1"
  }
}
```

The `package.json` file will initially be a subset of NPM's `package.json`,
only supporting one `dependencies` top-level key which internally has key/value
pairs with strings. Beyond this validation though no validation will be
performed of either key or value pairs within `dependencies`. In the future
it's intended that more keys of `package.json` in NPM will be supported, but
this RFC is intended to be an MVP for now to enable dependencies on NPM at all.

After this `package.json` file is created, the package next needs to be
imported in the Rust crate. Like with other Rust dependencies on JS, this will
be done with the `#[wasm_bindgen]` attribute:

```rust
#[wasm_bindgen(module = "foo")]
extern "C" {
    fn function_in_foo_package();
}
```

> **Note**: in JS the above import would be similar to:
>
> ```js
> import { function_in_foo_package } from "foo";
> ```

The exiting `module` key in the `#[wasm_bindgen]` attribute can be used to
indicate which ES module the import is coming from. This affects the `module`
key in the final output wasm binary, and corresponds to the name of the package
in `package.json`. This is intended to match how bundler conventions already
interpret NPM packages as ES modules.

After these two tools are in place, all that's needed is a `wasm-pack build` and
you should be good to go! The final `package.json` will have the `foo`
dependency listed in our `package.json` above and be ready for consumption via a
bundler.

### Technical Implementation

Under the hood there's a few moving parts which enables all of this to happen.
Let's first take a look at the pieces in `wasm-bindgen`.

The primary goal of this RFC is to enable *tranparent* and *transitive*
dependencies on NPM. The `#[wasm_bindgen]` macro is the only aspect of a crate's
build which has access to all transitive dependencies, so this is what we'll be
using to slurp up `package.json`. When `#[wasm_bindgen]` with a `module` key is
specified it will look for `package.json` inside the cwd of the procedural macro
(note that the cwd is set by Cargo to be the directory with the crate's
`Cargo.toml` that is being compiled, or the crate in which `#[wasm_bindgen]` is
written). This `package.json`, if found, will have an absolute path to it
encoded into the custom section that `wasm-bindgen` already emits.

Later, when the `wasm-bindgen` CLI tool executes, it will parse an interpret all
items in the wasm-bindgen custom section. All `package.json` files listed will
be loaded, parsed, and validated (aka only `dependencies` allowed for now). If
any `package.json` is loaded then a `package.json` file will be emitted next to
the output JS file inside of `--out-dir`.

After `wasm-bindgen` executes, then `wasm-pack` will read the `package.json`
output, if any, and augment it with metadata and other items which are already
emitted.

If more than one crate in a dependency graph depends on an NPM package then in
this MVP proposal an error will be generated. In the future we can implement
some degree of merging version requirements, but for now to remain simple
`wasm-bindgen` will emit an error.

### Interaction with `--no-modules`

Depending on NPM packages fundamentally requires, well, NPM, in one way or
another. The `wasm-bindgen` and `wasm-pack` CLI tools have modes of output
(notably `wasm-bindgen`'s `--no-modules` and `wasm-pack`'s `--target no-modules`
flags) which are intended to not require NPM and other JS tooling. In these
situations if a `package.json` in any Rust crate is detected an error will be
emitted indicating so.

Note that this means that core crates which are intended to work with
`--no-modules` will not be able add NPM dependencies. Instead they'll have to
either import Rust dependencies from crates.io or use a feature like [local JS
snippets][js] to import custom JS code.

[js]: https://github.com/rustwasm/rfcs/pull/6

# Drawbacks
[drawbacks]: #drawbacks

One of the primary drawbacks of this RFC is that it's fundamentally incompatible
with a major use case of `wasm-bindgen` and `wasm-pack`, the `--no-modules` and
`--target no-modules` flags. As a short-term band-aid this RFC proposes making
it a hard error which would hinder the adoption of this feature in crates that
want to be usable in this mode.

In the long-term, however, it may be possible to get this working. For example
many NPM packages are available on `unpkg.com` or in other locations. It may be
possible, if all packages in these locations adhere to well-known conventions,
to generate code that's compatible with these locations of hosting NPM packages.
In these situations it may then be possible to "just drop a script tag" in a few
locations to get `--no-modules` working with NPM packages. It's unclear how
viable this is, though.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

When developing this RFC, some guiding values for its design have been
articulated:

- Development on Rust-generated WebAssembly projects should allow developers to
  use the development environment they are most comfortable with. Developers
  writing Rust should get to use Rust, and developers using JavaScript should
  get to use a JS based runtime environment (Node.js, Chakra, etc).

- JavaScript tooling and workflows should be usable with Rust-generated
  WebAssembly projects. For example, bundlers like WebPack and Parcel, or
  dependency management tools such as `npm audit` and GreenKeeper.

- When possible, decisions should be made that allow the solution to be
  available to developers of not just Rust, but also C, and C++.

- Decisions should be focused on creating workflows that allow developers an
  easy learning curve and productive development experience.

These principles lead to the above proposal of using `package.json` to declare
NPM dependencies which is then grouped together by `wasm-bindgen` to be
published by `wasm-pack`. By using `package.json` we get inherent compatibility
with existing workflows like GreenKeeper and `npm install`. Additionally
`package.json` is very well documented and supported throughout the JS ecosystem
making it very familiar.

Some other alternatives to this RFC which have been ruled out are:

* **Using `Cargo.toml` instead of `package.json`** to declare NPM dependencies.
  For example we could use:

  ```toml
  [package.metadata.npm.dependencies]
  foo = "0.1"
  ```

  This has the drawback though of being incompatible with all existing workflows
  around `package.json`. Additionally it also highlights a discrepancy between
  NPM and Cargo and how `"0.1"` as a version requirement is interpreted (e.g.
  `^0.1` or `~0.1`).

* **Adding a separate manifest file** instead of using `package.json` is also
  possibility and might be easier for `wasm-bindgen` to read and later
  parse/include. This has a possible benefit of being scoped to exactly our use
  case and not being misleading by disallowing otherwise-valid fields of
  `package.json`. The downside of this approach is the same as `Cargo.toml`,
  however, in that it's an unfamiliar format to most and is incompatible with
  existing tooling without bringing too much benefit.

* **Annotating version dependencies inline** could be used rather than
  `package.json` as well, such as:

  ```rust
  #[wasm_bindgen(module = "foo", version = "0.1")]
  extern "C" {
      // ...
  }
  ```

  As with all other alternatives this is incompatible with existing tooling, but
  it's also not aligned with Rust's own mechanism for declaring dependencies
  which separates the location for version information and the code iteslf.

# Unresolved Questions
[unresolved]: #unresolved-questions

* Is the MVP restriction of only using `dependencies` too limiting? Should more
  fields be supported in `package.json`?
