- Start Date: 2018-07-10
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Support defining single inheritance relationships in `wasm-bindgen`'s imported
types, and how to up- and downcast between concrete types in the emitted
bindings. For the proc-macro frontend, we add the `#[wasm_bindgen(extends =
Base)]` attribute to the derived type. For the WebIDL frontend, we will use
WebIDL's existing interface inheritance syntax. Finally, we introduce the
`wasm_bindgen::Upcast` and `wasm_bindgen::Downcast` traits, which can be used to
up- and downcast concrete types at runtime. `wasm-bindgen` will emit
implementations of these traits as in its generated bindings.

# Motivation
[motivation]: #motivation

Prototype chains and ECMAScript classes allow JavaScript developers to define
single inheritance relationships between types. [WebIDL interfaces can inherit
from one another,][webidl-inheritance] and Web APIs make widespread use of this
feature. We want to be able to support these features in `wasm-bindgen`.

# Stakeholders
[stakeholders]: #stakeholders

Anyone who is using `wasm-bindgen` directly or transitively through the
`web-sys` crate is affected. This does *not* affect the larger wasm ecosystem
outside of Rust (eg Webpack). Therefore, the usual advertisement of this RFC on
*This Week in Rust and WebAssembly* and at our working group meetings should
suffice in soliciting feedback.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

## Simplest Example

Consider the following JavaScript class definitions:

```js
class MyBase { }
class MyDerived extends MyBase { }
```

We translate this into `wasm-bindgen` proc-macro imports like this:

```rust
#[wasm_bindgen]
extern {
    pub extern type MyBase;

    #[wasm_bindgen(extends = MyBase)]
    pub extern type MyDerived;
}
```

Note the `#[wasm_bindgen(extends = MyBase)]` annotation on `extern type
MyDerived`. This tells `wasm-bindgen` that `MyDerived` inherits from
`MyBase`. In the generated bindings, `wasm-bindgen` will emit these trait
implementations:

1. `Upcast for MyDerived`,
2. `From<MyDerived> for MyBase`, and
3. `Downcast<MyDerived> for MyBase`

Using these trait implementations, we can cast between `MyBase` and `MyDerived`
types:

```rust
// Get an instance of `MyDerived` from somewhere.
let derived: MyDerived = get_derived();

// Upcast the `MyDerived` instance into a `MyBase` instance. This could also be
// written `derived.into()`.
let base: MyBase = derived.upcast();

// Downcast back into an instance of `MyDerived`. We `unwrap` because we know
// that this instance of `MyBase` is also an instance of `MyDerived` in this
// particular case.
let derived: MyDerived = base.downcast().unwrap();
```

## The Casting Traits

### `Upcast`

The `Upcast` trait allows one to cast a derived type "up" into its base
type. The trait methods are safe because if a type implements `Upcast` then we
statically know that it is also an `Upcast::Base`. Implementing the trait is
`unsafe` because if you incorrectly implement it, it allows imported methods to
be called with an incorrectly typed receiver.

```rust
pub unsafe trait Upcast {
    type Base: From<Self>;

    fn upcast(self) -> Self::Base;
    fn upcast_ref(&self) -> &Self::Base;
    fn upcast_mut(&mut self) -> &mut Self::Base;
}
```

Under the hood, all these upcasts are implemented with `transmute`s. Here is an
example implementation of `Upcast` that might be emitted by `wasm-bindgen`:

```rust
unsafe impl Upcast for MyDerived {
    type Base = MyBase;

    #[inline]
    fn upcast(self) -> Self::Base {
        unsafe { std::mem::transmute(self) }
    }

    #[inline]
    fn upcast_ref(&self) -> &Self::Base {
        unsafe { std::mem::transmute(self) }
    }

    #[inline]
    fn upcast_mut(&mut self) -> &mut Self::Base {
        unsafe { std::mem::transmute(self) }
    }
}
```

### `Downcast`

Casting "down" from an instance of a base type into an instance of a derived
type is fallible. It involves a dynamic check to see if the base instance is
also an instance of the derived type. The `downcast_{ref,mut}` methods return an
`Option` since casting failure doesn't withhold access to the original base
instance. The `downcast(self)` method returns a `Result` whose `Err` variant
gives ownership of the original base instance back to the caller. Because of the
`T: Upcast<Self>` bound, the `Downcast` trait does not need to be `unsafe`;
attempts to implement `Downcast<SomeTypeThatIsNotDerivedFromSelf>` will fail to
compile.

```rust
pub trait Downcast<T>
where
    T: Upcast<Self>
{
    fn downcast(self) -> Result<T, Self>;
    fn downcast_ref(&self) -> Option<&T>;
    fn downcast_mut(&mut self) -> Option<&mut T>;
}
```

The dynamic checks are implemented with `wasm-bindgen`-generated imported
functions that use the `instanceof` JavaScript operator.

```js
const __wbindgen_instance_of_MyDerived(idx) =
  idx => getObject(idx) instanceof MyDerived ? 1 : 0;
```

```rust
#[cfg(all(target_arch = "wasm32", not(target_os = "emscripten")))]
#[wasm_import_module = "__wbindgen_placeholder__"]
extern {
    fn __wbindgen_instance_of_MyDerived(idx: u32) -> u32;
}

#[cfg(not(all(target_arch = "wasm32", not(target_os = "emscripten"))))]
unsafe extern fn __wbindgen_instance_of_MyDerived(_: u32) -> u32 {
    panic!("function not implemented on non-wasm32 targets")
}

impl Downcast<MyDerived> for MyBase {
    #[inline]
    fn downcast(self) -> Result<MyDerived, MyBase> {
        unsafe {
            if __wbindgen_instance_of_MyDerived(self.obj.idx) == 1 {
                Ok(std::mem::transmute(self))
            } else {
                Err(self)
            }
        }
    }

    #[inline]
    fn downcast_ref(&self) -> Option<&MyDerived> {
        unsafe {
            if __wbindgen_instance_of_MyDerived(self.obj.idx) == 1 {
                Some(std::mem::transmute(self))
            } else {
                None
            }
        }
    }

    #[inline]
    fn downcast_mut(&mut self) -> Option<&mut MyDerived> {
        unsafe {
            if __wbindgen_instance_of_MyDerived(self.obj.idx) == 1 {
                Some(std::mem::transmute(self))
            } else {
                None
            }
        }
    }
}
```

# Drawbacks
[drawbacks]: #drawbacks

* We might accidentally *encourage* using this inheritance instead of the more
  Rust-idiomatic usage of traits.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

* We could instead use `From` and `TryFrom` instead of defining `Upcast` and
  `Downcast` traits. This would require more trait implementations, since we
  would be replacing `Upcast for MyDerived` with `From<MyDerived> for MyBase`,
  `From<&'a MyDerived> for &'a MyBase`, and `From<&'a mut MyDerived> for &'a mut
  MyBase`. Similar for downcasting.

* The `Upcast` trait could use type parameters for `Base` instead of an
  associated type. This would allow for defining multiple inheritance
  relationships. However, neither JavaScript nor WebIDL support multiple
  inheritance. Associated types also generally provide better type inference,
  and require less turbo fishing.

* Explicit casting does not provide very good ergonomics. There are a couple
  things we could do here:

  * Use the `Deref` trait to hide upcasting. This is generally considered an
    anti-pattern.

  * Automatically create a `MyBaseMethods` trait for base types that contain all
    the base type's methods and implement that trait for `MyBase` and
    `MyDerived`? Also emit a `MyDerivedMethods` trait that requires `MyBase` as
    a super trait, representing the inheritance at the trait level? This is the
    Rust-y thing to do and allows us to write generic functions with trait
    bounds. It is also orthogonal to casting between base and derived types! We
    leave exploring this design space to follow up RFCs.

# Unresolved Questions
[unresolved]: #unresolved-questions

* Should the `Upcast` and `Downcast` traits be re-exported in
  `wasm_bindgen::prelude`?

* Basically everything has `Object` at the root of its inheritance / prototype
  chain -- are we going to run up against orphan rule violations?

* Should the `instanceof` helper functions be generated and exposed as public
  utility methods for every imported type?

[webidl-inheritance]: https://heycam.github.io/webidl/#dfn-inherit
