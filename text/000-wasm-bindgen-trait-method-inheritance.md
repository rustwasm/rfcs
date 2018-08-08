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

The end goal is that it should be possible to write generic code which can
work with all sub-classes in the inheritance graph.

As an example, it should be possible to use the
[`appendChild`](https://developer.mozilla.org/en-US/docs/Web/API/Node/appendChild)
method with all of the classes which inherit from `Node` (e.g. `HTMLElement`,
`HTMLDivElement`, `SVGElement`, and many more).

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

There are different ways to accomplish this, but this RFC proposes the
following syntax:

```rust
#[wasm_bindgen]
pub trait IEventTarget {
    #[wasm_bindgen(js_name = addEventListener)]
    fn add_event_listener(&self, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(js_name = removeEventListener)]
    fn remove_event_listener(&self, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(js_name = dispatchEvent)]
    fn dispatch_event(&self, event: Event);
}
```

```rust
#[wasm_bindgen]
pub trait INode: IEventTarget {
    #[wasm_bindgen(getter = nodeName)]
    fn node_name(&self) -> JsString;

    #[wasm_bindgen(getter = textContent)]
    fn text_content(&self) -> JsString;

    #[wasm_bindgen(js_name = appendChild)]
    fn append_child<A: INode>(&self, child: A) -> A;

    #[wasm_bindgen(js_name = removeChild)]
    fn remove_child<A: INode>(&self, child: A) -> A;

    // And a bunch more methods...
}
```

When the `wasm-bindgen` attribute is used on a trait, it will do two things:

1. It adds an `AsRef<JsValue>` constraint, so `trait Foo` becomes `trait Foo: AsRef<JsValue>`

2. It generates externs for each method, and rewrites the methods so that they have default implementations which call the externs.

The end result is that the above two traits become translated into this:

```rust
#[wasm_bindgen]
extern {
    #[wasm_bindgen(method, structural, js_name = addEventListener)]
    fn add_event_listener(this: &JsValue, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, structural, js_name = removeEventListener)]
    fn remove_event_listener(this: &JsValue, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, structural, js_name = dispatchEvent)]
    fn dispatch_event(this: &JsValue, event: Event);
}

pub trait IEventTarget: AsRef<JsValue> {
    #[inline]
    fn add_event_listener(&self, name: &str, listener, &Closure<FnMut(Event)>, use_capture: bool) {
        add_event_listener(self.as_ref(), name, listener, use_capture)
    }

    #[inline]
    fn remove_event_listener(&self, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool) {
        remove_event_listener(self.as_ref(), name, listener, use_capture)
    }

    #[inline]
    fn dispatch_event(&self, event: Event) {
        dispatch_event(self.as_ref(), event)
    }
}
```

```rust
#[wasm_bindgen]
extern {
    #[wasm_bindgen(method, structural, getter = nodeName)]
    fn node_name(this: &JsValue) -> JsString;

    #[wasm_bindgen(method, structural, getter = textContent)]
    fn text_content(this: &JsValue) -> JsString;

    #[wasm_bindgen(method, structural, js_name = appendChild)]
    fn append_child<A: INode>(this: &JsValue, child: A) -> A;

    #[wasm_bindgen(method, structural, js_name = removeChild)]
    fn remove_child<A: INode>(this: &JsValue, child: A) -> A;
}

pub trait INode: IEventTarget {
    #[inline]
    fn node_name(&self) -> JsString {
        node_name(self.as_ref())
    }

    #[inline]
    fn text_content(&self) -> JsString {
        text_content(self.as_ref())
    }

    #[inline]
    fn append_child<A: INode>(&self, child: A) -> A {
        append_child(self.as_ref(), child)
    }

    #[inline]
    fn remove_child<A: INode>(&self, child: A) -> A {
        remove_child(self.as_ref(), child)
    }

    // And a bunch more methods...
}
```

As you can see, it moves the trait methods into an `extern` (which has a `wasm-bindgen` attribute).

Each method that takes `&self` or `&mut self` gets translated into a `method, structural` extern.

Everything else is moved as-is from the trait to the extern.

Then the trait methods are rewritten so that they call the extern functions (using `as_ref()` to convert `&self` to a `&JsValue`),
and they are marked as `#[inline]`.

Now that we have defined the desired traits and methods, we can add the methods to a type like this:

```rust
#[wasm_bindgen]
extern {
    type EventTarget;
}

impl IEventTarget for EventTarget {}
```

```rust
#[wasm_bindgen]
extern {
    type Node;
}

impl IEventTarget for Node {}
impl INode for Node {}
```

Because the traits contain default implementations, this is all that is needed to make it work.

## Mixins

The above technique works great for class-based inheritance, but it can also be used to support mixins.

As an example, the [`HTMLElement`](https://html.spec.whatwg.org/multipage/dom.html#htmlelement) class in
WebIDL extends from `Element`, but *in addition* it includes various mixins, such as
[`GlobalEventHandlers`](https://html.spec.whatwg.org/multipage/webappapis.html#globaleventhandlers) and
[`HTMLOrSVGElement`](https://html.spec.whatwg.org/multipage/dom.html#htmlorsvgelement).

This is essentially a form of multiple-inheritance, but thankfully Rust traits support multiple inheritance!

```rust
#[wasm_bindgen]
pub trait IGlobalEventHandlers {
    #[wasm_bindgen(setter)]
    fn onabort(&self, listener: &Closure<FnMut(Event)>);

    // And a bunch more methods...
}

#[wasm_bindgen]
pub trait IHtmlOrSvgElement {
    #[wasm_bindgen(getter)]
    fn nonce(&self) -> JsString;

    // And a bunch more methods...
}

#[wasm_bindgen]
pub trait IHtmlElement: IElement + IGlobalEventHandlers + IHtmlOrSvgElement {
    #[wasm_bindgen(getter = title)]
    fn title(&self) -> JsString;

    // And a bunch more methods...
}
```

As you can see, the `IHtmlElement` trait inherits from `IElement`, `IGlobalEventHandlers`, and `IHtmlOrSvgElements`,
thus achieving the multiple inheritance we need.

And now we can implement the above traits on a type:

```rust
#[wasm_bindgen]
extern {
    type HtmlElement;
}

impl IGlobalEventHandlers for HtmlElement {}
impl IHtmlOrSvgElement for HtmlElement {}
impl IEventTarget for HtmlElement {}
impl INode for HtmlElement {}
impl IElement for HtmlElement {}
impl IHtmlElement for HtmlElement {}
```

# Drawbacks
[drawbacks]: #drawbacks

The `wasm_bindgen` attribute needs to be extended so it can be used on `trait`,
this is a ***lot*** of extra complexity.

In addition, because the methods are on traits, it is necessary for the Rust
user to import the trait before they can use the methods:

```rust
let x: HtmlElement = ...;

// Error, because the INode trait isn't imported
x.append_child(y);
```

This drawback can be minimized by having a `traits` module which re-exports all
of the traits. So that way the user can just put this at the top of their module:

```rust
use web_sys::traits::*;
```

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

There is essentially only one other alternative design: inherit impl.

Rather than using traits, you can instead use inherit impls on every type in the class inheritance hierarchy.

As an example, the WebIDL generator could generate this code for the `Node` and `EventTarget` types:

```rust
#[wasm_bindgen]
extern {
    type EventTarget;

    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = addEventListener)]
    fn add_event_listener(this: &EventTarget, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, js_name = removeEventListener)]
    fn remove_event_listener(this: &EventTarget, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    fn dispatch_event(this: &EventTarget, event: Event);
}
```

```rust
#[wasm_bindgen]
extern {
    type Node;


    // Methods from EventTarget
    #[wasm_bindgen(method, js_name = addEventListener)]
    fn add_event_listener(this: &Node, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, js_name = removeEventListener)]
    fn remove_event_listener(this: &Node, name: &str, listener: &Closure<FnMut(Event)>, use_capture: bool);

    #[wasm_bindgen(method, js_name = dispatchEvent)]
    fn dispatch_event(this: &Node, event: Event);


    // Methods from Node
    #[wasm_bindgen(method, getter = nodeName)]
    fn node_name(this: &JsValue) -> JsString;

    #[wasm_bindgen(method, getter = textContent)]
    fn text_content(this: &JsValue) -> JsString;

    #[wasm_bindgen(method, js_name = appendChild)]
    fn append_child(this: &JsValue, child: Node) -> Node;

    #[wasm_bindgen(method, js_name = removeChild)]
    fn remove_child(this: &JsValue, child: Node) -> Node;
}
```

As you can see, it duplicates the `add_event_listener`, `remove_event_listener`, and `dispatch_event`
methods on `Node`.

Similarly, it would have to duplicate all of the `EventTarget` and `Node` methods on `Element`. And it
would have to duplicate all of the `EventTarget`, `Node`, and `Element` methods on `HtmlElement`, etc.

This is an incredible amount of duplication, so it's only really feasible for a tool which automatically
generates the methods (such as the WebIDL generator). Trying to do this duplication by hand is unmaintainable.

That means that if you're using inherit impls, it will be very painful to use method inheritance with anything
other than WebIDL, because of the maintenance burden.

However, it has the advantage that it works *right now*, without any changes to `wasm-bindgen`.
It also doesn't require the user to import the traits (because there are no traits).

On the other hand, it makes generic code impossible. For example, with traits, the `append_child` method is
generic over all `INode`, so you can call it with multiple different types:

```rust
foo.append_child(some_node)
foo.append_child(some_element)
foo.append_child(some_html_element)
```

But with inherit impls the `append_child` method accepts a `Node` (and *only* a `Node`), thus casting is necessary:

```rust
foo.append_child(bar.into())
```

# Unresolved Questions
[unresolved]: #unresolved-questions

In the above examples I used the `I` prefix for the traits (e.g. `IHtmlElement`, `IElement`, etc.)

This is because JavaScript ties classes and methods together, but Rust keeps them separate.

As an example, in Rust we have an `HtmlElement` type (which corresponds to `HTMLElement` in JavaScript),
but methods are split into a separate trait, and we cannot re-use the `HtmlElement` name for the
trait, so we essentially need two namespaces: one for types and one for traits.

And so, as a convention, I added the `I` prefix to the traits, which essentially put them into a
separate namespace from the types.

There are other conventions, and I'm not sure about the best way to solve this problem.

----

The `INode` trait has this method:

```rust
#[wasm_bindgen(js_name = appendChild)]
fn append_child<A: INode>(&self, child: A) -> A;
```

Note that it takes a generic `A: INode` parameter. This is excellent for ergonomics
(it means you can call `append_child` with many different types), but I'm not sure if
the implementation of `wasm-bindgen` can accomodate that.

----

Is it necessary to use `structural` for the extern functions?

If not, then it would be better to not use `structural` (unless it was explicitly specified in the trait method).
