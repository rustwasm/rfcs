- Start Date: 2018-07-10
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Support defining single inheritance relationships in `wasm-bindgen`'s imported
types. Specifically, we define static upcasts from a derived type to one of its
base types, checked dynamic casts from a type to any other type using
JavaScript's `instanceof` operator, and finally unchecked casts between any
JavaScript types as an escape hatch for developers. For the proc-macro frontend,
this is done by adding the `#[wasm_bindgen(extends = Base)]` attribute to the
derived type. For the WebIDL frontend, WebIDL's existing interface inheritance
syntax is used.

# Motivation
[motivation]: #motivation

Prototype chains and ECMAScript classes allow JavaScript developers to define
single inheritance relationships between types. [WebIDL interfaces can inherit
from one another,][webidl-inheritance] and Web APIs make widespread use of this
feature. We want to support calling base methods on an imported derived type and
passing an imported derived type to imported functions that expect a base type
in `wasm-bindgen`. We want to support dynamically checking whether some JS value
is an instance of a JS class, and dynamically-checked casts. Finally, the same
way that `unsafe` provides an encapsulatable escape hatch for Rust's ownership
and borrowing, we want to provide unchecked (but safe!) conversions between JS
classes and values.

# Stakeholders
[stakeholders]: #stakeholders

Anyone who is using `wasm-bindgen` directly or transitively through the
`web-sys` crate is affected. This does *not* affect the larger wasm ecosystem
outside of Rust (eg Webpack). Therefore, the usual advertisement of this RFC on
*This Week in Rust and WebAssembly* and at our working group meetings should
suffice in soliciting feedback.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

## Example Usage

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
MyDerived`. This tells `wasm-bindgen` that `MyDerived` inherits from `MyBase`.

Alternatively, we could describe these same classes as WebIDL interfaces:

```webidl
interface MyBase {}
interface MyDerived : MyBase {}
```

### Example Upcasting

We can upcast into a `MyBase` from a `MyDerived` type using the normal `From`
and `Into` conversions:

```rust
let derived: MyDerived = get_derived_from_somewhere();
let base: MyBase = derived.into();
```

### Example Dynamically-Checked Casting

We can do dynamically-checked downcasts from a `MyBase` into a `MyDerived`:

```
let base: MyBase = get_base_from_somewhere();
match base.try_into::<MyDerived>() {
    Ok(derived) => {
        // It was an instance of `MyDerived`!
    }
    Err(base) => {
        // It was some other kind of instance of `MyBase`.
    }
}
```

### Example Unchecked Casting

If we really know that a `MyBase` is an instance of `MyDerived` and we don't
want to pay the cost of a dynamic check, we can also use unchecked conversions:

```rust
let derived: MyDerived = get_derived_from_somewhere();
let base: MyBase = derived.into();

// We know that this is a `MyDerived` since we *just* converted it into `MyBase`
// from `MyDerived` above.
let derived: MyDerived = base.unchecked_into();
```

Unchecked casting serves as an escape hatch for developers, and while it can
lead to JavaScript exceptions, it cannot create memory unsafety.

## Foundation: The `InstanceOf` Trait

For dynamically-checked and arbitrary unchecked casting, we introduce the
`InstanceOf` trait. It provides a boolean predicate that whose implementations
consult JavaScript's `isntanceof` operator, as well as unchecked conversions
from JavaScript values.

```rust
pub trait InstanceOf {
    fn instanceof(val: &JsValue) -> bool;

    fn unchecked_from_js(val: JsValue) -> Self;
    fn unchecked_from_js_ref(val: &JsValue) -> &Self;
    fn unchecked_from_js_mut(val: &mut JsValue) -> &mut Self;
}
```

`InstanceOf` is not intended to be used to directly, but instead as a bound on
type parameters for generic methods on `JsValue` and imported types. Users of
`wasm-bindgen` will be able to ignore `InstanceOf` for the most part.

For every `extern type Whatever` imported with `wasm-bindgen`, we emit an
implementation of `InstanceOf` similar to this:

```rust
impl InstanceOf for Whatever {
    fn instanceof(val: &JsValue) -> bool {
        #[cfg(all(target_arch = "wasm32", not(target_os = "emscripten")))]
        #[wasm_import_module = "__wbindgen_placeholder__"]
        extern {
            fn __wbindgen_instanceof_Whatever(idx: u32) -> u32;
        }

        #[cfg(not(all(target_arch = "wasm32", not(target_os = "emscripten"))))]
        unsafe extern fn __wbindgen_instanceof_Whatever(_: u32) -> u32 {
            panic!("function not implemented on non-wasm32 targets")
        }

        __wbindgen_instance_of_MyDerived(val.idx) == 1
    }

    fn unchecked_from_js(val: JsValue) -> Whatever {
        Whatever {
            obj: val,
        }
    }

    fn unchecked_from_js_ref(val: &JsValue) -> &Whatever {
        unsafe {
            &*(val as *const JsValue as *const Whatever)
        }
    }

    fn unchecked_from_js_mut(val: &mut JsValue) -> &mut Whatever {
        unsafe {
            &mut *(val as *mut JsValue as *mut Whatever)
        }
    }
}
```

## Upcasting Implementation

For every `extends = MyBase` on a type imported with `extern type MyDerived`,
and for every base and derived interface in a WebIDL interface inheritance
chain, `wasm-bindgen` will emit these trait implementations that wrap unchecked
conversions methods from `InstanceOf` that we know are valid due to the
inheritance relationship:

1. A `From` implementation for `self`-consuming conversions:

   ```rust
   impl From<MyDerived> for MyBase {
       fn from(my_derived: MyDerived) -> MyBase {
           let val: JsValue = my_derived.into();
           <MyDerived as InstanceOf>::unchecked_from_js(val)
       }
   }
   ```

2. An `AsRef` implementation for shared reference conversions:

   ```rust
   impl AsRef<MyBase> for MyDerived {
       fn as_ref(&self) -> &MyDerived {
           let val: &JsValue = self.as_ref();
           <MyDerived as InstanceOf>::uncheck_from_js_ref(val)
       }
   }
   ```

3. An `AsMut` implementation for exclusive reference conversions:

   ```rust
   impl AsMut<MyBase> for MyDerived {
       fn as_mut(&mut self) -> &mut MyDerived {
           let val: &mut JsValue = self.as_mut();
           <MyDerived as InstanceOf>::uncheck_from_js_mut(val)
       }
   }
   ```

## The `JsCast` Trait

The `JsCast` trait wraps the `InstanceOf` trait to provide unchecked arbitrary
casting and dynamically-checked, fallible casting for `JsValue` and imported JS
classes.

```rust
pub trait JsCast
where
    Self: AsRef<JsValue> + AsMut<JsValue> + Into<JsValue>,
{
    // Unchecked conversions.

    fn unchecked_into<T>(self) -> T
    where
        T: InstanceOf,
    {
        T::unchecked_from_js(self.into())
    }
    fn unchecked_ref<T>(&self) -> &T
    where
        T: InstanceOf,
    {
        T::unchecked_from_js_ref(self.as_ref())
    }
    fn unchecked_mut<T>(&mut self) -> &mut T
    where
        T: InstanceOf,
    {
        T::unchecked_from_js_mut(self.as_mut())
    }

    // Dynamic instanceof check.

    fn is_instance_of<T>(&self) -> bool
    where
        T: InstanceOf,
    {
        T::instanceof(self.as_ref())
    }

    // Dynamically-checked conversions.

    fn try_into<T>(self) -> Result<T, Self>
    where
        T: InstanceOf,
    {
        if self.is_instance_of::<T>() {
            Ok(self.unchecked_into())
        } else {
            Err(self)
        }
    }

    fn try_ref<T>(&self) -> Option<&T>
    where
        T: InstanceOf,
    {
        if self.is_instance_of::<T>() {
            Some(self.unchecked_ref())
        } else {
            None
        }
    }

    fn try_mut<T>(&mut self) -> Option<&mut T>
    where
        T: InstanceOf,
    {
        if self.is_instance_of::<T>() {
            Some(self.unchecked_mut())
        } else {
            None
        }
    }
}
```

Using these methods provides better turbo-fishing syntax than using `InstanceOf`
trait methods directly.

```rust
fn get_it() -> JsValue { ... }

// Wack
SomeJsThing::unchecked_from_js(get_it()).method();

// Wow! Much chain, very ergo!
get_it()
    .unchecked_into::<SomeJsThing>()
    .method();
```

### `JsCast` Blanket Implementation

We provide a blanket implementation of `JsCast` for anything that is `JsValue`-y
in that it and its references can be converted into `JsValue`s. This covers all
`wasm-bindgen`-imported JS classes.

```rust
impl<T> JsCast for T where T: AsRef<JsValue> + AsMut<JsValue> + Into<JsValue> {}
```

We also add `AsRef<JsValue>` and `AsMut<JsValue>` implementations for `JsValue`
itself, so that the blanket implementation applies to `JsValue`:

```rust
impl AsRef<JsValue> for JsValue {
    fn as_ref(&self) -> &JsValue {
        self
    }
}

impl AsMut<JsValue> for JsValue {
    fn as_mut(&mut self) -> &mut JsValue {
        self
    }
}
```

## Deep Inheritance Chains Example

For deeper inheritance chain, like this example:

```js
class MyBase {}
class MyDerived extends MyBase {}
class MyDoubleDerived extends MyDerived {}
```

the proc-macro imports require an `extends` attribute for every transitive base:

```rust
#[wasm_bindgen]
extern {
    pub extern type MyBase;

    #[wasm_bindgen(extends = MyBase)]
    pub extern type MyDerived;

    #[wasm_bindgen(extends = MyBase, extends = MyDerived)]
    pub extern type MyDoubleDerived;
}
```

On the other hand, the WebIDL frontend can understand the full inheritance chain
and nothing more than the usual interface inheritance syntax is required:

```webidl
interface MyBase {}
interface MyDerived : MyBase {}
interface MyDoubleDerived : MyDerived {}
```

Given these definitions, we can upcast a `MyDoubleDerived` all the way to a
`MyBase`:

```rust
let dub_derived: MyDoubleDerived = get_it_from_somewhere();
let base: MyBase = dub_derived.into();
```

# Drawbacks
[drawbacks]: #drawbacks

* We might accidentally *encourage* using this inheritance instead of the more
  Rust-idiomatic usage of traits.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

* We could define an `Upcast` trait instead of using the standard `From` and
  `As{Ref,Mut}` traits. This would make it more clear that we are doing
  inheritance-related casts, but would also be a new trait that folks would have
  to understand vs pretty much every Rust programmer's familiarity with the
  `std` traits.

* We could use `TryFrom` for dynamically-checked casts instead of `JsCast`. This
  would introduce a new nightly feature requirement when using `wasm-bindgen`.

* Explicit upcasting still does not provide very good ergonomics. There are a
  couple things we could do here:

  * Use the `Deref` trait to hide upcasting. This is generally [considered an
    anti-pattern](https://github.com/rust-unofficial/patterns/blob/master/anti_patterns/deref.md).

  * Automatically create a `MyBaseMethods` trait for base types that contain all
    the base type's methods and implement that trait for `MyBase` and
    `MyDerived`? Also emit a `MyDerivedMethods` trait that requires `MyBase` as
    a super trait, representing the inheritance at the trait level? This is the
    Rust-y thing to do and allows us to write generic functions with trait
    bounds. This is what `stdweb` does with the `IHTMLElement` trait for
    `HTMLElement`'s methods.

    Whether we do this or not also happens to be orthogonal to casting between
    base and derived types. We leave exploring this design space to follow up
    RFCs, and hope to land just the casting in an incremental fashion.

* Traits sometimes get in the way of learning what one can do with a thing. They
  aren't as up-front in the generated documentation, and can lead people to
  thinking they *must* write code that is generic over a trait when it isn't
  necessary. There are two ways we could get rid of the `JsCast` trait:

  1. Only implement its methods on `JsValue` and require that conversions like
     `ImportedJsClassUno` -> `ImportedJsClassDos` go to `JsValue` in between:
     `ImportedJsClassUno` -> `JsValue` -> `ImpiortedJsClassDos`.

  2. We could redundantly implement all its methods on `JsValue` and imported JS
     classes directly.

* We could only implement unchecked casts for everything all the time. This
  would encourage a loose, shoot-from-the-hip programming style. We would prefer
  leveraging types when possible. We realize that escape hatches are still
  required at times, and we do provide arbitrary unchecked casts, but guide
  folks towards upcasting with `From`, `AsRef`, and `AsMut` and doing
  dynamically checks for other types of casts.

# Unresolved Questions
[unresolved]: #unresolved-questions

* Should the `JsCast` trait be re-exported in `wasm_bindgen::prelude`? It seems
  pretty clear that `InstanceOf` should not be, since it isn't intended to be
  used often. `JsCast` seems like it might be used often enough that it should
  be in the prelude. Either way, we can initially ship without re-exporting it
  in prelude and see what it feels like.

[webidl-inheritance]: https://heycam.github.io/webidl/#dfn-inherit
