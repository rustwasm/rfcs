- Start Date: 2020-02-14
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Dramatically improve the ergonomics of error handling by adding a new
`try_catch` function and changing JS functions to no longer return `Result`.


# Motivation
[motivation]: #motivation

Right now almost all APIs in the wasm-bindgen ecosystem return
`Result<T, JsValue>`. This is true even in the cases where the API cannot error.

This causes a large amount of friction when using the APIs, because it is
necessary to either propagate the error or use `.unwrap_throw()`.

In addition, Rust has the policy that programmer errors should be handled via
`panic`, but runtime failures should be handled by `Result`. This distinction has
also been noticed in the JavaScript community, as shown in this 2014 article:

https://www.joyent.com/node-js/production/design/errors

But the current system with wasm-bindgen conflates those two together, with
programmer errors being handled via `Result`.

The current system also has a small performance cost, since every function/method
call must use `try`/`catch` to convert the error into `Result`. And this also
bloats up the generated JS glue file, because the `try`/`catch` cannot really
be deduplicated.

Lastly, the current system means we must always use JS glue code,
even after interface types are implemented in the browsers.

And all of the above costs are unavoidable: even if you *know* that it will never
error, you must still pay the cost in JS glue, file size, and runtime performance.

This means wasm-bindgen is not truly zero-cost. And unfortunately
this problem is pervasive throughout the entire wasm-bindgen ecosystem,
so even though the costs may be small for a single function, it adds up with
hundreds or thousands of functions.

As a more meta note, it is idiomatic in Rust to return custom error types,
such as `Result<T, MyCustomError>`. However the current system heavily
encourages users to *not* do that and instead just return `Result<T, JsValue>`.

The reason is because if you return `Result<T, JsValue>` then you can use the
`?` syntax, which is far more ergonomic. So by changing the error handling
system we can encourage users to create meaningful custom errors, rather
than `Result<T, JsValue>`.

Also, in the past we had made decisions to adopt a more JS-centric API
(such as using `Deref` rather than traits). This proposal is in line with
that, because it is idiomatic in JS to only use `try`/`catch` when needed,
rather than on every function call.


# Stakeholders
[stakeholders]: #stakeholders

This affects basically the entire wasm-bindgen ecosystem, since it is a
breaking change for the `js-sys` and `web-sys` crates.

I'm not sure what approach is appropriate for gaining feedback.


# Detailed Explanation
[detailed-explanation]: #detailed-explanation

The current system looks like this:

```rust
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(catch)]
    fn foo() -> Result<u32, JsValue>;
}

fn bar() {
    foo().unwrap_throw();
}
```

This generates the following JS glue code:

```js
imports.wbg.__wbg_foo_12a2d9a2dfcf125f = function() {
    try {
        var ret = foo();
        return ret;
    } catch (e) {
        handleError(e);
    }
};
```

What I propose is to remove the `catch` attribute and no longer
have `wasm_bindgen` functions return `Result`.

Instead, wasm-bindgen would define a new `try_catch` function, with
this signature:

```rust
fn try_catch<A, F>(f: F) -> Result<A, JsValue>
    where F: FnOnce() -> A + UnwindSafe
```

This function would call a new primitive, which basically does this:

```js
function try_catch(f) {
    try {
        return f();
    } catch (e) {
        handleError(e);
    }
}
```

(It will actually be implemented differently, because it has to call a
Rust closure, not a JS function, but that's implementation details.)

Now it is possible to catch JS errors and convert them into `Result`:

```rust
#[wasm_bindgen]
extern "C" {
    fn foo() -> u32;
}

fn bar() {
    try_catch(|| foo()).unwrap_throw();
}
```

This has the same behavior as the earlier code which uses the `catch`
attribute.

However, it fixes all of the issues described in the motivation:

* Users don't need to use `try_catch` in the situations where they know
   that the call won't error.

* Users don't need to use `try_catch` in the situations where the error
  is a programmer error and not a runtime failure.

* Users can put multiple calls within the `try_catch` closure, thus
   amortizing the runtime costs.

* The `try`/`catch` functionality only needs to be defined once,
   rather than repeated in every `catch` function.

* The JS glue code is significantly reduced, and with interface types
   it can be completely eliminated.

* With the current system, if the author did not use the `catch`
   attribute then you cannot catch the error. But with `try_catch` you
   can! Thus this is more flexible.


# Drawbacks
[drawbacks]: #drawbacks

* This is a major breaking change to the entire ecosystem. It will obviously
   need major version bumps in `wasm-bindgen`, `js-sys`, `web-sys`, and any
   crates which transitively use them.

   Therefore, if this is accepted we should make the change ASAP, so we can
   minimize the pain of transitioning. It's better to make a large change like
   this now, rather than later when there are more people using Wasm.

* Another drawback is that this can encourage users to not handle errors at
   all, because the APIs no longer return `Result`.

   However, in practice users already don't handle errors (they just use
   `.unwrap_throw()`), and it is difficult to properly handle errors in JS
   anyways, because you need to do string parsing to figure out what the
   error is.

   So if we want to encourage users to properly handle errors, I think
   there are far better ways to do that, such as providing excellent
   APIs for parsing and handling errors.

   Also, the current system of always returning `JsValue` is really terrible
   for error handling. It is far better to create custom errors, which is
   something that gloo can do.


# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

Obviously we can choose to not do this, but that means accepting all of
the problems in the Motivation forever.

I'm unaware of any other alternatives.


# Future Extensions
[future]: #future-extensions

N/A


# Unresolved Questions
[unresolved]: #unresolved-questions

The implementation will be a little tricky, it basically involves boxing
the `FnOnce` closure, sending the pointer to JS, then having JS call back
into Wasm with that pointer.

It's also an open question how things like Rust panics will be handled.
I added `UnwindSafe` to the signature for `try_catch`, which is *probably*
good enough, but I haven't thought particularly hard about this.

And right now there isn't good interop between Wasm traps and JS exceptions,
and the Wasm exceptions standard is still up in the air. So we don't really know
how all of that will play out.

However, I imagine that eventually Wasm will get first-class support for
unwinding and catching JS exceptions, and the `try_catch` function will be
able to seamlessly use that in the future.
