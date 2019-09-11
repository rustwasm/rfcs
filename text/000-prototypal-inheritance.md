- Start Date: 2019-08-16
- RFC PR: 
- Tracking Issue: 

# Summary
[summary]: #summary

Enable each exported Rust struct to specify the prototype chain acquired by instances of its generated JavaScript shim.

This inheritance relationship should also be reflected on the Rust side, in the same way that `#[wasm_bindgen(extends)]` effects such relationships in classes imported from JavaScript by implementing relevant traits on the associated Rust struct.


# Motivation
[motivation]: #motivation

Some JavaScript APIs expect their clients to provide objects that inherit behaviour from another (usually supplied by the API) by ensuring that the latter is on the former's prototype chain.  For example:

* the object referenced by the `prototype` property of [`React.Component`](https://reactjs.org/docs/react-component.html) is expected to be on the prototype chain of one's [stateful React components](https://reactjs.org/docs/state-and-lifecycle.html); and

*  the object referenced by the `prototype` property of the relevant DOM constructor is expected to be on the prototype chain of one's [custom elements](https://html.spec.whatwg.org/multipage/custom-elements.html).

Correct consumption of such APIs in Rust via `wasm-bindgen` requires each object returned to JavaScript to have the appropriate prototype chain.


# Stakeholders
[stakeholders]: #stakeholders

The major stakeholders in this RFC are:  

* JavaScript library developers whose APIs expect clients to use prototypal delegation; and

* Users of `#[wasm_bindgen]` who wish to consume such APIs.

In respect of the former group, we have already identified the developers of React and the authors of the Web Component specification. ***It is not yet known how feedback can best be solicited from this group—input welcome!***

In respect of the latter group, various related issues have been identified in the `rustwasm` repositories and comments will be posted thereto directing contributors to this RFC.


# Detailed Explanation
[detailed-explanation]: #detailed-explanation

There are three key problems with the status quo that currently prevent exported types from participating in JavaScript's prototypal inheritance:

1. There is currently no way in Rust to specify the inheritance relationship and thereby guide what [`extends`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Classes/extends) clause should be generated on the JavaScript shim class, which makes it more difficult (if not impossible) to construct objects in the manner required by many APIs; indeed, Web Components' customized built-in elements explicitly require use of the `extends` clause, per the normative [core concepts](https://html.spec.whatwg.org/multipage/custom-elements.html#custom-elements-core-concepts) section of their specification.

2. Even if an `extends` clause is somehow generated, the shim's `constructor()` (which presently just wraps whatever WASM function was annotated with `#[wasm_bindgen(constructor)`) **must** invoke its super-constructor before returning: but there is presently no way to make this invocation from within WASM.  Moreover, the shim's `constructor()` presently returns an object other than `this`, which violates the expectations of many APIs (including the explicit [conformance requirements of Web Components' custom elements](https://html.spec.whatwg.org/multipage/custom-elements.html#custom-element-conformance)); changing this behaviour could necessitate the delegated WASM constructor having access to `this` in order to perform correct initialisation (e.g. where there is some dependency upon inherited behaviour or state set by super-constructors).

3. `wasm-bindgen`'s existing approach to passing WASM objects to JavaScript does not provide for their polymorphism into parent types on their return to WASM.  In particular, when WASM transfers out to JavaScript an opaque pointer (in fact the address of a boxed `WasmRefCell`) to some `Child` instance and later receives that pointer back as part of an incoming FFI that expects a pointer to a `Parent`, any resulting attempt to dereference the pointer as a `Parent` when it is in fact a `Child` will of course be Undefined Behaviour—despite the fact that this *should* be permitted under the inheritance relationship.

This RFC proposes a solution to all of these points, and furthermore also proposes a solution to the related problem of obtaining a [`JsValue`](https://rustwasm.github.io/wasm-bindgen/api/wasm_bindgen/struct.JsValue.html) for any given export or import which could be used, for example, to pass a `struct` to a JS API that expects a constructor function (such as [`web_sys::CustomElementRegistry::define`](https://rustwasm.github.io/wasm-bindgen/api/web_sys/struct.CustomElementRegistry.html#method.define)).

These problems are addressed in this order below, but consideration is at first only given to how exported types are instantiated from JavaScript; the problem of correctly instantiating exported types from within WASM is not visited until the third section (on FFI polymorphism).

### Generating `extends` clause in shim classes

A new attribute, `prototype`, is added to the `#[wasm_bindgen]` macro for this purpose; the stipulated prototype may be any Rust type that it is either (a) exported to or (b) imported from JavaScript.  For example:

```rust
// superclass exported to JavaScript
#[wasm_bindgen]
struct Parent {}
#[wasm_bindgen(prototype=Parent)]
struct Child {}

// superclass imported from JS
#[wasm_bindgen]
extern "C" {
    pub type ImportedParent;
}
#[wasm_bindgen(prototype=ImportedParent)]
pub struct ChildOfImportedParent { ... }

// or a built-in published by the `js_sys` crate
#[wasm_bindgen(prototype=js_sys::Date)]
pub struct CustomDate { ... }

// or a Web IDL implementation published by the `web_sys` crate
#[wasm_bindgen(prototype=web_sys::XmlHttpRequest)]
pub struct MyAjaxRequest { ... }
```

This inheritance relationship is then included within the custom `__wasm_bindgen_unstable` section of the compiled `.wasm`: in particular, as part of the encoding of each [`Struct`](https://docs.rs/wasm-bindgen-shared/0.2.50/src/wasm_bindgen_shared/lib.rs.html#115-119).  Since the relevant prototype will be defined elsewhere within that same section of that same `.wasm`, as either (a) another `Struct` or (b) an [`ImportType`](https://docs.rs/wasm-bindgen-shared/0.2.50/src/wasm_bindgen_shared/lib.rs.html#82-86), internal identifiers are added to those types and used for referencing:

```rust
   struct ImportType<'a> {
+      id: TypeReference,
       name: &'a str,
       instanceof_shim: &'a str,
       vendor_prefixes: Vec<&'a str>,
   }

   struct Struct<'a> {
+      id: TypeReference,
       name: &'a str,
       fields: Vec<StructField<'a>>,
       comments: Vec<&'a str>,
+      prototype: Option<TypeReference>,
   }
```

*(The current prototype implementation encodes `TypeReference` in the generated `.wasm` as eight bytes: `[u8; 8]`, being the raw value of a unique `ShortHash`).*

Finally, the relevant `extends` clause is generated on the shim class (note that because class definitions are not hoisted, it will be necessary to ensure that exported classes are written out in the correct order: i.e. `Parent` *before* `Child`):

```javascript
-  export class Child {
+  export class Child extends Parent {
```

### The shim class constructor

New descriptors are defined, one for each of two possible callbacks from the delegated WASM "constructor" to arrow functions that are declared within the JavaScript shim constructor—these callbacks, respectively: (i) invoke `super()` with [spread](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Spread_syntax) arguments; and (ii) return `this`.  The generated shim constructor then passes those arrow functions in place of any WASM constructor arguments of the relevant type.

```rust
   #[wasm_bindgen(prototype=Parent)]
   struct Child {}

   #[wasm_bindgen]
   impl Child {
       #[wasm_bindgen(constructor)]
       fn new(_super: wasm_bindgen::SuperconstructorCallback, a: u32, b: u32) -> {
           _super.invoke(vec![
               // JsValues of super-constructor arguments here
           ]);
           Child {}
       }
   }
```

*(The `.invoke()` method is implemented with the assistance of a new intrinsic function)*.

In the above example, the `_super` argument is described as a `SUPERCONSTRUCTOR_CALLBACK` which results in the following JavaScript shim:

```javascript
   export class Child extends Parent {
       constructor(a, b) {
-          const ret = wasm.child_new(a, b);
-          return Child.__wrap(ret);
+          const _super = (...args) => super(...args);
+          this.ptr = wasm.child_new(addHeapObject(_super), a, b);
       }
   }
```

Similarly, an argument of type `wasm_bindgen::ThisCallback` is described as `THIS_CALLBACK` and receives `() => this`.

### FFI polymorphism

Two issues arise, regarding the internal pointers these shim objects maintain to their underlying WASM objects:

1. A pure JS class that extends an exported WASM type may overwrite `this.ptr` or otherwise abuse it.  The internal pointer should therefore be stored under a property keyed by internal [Symbol](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Symbol) instead:

    ```javascript
    +  const WASM_PTRS = Symbol();
    
       export class SomeClass {
           // ...
    -      this.ptr
    +      this[WASM_PTRS]
           // ...
       }
    ```

2. Objects in JavaScript must maintain pointers to WASM objects *for each exported type in their prototype chains*, however there is only one `this[WASM_PTRS]` for a given object.  The pointers should therefore be held in a sub-object (again keyed by Symbol, this time to avoid name collisions)—and instance methods will then be able to access the correct pointer for any FFI calls they need to make:

    ```javascript
       const WASM_PTRS = Symbol();
    +  const PTR_KEY = Symbol();

       export class Parent {
           // ...
    -      this[WASM_PTRS]
    +      this[WASM_PTRS][Parent[PTR_KEY]]
           // ...
       }
    +  Parent[PTR_KEY] = Symbol();
    
       export class Child extends Parent {
           // ...
    -      this[PTR]
    +      this[PTR][Child[PTR_KEY]]
           // ...
       }
    +  Class[PTR_KEY] = Symbol();
    ```

### Obtaining `JsValue` of imports and exports

1. On start-up, JS glue module populates a `DEFINITION_MAP` of internal-identifiers-to-exported-objects:

    ```javascript
    +  const DEFINITION_MAP = {};

       export class Child {
           // ...
       }

    +  Object.assign(DEFINITION_MAP, {
    +      "uniqueid": Child,
    +      // ...
    +  });
    ```

2. A new intrinsic function is exported from JavaScript that uses this map to look-up a sought export by its identifier and return the result:

    ```javascript
    +  export const __wbindgen_export_get = function(identifier) {
    +      return addHeapObject(DEFINITION_MAP[identifier]);
    +  };
    ```

3. A new trait `WasmBindgenReferenceable` is implemented on structs exported from Rust, providing access to a unique identifier (actually in the prototype implementation this happens to be their `TypeReference` used above, but this is not mandatory):

    ```rust
    +  trait WasmBindgenReferenceable {
    +      const ID: [u8; 8];
    +  }
    +   
    +  impl WasmBindgenReferenceable for Child {
    +      const ID: [u8; 8] = b"uniqueid";
    +  }
    ```

4. Finally, a static generic method can call into the lookup function in order to obtain the relevant constructor as a `JsValue`:

    ```rust
       externs! {
           #[link(wasm_import_module = "__wbindgen_placeholder__")]
           extern "C" {
               // ...
    +          fn __wbindgen_export_get(identifier: u64) -> u32;
           }
       }

       impl JsValue {
           // ...
    +      #[inline]
    +      pub fn from_export::<T: WasmBindgenExport>() -> JsValue {
    +          JsValue::_new(unsafe {
    +              __wbindgen_export_get(
    +                  u64::from_be_bytes(<T as WasmBindgenExport>::ID)
    +              )
    +          })
    +      }
       }
    ```

*(The prototype implementation actually breaks the 64-bit identifier into two `u32` arguments for transfer across the ABI, and on the JavaScript side these are represented as the concatenation of their base-32 representations.  See unresolved question #3.)*

### Object instantiation

1. Change the body of methods annotated with `#[wasm_bindgen(constructor)]` to simply forward their arguments to the shim constructor, through a new intrinsic function (that specifies the desired JavaScript class to be instantiated using the above lookup).  Such methods will therefore now return a `JsValue` representing the shim object.

2. Change the exported instantiation function that is called by the shim constructor so that, instead of *delegating* to the now-altered receiver (i.e. the above method annotated with the `#[wasm_bindgen(constructor)]` attribute), the original contents of that receiver are instead moved inside this exported function (the result is still stored on the heap in a `WasmRefCell`, a pointer to which is returned to the shim constructor over the ABI).

3. Remove implementations of `IntoWasmAbi`, `OptionIntoWasmAbi`, `FromWasmAbi`, `OptionFromWasmAbi` and `From<#name> for JsValue` from derived exported types to ensure that any such objects instantiated outside of the nominated constructor function cannot be erroneously sent to JavaScript.

# Drawbacks
[drawbacks]: #drawbacks

* Additional runtime overhead (see unresolved question #1).

* Surprising behaviour (see unresolved question #2).

* Increased complexity.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

### Object instantiation

This is perhaps the most significant change being proposed, with the greatest impact.

Currently, instantiating an exported WASM type (i.e. Rust struct annotated with `#[wasm_bindgen]`) from within Rust does just that; no JavaScript shim object is generated unless/until the WASM instance is sent over the FFI to JavaScript whereupon it is "wrapped" by the shim class's static `__wrap()` method.  This method instantiates the shim using [`Object.create()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/create) and thereby avoids calling the class's constructor function.  If ownership of the underlying WASM object returns to WASM, the shim object is destroyed; should the WASM object be sent across the FFI to JavaScript again, an entirely new shim object is instantiated to wrap it.

This approach works for the status quo because the shim objects are mere wrappers for the underlying WASM object, holding no state of their own beyond what is necessary for forwarding all behaviours over the FFI.  Moreover, there is no need to invoke the shim's constructor (which merely instantiates and wraps a fresh underlying WASM object) because the underlying WASM object to be wrapped already exists.

However, this approach no longer works once the exported type specifies a prototype chain: it would result in only partially constructed shims, because super-constructors would not have been invoked (potentially necessary for establishing state required by methods on the prototype chain—which might include linking to other WASM objects should other exported types be on the prototype chain).

Shims for exported derived types (i.e. those that specify a `[#wasm_bindgen(prototype)]` attribute) must therefore *always* be constructed with the [`new`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/new) operator.  Since this might necessarily touch code outside of the derived type itself (indeed, potentially outside the user's own control), it should occur at most *once* per WASM object: that is, the fully constructed shim should survive until it will never be required in JavaScript again—it is not acceptible to construct a second shim for the same object.

It is conceivable that this could be accomplished in such a way that shim construction occurs, as in the status quo, only when a WASM object is sent over the FFI and requires wrapping—however, ensuring that the super-constructor is invoked with appropriate arguments (which might be some function of the object's state) and then maintaining the shim object for the long-term (where would it be "owned"?) would be complex.  Instead, it is proposed to do away entirely with the notion of "wrapping" instances of exported derived types and instead to require that their instantiation always occurs via the shim constructor and therefore always returns the shim object.

### Use of `ShortHash` identifiers for `TypeReference` and `FunctionReference`

The new `prototype` attribute for `#[wasm_bindgen]` takes a path to a Rust type as its value.  However, since the proc macro is expanded before the compiler performs name resolution, resolving this path into an identifier that can be used in the generated bindings section is not straightforward: it is not, for example, possible to access metadata that is attached to the target type, such as the values of its own `#[wasm_bindgen]` attributes.

There are two possible solutions to this: (a) require the attribute value instead to be an identifier already known to wasm-bindgen (such as the desired target's import/export name); or (b) store a suitable identifier for each import/export in a constant that is at a known location, such that user-given paths can be converted into references to that constant.  The first option is not very ergonomic: it requires users to carefully track metadata (that may not even be their concern, e.g. if the target is from a library); and so, the second approach was adopted instead.

The "suitable identifier" used for the constant value could be variable-length (e.g. strings such as the item's import/export name), but only if a second constant is generated indicating the value's length (at least until rustc lands some const way to lookup that same information at compile-time).  Furthermore, the identifier must be unique in the WASM module—and it wasn't clear whether this is guaranteed to be true of natural identifiers such as import/export names (at least not without additional context).  Consequently, fixed-size synthetic identifiers were selected for both their ease of implementation and their uniqueness guarantees.

`ShortHash` produces 64-bit hashes, encoded as 16-character hexadecimal strings.  To save space, these are converted back to their raw 8-byte values and stored as a constant `[u8; 8]` that is in turn referenced by the custom section byte-by-byte whenever a `TypeReference` or `FunctionReference` is encoded.

### Use of map for `DEFINITION_MAP`

This was again driven by implementation concerns, but mostly from reuse of the 8-byte `TypeReference` in the `__wbindgen_export_get` ABI call.  A sparse array was considered instead, but JavaScript does not currently support 8-byte integer array indexes—so conversion into map keys was necessary instead.

Rather than reusing the 8-byte bindgen identifiers, some other identifier from the bindgen could be used instead—e.g. the class name itself.  This could certainly aid debugging (and was indeed the first implementation that was prototyped).  It was however eventually dropped in favour of the `TypeReference` so that extending to imports would be trivial (else `__wbindgen_export_get` would somehow have to resolve potential key collisions/renamed imports).

During monomorphization of the `JsValue::from_export` function, rustc will determine a definitive list of all the exports that one's code can actually request—if this could somehow be injected into the bindgen, `DEFINITION_MAP` could be substantially reduced to only those imports/exports.

### Use of `extends`

Instead of inheriting the required behaviours via their prototype chain, objects returned to JavaScript could inherit them using composition instead.  However, this might violate the API's expectations (it certainly violates the conformance requirements of Web Components' custom elements): either because the library explicitly searches the prototype chain for the sought behaviour, or because it modifies the inherited behaviour after object creation.  Such an approach could therefore introduce outright failures through to subtle or difficult-to-trace bugs, and is therefore not considered a viable alternative.

Instead of setting the prototype of constructed objects via the `extends` clause, they could instead be set with [`Object.setPrototypeOf()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/setPrototypeOf) or similar.  This would enable one to specify as prototypes objects that are not themselves classes/constructors, but prevents one from invoking the parent's [`[[Construct]]`](https://www.ecma-international.org/ecma-262/10.0/index.html#sec-ecmascript-function-objects-construct-argumentslist-newtarget) internal method, which `extends` enables via `super()`.  Calling the parent's `[[Construct]]` internal method is, in the author's view, a more common requirement than setting the prototype to a non-constructor object (and, again, it is indeed required of Web Components' custom elements).

# Unresolved Questions
[unresolved]: #unresolved-questions

1. Having to call from WASM to JavaScript (and back) in order to instantiate objects of exported types adds runtime overhead.  How significant is it?  Should it occur for derived types only?

2. Receiving a `JsValue` from `#[wasm_bindgen(constructor)]` methods that appear to return instances of their actual Rust type is rather surprising.  Perhaps the user should be required to give the method such an explicit return type in its signature, and to (at very least) call a no-op macro upon returned values to signify their transformation?

3. Rather than using synthetic identifiers (8-byte raw `ShortHash` values), should we instead use natural identifiers such as the item's import/export name?  This would aid debugging and, at least in modules with relatively few references (suspected to be the majority), smaller file sizes; however, calls to `__wbindgen_export_get` would involve more data being copied over the ABI (albeit without then any need to decode into suitable property keys in the lookup maps).  Are the import/export names guaranteed to be unique?