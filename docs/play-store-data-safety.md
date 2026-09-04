# Play Console "Data safety" form — draft answers

This maps WealthTriangle's actual data handling (from `privacy-policy.md`
in this folder) onto Google Play Console's Data Safety questionnaire.

**Caveat:** Play Console's exact categories/wording change over time and
this was drafted from a general understanding of the form's structure —
open the real form in Play Console and use this as a checklist to answer
against, not a copy-paste-and-submit source. Cross-check every row
against what's actually in Play Console the day you submit.

## Does your app collect or share any of the required user data types?
**Yes.**

## Data types

| Play Console category | Collected? | Shared with 3rd party? | Purpose | Notes |
|---|---|---|---|---|
| Personal info > Email address | Yes | No (Firebase processes it as our processor, not an independent third party under Play's definition) | Account management | Via Firebase Auth / Google Sign-In |
| Financial info > Purchase history / Financial info | Optional — **your call** | No | App functionality | Salary/expenses/savings/goal are **self-reported, simulated** figures, not linked to a real bank/brokerage. Some teams still declare this category to be safe; decide based on your risk tolerance |
| App activity > App interactions | Yes | No | App functionality, analytics | Portfolio actions, lesson completion, watchlist, AI chat prompts |
| App activity > In-app search history | Yes (AI Assistant prompts) | Yes — Google Gemini or OpenAI | App functionality | Only the prompt text, not full account data |
| App info and performance > Crash logs | Yes | No (processed by Firebase Crashlytics, our processor) | Analytics | Stack traces, device/app version |
| App info and performance > Diagnostics | Yes (backend only, if `SENTRY_DSN` set) | No (Sentry as processor) | Analytics | PII scrubbing enabled server-side |
| Device or other IDs | Yes | No | App functionality | Firebase installation ID |
| Location | No | — | — | Not collected |
| Photos/videos > Photos | Yes | Yes — Google Gemini (OCR/vision) | App functionality | Camera/gallery images for receipt-OCR transaction entry and the floating assistant's vision input; sent to the backend, then to Gemini for processing. Not stored server-side beyond the request. |
| Audio > Voice or sound recordings | Yes | No | App functionality | Microphone input for the floating assistant's voice queries, transcribed on-device (`speech_to_text`) before the text prompt is sent to the backend — raw audio itself is not transmitted |
| Files/docs, Contacts, Calendar, Messages, Health & fitness, Web browsing | No | — | — | Not collected |

## Is all of the user data collected by your app encrypted in transit?
**Yes** — all traffic to Firebase and to the Flask backend goes over
HTTPS/TLS. *(Confirm your Render/host deployment enforces HTTPS — Render
does this by default.)*

## Do you provide a way for users to request that their data be deleted?
**Currently: No in-app flow.** Either:
- Answer "No" honestly and add an in-app "Delete My Account" button before
  you rely on this being "Yes" (recommended before a public release —
  Play increasingly expects this for apps handling accounts), or
- Answer "Yes" only if you commit to actually deleting data within a
  reasonable time after a request to your support email (see
  `privacy-policy.md` §4), and disclose that email as the deletion
  mechanism.

## Privacy policy URL
Host `privacy-policy.md` (rendered as a public web page, not a raw
GitHub file) and enter that URL here. GitHub Pages, a simple Firebase
Hosting static page, or Notion's public-page export all work for a v1.

## Independent security review / data safety section approval
Not required for most apps at this size — only relevant if Play flags
your app's category for extra review.

---

### Before you submit, also double check
- [ ] Add an in-app account-deletion flow, or accept the "No" answer above
- [ ] Publish the privacy policy at a stable public URL and put that URL
      in both this form and the app's own Settings/About screen
- [ ] Re-open Play Console's actual Data Safety form and verify the
      category names/options here still match — Google revises this
      periodically
