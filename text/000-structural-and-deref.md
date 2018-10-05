- Start Date: 2018-10-05
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Change `#[wasm_bindgen]` to use `structural` by default, and add a new
attribute `final` for an opt-in to today's behavior. Once implemented then use
`Deref` to model the class inheritance hierarchy in `web-sys` and `js-sys` to
enable ergonomic usage of superclass methods of web types.

# Motivation
[motivation]: #motivation

The initial motivation for this is outlined [RFC 3], namely that the `web-sys`
crate provides bindings for many APIs found on the web but accessing the
functionality of parent classes is quite cumbersome.

The web makes extensive use of class inheritance hierarchies, and in `web-sys`
right now each class gets its own `struct` type with inherent methods. These
types implement `AsRef` between one another for subclass relationships, but it's
quite unergonomic to actually reference the functionality! For example:

```rust
let x: &Element = ...;
let y: &Node = x.as_ref();
y.append_child(...);
```

or...

```rust
let x: &Element = ...;
<Element as AsRef<Node>>::as_ref(x)
    .append_child(...);
```

It's be much nicer if we could support this in a more first-class fashion and
make it more ergonomic!

[RFC 3]: https://github.com/rustwasm/rfcs/pull/3

> **Note**: While this RFC has the same motivation as [RFC 3] it's proposing an
> alternative solution, specifically enabled by switching by `structural` by
> default, which is discussed in [RFC 3] but is hopefully formally outlined
> here.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

This RFC proposes using the built-in `Deref` trait to model the class hierarchy
found on the web in `web-sys`. This also proposes changes to `#[wasm_bindgen]`
to make using `Deref` feasible for binding arbitrary JS apis (such as those on
NPM) with `Deref` as well.

For example, `web-sys` will contain:

```rust
impl Deref for Element {
    type Target = Node;

    fn deref(&self) -> &Node { /* ... */ }
}
```

allowing us to write our example above as:

```rust
let x: &Element = ...;
x.append_child(...); // implicit deref to `Node`!
```

All JS types in `web-sys` and in general have at most one superclass. Currently,
however, the `#[wasm_bindgen]` attribute allows specifying multiple `extends`
attributes to indicate superclasses:

```rust
#[wasm_bindgen]
extern {
    #[wasm_bindgen(extends = Node, extends = Object)]
    type Element;

    // ...
}
```

The `web-sys` API generator currently lists an `extends` for all superclasses,
transitively. This is then used in the code generator to generate `AsRef`
implementatiosn for `Element`.

The code generation of `#[wasm_bindgen]` will be updated with the following
rules:

* If no `extends` attribute is present, defined types will implement
  `Deref<Target=JsValue>`.
* Otherwise, the *first* `extends` attribute is used to implement
  `Deref<Target=ListedType>`.

This means that `web-sys` may need to be updated to ensure that the immediate
superclass is listed first in `extends`. Manual bindings will continue to work
and will have the old `AsRef` implementations as well as a new `Deref`
implementation.

The `Deref` implementation will concretely be implemented as:

```rust
impl Deref for #imported_type {
    type Target = #target_type;

    #[inline]
    fn deref(&self) -> &#target_type {
        ::wasm_bindgen::JsCast::unchecked_ref(self)
    }
}
```

### Switching to `structural` by default

If we were to implement the above `Deref` proposal as-is today in
`wasm-bindgen`, it would have a crucial drawback. It may not handle inheritance
correctly! Let's explore this with an example. Say we have some JS we'd like to
import:

```js
class Parent {
    constructor() {}
    method() { console.log('parent'); }
}

class Child extends Parent {
    constructor() {}
    method() { console.log('child'); }
}
```

we would then bind this in Rust with:

```rust
#[wasm_bindgen]
extern {
    type Parent;
    #[wasm_bindgen(constructor)]
    fn new() -> Parent;
    #[wasm_bindgen(method)]
    fn method(this: &Parent);

    #[wasm_bindgen(extends = Parent)]
    type Child;
    #[wasm_bindgen(constructor)]
    fn new() -> Child;
    #[wasm_bindgen(method)]
    fn method(this: &Child);
}
```

and we could then use it like so:

```rust
#[wasm_bindgen]
pub fn run() {
    let parent = Parent::new();
    parent.method();
    let child = Child::new();
    child.method();
}
```

and we would today see `parent` and `child` logged to the console. Ok everything
is working as expected so far! We know we've got `Deref<Target=Parent> for
Child`, though, so let's say we tweak this example a bit:

```rust
#[wasm_bindgen]
pub fn run() {
    call_method(&Parent::new());
    call_method(&Child::new());
}

fn call_method(object: &Parent) {
    object.method();
}
```

Here we'd naively (and correctly) expect `parent` and `child` to be output like
before, but much to our surprise this actually prints out `parent` twice!

The issue with this is how `#[wasm_bindgen]` treats method calls today. When you
say:

```rust
#[wasm_bindgen(method)]
fn method(this: &Parent);
```

then `wasm-bindgen` (the CLI tool) generates JS that looks like this:

```js
const Parent_method_target = Parent.prototype.method;

export function __wasm_bindgen_Parent_method(obj) {
    Parent_method_target.call(getObject(obj));
}
```

Here we can see that, by default, `wasm-bindgen` is **reaching into the
`prototype` of each class to figure out what method to call**. This in turn
means that when `Parent::method` is called in Rust, it unconditionally uses the
method defined on `Parent` rather than walking the protype chain (that JS
usually does) to find the right `method` method.

To improve the situation there's a `structural` attribute to wasm-bindgen to fix
this, which when applied like so:

```rust
#[wasm_bindgen(method, structural)]
fn method(this: &Parent);
```

means that the following JS code is generated:

```js
const Parent_method_target = function() { this.method(); };

// ...
```

Here we can see that a JS function shim is generated instead of using the raw
function value in the prototype. This, however, means that our example above
will indeed print `parent` and then `child` because JS is using prototype
lookups to find the `method` method.

Phew! Ok with all that information, we can see that **if `structural` is omitted
then JS class hierarchies can be subtly incorrect when methods taking parent
classes are passed child classes which override methods**.

An easy solution to this problem is to simply use `structural` everywhere, so...
let's propose that! Consequently, this RFC proposes changing `#[wasm_bindgen]`
to act as if all bindings are labeled as `structural`. This will not be a
breaking change because the generated bindings will still have the same behavior
as before, they'll just handle subclassing correctly!

### Adding `#[wasm_bindgen(final)]`

Since `structural` is not the default today we don't actually have a name for
the default behavior of `#[wasm_bindgen]` today. This RFC proposes adding a new
attribute to `#[wasm_bindgen]`, `final`, which indicates that it should have
today's behavior.

When attached to an attribute or method, the `final` attribute indicates that
the method or attribute should be processed through the `prototype` of a class
rather than looked up structurally via the prototype chain.

You can think of this as "everything today is `final` by default".

### Why is it ok to make `structural` the default?

One pretty reasonable question you might have at this point is "why, if
`structural` is the default today, is it ok to switch?" To answer this, let's
first explore why `final` is the default today!

From its inception `wasm-bindgen` has been designed with the future [host
bindings] proposal for WebAssembly. The host bindings proposal promises
faster-than-JS DOM access by removing many of the dynamic checks necessary when
calling DOM methods. This proposal, however, is still in relatively early stages
and hasn't been implemented in any browser yet (as far as we know).

In WebAssembly on the web all imported functions must be plain old JS functions.
They're all currently invoked with `undefined` as the `this` parameter. With
host bindings, however, there's a way to say that an imported function uses the
first argument to the function as the `this` parameter (like `Function.call` in
JS). This in turn brings the promise of *eliminating any shim functions
necessary when calling imported functionality*.

As an example, today for `#[wasm_bindgen(method)] fn parent(this: &Parent);` we
generate JS that looks like:

```rust
#[wasm_bindgen(method, structural)]
fn method(this: &Parent);
```

means that the following JS code is generated:

```js
const Parent_method_target = Parent.prototype.method;

export function __wasm_bindgen_Parent_method(idx) {
    Parent_method_target.call(getObject(idx));
}
```

If we assume for a moment that [`anyref` is implemented][reference-types] we
could instead change this to:

```js
const Parent_method_target = Parent.prototype.method;

export function __wasm_bindgen_Parent_method(obj) {
    Parent_method_target.call(obj);
}
```

(note the lack of need for `getObject`). And finally, with [host bindings] we
can say that the wasm module's import of `__wasm_bindgen_Parent_method` uses the
first parameter as `this`, meaning we can transform this to:

```js
export const __wasm_bindgen_Parent_method = Parent.prototype.method;
```

and *voila*, no JS shims necessary! With `structural` we'll still need a shim in
this future world:

```js
export const __wasm_bindgen_Parent_method = function() { this.method(); };
```

Alright, with some of those basics out of the way, let's get back to
why-`final`-by-default. The promise of [host bindings] is that by eliminating
all these JS shims necessary we can be faster than we would otherwise be,
providing a feeling that `final` is faster than `structural`. This future,
however, relies on a number of unimplemented features in wasm engines today.
Let's consequently get an idea of what the performance looks like today!

I've been slowly over time preparing a [microbenchmark suite][bm] for measuring
JS/wasm/wasm-bindgen performance. The interesting one here is the benchmark
"`structural` vs not". If you click "Run test" in a browser after awhile you'll
see two bars show up. The left-hand one is a method call with `final` and the
right-hand one is a method call with `structural`. The results I see on my
computer are:

* Firefox 62, `structural` is 3% faster
* Firefox 64, `structural` is 3% slower
* Chrome 69, `structural` is 5% slower
* Edge 42, `structural` is 22% slower
* Safari 12, `strutural` is 17% slower

So it looks like for Firefox/Chrome it's not really making much of a difference
but in Edge/Safari it's much faster to use `final`! It turns out, however, that
we're not optimizing `structural` as much as we can. Let's change our generated
code from:

```js
const Parent_method_target = function() { this.method(); };

export function __wasm_bindgen_Parent_method(obj) {
    Parent_method_target.call(getObject(obj));
}
```

to...

```js
export function __wasm_bindgen_Parent_method(obj) {
    getObject(obj).method();
}
```

(manually editing the JS today)

and if we rerun the benchmarks (sorry no online demo) we get:

* Firefox 62, `structural` is 22% faster
* Firefox 64, `structural` is 10% faster
* Chrome 69, `structural` is 0.3% slower
* Edge 42, `structural` is 15% faster
* Safai 12, `structural` is 8% slower

and these numbers look quite different! There's some strong data here showing
that `final` *is not universally faster today* and is actually almost
universally slower (when we optimize `structural` slightly).

Ok! That's all basically a very long winded way of saying **`final` was the
historical default because we thought it was faster, but it turns out that in JS
engines today it isn't always faster**. As a result, this RFC proposes that it's
ok to make `structural` the default.

[host bindings]: https://github.com/WebAssembly/host-bindings
[reference-types]: https://github.com/WebAssembly/reference-types
[bm]: https://alexcrichton.github.io/rust-wasm-benchmark/

# Drawbacks

`Deref` is a somewhat quiet trait with disproportionately large ramifications.
It affects method resolution (the `.` operator) as well as coercions (`&T` to
`&U`). Discovering this in `web-sys` and/or JS apis in the ecosystem isn't
always the easiest thing to do. It's thought, though, that this aspect of
`Deref` won't come up very often when using JS apis in practice. Instead most
APIs will work "as-is" as you might expect in JS in Rust as well, with `Deref`
being an unobtrusive solution for developers to mostly ignore it an just call
methods.

Additionally `Deref` has the drawback that it's not explicitly designed for
class inheritance hierarchies. For example `*element` produces a `Node`,
`**element` produces an `Object`, etc. This is expected to not really come up
that much in practice, though, and instead automatic coercions will cover almost
all type conversions.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

The primary alternative to this design is [RFC 3], using traits to model the
inheritance hierarchy. The pros/cons of that proposal are well listed in [RFC
3].

# Unresolved Questions
[unresolved]: #unresolved-questions

None right now!
