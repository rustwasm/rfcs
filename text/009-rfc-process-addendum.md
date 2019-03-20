- Start Date: 2019-03-06
- RFC PR: https://github.com/rustwasm/rfcs/pull/9
- Tracking Issue: (leave this empty)

# Summary
[summary]: #summary

Amend our RFC process so that if one team member of the working group is
unavailable, the whole RFC process is not halted at a stand still. Concretely,
if after fourteen calendar days a team member has not formally responded to
a proposal that an RFC enter its final comment period (FCP), then they
automatically defer the FCP decision to the other team members.

# Motivation
[motivation]: #motivation

A key goal of this RFC process amendment is that if a team member is busy or
otherwise unavailable, they can be accommodated, and they still have the
opportunity to provide input on the RFC and the FCP proposal. However, they must
communicate to the other team members, and if they fail to do that, as a last
resort it does not halt RFC progress.

I'd like to emphasize that the intention of this amendment is **not** to provide
a way to ram RFCs through the RFC process. It is only to provide a release valve
for the current RFC procedure's failure mode where if a single team member is
unavailable or otherwise unresponsive, then the whole RFC process grinds to a
halt. Additionally, this amendment does not remove the ability for team members
to file their own post facto amendments to RFCs for which they were unavailable,
nor does it remove their ability to engage in the original RFC and FCP proposal
discussion or raise FCP-blocking concerns.

# Stakeholders
[stakeholders]: #stakeholders

The stakeholders are the members of this working group, and the WG core team in
particular.

# Detailed Explanation
[detailed-explanation]: #detailed-explanation

We add this amendment to our RFC process's FCP proposal step:

> Once a team member proposes that an RFC enter its final comment period, the
> other team members have fourteen calendar days to formally respond. The
> response may be one of:
>
> * Signing off on entering FCP by checking their checkbox.
> * Lodging a concern that must be addressed before the RFC can enter FCP.
> * Requesting a time extension, which extends the time-to-respond period from
>   fourteen days to 28 days from the FCP proposal date.
>
> If a team member has not responded by the end of the time-to-respond period,
> then it is considered that they have deferred the FCP decision to the other
> team members.

## Examples

Here are some example timelines for RFCs with team members X, Y, and Z.

### All Members Sign Off on FCP

* 2019-01-01: The RFC is written and proposed. Community discussion begins.
* 2019-01-10: Consensus has formed, and X proposes that the RFC enter its FCP
  with disposition to merge.
* 2019-01-12: Y signs off on the FCP proposal.
* 2019-01-17: Z signs off on the FCP proposal. All team members have now signed
  off, and the RFC enters FCP.
* 2019-01-24: The seven-day FCP period has passed without additional concerns
  being raised, so the RFC is merged.

### X Does Not Respond to the FCP Proposal

* 2019-01-01: The RFC is written and proposed. Community discussion begins.
* 2019-01-10: Consensus has formed, and Z proposes that the RFC enter its FCP
  with disposition to merge.
* 2019-01-12: Y signs off on the FCP proposal.
* 2019-01-24: X has not responded to the FCP in fourteen days, so they
  automatically defer to Y and Z. The RFC enters its FCP.
* 2019-01-31: The seven-day FCP period has passed without additional concerns
  being raised, so the RFC is merged.

### Y Requests a Time-to-Respond Extension and then Later Responds

* 2019-01-01: The RFC is written and proposed. Community discussion begins.
* 2019-01-10: Consensus has formed, and X proposes that the RFC enter its FCP
  with disposition to merge.
* 2019-01-12: Z signs off on the FCP proposal.
* 2019-01-15: Y is going on vacation and hasn't had a chance to give the RFC
  deep consideration. They request a time-to-respond extension.
* 2019-01-28: Y comes back from vacation, considers the RFC, and signs off on
  it. All team members have now signed off and the RFC enters FCP.
* 2019-02-05: The seven-day FCP period has passed without additional concerns
  being raised, so the RFC is merged.

### Z Requests a Time-to-Respond Extension and then Fails to Respond

* 2019-01-01: The RFC is written and proposed. Community discussion begins.
* 2019-01-10: Consensus has formed, and X proposes that the RFC enter its FCP
  with disposition to merge.
* 2019-01-12: Y signs off on the FCP proposal.
* 2019-01-13: Z requests a time-to-respond extension.
* 2019-02-11: It has been 28 days since the date of the FCP proposal, and Z has
  still not responded. Therefore, they automatically defer to X and Y. The RFC
  enters its FCP.
* 2019-02-18: The seven-day FCP period has passed without additional concerns
  being raised, so the RFC is merged.

# Drawbacks, Rationale, and Alternatives
[alternatives]: #drawbacks-rationale-and-alternatives

The primary drawback to this RFC is that it enables going forward with RFCs that
have not been considered by every team member. The alternative, and our current
state of affairs, is delaying the RFC until every team member has signed off on
the RFC regardless how long that might take.

This RFC amendment also identifies a variable we can tweak: how long to wait for
a response before considering an unavailable team member to have deferred to the
other team members' collective judgment. Right now it is effectively set to
"infinite time", and this RFC proposes fourteen days, with the option to extend
it to 28 days. We could potentially change those numbers to seven days and
fourteen days, or to 28 and 56 days. We could potentially remove the extension
option and have only a single time-to-respond limit.

As far as prior art goes, the main Rust RFC process ran into similar problems
that this amendment is attempting to solve, and [adopted a similar mechanism for
entering FCP](https://github.com/anp/rfcbot-rs/pull/188).

# Unresolved Questions
[unresolved]: #unresolved-questions

- Does a fourteen day time-to-respond, with the option of extending it to 28
  days sound good? Should we tweak these numbers a little?
