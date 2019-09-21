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

1. Exported type `T` **MAY** be annotated with an additional input to its `#[wasm_bindgen]` outer attribute: namely `prototype=path::to::Parent`, where `Parent` is either an imported or another exported wasm-bindgen type.

2. A field is injected into the definition of `T`; it is either named `__proto__` or appended to the existing unnamed field list, as appropriate (unit types are converted to having a single field named `__proto__`).  This injected field is either of type `Parent` (if the `prototype` input was specified above), or else of type `JsValue` (otherwise).  Users never need access this field directly; instead `T` implements both `Deref<Target=Parent>` (or `Target=JsValue`, as appropriate) and `DerefMut` that return references to it.

3. In JavaScript, the generated `class T [extends Parent]` has a `constructor()` that forwards its arguments (together with either a `(...args) => { super(...args); return this[WASM_PTR]; }` or a `() => addHeapObject(this)` callback, for derived and base classes respectively) to a generated/exported Rust function.  The user-provided instantiation code (from method annotated with `#[wasm_bindgen(constructor)]`) is injected into the body of this generated export, and **MUST** use a new `instantiate! {}` macro that does the following:

    - invokes the super-constructor via the injected callback, with provided arguments (if relevant);
    - instantiates a `T` object in Rust with the correct value injected into the `__proto__` (or unnamed) field specified above;
    - wraps that instantiated object as `Box<WasmRefCell<T>>`;
    - mutably borrows from that `WasmRefCell<T>`, obtaining a `RefMut<T>` that is returned in the final step below;
    - converts the box `into_raw()` and sends the value of the resulting raw pointer to JavaScript for storage on the shim object, effectively transferring to the shim object "ownership" of the `WasmRefCell` (which in turn owns `T` and all its prototype objects via the chain of injected fields);
    - returns the `RefMut<T>` from the step before last.

4. The body of the method annotated with `#[wasm_bindgen(constructor)]` is replaced so that it merely forwards its arguments to an invocation of `new T()` in JavaScript; it **MUST** have a `RefMut<T>` return type.

For example, one might have the following:

```rust
#[wasm_bindgen]
pub struct Parent { area: u32 }

#[wasm_bindgen]
impl Parent {
    #[wasm_bindgen(constructor)]
    pub fn new(area: u32) -> RefMut<Parent> {
        insantiate! { Parent { area } }
    }

    fn parent_method(&mut self) {}
}

#[wasm_bindgen(prototype=Parent)]
pub struct Child(Foo, Bar);

#[wasm_bindgen]
impl Child {
    #[wasm_bindgen(constructor)]
    pub fn new(foo: Foo) -> RefMut<Child> {
        let this = instantiate! {
            super(123);
            Child(foo, Bar::default())
        };

        this.parent_method();

        this
    }
}
```

In broad strokes (implementation details may differ), the above might expand to (amongst other things) the following—

```rust
extern "C" {
    fn __wbindgen_instantiate(ctor: u32, args: WasmSlice) -> u32;
    fn __wbindgen_invoke(func: u32, args: WasmSlice) -> u32;
    fn __wbindgen_wasm_pointer_set(idx: u32, ptr: u32);
}

trait WasmType { const ID: u32; }

pub struct Parent { area: u32, __proto__: JsValue }
impl WasmType for Parent { const ID = 12345; }

impl Deref for Parent {
    type Target = JsValue;
    fn deref(&self) -> &JsValue { &self.__proto__ }
}

impl Parent {
    pub fn new(area: u32) -> RefMut<Parent> {
        let args: Box([JsValue]) = Box::new([ area.into() ]);
        let ptr = unsafe { __wbindgen_instantiate(Parent::ID, args.into()) }
            as *WasmRefCell<Parent>;

        return (unsafe { *ptr }).borrow_mut();

        pub extern "C" fn __wasm_bindgen_generated_Parent_new(area: u32, _callback : u32) {
            let _ret = {
                let area = unsafe { u32::from_abi(area) };

                {
                    let args: Box([JsValue]) = Box::new([]);
                    let __proto__ = unsafe {
                        JsValue::from_abi(__wbindgen_invoke(_callback, args.into()))
                    };
                    let wrapped = Box::new(WasmRefCell::new(
                        Parent { area, __proto__ }
                    ));

                    let borrowed = wrapped.borrow_mut();
                    let idx = <&JsValue>::from(borrowed).into_abi();
                    let ptr = Box::into_raw(wrapped) as u32;

                    unsafe { __wbindgen_wasm_pointer_set(idx, ptr) };

                    borrowed
                }
            };
        }
    }

    fn parent_method(&mut self) {}
}

pub struct Child(Foo, Bar, Parent);
impl WasmType for Child { const ID = 67890; }

impl Deref for Child {
    type Target = Parent;
    fn deref(&self) -> &Parent { &self.2 }
}

impl DerefMut for Child {
    fn deref_mut(&mut self) -> &mut Parent { &mut self.2 }
}

impl Child {
    pub fn new(foo: Foo) -> RefMut<Child> {
        let args: Box([JsValue]) = Box::new([ foo.into() ]);
        let ptr = unsafe { __wbindgen_instantiate(Child::ID, args.into()) }
            as *WasmRefCell<Child>;

        return (unsafe { *ptr }).borrow_mut();

        pub extern "C" fn __wasm_bindgen_generated_Child_new(foo: u32, _callback : u32) {
            let _ret = {
                let foo = unsafe { Foo::from_abi(foo) };
                
                let this = {
                    let args: Box([JsValue]) = Box::new([ 123.into() ]);
                    let __proto__ = unsafe {
                        Parent::from_abi(__wbindgen_invoke(_callback, args.into()))
                    };
                    let wrapped = Box::new(WasmRefCell::new(
                        Child(foo, Bar::default(), __proto__)
                    ));

                    let borrowed = wrapped.borrow_mut();
                    let idx = <&JsValue as From>::from(borrowed).into_abi();
                    let ptr = Box::into_raw(wrapped) as u32;

                    unsafe { __wbindgen_wasm_pointer_set(idx, ptr) };

                    borrowed
                };
                
                this.parent_method();
                
                this
            };
        }
    }
}
```

and the generated JavaScript would be:

```javascript
const WASM_PTR = Symbol();  // to avoid collisions with prototype expectations for this.ptr

export class Parent {
    constructor(area) {
        try {
            let _callback = () => addHeapObject(this);
            wasm.__wasm_bindgen_generated_Parent_new(area, addBorrowedObject(_callback));
        } finally {
            heap[stack_pointer++] = undefined;
        }
    }
}

export class Child extends Parent {
    constructor(foo) {
        try {
            let _callback = (...args) => { super(...args); return this[WASM_PTR]; };
            wasm.__wasm_bindgen_generated_Child_new(addBorrowedObject(foo), addBorrowedObject(_callback));
        } finally {
            heap[stack_pointer++] = undefined;
            heap[stack_pointer++] = undefined;
        }
    }
}

const DEFINITION_MAP = {
    12345: Parent,
    67890: Child,
};

export function __wbindgen_instantiate(arg0, arg1, arg2) {
    let ctor = DEFINITION_MAP[arg0];
    let args = getArrayJsValueFromWasm(arg1, arg2);
    let instance = new ctor(...args);
    return instance[WASM_PTR];
}

export function __wbindgen_invoke(arg0, arg1, arg2) {
    let func = getObject(arg0);
    let args = getArrayJsValueFromWasm(arg1, arg2);
    return func(...args);
}

export function __wbindgen_wasm_pointer_set(idx, ptr) {
    let instance = getObject(arg0);
    instance[WASM_PTR] = ptr;
}
```

Accordingly, the `JsValue` at the end of the chain of injected fields encapsulates a JavaScript heap index for the shim object.  This reference from the JavaScript heap to the shim object **MUST** be "hard" whenever the `WasmRefCell` is borrowed, but **SHOULD** be "weak"\* when it is no longer borrowed; thus, if there are no other references in JavaScript to the shim object, it will (eventually) be garbage-collected whereupon a finalizer can transfer ownership of the `WasmRefCell` back to Rust so that it can be dropped \[NB: the heap reference **MUST NOT** become weak until object construction has completely terminated, otherwise there is a risk that the object could be GC'd between `__wbindgen_instantiate` returning and the result being borrowed in Rust\].  Note that when the `WasmRefCell` is dropped, so too will be the `JsValue` which will also result in the (now weak) reference being freed from the JavaScript heap.

If a Rust-native method is invoked from JavaScript, the pointer that is sent to Rust in every case will be `this[WASM_PTR]` which is the address of the `WasmRefCell<Child>` but the exported method's "receiver" may actually be a `Parent`.  To address this, rather than the JavaScript binding for `NonstandardIncoming::RustTypeRef` arguments generating a mere forward of the pointer (as at present), a lookup function is exported to the shim object through which a `Box<Ref<Parent>>` or `Box<RefMut<Parent>>` as appropriate (via `Ref::map` or `RefMut::map` on `WasmRefCell::borrow` or `WasmRefCell::borrow_mut`) can be obtained—and the address of *that* is passed to the invoked Rust method instead.  (This lookup function receives from JavaScript the `WasmType::ID` for the desired Rust type, and then traverses the `__proto__` chain until a matching object is found).

\* Obviously this depends on the [WeakReferences TC39 proposal](https://github.com/tc39/proposal-weakrefs); in the interim, a `free` function on the shim object should be exposed for manual release of the `WasmRefCell` (and ensuing release of the JavaScript heap reference to the shim).  Of course, any other JavaScript objects that refer to the shim will then find it to be broken for properties that are native to Rust (effectively a use-after-free error) but still functioning for properties that are native to JavaScript!  One possible mitigation might be for the shims to actually to be `Proxy` objects such that all property accesses can be made to throw after `free` has been called.

# Drawbacks
[drawbacks]: #drawbacks

* Breaking changes / new API.  Objects of exported types can *only* be constructed using their exported constructor function.  Methods that take ownership of `self` can no longer be called (indeed, ownership of exported types is no longer possible).  Injected field into exported types breaks destructuring patterns (do we recommend use of the `..` "et cetera" pattern, or explicit use of the named/unnamed field?).  Exported types can no longer implement `Copy`.

* Objects live on both Rust and JavaScript heaps for entire lifetime of every instance of an exported type, increasing overall memory consumption.

* Object instantiation via JavaScript adds runtime overhead, which may be entirely uneccessary if the type's prototype chain involves only Rust-exported types and the instance is never actually required in JavaScript.


# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

Currently, instantiating an exported WASM type (i.e. Rust struct annotated with `#[wasm_bindgen]`) from within Rust does just that; no JavaScript shim object is generated unless/until the WASM instance is sent over the FFI to JavaScript whereupon it is "wrapped" by the shim class's static `__wrap()` method.  This method instantiates the shim using [`Object.create()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/create) and thereby avoids calling the class's constructor function.  If ownership of the underlying WASM object returns to WASM, the shim object is destroyed; should the WASM object be sent across the FFI to JavaScript again, an entirely new shim object is instantiated to wrap it.

This approach works for the status quo because the shim objects are mere wrappers for the underlying WASM object, holding no state of their own beyond what is necessary for forwarding all behaviours over the FFI.  Moreover, there is no need to invoke the shim's constructor (which merely instantiates and wraps a fresh underlying WASM object) because the underlying WASM object to be wrapped already exists.

However, this approach no longer works once the exported type specifies a prototype chain: it would result in only partially constructed shims, because super-constructors would not have been invoked (potentially necessary for establishing state required by methods on the prototype chain—which might include linking to/from other objects).

Shims for exported derived types (i.e. those that specify a `[#wasm_bindgen(prototype)]` attribute) must therefore *always* be constructed with the [`new`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/new) operator.  Since this might have side effects outside of the instance itself (indeed, potentially outside the user's own control: e.g. consider a JavaScript-native parent type whose constructor registers the object in some global registry), it should occur at most *once* per WASM object: that is, the fully constructed shim must survive until it is never required in JavaScript again—it is not acceptible to construct a second shim for the same object.

It is conceivable that this could be accomplished in such a way that shim construction occurs, as in the status quo, only when a WASM object is sent over the FFI and requires wrapping—however, ensuring that the super-constructor is invoked with appropriate arguments (which might be some function of the object's state) and then maintaining the shim object for the long-term (where would it be "owned"?) would be complex.  Instead, it is proposed to do away entirely with the notion of "wrapping" instances of exported derived types and instead to require that their instantiation always occurs via the shim constructor and therefore always returns the shim object.

### Why have `__wbindgen_wasm_pointer_set` ?

The `__wbindgen_wasm_pointer_set` function appears to be almost superfluous, since the exported functions could simply return that value for the JavaScript `constuctor()` to assign to `this[WASM_PTR]`; however, were this the case, any user code that attempts to use the insantiated object (returned from the `instantiate!` macro) before returning could fail due to the pointer on the shim not having yet been properly instantiated.

# Unresolved Questions
[unresolved]: #unresolved-questions

1. What about exported field getters?  They currently return a copy of the field's content, but this is no longer possible for fields of exported types (since exported types can no longer be `Copy` in order to ensure proper prototype chain instantiation and shim ownership).  They should probably return a `Ref` or `RefMut` instead?  But how would their lifetimes be tracked, in order that they are appropriately dropped when no longer required?  What if JavaScript actually wants to hold those references for the long-term?  The ensuing long-lived borrow of the owning object could block one's entire application.
