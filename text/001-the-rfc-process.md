- Start Date: 2018-06-28
- RFC PR: (leave this empty)
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Adopt a simplified version of the Rust RFC process to the Rust and WebAssembly
domain working group. The RFC process will provide a single place to decide on
substantial changes and additions across the ecosystem for all stakeholders.

# Motivation
[motivation]: #motivation

There are some decisions which have broad impact across the Rust and WebAssembly
ecosystem, and therefore have many stakeholders who deserve to have a say in the
decision and provide feedback on proposals and designs. Right now, these
decisions tend to be made in whatever local repository pull request or issue
tracker. This makes it difficult for stakeholders to stay on top of these
decisions, because they need to watch many different places. For a repository
owner or team, it is also difficult to determine whether the ecosystem is in
favor of a feature or not.

After adopting this RFC process, stakeholders should have an easier time staying
on top of substantial changes and features within the ecosystem. Additionally,
the maintainers of a particular repository within the Rust and WebAssembly
ecosystem should feel confident that they've solicited feedback from everyone
involved after going through an RFC, and won't get angry bug reports from users
who felt that they were not consulted. Everyone should have shared confidence in
the direction that the ecosystem evolves in.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

Right now, governance for repositories within the `rustwasm` organization
[follow these rules][repo-governance] describing policy for merging pull
requests:

> Unless otherwise noted, each `rustwasm/*` repository has the following general
> policies:
>
> * All pull requests must be reviewed and approved of by at least one relevant
>   team member or repository collaborator before merging.
>
> * Larger, more nuanced decisions about design, architecture, breaking changes,
>   trade offs, etc are made by the relevant team and/or repository
>   collaborators consensus. In other words, decisions on things that aren't
>   straightforward improvements to or bug fixes for things that already exist
>   in the project.

This policy categorizes pull requests as either "larger, more nuanced ..."
changes or not (we will use "substantial" from now on). When a change is not
substantial, it requires only a single team member approve of it. When a change
is larger and more substantial, then the relevant team comes to consensus on how
to proceed.

This RFC intends to further sub-categorize substantial changes into those that
affect only maintenance of the repository itself, and are therefore only
substantial *internally* to the maintainers, versus those substantial changes
that have an impact on *external* users and the larger Rust and WebAssembly
community. For internally substantial changes, we do not intend to change the
current policy at all. For substantial changes that have external impact, we
will adopt a lightweight version of Rust's RFC process.

## When does a change need an RFC?

You need to follow the RFC process if you intend to make externally substantial
changes to any repository within the [`rustwasm` organization][org], or the RFC
process itself. What constitutes a "substantial" change is evolving based on
community norms and varies depending on what part of the ecosystem you are
proposing to change, but may include the following:

- The removal of or breaking changes to public APIs in widespread use.
- Public API additions that extend the public API in new ways (i.e. more than
  "we implement `SomeTrait` for `ThisThing`, so also implement `SomeTrait` for
  `RelatedThing`").

Some changes do not require an RFC:

- Rephrasing, reorganizing, refactoring, or otherwise "changing shape does
  not change meaning".
- Additions that strictly improve objective, numerical quality criteria
  (warning removal, speedup, better platform coverage, more parallelism, trap
  more errors, etc.)
- Additions only likely to be _noticed by_ other maintainers, and remain
  invisible to users.

If you submit a pull request to implement a new feature without going through
the RFC process, it may be closed with a polite request to submit an RFC first.

## The RFC process step by step

> NOTE: this process was [amended in RFC
> 009](https://rustwasm.github.io/rfcs/009-rfc-process-addendum.html) and the
> canonical, up-to-date process is now defined in [the `README.md` of the
> `rustwasm/rfcs`
> repository](https://github.com/rustwasm/rfcs/blob/master/README.md#the-rfc-process).

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
  - Before actually entering FCP, *all* members of the team(s) must sign off;
    this is often the point at which many team members first review the RFC in
    full depth.
- The FCP lasts seven calendar days. It is also advertised widely, e.g. in an
  issue of ["This Week in Rust and WebAssembly" on the Rust and WebAssembly
  blog](https://rustwasm.github.io/). This way all stakeholders have a chance to
  lodge any final objections before a decision is reached.
- In most cases, the FCP period is quiet, and the RFC is either merged or
  closed. However, sometimes substantial new arguments or ideas are raised,
  the FCP is canceled, and the RFC goes back into development mode.

## From RFC to implementation

Once an RFC is merged it becomes "active" then authors may implement it and
submit the feature as a pull request to the relevant repositories. Being
"active" is not a rubber stamp, and in particular still does not mean the
feature will ultimately be merged; it does mean that in principle all the major
stakeholders have agreed to the feature and are amenable to merging it.

Furthermore, the fact that a given RFC has been accepted and is "active" implies
nothing about what priority is assigned to its implementation, nor does it imply
anything about whether a developer has been assigned the task of implementing
the feature. While it is not *necessary* that the author of the RFC also write
the implementation, it is by far the most effective way to see an RFC through to
completion: authors should not expect that other project developers will take on
responsibility for implementing their accepted feature.

Modifications to "active" RFCs can be done in follow-up pull requests. We strive
to write each RFC in a manner that it will reflect the final design of the
feature; but the nature of the process means that we cannot expect every merged
RFC to actually reflect what the end result will be at the time of the next
major release.

In general, once accepted, RFCs should not be substantially changed. Only very
minor changes should be submitted as amendments. More substantial changes should
be new RFCs, with a note added to the original RFC.

# Rationale and Alternatives
[alternatives]: #rationale-and-alternatives

The design space for decision making is very large, from democratic to
autocratic and more.

Forking and simplifying Rust's RFC process is *practical*. Rather than designing
a decision making process from scratch, we take an existing one that works well
and tailor it to our needs. Many Rust and WebAssembly stakeholders are already
familiar with it.

The main differences from the Rust RFC process are:

- FCP lasts seven calendar days rather than ten. This reflects our desire for a
  lighter-weight process that moves more quickly than Rust's RFC process.
- The RFC template is shorter and merges together into single sections what were
  distinct sections in the Rust RFC template. Again, this reflects our desire
  for a lighter-weight process where we do not need to go into quite as much
  painstaking detail as Rust RFCs sometimes do (perhaps excluding *this* RFC).

The phases of RFC development and post-RFC implementation are largely the same
as the Rust RFC process. We found that the motivations for nearly every phase of
Rust's RFC process are equally motivating for the Rust and WebAssembly
domain. We expected to simplify phases a lot, for example, we initially
considered removing FCP and going straight to signing off on accepting an RFC or
not. However, FCP exists as a way to (1) allow stakeholders to voice any final
concerns that hadn't been brought up yet, and (2) help enforce the "no new
rationale" rule. Both points apply equally well to the Rust and WebAssembly
domain working group and ecosystem as they apply to Rust itself.

We can also avoid adopting an RFC process, and move more quickly by allowing
each repository's team or owner to be dictators of their corner of the
ecosystem. However, this will result in valuable feedback, opinions, and insight
not getting voiced, and narrow decisions being made.

# Unresolved Questions
[unresolved]: #unresolved-questions

- Will we use [`@rfcbot`][rfcbot]? If we can, we probably should, but this can
  be decided separately from whether to accept this RFC.

- How to best advertise new RFCs and FCP? Should we make "This Week in Rust and
  WebAssembly" actually be weekly rather than every other week? The interaction
  between FCP length and frequency of TWiRaWA posting seems important.

[rfcbot]: https://github.com/anp/rfcbot-rs
[teams]: https://github.com/rustwasm/team/blob/master/GOVERNANCE.md#teams
[org]: https://github.com/rustwasm
[rfc-repo]: http://github.com/rustwasm/rfcs
[repo-governance]: https://github.com/rustwasm/team/blob/master/GOVERNANCE.md#repositories
