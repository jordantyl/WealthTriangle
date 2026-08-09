# Backlog

Not urgent — parked here so they don't get lost.

## Add AI API key handling
Currently the backend's Gemini call path (`backend/app.py`) reads `GEMINI_API_KEY`
from the environment (set in the Render dashboard) — there's no in-app UI for a
user or admin to add/rotate an AI API key. Revisit whether that's needed (e.g.
admin panel field to swap the key without redeploying) or if env-var-only is fine
long term.

## Replace app logo / branding
The lock icon on the login screen (and app icon/launcher assets) is a placeholder.
Swap for real WealthTriangle branding when there's a logo/image to use. No rush —
flag if a concept or reference image shows up.
