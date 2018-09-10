# RFC: npm Dependency Expression

## Summary

Allow for the expression of npm dependencies in Rust-generated WebAssembly projects that use the `wasm-pack` workflow.

## Motivation

In keeping with the team’s goal to allow the surgical replacement of JS codepaths with Rust-generated WebAssembly, developers using the `wasm-pack` workflow should be able to express dependency on packages from the npm registry, other registry, or version-control repository. 

## Guiding Values
- Development on Rust-generated WebAssembly projects should allow developers to use the development environment they are most comfortable with. Developers writing Rust should get to use Rust, and developers using JavaScript should get to use a JS based runtime environment (Node.js, Chakra, etc).
- JavaScript tooling and workflows should be usable with Rust-generated WebAssembly projects. For example, bundlers like WebPack and Parcel, or dependency management tools such as `npm audit` and GreenKeeper.
- When possible, decisions should be made that allow the solution to be available to developers of not just Rust, but also C, and C++.
- Decisions should be focused on creating workflows that allow developers an easy learning curve and productive development experience.



## Solutions

Any solution to a problem like this involves 2 steps: 
  
1. How to index the third-party dependencies (in this case: npm packages), and 
2. How to "require" or "import" the packages into code. 

The second of these is simpler than the first so let's start with that: 

### Requiring an npm package

To require an npm package in your Rust code, you will use the `wasm-bindgen`
attribute, passing in `module = "name-of-package"`.

```rs
// src/foo.rs
    
#[wasm_bindgen(module = "moment")]
extern {
  // imported from moment.js
}
```

This syntax is already supported by `wasm-bindgen` for other types of JavaScript imports.

## Indexing the npm packages

This question of how to index, or even if, to index, the npm packages is a large one with
several considerations. The below options were all considered. We believe that the
`package.json` solution is the best, at the moment.

### `package.json`

*This is likely the best choice. Although it requires that Rust developers use a* `*package.json*` *file, it allows the best interoperability with existing JavaScript tooling and is agnostic to source language (Rust, C, C++).*

Create a file called `package.json` in the root of your Rust library. Fill out dependencies as per specification: https://docs.npmjs.com/files/package.json#dependencies. You can use `npm install` to add dependencies: Although npm will warn that your `package.json` is missing metadata, it will add the dependency entry.

Note: All meta-data in this file override any duplicate fields that may be expressed in the `Cargo.toml` during the  `wasm-pack build` step. This allows the library author the flexibility to change the value of fields that may be present in the metadata in the `Cargo.toml`. For example, this would allow the user to provide a different name for the npm package (since the naming rules are slightly different). The confusion that may arise from the interaction of the potential duplication of metadata is a downside to this solution.

Note: semver expression in `package.json` are based on npm rules. This is counter to the implicit `^` in a `Cargo.toml`. This confusion is also a downside to this solution, but is difficult to avoid in any potential solution to this problem.

Example:

```json

{
  "dependencies": {
    "foo" : "1.0.0 - 2.9999.9999",
    "bar" : ">=1.0.2 <2.1.2",
    "baz" : ">1.0.2 <=2.3.4",
    "boo" : "2.0.1",
    "qux" : "<1.0.0 || >=2.3.1 <2.4.5 || >=2.5.2 <3.0.0",
    "asd" : "http://asdf.com/asdf.tar.gz"
  },
  "devDependencies": {
    "til" : "~1.2",
    "elf" : "~1.2.3",
    "two" : "2.x",
    "thr" : "3.3.x",
    "lat" : "latest",
    "dyl" : "file:../dyl"
  },
  "optionalDependencies": {
    "express": "expressjs/express",
    "mocha": "mochajs/mocha#4727d357ea",
    "module": "user/repo#feature\/branch"
  }
}
```

### `Cargo.toml`

*Ultimately this is not a good choice because it lacks interoperability with existing JavaScript tooling, but could be considered if we anticipate that we can get tooling to use this format.*

To express npm dependencies, add a table to your `Cargo.toml` called `npm`. This table will have a key-value store of the dependencies you would like to use. The key is the name of the dependency followed by a value that is consistent with dependency values as specc’d in [this document](https://docs.npmjs.com/files/package.json#dependencies), many of which are demonstrated in the below example.

```toml
# Cargo.toml

[package]
#...

[dependencies]
#...

[npm]
moment = "~2.22" 
#sugar for moment = { version: "~2.22", type: prod }
mocha = { version: "mochajs/mocha#4727d357ea", type: dev }
chai = { version: "^4", type: dev }
optional = { version: "6.6.6", type: optional }
git = { version: "http://asdf.com/asdf.tar.gz" }
```

### New Manifest File Format
*We rejected this outright based on inherent complexity, community exhaustion, and its lack of interoperability with JavaScript tooling.*

### Inline Annotations
*This was the original solution that was implemented. It was good because it worked equally well with Rust and other languages such as C or C++. It was not good because it added high management complexity and lacked operability with JavaScript tooling.*

This would look like this, and have no external manifest file:

```rust
#[wasm_bindgen(module = "moment", version = "2.0.0")]
extern {
    type Moment;
    fn moment() -> Moment;
    #[wasm_bindgen(method)]
    fn format(this: &Moment) -> String;
}
```
