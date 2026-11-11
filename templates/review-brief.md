TIME AND ORDER (read this first). You have about 40 minutes. Write your report by minute 35 even
if you have not read everything, and list what you did not read under NOT READ: a review stopped
before it writes is lost. Read in this order and no further than you need:
1. <THE DIFF, OR THE PART OF IT, THAT CARRIES MONEY, RECORDS OR STATE: FILE PATHS>
2. <THE REST OF THE MILESTONE'S CODE CHANGES: FILE PATHS>
Skip tests, fixtures, packaging and docs unless you need one to confirm a specific finding. Do not
read whole large files; open only the lines around the change.

You are reviewing milestone <N> of a build: <ONE-SENTENCE SUMMARY OF WHAT NOW WORKS>.

You are one of several independent reviewers. Review only; do not change any file, do not run
anything that writes, and do not go online.

Where:
- The pinned checkout `<REVIEW_CHECKOUT>` at commit `<PIN>` (branch `<BRANCH>`). Read the code
  there.
- The change: `<BUILD>/reviews/m<N>.diff` (`git diff <FROM>..<PIN>`) and the commit list
  `<BUILD>/reviews/m<N>-commits.txt`.
- The plan: `<BUILD>/plan.md`. <WHICH SECTIONS BIND THIS MILESTONE, AND WHICH WIN ON CONFLICT>
- The status file: `<BUILD>/status.md` (what each task claims, its commits and its test results).

What this milestone was meant to do:
<THE MILESTONE'S TASKS, ONE LINE EACH, WITH THE OWNER DECISIONS THEY CARRY OUT>

Test results the lead ran itself at the pin:
<COMMANDS, EXIT CODES, COUNTS>

Known limits and items already on the follow-up list (do not report these again):
<LIST, OR "none">

Look for problems that matter, checked against the code rather than the summary:
- Does the change do what the plan says, for the owner decisions listed above?
- Money moving wrongly, data lost or written somewhere it must not be, a false or misleading
  sentence on a screen, a security hole, a race, a crash path, a failing or skipped test that hides
  a defect, a screen that visibly misses its approved design.
- Tests that pass without proving the behaviour (they would still pass if the code were wrong).

Classify each finding:
- BIG: one of the problems in the second bullet above, or the change does not do what the plan
  says. Only BIG findings are repaired before the build ends.
- SMALL: everything else worth fixing later.

Reply with the report only, in this shape:

VERDICT: READY | READY AFTER THE BIG FIXES | NOT READY
BIG:
1. <file>:<line> — what is wrong, the input or state that triggers it, and what the person or the
   data would see. Evidence: <the code that shows it>.
SMALL:
1. <file>:<line> — what and why.
NOT READ: <anything you could not open or check>

If you find nothing, write `BIG: none` and `SMALL: none`. Do not invent findings to fill the list.
