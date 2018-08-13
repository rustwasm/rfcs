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
  void addEventListener(DOMString type, EventListener? callback, optional (AddEventListenerOptions or boolean) options);
  void removeEventListener(DOMString type, EventListener? callback, optional (EventListenerOptions or boolean) options);
  boolean dispatchEvent(Event event);
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
    #[wasm_bindgen(method, js_name = addEventListener)]
    fn add_event_listener(this: &EventTarget, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = removeEventListener)]
    fn remove_event_listener(this: &EventTarget, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    fn dispatch_event(this: &EventTarget, event: Event);
}

pub trait IEventTarget: AsRef<EventTarget> {
    #[inline]
    fn add_event_listener(&self, type: &str, callback: &Closure<FnMut(Event)>, options: bool) {
        EventTarget::add_event_listener(self.as_ref(), type, callback, options)
    }

    #[inline]
    fn remove_event_listener(&self, type: &str, callback: &Closure<FnMut(Event)>, options: bool) {
        EventTarget::remove_event_listener(self.as_ref(), type, callback, options)
    }

    #[inline]
    fn dispatch_event(&self, event: Event) {
        EventTarget::dispatch_event(self.as_ref(), event)
    }
}

impl IEventTarget for EventTarget {}
```

```rust
#[wasm_bindgen]
extern {
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

Essentially, it does this:

1. It adds concrete private methods to the types (e.g. `EventTarget` and `Node`)

2. It creates a new trait which has the same name as the type, but prefixed with `I` (e.g. `IEventTarget` and `INode`)

3. This trait has an `AsRef<Type>` constraint

4. If the WebIDL interface extends from another interface, then that is also added as a constraint (e.g. `INode` inherits from `IEventTarget`)

5. The trait has `#[inline]` default methods which calls `self.as_ref()` and then calls the concrete private methods (forwarding any arguments along as-is)

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
x.add_event_listener("foo", some_listener, true);
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

As explained above, this drawback can be minimized by having a `traits` module which
re-exports all of the traits. So that way the user can just put this at the top of
their module:

```rust
// Now all of the methods work!
use web_sys::traits::*;
```

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

There is essentially only one other alternative design: inherit impl.

Rather than using traits, it can instead use inherit impls on every type in the class inheritance hierarchy.

As an example, the WebIDL generator could generate this code for the `EventTarget` and `Node` types:

```rust
#[wasm_bindgen]
extern {
    type EventTarget;

    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = addEventListener)]
    pub fn add_event_listener(this: &EventTarget, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = removeEventListener)]
    pub fn remove_event_listener(this: &EventTarget, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    pub fn dispatch_event(this: &EventTarget, event: Event);
}
```

```rust
#[wasm_bindgen]
extern {
    type Node;


    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = addEventListener)]
    pub fn add_event_listener(this: &Node, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = removeEventListener)]
    pub fn remove_event_listener(this: &Node, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    pub fn dispatch_event(this: &Node, event: Event);


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

As you can see, it duplicates the `add_event_listener`, `remove_event_listener`, and `dispatch_event`
methods on `Node`.

Similarly, it would have to duplicate all of the `EventTarget` and `Node` methods on `Element`. And it
would have to duplicate all of the `EventTarget`, `Node`, and `Element` methods on `HTMLElement`, etc.

This is an incredible amount of duplication, so it's only really feasible for a tool which automatically
generates the methods (such as the WebIDL generator). Trying to do this duplication by hand is unmaintainable.

That means that if you're using inherit impls, it will be very painful to use method inheritance with anything
other than WebIDL, because of the maintenance burden.

And because class-based inheritance is used outside of WebIDL, we want to be able to support non-WebIDL use
cases.

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

----

This proposal requires a lot of boilerplate (to define the inherit and trait methods). This is acceptable
for WebIDL which automatically generates the code, but it is awkward for non-WebIDL use cases.

As a possible future extension, we could extend the `wasm_bindgen` attribute
so that it works on traits:

```rust
#[wasm_bindgen(type = EventTarget)]
pub trait IEventTarget {
    #[wasm_bindgen(js_name = addEventListener)]
    fn add_event_listener(&self, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(js_name = removeEventListener)]
    fn remove_event_listener(&self, type: &str, callback: &Closure<FnMut(Event)>, options: bool);

    #[wasm_bindgen(js_name = dispatchEvent)]
    fn dispatch_event(&self, event: Event);
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
