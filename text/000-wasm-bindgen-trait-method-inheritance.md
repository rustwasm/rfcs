- Start Date: 2018-08-08
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Support JavaScript class-based inheritance in `wasm-bindgen` by leveraging
Rust's trait system.

Inheritance between JavaScript classes is instead turned into inheritance
between Rust traits.

This idea has been used very successfully in [`stdweb`](https://crates.io/crates/stdweb),
though the implementation is very different.

# Motivation
[motivation]: #motivation

Class-based inheritance is very common in JavaScript, especially with the
[WebIDL bindings](https://heycam.github.io/webidl/#dfn-inherit).

Given how prelevant this pattern is in JavaScript, it would be very useful to
have a convenient and ergonomic way to make use of this inheritance while
maintaining optimal code reuse in Rust.

It is currently possible to use method inheritance, but it is very awkward, because
it requires type annotations with `.into()`:

```rust
let x: Node = some_html_element.into();
x.append_child(some_node);
```

The end goal is that it should be possible to write generic code which can
work with all sub-classes in the inheritance graph.

As an example, it should be possible to use the
[`appendChild`](https://developer.mozilla.org/en-US/docs/Web/API/Node/appendChild)
method with all of the classes which inherit from `Node` (e.g. `HTMLElement`,
`HTMLDivElement`, `SVGElement`, and many more). This should be possible without any
casting operations (such as `into` or `dyn_into`):

```rust
some_html_element.append_child(some_node);
```

As a side effect, this also makes it possible to write generic code like this:

```rust
fn foo<A: INode>(node: A) { ... }
```

However, due to the potential for code bloat, this sort of pattern is *not* encouraged
by this RFC.

Instead, users should use the specific type that they need:

```rust
fn foo(node: &Node) { ... }
```

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

Let's consider adding in methods for the [`EventTarget`](https://developer.mozilla.org/en-US/docs/Web/API/EventTarget)
and [`Node`](https://developer.mozilla.org/en-US/docs/Web/API/Node) classes.

In WebIDL, they are specified like this:

```
[Constructor,
 Exposed=(Window,Worker,AudioWorklet)]
interface EventTarget {
  boolean dispatchEvent(Event event);

  ... other attributes and methods ommitted ...
};
```

```
[Exposed=Window]
interface Node : EventTarget {
  [CEReactions] attribute DOMString? nodeValue;
  [CEReactions] attribute DOMString? textContent;

  [CEReactions] Node appendChild(Node node);
  [CEReactions] Node removeChild(Node child);

  ... other attributes and methods ommitted ...
};
```

Based upon that WebIDL spec, the WebIDL generator will generate this Rust code:

```rust
#[wasm_bindgen]
extern {
    pub type EventTarget;

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    fn dispatch_event(this: &EventTarget, event: Event) -> bool;
}

pub trait IEventTarget: AsRef<EventTarget> {
    #[inline]
    fn dispatch_event(&self, event: Event) -> bool {
        EventTarget::dispatch_event(self.as_ref(), event)
    }
}

impl IEventTarget for EventTarget {}
```

```rust
#[wasm_bindgen]
extern {
    pub type Node;

    #[wasm_bindgen(method, getter = nodeName)]
    fn node_value(this: &Node) -> JsString;

    #[wasm_bindgen(method, getter = textContent)]
    fn text_content(this: &Node) -> JsString;

    #[wasm_bindgen(method, js_name = appendChild)]
    fn append_child(this: &Node, node: Node) -> Node;

    #[wasm_bindgen(method, js_name = removeChild)]
    fn remove_child(this: &Node, child: Node) -> Node;
}

pub trait INode: IEventTarget + AsRef<Node> {
    #[inline]
    fn node_value(&self) -> JsString {
        Node::node_value(self.as_ref())
    }

    #[inline]
    fn text_content(&self) -> JsString {
        Node::text_content(self.as_ref())
    }

    #[inline]
    fn append_child(&self, node: Node) -> Node {
        Node::append_child(self.as_ref(), node)
    }

    #[inline]
    fn remove_child(&self, child: Node) -> Node {
        Node::remove_child(self.as_ref(), child)
    }
}

impl IEventTarget for Node {}
impl INode for Node {}
```

(It doesn't *literally* generate the above code, instead it generates something *equivalent* to the above code.)

Essentially, it does this:

1. It adds concrete private methods to the types (e.g. `EventTarget` and `Node`).

2. It creates a new trait which has the same name as the type, but prefixed with `I` (e.g. `IEventTarget` and `INode`).

3. This trait has an `AsRef<Type>` constraint.

4. If the WebIDL interface extends from another interface, then that is also added as a constraint (e.g. `INode` inherits from `IEventTarget`).

   It only adds the *immediate* parent as a constraint. For example, `Element` extends from `Node`, so this will be generated:

   ```rust
   pub trait IElement: INode + AsRef<Element> {
       ...
   }
   ```

   Because `INode` inherits from `IEventTarget`, that means that `IElement` also indirectly inherits from `IEventTarget`.

5. The trait has `#[inline]` default methods which calls `self.as_ref()` and then calls the concrete private methods (forwarding any arguments along as-is).

6. Lastly it uses `impl Trait for Type {}` to implement the trait for the types. It needs to implement the entire trait hierarchy for each type:

   ```rust
   impl IEventTarget for EventTarget {}

   impl IEventTarget for Node {}
   impl INode for Node {}

   impl IEventTarget for Element {}
   impl INode for Element {}
   impl IElement for Element {}

   impl IEventTarget for HTMLElement {}
   impl INode for HTMLElement {}
   impl IElement for HTMLElement {}
   impl IHTMLElement for HTMLElement {}
   ```

For the sake of ergonomics, the WebIDL generator should also create a `traits` module which re-exports all of the traits:

```rust
pub mod traits {
    pub use super::{IEventTarget, INode, IElement, IHTMLElement};
}
```

This allows users to add `use web_sys::traits::*` to import all of the traits.

The end result is that the user can now use the various methods without any casting:

```rust
use web_sys::traits::*;

let x: HTMLElement = ...;

x.append_child(some_node);
x.dispatch_event(some_event);
```

## Mixins

The WebIDL generator already handles mixins, so they will automatically work correctly with this proposal.

# Drawbacks
[drawbacks]: #drawbacks

Because the methods are on traits, it is necessary for the Rust
user to import the trait before they can use the methods:

```rust
let x: HTMLElement = ...;

// Error, because the INode trait isn't imported
x.append_child(y);
```

This is a breaking change (because `web-sys` currently doesn't use traits).

As explained above, this drawback can be minimized by having a `traits` module which
re-exports all of the traits. So that way the user can just put this at the top of
their module:

```rust
// Now all of the methods work!
use web_sys::traits::*;
```

Another downside is that the documentation is less discoverable: with inherent impls
the user can see all of the methods available for the type, but with traits they have
to look at the trait documentation in order to see the methods.

Lastly, because traits are monomorphized in Rust, if users aren't careful they can
create a lot of bloat from monomorphized functions/methods.

However, this is true with *all* Rust code (traits are *extremely* common in Rust!),
and there are many ways to avoid the cost of monomorphization.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

There are two possible alternatives: inherent impl and `Deref`.

First, let's discuss inherent impls. Rather than using traits, it can instead generate inherent impls on every type in the class inheritance hierarchy.

As an example, the WebIDL generator could generate this code for the `EventTarget` and `Node` types:

```rust
#[wasm_bindgen]
extern {
    pub type EventTarget;

    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = dispatchEvent)]
    pub fn dispatch_event(this: &EventTarget, event: Event) -> bool;
}
```

```rust
#[wasm_bindgen]
extern {
    pub type Node;


    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = dispatchEvent)]
    pub fn dispatch_event(this: &Node, event: Event) -> bool;


    // Methods from Node
    #[wasm_bindgen(method, getter = nodeName)]
    pub fn node_value(this: &Node) -> JsString;

    #[wasm_bindgen(method, getter = textContent)]
    pub fn text_content(this: &Node) -> JsString;

    #[wasm_bindgen(method, js_name = appendChild)]
    pub fn append_child(this: &Node, node: Node) -> Node;

    #[wasm_bindgen(method, js_name = removeChild)]
    pub fn remove_child(this: &Node, child: Node) -> Node;
}
```

As you can see, it duplicates the `dispatch_event` method on `Node`.

Similarly, it would have to duplicate all of the `EventTarget` and `Node` methods on `Element`. And it
would have to duplicate all of the `EventTarget`, `Node`, and `Element` methods on `HTMLElement`, etc.

This is an incredible amount of duplication, so it's only really feasible for a tool which automatically
generates the methods (such as the WebIDL generator). Trying to do this duplication by hand is unmaintainable.

That means that if you're using inherent impls, it will be very painful to use method inheritance with anything
other than WebIDL, because of the maintenance burden.

And because class-based inheritance is used outside of WebIDL, we want to be able to support non-WebIDL use
cases.

----

The other alternative is `Deref`. Let's look back at the example WebIDL:

```
[Constructor,
 Exposed=(Window,Worker,AudioWorklet)]
interface EventTarget {
  boolean dispatchEvent(Event event);

  ... other attributes and methods ommitted ...
};
```

```
[Exposed=Window]
interface Node : EventTarget {
  [CEReactions] attribute DOMString? nodeValue;
  [CEReactions] attribute DOMString? textContent;

  [CEReactions] Node appendChild(Node node);
  [CEReactions] Node removeChild(Node child);

  ... other attributes and methods ommitted ...
};
```

The WebIDL generator would generate this Rust code:

```rust
#[wasm_bindgen]
extern {
    pub type EventTarget;

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    pub fn dispatch_event(this: &EventTarget, event: Event) -> bool;
}
```

```rust
#[wasm_bindgen]
extern {
    pub type Node;

    #[wasm_bindgen(method, getter = nodeName)]
    pub fn node_value(this: &Node) -> JsString;

    #[wasm_bindgen(method, getter = textContent)]
    pub fn text_content(this: &Node) -> JsString;

    #[wasm_bindgen(method, js_name = appendChild)]
    pub fn append_child(this: &Node, node: Node) -> Node;

    #[wasm_bindgen(method, js_name = removeChild)]
    pub fn remove_child(this: &Node, child: Node) -> Node;
}

impl Deref for Node {
    type Target = EventTarget;

    #[inline]
    fn deref(&self) -> Self::Target {
        JsCast::unchecked_from_js_ref(self.as_ref())
    }
}
```

(It doesn't *literally* generate the above code, instead it generates something *equivalent* to the above code.)

Essentially, it does this:

1. It adds concrete **public** methods to the types (e.g. `EventTarget` and `Node`).

2. It creates a `Deref` implementation for `Node` which derefs to `EventTarget` (by using `unchecked_from_js_ref`).

   For deeper hierarchies (e.g. `Element`) it only needs to implement a `Deref` to the immediate parent:

   ```rust
   impl Deref for Element {
       type Target = Node;

       #[inline]
       fn deref(&self) -> Self::Target {
           JsCast::unchecked_from_js_ref(self.as_ref())
       }
   }
   ```

There are quite a lot of advantages to this:

1. It is possible to use methods on the parent class without any casts:

   ```rust
   let x: HTMLElement = ...;

   x.append_child(some_node);
   x.dispatch_event(some_event);
   ```

2. It is possible to very efficiently and easily cast into a parent class anywhere in the class hierarchy:

   ```rust
   let x: HTMLElement = ...;
   let y: &EventTarget = &x;
   ```

3. It is possible to pass a sub-class as an argument to a function/method which expects a super-class:

   ```rust
   fn foo(node: &EventTarget) { ... }

   let x: HTMLElement = ...;

   // This works!
   foo(&x);
   ```

   (This behavior is similar to sub-typing, but it is implemented completely differently from sub-typing.)

4. We can start out without `Deref` and then add it in the future in a backwards-compatible way.

5. All of the methods for the super-classes show up in the documentation for the sub-classes.

However there are some downsides too:

1. This pattern is **not** the intended usage of `Deref`, thus there is the chance it will cause confusion for users.

2. If you have a variable `x: HTMLElement`, it is surprising that `*x` is an `Element`, `**x` is a `Node`, and `***x` is an `EventTarget`.

3. Because the type conversion is implicit and is based upon the *expected* type, this can cause surprising behavior:

   ```rust
   let a: HTMLElement = ...;
   let b: &Element = &a;
   let c: &Node = &a;
   let d: &EventTarget = &a;

   fn foo(x: &EventTarget) { ... }

   foo(&a);
   ```

   As you can see, the same expression (`&a`) has completely different meanings depending on what the expected type is.

   When type annotations are omitted, this can make it difficult to determine what type it is being silently and implicitly converted into.

4. Traits are not inherited with `Deref` (if a trait is implemented on `EventTarget` it will not show up on `Node`).

   That is *also* true with this trait RFC, but there is a difference in expectations: users might expect `Deref` to forward along traits, but users don't expect traits to forward along traits.

5. If a sub-class overrides a method on a super-class, this can lead to *very* surprising behavior!

   Consider this hypothetical WebIDL:

   ```
   [Constructor]
   interface Foo {
      boolean some_method();
   };

   [Constructor]
   interface Bar : Foo {
      boolean some_method();
   };
   ```

   As you can see, the `Bar` class is overriding the `some_method` method from the `Foo` class.

   The WebIDL generator will create this Rust code based upon that WebIDL:

   ```rust
   #[wasm_bindgen]
   extern {
       pub type Foo;

       #[wasm_bindgen(method)]
       pub fn some_method(this: &Foo) -> bool;
   }
   ```

   ```rust
   #[wasm_bindgen]
   extern {
       pub type Bar;

       #[wasm_bindgen(method)]
       pub fn some_method(this: &Bar) -> bool;
   }

   impl Deref for Bar {
       type Target = Foo;

       #[inline]
       fn deref(&self) -> Self::Target {
           JsCast::unchecked_from_js_ref(self.as_ref())
       }
   }
   ```

   At first, everything seems okay:

   ```rust
   let foo: Foo = ...;
   let bar: Bar = ...;

   // Calls Foo::some_method
   foo.some_method();

   // Calls Bar::some_method
   bar.some_method();
   ```

   The problem happens when you have a function or method which accepts a `Foo`:

   ```rust
   fn my_fn(x: &Foo) -> bool { x.some_method() }

   // Calls Foo::some_method
   my_fn(&foo);

   // Also calls Foo::some_method
   my_fn(&bar);
   ```

   As you can see, even though we passed in a `Bar`, it still ended up calling `Foo::some_method`!

   This is not at all how sub-classes in JavaScript behave, so it is extremely surprising.

   That situation can be avoided with this trait RFC (at the cost of potential monomorphization bloat if the user isn't careful):

   ```rust
   fn my_fn<A: IFoo>(x: &A) -> bool { x.some_method() }

   // Calls Foo::some_method
   my_fn(&foo);

   // Calls Bar::some_method
   my_fn(&bar);
   ```

   This works because `Bar` can impl `IFoo` (and thus override `some_method`):

   ```rust
   impl IFoo for Bar {
       fn some_method(&self) -> bool {
           ...
       }
   }
   ```

It's also possible to *combine* this trait RFC with `Deref`, combining the benefits of both. But this has the additional downside of confusing users: when should they use traits and when should they use `Deref`?

It's also important to note that many of the benefits of this trait RFC can be obtained by using `AsRef<Type>`:

```rust
fn my_fn<A: AsRef<Foo>>(foo: A) { ... }
```

So the biggest downside of `Deref` is the very poor handling of overridden methods.

----

As an implicit third possibility, we can simply do nothing and continue to require `.into()` calls for upcasting.

This has the benefit that it requires no work, however it is quite clunky for users, and if we decide to add in traits later then that is a breaking change, so it's better to make breaking changes now rather than later.

# Future Extensions
[future]: #future-extensions

This proposal requires a lot of boilerplate (to define the inherent and trait methods). This is acceptable
for WebIDL which automatically generates the code, but it is awkward for non-WebIDL use cases.

As a possible future extension, we could extend the `wasm_bindgen` attribute
so that it works on traits:

```rust
#[wasm_bindgen(type = EventTarget)]
pub trait IEventTarget {
    #[wasm_bindgen(js_name = dispatchEvent)]
    fn dispatch_event(&self, event: Event) -> bool;
}
```

```rust
#[wasm_bindgen(type = Node)]
pub trait INode: IEventTarget {
    #[wasm_bindgen(getter = nodeName)]
    fn node_value(&self) -> JsString;

    #[wasm_bindgen(getter = textContent)]
    fn text_content(&self) -> JsString;

    #[wasm_bindgen(js_name = appendChild)]
    fn append_child(&self, node: Node) -> Node;

    #[wasm_bindgen(js_name = removeChild)]
    fn remove_child(&self, child: Node) -> Node;
}
```

This makes it dramatically easier to define trait methods.

However, this RFC is forwards-compatible with using `wasm_bindgen` on traits, and it is not necessary
right now, so it is deferred for a future RFC.


# Unresolved Questions
[unresolved]: #unresolved-questions

In the above examples I used the `I` prefix for the traits (e.g. `IHtmlElement`, `IElement`, etc.)

This is because JavaScript ties classes and methods together, but Rust keeps them separate.

As an example, in Rust we have an `HTMLElement` type (which corresponds to `HTMLElement` in JavaScript),
but methods are split into a separate trait, and we cannot re-use the `HTMLElement` name for the
trait, so we essentially need two namespaces: one for types and one for traits.

And so, as a convention, I added the `I` prefix to the traits, which essentially put them into a
separate namespace from the types.

There are other conventions, and I'm not sure about the best way to solve this problem.
