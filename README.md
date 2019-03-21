# Rust and WebAssembly RFCs
[Rust RFCs]: #rust-rfcs

Many changes, including bug fixes and documentation improvements can be
implemented and reviewed via the normal GitHub pull request workflow.

Some changes though are "substantial", and we ask that these be put through a
bit of a design process and produce a consensus among the Rust and WebAssembly
community.

The "RFC" (request for comments) process is intended to provide a consistent and
controlled path for substantial changes and additions to enter the Rust and
WebAssembly ecosystem, so that all stakeholders can be confident about the
direction the ecosystem is evolving in.

## The RFC Process

> When does a change require an RFC? How does an RFC get approved or rejected?
> What is the RFC life cycle?

[These questions were initially answered in RFC 001][rfc-001] and then later
[amended in RFC 009][rfc-009]. The canonical RFC process is documented here:

- Fork the [RFC repository][rfc-repo].
- Copy `000-template.md` to `text/000-my-feature.md` (where "my-feature" is
  descriptive. Don't assign an RFC number yet).
- Fill in the RFC. Put care into the details: RFCs that do not present
  convincing motivation, demonstrate understanding of the impact of the design,
  or are disingenuous about the drawbacks or alternatives tend to be
  poorly-received.
- Submit a pull request. As a pull request, the RFC will receive design feedback
  from the larger community, and the author should be prepared to revise it in
  response.
- Each new RFC pull request will be triaged in the next Rust and WebAssembly
  domain working group meeting and assigned to one or more of the [`@rustwasm/*`
  teams][teams].
- Build consensus and integrate feedback. RFCs that have broad support are
  much more likely to make progress than those that don't receive any
  comments. Feel free to reach out to the RFC assignee in particular to get
  help identifying stakeholders and obstacles.
- The team(s) will discuss the RFC pull request, as much as possible in the
  comment thread of the pull request itself. Offline discussion will be
  summarized on the pull request comment thread.
- RFCs rarely go through this process unchanged, especially as alternatives
  and drawbacks are shown. You can make edits, big and small, to the RFC to
  clarify or change the design, but make changes as new commits to the pull
  request, and leave a comment on the pull request explaining your changes.
  Specifically, do not squash or rebase commits after they are visible on the
  pull request.
- At some point, a member of the subteam will propose a "motion for final
  comment period" (FCP), along with a *disposition* for the RFC (merge, close,
  or postpone).
  - This step is taken when enough of the tradeoffs have been discussed that the
    team(s) are in a position to make a decision. That does not require
    consensus amongst all participants in the RFC thread (which may be
    impossible). However, the argument supporting the disposition on the RFC
    needs to have already been clearly articulated, and there should not be a
    strong consensus *against* that position outside of the team(s). Team
    members use their best judgment in taking this step, and the FCP itself
    ensures there is ample time and notification for stakeholders to push back
    if it is made prematurely.
  - For RFCs with lengthy discussion, the motion to FCP should be preceded by a
    *summary comment* trying to lay out the current state of the discussion and
    major tradeoffs/points of disagreement.
  - Before actually entering FCP, members of the team(s) must sign off; this is
    often the point at which many team members first review the RFC in full
    depth.
  - Team members have fourteen calendar days to formally respond. The
    response may be one of:
    - Signing off on entering FCP by checking their checkbox.
    - Lodging a concern that must be addressed before the RFC can enter FCP.
    - Requesting a time extension, which extends the time-to-respond period from
      fourteen days to 28 days from the FCP proposal date.
    If a team member has not responded by the end of the time-to-respond period,
    then it is considered that they have deferred the FCP decision to the other
    team members.
- The FCP lasts seven calendar days. It is also advertised widely, e.g. in an
  issue of ["This Week in Rust and WebAssembly" on the Rust and WebAssembly
  blog](https://rustwasm.github.io/). This way all stakeholders have a chance to
  lodge any final objections before a decision is reached.
- In most cases, the FCP period is quiet, and the RFC is either merged or
  closed. However, sometimes substantial new arguments or ideas are raised,
  the FCP is canceled, and the RFC goes back into development mode.

[rfc-001]: https://rustwasm.github.io/rfcs/001-the-rfc-process.html
[rfc-009]: https://rustwasm.github.io/rfcs/009-rfc-process-addendum.html

## License
[License]: #license

This repository is currently in the process of being licensed under either of

* Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
  http://www.apache.org/licenses/LICENSE-2.0)
* MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option. Some parts of the repository are already licensed according to
those terms. For more see [RFC
2044](https://github.com/rust-lang/rfcs/pull/2044) and its [tracking
issue](https://github.com/rust-lang/rust/issues/43461).

### Contributions

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
